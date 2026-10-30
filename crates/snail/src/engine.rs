//! What every subcommand shares: one engine configured for what the
//! compiler's backend emits, modules loaded from `.wasm` or precompiled
//! `.cwasm` files, the WASI context Node's hosts give a module, calls into
//! a reactor's exports, and failures told as `snail: MESSAGE`.

use std::num::NonZeroUsize;
use std::path::Path;

use wasmtime::{
    AsContextMut, Collector, Config, Engine, Instance, Module, OptLevel, Trap, Val, WasmBacktrace,
    WasmResults,
};
use wasmtime_wasi::p1::WasiP1Ctx;
use wasmtime_wasi::{FsPerms, I32Exit, WasiCtxBuilder};

// ---- The engine ----

// How deep Wasm may recurse, on the large thread `main` starts. Node runs
// the compiler with a 4 MiB stack; wasmtime's frames are larger, and a
// limit this generous only ever matters to a program that would overflow.
pub const WASM_STACK: usize = 64 << 20;

// GC types, typed function references and tail calls, and no exceptions,
// which the backend never emits. Deferred reference counting is wasmtime's
// one working collector; it cannot collect cycles, so a cycle lives as long
// as its store, which here is the process. Wasmtime checks the stack limit
// against the stack it would give async calls, though none are made.
pub fn engine() -> wasmtime::Result<Engine> {
    let mut config = Config::new();
    config
        .wasm_gc(true)
        .wasm_function_references(true)
        .wasm_tail_call(true)
        .wasm_exceptions(false)
        .collector(Collector::DeferredReferenceCounting)
        .max_wasm_stack(WASM_STACK)
        .async_stack_size(WASM_STACK)
        .wasm_backtrace_max_frames(NonZeroUsize::new(32))
        .cranelift_opt_level(OptLevel::Speed);
    Engine::new(&config)
}

// A `.cwasm` file is machine code `snail precompile` wrote; anything else
// is a module to compile.
pub fn is_precompiled(path: &Path) -> bool {
    path.extension()
        .is_some_and(|extension| extension == "cwasm")
}

pub fn load(engine: &Engine, path: &Path) -> wasmtime::Result<Module> {
    if is_precompiled(path) {
        // SAFETY: deserializing trusts the file to be wasmtime's own output,
        // which the build driver writes beside the module it compiled.
        // Wasmtime still refuses one from another version or configuration.
        unsafe { Module::deserialize_file(engine, path) }
    } else {
        Module::from_file(engine, path)
    }
}

// Compiling the compiler takes Cranelift most of a second, which every
// compile would otherwise pay again. A `.cwasm` file is specific to this
// binary's wasmtime version and configuration and to the CPU, so it is a
// build output beside its module and is never committed. It is written
// beside OUTPUT and renamed into place, so no run loads half of one.
pub fn precompile(module: &str, output: &str) -> u8 {
    let written = engine().and_then(|engine| {
        let code = engine.precompile_module(&std::fs::read(module)?)?;
        let partial = format!("{output}.{}.partial", std::process::id());
        std::fs::write(&partial, code)?;
        Ok(std::fs::rename(&partial, output)?)
    });
    match written {
        Ok(()) => 0,
        Err(error) => {
            report(&error, false);
            2
        }
    }
}

// ---- WASI ----

// What host/native/run-snail.mjs gives Node's WASI: the module first
// among the arguments, the host's environment with SNAIL_CWD naming the
// working directory, and the host's root preopened as `/`. wasi-libc
// resolves a relative path against `/`, so a module resolves one against
// SNAIL_CWD itself. File operations block this thread rather than
// wasmtime-wasi's Tokio pool, since nothing else runs meanwhile.
pub fn wasi(module: &str, arguments: &[String]) -> wasmtime::Result<WasiP1Ctx> {
    let mut builder = WasiCtxBuilder::new();
    builder
        .inherit_stdio()
        .allow_blocking_current_thread(true)
        .arg(module)
        .args(arguments);
    let environment = std::env::vars_os()
        .filter_map(|(name, value)| Some((name.into_string().ok()?, value.into_string().ok()?)));
    for (name, value) in environment.filter(|(name, _)| name != "SNAIL_CWD") {
        builder.env(name, value);
    }
    builder.env("SNAIL_CWD", std::env::current_dir()?.to_string_lossy());
    builder.preopened_dir("/", "/", FsPerms::ReadWrite)?;
    Ok(builder.build_p1())
}

// ---- Calls ----

// Calls an export that takes no arguments.
pub fn call<R: WasmResults>(
    mut store: impl AsContextMut,
    instance: &Instance,
    name: &str,
) -> wasmtime::Result<R> {
    instance
        .get_typed_func::<(), R>(&mut store, name)?
        .call(&mut store, ())
}

// Calls an export that takes no arguments for its effect, discarding its
// results, as a JavaScript host does: an exposed Unit function answers 0.
pub fn run_export(
    mut store: impl AsContextMut,
    instance: &Instance,
    name: &str,
) -> wasmtime::Result<()> {
    let Some(function) = instance.get_func(&mut store, name) else {
        wasmtime::bail!("the module exports no function {name}")
    };
    let mut results = vec![Val::I32(0); function.ty(&store).results().len()];
    function.call(&mut store, &[], &mut results)
}

// A WASI exit is a status, not a failure.
pub fn exit_status(called: wasmtime::Result<()>) -> wasmtime::Result<u8> {
    match called {
        Ok(()) => Ok(0),
        Err(error) => match error.downcast_ref::<I32Exit>() {
            Some(exit) => Ok(exit.0 as u8),
            None => Err(error),
        },
    }
}

// ---- Failures ----

// A failure of the host or a trap, as `snail: MESSAGE`. With `backtrace`,
// the Wasm frames follow the message.
pub fn report(error: &wasmtime::Error, backtrace: bool) {
    match error.downcast_ref::<Trap>() {
        Some(trap) => eprintln!("snail: {}", trap_message(*trap)),
        None => eprintln!("snail: {error}"),
    }
    if let (true, Some(frames)) = (backtrace, error.downcast_ref::<WasmBacktrace>()) {
        eprintln!("{frames}");
    }
}

// The message V8 gives each trap, which a program's expected output records
// after `snail: `. Wasmtime has one code for dividing by zero and taking a
// remainder by zero, which V8 tells apart.
pub fn trap_message(trap: Trap) -> String {
    let message = match trap {
        Trap::StackOverflow => "Maximum call stack size exceeded",
        Trap::MemoryOutOfBounds => "memory access out of bounds",
        Trap::HeapMisaligned => "operation does not support unaligned accesses",
        Trap::TableOutOfBounds => "table index is out of bounds",
        Trap::IndirectCallToNull | Trap::BadSignature => {
            "null function or function signature mismatch"
        }
        Trap::IntegerOverflow => "divide result unrepresentable",
        Trap::IntegerDivisionByZero => "divide by zero",
        Trap::BadConversionToInteger => "float unrepresentable in integer range",
        Trap::UnreachableCodeReached => "unreachable",
        Trap::NullReference => "dereferencing a null pointer",
        Trap::ArrayOutOfBounds => "array element access out of bounds",
        Trap::CastFailure => "illegal cast",
        Trap::AllocationTooLarge => "requested new array is too large",
        other => return other.to_string(),
    };
    message.to_string()
}

// ---- Tests ----

#[cfg(test)]
pub mod tests {
    use super::*;

    // The module's text assembled into a file of its own.
    pub fn module_file(name: &str, text: &str) -> String {
        let path =
            std::env::temp_dir().join(format!("snail-test-{}-{name}.wasm", std::process::id()));
        std::fs::write(&path, wat::parse_str(text).unwrap()).unwrap();
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn traps_are_told_as_v8_tells_them() {
        assert_eq!(trap_message(Trap::IntegerDivisionByZero), "divide by zero");
        assert_eq!(trap_message(Trap::UnreachableCodeReached), "unreachable");
        assert_eq!(
            trap_message(Trap::StackOverflow),
            "Maximum call stack size exceeded"
        );
    }

    #[test]
    fn a_precompiled_module_loads_in_place_of_its_source() {
        let source = module_file(
            "precompiled",
            "(module (func (export \"answer\") (result i32) (i32.const 42)))",
        );
        let precompiled = source.replace(".wasm", ".cwasm");
        assert_eq!(precompile(&source, &precompiled), 0);
        let engine = engine().unwrap();
        let mut store = wasmtime::Store::new(&engine, ());
        let instance = Instance::new(
            &mut store,
            &load(&engine, Path::new(&precompiled)).unwrap(),
            &[],
        )
        .unwrap();
        assert_eq!(call::<i32>(&mut store, &instance, "answer").unwrap(), 42);
    }

    #[test]
    fn a_wasi_exit_is_a_status() {
        let exit = wasmtime::Error::new(I32Exit(1));
        assert_eq!(exit_status(Err(exit)).unwrap(), 1);
        assert!(exit_status(Err(wasmtime::Error::new(Trap::UnreachableCodeReached))).is_err());
    }
}
