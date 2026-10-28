//! The compiled compiler's reactor protocol, which host/native/run-compiler.mjs
//! implements on Node: instantiate, `_initialize`, `main`, then
//! `compiler-compile`; on exit 1 `compiler-request`; and `close-resources`
//! always.
//!
//! `run-compiler MODULE MODE SOURCE OUTPUT GENERATED DIRECTORY ...` exits 0
//! when OUTPUT is written, and 1 when the compile failed, its diagnostic on
//! standard error, or wrote GENERATED/request.datum asking the driver for
//! an input (host/chibi/snail/stage0/build.sld). Any other failure, of the
//! host or of the module, is status 2, with the Wasm frames of a trap.

use wasmtime::{Instance, Linker, Store};
use wasmtime_wasi::p1::{self, WasiP1Ctx};

use crate::engine::{call, engine, exit_status, load, report, run_export, wasi};

// ---- Running ----

pub fn run(module: &str, arguments: &[String]) -> u8 {
    match compile(module, arguments) {
        Ok(status) => status,
        Err(error) => {
            report(&error, true);
            2
        }
    }
}

// Resources are closed whatever happened, and a failure to close them is
// status 2; when the compile itself failed, that failure is the one told.
fn compile(module: &str, arguments: &[String]) -> wasmtime::Result<u8> {
    let engine = engine()?;
    let mut linker = Linker::new(&engine);
    p1::add_to_linker_sync(&mut linker, |wasi: &mut WasiP1Ctx| wasi)?;
    let mut store = Store::new(&engine, wasi(module, arguments)?);
    let instance = linker.instantiate(&mut store, &load(&engine, module)?)?;
    let compiled = request(&mut store, &instance);
    let closed = call::<i32>(&mut store, &instance, "close-resources");
    let status = compiled?;
    Ok(if closed? == 0 { status } else { 2 })
}

// `main` initializes the request state before any fallible source loading.
// Exit 1 ends a failed compile and one that needs an input alike; only that
// exit publishes the pending request, so `compiler-request` writes it
// after the stack that asked has unwound.
fn request(store: &mut Store<WasiP1Ctx>, instance: &Instance) -> wasmtime::Result<u8> {
    call::<()>(&mut *store, instance, "_initialize")?;
    call::<i32>(&mut *store, instance, "main")?;
    let status = exit_status(run_export(&mut *store, instance, "compiler-compile"))?;
    if status == 1 {
        run_export(&mut *store, instance, "compiler-request")?;
    }
    Ok(status)
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::tests::module_file;
    use crate::engine::trap_message;
    use wasmtime::{Module, Trap};

    // A compiler's exports around a compile whose body is `compile`; the
    // global `requested` records a call to `compiler-request`.
    fn compiler(compile: &str, close: i32) -> String {
        format!(
            r#"(module
                 (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
                 (memory (export "memory") 1)
                 (global $requested (export "requested") (mut i32) (i32.const 0))
                 (func (export "_initialize"))
                 (func (export "main") (result i32) (i32.const 0))
                 (func (export "compiler-compile") (result i32) {compile})
                 (func (export "compiler-request") (result i32) (global.set $requested (i32.const 1)) (i32.const 0))
                 (func (export "close-resources") (result i32) (i32.const {close})))"#
        )
    }

    // The status `request` answers and whether it published the request.
    fn requested(text: &str) -> (wasmtime::Result<u8>, i32) {
        let engine = engine().unwrap();
        let mut linker = Linker::new(&engine);
        p1::add_to_linker_sync(&mut linker, |wasi: &mut WasiP1Ctx| wasi).unwrap();
        let mut store = Store::new(&engine, wasi("compiler.wasm", &[]).unwrap());
        let module = Module::new(&engine, wat::parse_str(text).unwrap()).unwrap();
        let instance = linker.instantiate(&mut store, &module).unwrap();
        let status = request(&mut store, &instance);
        let global = instance.get_global(&mut store, "requested").unwrap();
        (status, global.get(&mut store).unwrap_i32())
    }

    #[test]
    fn a_compile_that_returns_succeeds_without_a_request() {
        let (status, published) = requested(&compiler("(i32.const 0)", 0));
        assert_eq!((status.unwrap(), published), (0, 0));
    }

    #[test]
    fn exit_1_publishes_the_request_after_unwinding() {
        let (status, published) =
            requested(&compiler("(call $exit (i32.const 1)) (unreachable)", 0));
        assert_eq!((status.unwrap(), published), (1, 1));
    }

    #[test]
    fn another_exit_is_its_status_without_a_request() {
        let (status, published) =
            requested(&compiler("(call $exit (i32.const 3)) (unreachable)", 0));
        assert_eq!((status.unwrap(), published), (3, 0));
    }

    #[test]
    fn a_trap_is_a_failure() {
        let (status, _) = requested(&compiler("(i32.div_s (i32.const 1) (i32.const 0))", 0));
        let error = status.unwrap_err();
        assert_eq!(
            trap_message(*error.downcast_ref::<Trap>().unwrap()),
            "divide by zero"
        );
    }

    #[test]
    fn failing_to_close_resources_is_status_2() {
        assert_eq!(
            run(&module_file("closing", &compiler("(i32.const 0)", 0)), &[]),
            0
        );
        assert_eq!(
            run(&module_file("unclosed", &compiler("(i32.const 0)", 1)), &[]),
            2
        );
    }

    #[test]
    fn a_failed_compile_is_told_over_a_failure_to_close() {
        let path = module_file("both", &compiler("(unreachable)", 1));
        let error = compile(&path, &[]).unwrap_err();
        assert_eq!(
            *error.downcast_ref::<Trap>().unwrap(),
            Trap::UnreachableCodeReached
        );
    }

    #[test]
    fn a_trap_is_status_2() {
        assert_eq!(
            run(&module_file("trapping", &compiler("(unreachable)", 0)), &[]),
            2
        );
    }
}
