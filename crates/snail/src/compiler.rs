//! The compiled compiler's reactor protocol, which host/native/run-compiler.mjs
//! implements on Node: instantiate, `_initialize`, `main`, then
//! `compiler-compile`, and `close-resources` always.
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
    let compiled = invoke(&mut store, &instance);
    let closed = call::<i32>(&mut store, &instance, "close-resources");
    let status = compiled?;
    Ok(if closed? == 0 { status } else { 2 })
}

// `main` initializes the module state before any fallible source loading.
// Exit 1 ends a failed compile and one that needs an input alike: the
// compile wrote that one's request before it exited.
fn invoke(store: &mut Store<WasiP1Ctx>, instance: &Instance) -> wasmtime::Result<u8> {
    call::<()>(&mut *store, instance, "_initialize")?;
    call::<i32>(&mut *store, instance, "main")?;
    exit_status(run_export(&mut *store, instance, "compiler-compile"))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::tests::module_file;
    use crate::engine::trap_message;
    use wasmtime::{Module, Trap};

    // A compiler's exports around a compile whose body is `compile`.
    fn compiler(compile: &str, close: i32) -> String {
        format!(
            r#"(module
                 (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
                 (memory (export "memory") 1)
                 (func (export "_initialize"))
                 (func (export "main") (result i32) (i32.const 0))
                 (func (export "compiler-compile") (result i32) {compile})
                 (func (export "close-resources") (result i32) (i32.const {close})))"#
        )
    }

    // The status `invoke` answers for a compiler.
    fn invoked(text: &str) -> wasmtime::Result<u8> {
        let engine = engine().unwrap();
        let mut linker = Linker::new(&engine);
        p1::add_to_linker_sync(&mut linker, |wasi: &mut WasiP1Ctx| wasi).unwrap();
        let mut store = Store::new(&engine, wasi("compiler.wasm", &[]).unwrap());
        let module = Module::new(&engine, wat::parse_str(text).unwrap()).unwrap();
        let instance = linker.instantiate(&mut store, &module).unwrap();
        invoke(&mut store, &instance)
    }

    #[test]
    fn a_compile_that_returns_succeeds() {
        assert_eq!(invoked(&compiler("(i32.const 0)", 0)).unwrap(), 0);
    }

    #[test]
    fn an_exit_is_its_status() {
        for code in [1, 3] {
            let compile = format!("(call $exit (i32.const {code})) (unreachable)");
            assert_eq!(invoked(&compiler(&compile, 0)).unwrap(), code as u8);
        }
    }

    #[test]
    fn a_trap_is_a_failure() {
        let status = invoked(&compiler("(i32.div_s (i32.const 1) (i32.const 0))", 0));
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
