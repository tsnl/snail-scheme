//! Running a compiled program, as host/native/run-snail.mjs runs one on
//! Node, for a program that needs of its host only WASI, the files it links
//! (links.rs) and loading modules (modules.rs).
//!
//! `snail run-wasm PROGRAM ARGUMENT ...` runs PROGRAM, one linked module or
//! the modules.json of a program compiled one library at a time
//! (modules.rs). WASI gives it PROGRAM and the arguments, the environment
//! with SNAIL_CWD, and `/` (engine.rs). The protocol:
//!
//! 1. instantiate, then call `_initialize`;
//! 2. call each module's `main` in program order: the last one's result is
//!    the exit status when it is 0 to 255, and 1 otherwise, while a WASI
//!    exit ends the program with its own status;
//! 3. close the program's resources whatever happened, `close-resources`
//!    or the runtime's `snail:io/close-all`; failing to close them makes a
//!    successful run's status 1.
//!
//! A trap, or a failure of the host, is status 2, told as `snail: MESSAGE`
//! with the Wasm frames after it on standard error.
//!
//! Node's event loop schedules tasks, sockets and processes
//! (host/browser/tasks.mjs) until tasks become effects (#511), so a program
//! that imports them is refused before it is compiled. `snail imports
//! PROGRAM` lists the modules a program imports from, so the build driver
//! can run such a program on Node instead.

use std::collections::BTreeSet;
use std::path::Path;

use wasmtime::{AsContextMut, Engine, Instance, Linker, Module, Store, Val, bail, format_err};
use wasmtime_wasi::p1::{self, WasiP1Ctx};

use crate::engine::{call, engine, exit_status, report, wasi};
use crate::links::{self, Files};
use crate::modules::{self, Libraries, Loading, Manifest};

// ---- Running ----

/// A program's store: its WASI context, the files it links, and the
/// modules it loads while it runs.
pub struct Host {
    pub wasi: WasiP1Ctx,
    pub files: Files,
    pub loading: Loading,
}

/// A program ready to start: the instance holding the runtime, whose
/// memory the program's code shares; its export that closes the program's
/// resources; and the instances whose mains run, in program order.
pub struct Linked {
    pub runtime: Instance,
    pub close: &'static str,
    pub mains: Vec<Instance>,
}

pub fn run(path: &str, arguments: &[String]) -> u8 {
    match execute(path, arguments) {
        Ok(status) => status,
        Err(error) => {
            report(&error, true);
            2
        }
    }
}

// Every file the program links is read before any module is instantiated.
fn execute(path: &str, arguments: &[String]) -> wasmtime::Result<u8> {
    let engine = engine()?;
    let payload = Payload::compile(&engine, Path::new(path))?;
    let names = links::linked_names(payload.modules());
    let files = Files::read(Path::new(path).parent().unwrap_or(Path::new("")), &names)?;
    let mut linker = host_linker(&engine, &names)?;
    let host = Host {
        wasi: wasi(path, arguments)?,
        files,
        loading: Loading::new(linker.clone()),
    };
    let mut store = Store::new(&engine, host);
    let program = payload.link(&mut store, &mut linker)?;
    let ran = start(&mut store, &program);
    let closed = call::<i32>(&mut store, &program.runtime, program.close);
    settle(ran, closed)
}

// What a program run here may import of its host: WASI, the files the
// payload links, and loading modules.
fn host_linker(engine: &Engine, links: &[String]) -> wasmtime::Result<Linker<Host>> {
    let mut linker = Linker::new(engine);
    p1::add_to_linker_sync(&mut linker, |host: &mut Host| &mut host.wasi)?;
    links::define(&mut linker, links)?;
    modules::define_loading(&mut linker)?;
    Ok(linker)
}

// Each module's main runs in program order; the program's own, last,
// answers the status.
fn start(store: &mut Store<Host>, program: &Linked) -> wasmtime::Result<u8> {
    let mut status = 0;
    for instance in &program.mains {
        match main_status(&mut *store, instance) {
            Ok(result) => status = result,
            Err(error) => return exit_status(Err(error)),
        }
    }
    Ok(status)
}

// What `main` answers, as run-snail.mjs reads it: nothing is 0, an
// integer from 0 to 255 is itself, and any other value is 1.
fn main_status(mut store: impl AsContextMut, instance: &Instance) -> wasmtime::Result<u8> {
    let Some(main) = instance.get_func(&mut store, "main") else {
        bail!("the module exports no function main")
    };
    let mut results = vec![Val::I32(0); main.ty(&store).results().len()];
    main.call(&mut store, &[], &mut results)?;
    Ok(match results.first() {
        None => 0,
        Some(Val::I32(result)) => u8::try_from(*result).unwrap_or(1),
        Some(Val::I64(result)) => u8::try_from(*result).unwrap_or(1),
        Some(_) => 1,
    })
}

// A failure to close resources fails a run that succeeded; when the run
// itself failed, that failure is the one told.
fn settle(ran: wasmtime::Result<u8>, closed: wasmtime::Result<i32>) -> wasmtime::Result<u8> {
    let status = ran?;
    Ok(if closed? != 0 && status == 0 {
        1
    } else {
        status
    })
}

// ---- Payloads ----

/// What `run-wasm` was given, compiled: one linked module, or the runtime
/// and each library's module of a program compiled one library at a time.
enum Payload {
    Module(Module),
    Libraries(Libraries),
}

impl Payload {
    fn compile(engine: &Engine, path: &Path) -> wasmtime::Result<Payload> {
        Ok(if is_manifest(path) {
            Payload::Libraries(Libraries::compile(engine, &Manifest::read(path)?)?)
        } else {
            Payload::Module(compile_module(engine, path)?)
        })
    }

    // The modules whose imports name the files the program links.
    fn modules(&self) -> Vec<&Module> {
        match self {
            Payload::Module(module) => vec![module],
            Payload::Libraries(libraries) => libraries.modules().collect(),
        }
    }

    fn link(self, store: &mut Store<Host>, linker: &mut Linker<Host>) -> wasmtime::Result<Linked> {
        match self {
            Payload::Module(module) => link_module(store, linker, &module),
            Payload::Libraries(libraries) => libraries.link(store, linker),
        }
    }
}

fn is_manifest(path: &Path) -> bool {
    path.extension()
        .is_some_and(|extension| extension == "json")
}

// One linked module holds the runtime itself, so it closes its own
// resources, and is the instance a module it loads sees as the library.
fn link_module(
    store: &mut Store<Host>,
    linker: &mut Linker<Host>,
    module: &Module,
) -> wasmtime::Result<Linked> {
    let instance = linker.instantiate(&mut *store, module)?;
    store.data_mut().loading.set_runtime(instance);
    call::<()>(&mut *store, &instance, "_initialize")?;
    Ok(Linked {
        runtime: instance,
        close: "close-resources",
        mains: vec![instance],
    })
}

// ---- Programs this host does not run ----

/// The host modules only Node provides, until tasks become effects (#511).
pub const NODE_ONLY: [&str; 3] = ["snail.tasks", "snail.socket", "snail.process"];

/// The module in `file`, compiled, unless it imports what only Node
/// provides; its import section is read first, so a refused module costs
/// no compile.
pub fn compile_module(engine: &Engine, file: &Path) -> wasmtime::Result<Module> {
    let bytes = read(file)?;
    let imported = import_modules(&bytes)?;
    if let Some(node) = imported
        .iter()
        .find(|module| NODE_ONLY.contains(&module.as_str()))
    {
        bail!(
            "{} imports {node}: a program that uses tasks, sockets or processes runs on Node until tasks become effects (#511)",
            file.display()
        )
    }
    Module::new(engine, &bytes)
}

fn read(file: &Path) -> wasmtime::Result<Vec<u8>> {
    std::fs::read(file).map_err(|error| format_err!("cannot read {}: {error}", file.display()))
}

// ---- What a program imports ----

/// `snail imports PROGRAM`: each module PROGRAM's modules import from, a
/// line each in sorted order, read from their import sections without
/// compiling them.
pub fn imports(path: &str) -> u8 {
    match program_imports(Path::new(path)) {
        Ok(modules) => {
            modules.iter().for_each(|module| println!("{module}"));
            0
        }
        Err(error) => {
            report(&error, false);
            2
        }
    }
}

fn program_imports(path: &Path) -> wasmtime::Result<BTreeSet<String>> {
    let files = if is_manifest(path) {
        Manifest::read(path)?.files()
    } else {
        vec![path.into()]
    };
    let mut modules = BTreeSet::new();
    for file in files {
        modules.extend(import_modules(&read(&file)?)?);
    }
    Ok(modules)
}

// The modules a module's import section names.
fn import_modules(bytes: &[u8]) -> wasmtime::Result<BTreeSet<String>> {
    let mut modules = BTreeSet::new();
    for payload in wasmparser::Parser::new(0).parse_all(bytes) {
        if let wasmparser::Payload::ImportSection(section) = payload? {
            for import in section.into_imports() {
                modules.insert(import?.module.to_string());
            }
        }
    }
    Ok(modules)
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::tests::module_file;

    // A program importing `imports` whose main is `main` and whose
    // resources close with `close`.
    fn program(imports: &str, main: &str, close: i32) -> String {
        format!(
            r#"(module {imports}
                 (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
                 (memory (export "memory") 1)
                 (func (export "_initialize"))
                 (func (export "main") (result i32) {main})
                 (func (export "close-resources") (result i32) (i32.const {close})))"#
        )
    }

    fn status(name: &str, main: &str, close: i32) -> u8 {
        run(&module_file(name, &program("", main, close)), &[])
    }

    #[test]
    fn mains_result_is_the_status_when_it_is_a_byte() {
        assert_eq!(status("three", "(i32.const 3)", 0), 3);
        assert_eq!(status("large", "(i32.const 300)", 0), 1);
        assert_eq!(status("negative", "(i32.const -1)", 0), 1);
    }

    #[test]
    fn a_wasi_exit_is_its_own_status() {
        assert_eq!(
            status("exits", "(call $exit (i32.const 7)) (i32.const 0)", 0),
            7
        );
    }

    #[test]
    fn a_trap_is_status_2() {
        assert_eq!(status("traps", "(unreachable)", 0), 2);
    }

    #[test]
    fn unclosed_resources_fail_only_a_successful_run() {
        assert_eq!(status("unclosed-run", "(i32.const 0)", 1), 1);
        assert_eq!(status("unclosed-failure", "(i32.const 4)", 1), 4);
    }

    #[test]
    fn a_program_that_uses_tasks_is_refused_naming_511() {
        let imports = r#"(import "snail.tasks" "spawn" (func (param i32)))"#;
        let file = module_file("tasks", &program(imports, "(i32.const 0)", 0));
        let engine = engine().unwrap();
        let error = compile_module(&engine, Path::new(&file))
            .unwrap_err()
            .to_string();
        assert!(error.ends_with(
            "imports snail.tasks: a program that uses tasks, sockets or processes runs on Node until tasks become effects (#511)"
        ));
        assert_eq!(run(&file, &[]), 2);
    }

    #[test]
    fn imports_are_read_without_compiling() {
        let imports = r#"(import "snail.socket" "open" (func (result i32)))"#;
        let file = module_file("imports", &program(imports, "(i32.const 0)", 0));
        let read = program_imports(Path::new(&file)).unwrap();
        assert_eq!(
            read.into_iter().collect::<Vec<_>>(),
            ["snail.socket", "wasi_snapshot_preview1"]
        );
    }
}
