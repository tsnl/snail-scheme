//! Running a compiled program, as host/native/run-snail.mjs runs one on
//! Node, for a program that needs of its host only WASI, the files it links
//! (links.rs) and loading modules (modules.rs).
//!
//! `snail run-wasm PROGRAM ARGUMENT ...` runs PROGRAM, one linked module or
//! the manifest of a program compiled one library at a time
//! (modules.rs). WASI gives it PROGRAM and the arguments, the environment
//! with SNAIL_CWD, and `/` (engine.rs). The protocol:
//!
//! 1. instantiate, then call `_initialize`;
//! 2. create the scheduler and call `main` with it, which starts the
//!    program's main as its first task, and run the first turn: a WASI exit
//!    there ends the program with its own status;
//! 3. drive the program's tasks until none is live: a task that traps is
//!    told, and a task that panics tells its message and exits; either
//!    fails the run, status 1, and ends driving; reachable queued work is
//!    disposed during close;
//! 4. close queued work, let go of the scheduler, and close the program's
//!    resources whatever happened, `close-resources` or the runtime's
//!    `snail:io/close-all`; failing to close them makes a successful run's
//!    status 1.
//!
//! A trap, or a failure of the host, is status 2, told as `snail: MESSAGE`
//! with the Wasm frames after it on standard error.
//!
//! Sockets and processes are Node's (host/native/socket-imports.mjs and
//! process-imports.mjs), so a program that imports them is refused before
//! it is compiled. `snail imports PROGRAM` lists the modules a program
//! imports from, so the build driver can run such a program on Node
//! instead.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use wasmtime::{
    AnyRef, AsContext, AsContextMut, Engine, ExternType, Instance, Linker, Module, OwnedRooted,
    RootScope, Rooted, Store, Val, bail, format_err,
};
use wasmtime_wasi::I32Exit;
use wasmtime_wasi::p1::{self, WasiP1Ctx};

use crate::async_files;
use crate::engine::{call, engine, exit_status, is_precompiled, load, report, wasi};
use crate::links::{self, Files};
use crate::modules::{self, Loading, Manifest};

// ---- Running ----

/// A program's store: its WASI context, the files it links, and the
/// modules it loads while it runs.
pub struct Host {
    pub wasi: WasiP1Ctx,
    pub files: Files,
    pub async_files: async_files::Files,
    pub loading: Loading,
    pub entry: Option<Entry>,
}

/// A program ready to start: the instance holding the runtime, whose
/// memory the program's code shares, and its resource cleanup export.
pub struct Linked {
    pub runtime: Instance,
    pub close: &'static str,
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

// One linked module is the program; a manifest is run by the engine
// ((snail shell engine), which the command line holds, at
// SNAIL_ENGINE_MODULE or build/bootstrap/snail-scheme.wasm beside this
// executable's build), started with the manifest in
// SNAIL_MANIFEST, which links the program's objects through the Wasm
// primitives of modules.rs, runs each main, serves the files it links, and
// forwards its scheduler as its own exports. A file a linked module links
// is an object of store/ beside it, read when a task first asks for it.
fn execute(path: &str, arguments: &[String]) -> wasmtime::Result<u8> {
    let engine = engine()?;
    let payload = Payload::compile(&engine, Path::new(path))?;
    let names = links::linked_names([&payload.module]);
    let files = Files::new(&payload.store, &names);
    let mut linker = host_linker(&engine, &names)?;
    define_node_only(&mut linker, &payload.module)?;
    let host = Host {
        wasi: wasi(path, arguments, &payload.environment)?,
        files,
        async_files: async_files::Files::default(),
        loading: Loading::new(linker.clone()),
        entry: None,
    };
    let mut store = Store::new(&engine, host);
    let program = link_module(&mut store, &mut linker, &payload.module)?;
    store.data_mut().entry = Entry::create(&mut store, program.runtime, payload.engine)?;
    let ran = start(&mut store);
    let closed = close(&mut store, &program);
    settle(ran, closed)
}

// What a program run here may import of its host: WASI, the files the
// payload links, loading modules, and the platform's error report, which
// a runtime the engine links imports.
fn host_linker(engine: &Engine, links: &[String]) -> wasmtime::Result<Linker<Host>> {
    let mut linker = Linker::new(engine);
    p1::add_to_linker_sync(&mut linker, |host: &mut Host| &mut host.wasi)?;
    links::define(&mut linker, links)?;
    async_files::define(&mut linker)?;
    modules::define_loading(&mut linker)?;
    modules::define_platform(&mut linker)?;
    Ok(linker)
}

// The program's resources close, the engine's program's through
// `engine:close` first; a status other than 0 is a resource left open.
fn close(store: &mut Store<Host>, program: &Linked) -> wasmtime::Result<i32> {
    // Keep services and the root live while queue disposal calls cleanup.
    // Attempt each teardown even if a previous one trapped.
    let queues = if store.data().entry.is_some() {
        entry_task(&mut *store, "close", &[]).map(|_| ())
    } else {
        Ok(())
    };
    let children = if engine_entry(&*store) {
        entry_call(&mut *store, "engine:close", &[])
    } else {
        Ok(0)
    };
    if let Some(entry) = store.data_mut().entry.as_mut() {
        entry.scheduler = None;
    }
    let files = store.data_mut().async_files.close();
    let own = call::<i32>(&mut *store, &program.runtime, program.close);
    queues?;
    files?;
    let children = children?;
    let own = own?;
    Ok(if children != 0 { children as i32 } else { own })
}

// A source program has one explicit main, which takes the scheduler and
// starts the program's main as its first task. The engine links a program
// in its first task and starts that main under the same scheduler. The
// first turn runs here, so a trap in it fails the start, status 2.
fn start(store: &mut Store<Host>) -> wasmtime::Result<u8> {
    let main = if engine_entry(&*store) {
        "engine:start"
    } else {
        "main"
    };
    let started = entry_call(&mut *store, main, &[])
        .and_then(|_| entry_task(&mut *store, "turn", &[Val::I64(now())]));
    if let Err(error) = started {
        return exit_status(Err(error));
    }
    match drive(store) {
        Ok(true) => Ok(1),
        Ok(false) => Ok(0),
        Err(error) => exit_status(Err(error)),
    }
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

// ---- Entries ----

/// The scheduler the program's `create` made, and the instance whose
/// exports take it. Closing the run lets go of it, so no later import
/// wrapper can call in.
pub struct Entry {
    instance: Instance,
    scheduler: Option<OwnedRooted<AnyRef>>,
    prefix: &'static str,
}

impl Entry {
    // The engine's exports when it runs a manifest; otherwise the
    // program's own scheduler, which the command line also has.
    fn create(
        store: &mut Store<Host>,
        instance: Instance,
        engine: bool,
    ) -> wasmtime::Result<Option<Entry>> {
        for prefix in [if engine { "engine" } else { "tasks" }] {
            let Some(create) = instance.get_func(&mut *store, &format!("{prefix}:create")) else {
                continue;
            };
            let mut scope = RootScope::new(&mut *store);
            let value = create
                .typed::<(), Rooted<AnyRef>>(&scope)?
                .call(&mut scope, ())?;
            let scheduler = Some(value.to_owned_rooted(&mut scope)?);
            return Ok(Some(Entry {
                instance,
                scheduler,
                prefix,
            }));
        }
        Ok(None)
    }
}

pub fn engine_entry(store: impl AsContext<Data = Host>) -> bool {
    store
        .as_context()
        .data()
        .entry
        .as_ref()
        .is_some_and(|entry| entry.prefix == "engine")
}

/// Import wrappers pass the scheduler to each call, never a copy of their
/// own. A temporary GC root keeps it alive through a reentrant call, and no
/// longer than the entry holds it.
pub fn entry_call(
    mut store: impl AsContextMut<Data = Host>,
    name: &str,
    args: &[Val],
) -> wasmtime::Result<i64> {
    let (instance, scheduler) = {
        let context = store.as_context();
        let entry = context
            .data()
            .entry
            .as_ref()
            .ok_or_else(|| format_err!("this program has no task entry"))?;
        let scheduler = entry
            .scheduler
            .as_ref()
            .ok_or_else(|| format_err!("the program's tasks have closed"))?;
        (entry.instance, scheduler.clone())
    };
    let mut scope = RootScope::new(&mut store);
    let function = instance
        .get_func(&mut scope, name)
        .ok_or_else(|| format_err!("the entry exports no {name}"))?;
    let mut arguments = vec![Val::AnyRef(Some(scheduler.to_rooted(&mut scope)))];
    arguments.extend_from_slice(args);
    let mut results = vec![Val::I32(0); function.ty(&scope).results().len()];
    function.call(&mut scope, &arguments, &mut results)?;
    match results.first() {
        None => Ok(0),
        Some(Val::I32(value)) => Ok(i64::from(*value)),
        Some(Val::I64(value)) => Ok(*value),
        _ => bail!("{name} must return an integer or Unit"),
    }
}

fn entry_task(
    mut store: impl AsContextMut<Data = Host>,
    name: &str,
    args: &[Val],
) -> wasmtime::Result<i64> {
    let engine = engine_entry(&store);
    let prefix = if engine { "engine" } else { "tasks" };
    let name = if engine && name == "close" {
        "close-tasks"
    } else {
        name
    };
    entry_call(&mut store, &format!("{prefix}:{name}"), args)
}

// ---- Tasks ----

// Turns are bounded FIFO batches. A trap is terminal: Wasm does not unwind
// the trapping frame. Close can still dispose of reachable queued work.
fn drive(store: &mut Store<Host>) -> wasmtime::Result<bool> {
    if store.data().entry.is_none() {
        return Ok(false);
    }
    loop {
        let answer = entry_task(&mut *store, "turn", &[Val::I64(now())]);
        let waking = store.data_mut().files.take_waking();
        let file_reads = store.data_mut().async_files.collect()?;
        let has_completions = !waking.is_empty() || !file_reads.is_empty();
        let files_pending = store.data().async_files.pending();
        match answer {
            Ok(-1) => return Ok(false),
            Ok(-2) if !has_completions && !files_pending => {
                bail!("every task waits on a ticket, and this host completes none")
            }
            Ok(-2) if !has_completions => store.data_mut().async_files.wait(None)?,
            Ok(delay) if delay > 0 && !has_completions => {
                let timeout = Duration::from_millis(delay as u64);
                if files_pending {
                    store.data_mut().async_files.wait(Some(timeout))?;
                } else {
                    thread::sleep(timeout);
                }
            }
            Ok(_) => {}
            Err(error) => {
                if error.downcast_ref::<I32Exit>().is_none() {
                    report(&error, true);
                }
                return Ok(true);
            }
        }
        for ticket in waking {
            entry_task(&mut *store, "wake", &[Val::I64(ticket)])?;
        }
        for (ticket, id) in file_reads {
            if entry_task(&mut *store, "wake", &[Val::I64(ticket)])? == 0 {
                store.data_mut().async_files.cancel(id);
            }
        }
    }
}

// Milliseconds since the Unix epoch, as `Date.now()` gives them.
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_millis() as i64)
}

// ---- Payloads ----

/// What `run-wasm` was given, compiled: one linked module, or the engine,
/// given a manifest to run through SNAIL_MANIFEST; the store the files the
/// module links are objects of, `store/` beside it; what the module's
/// environment says beyond the host's; and whether it is the engine.
struct Payload {
    module: Module,
    store: PathBuf,
    environment: Vec<(String, String)>,
    engine: bool,
}

impl Payload {
    fn compile(engine: &Engine, path: &Path) -> wasmtime::Result<Payload> {
        let (file, environment) = if is_manifest(path) {
            let manifest = std::path::absolute(path)?.to_string_lossy().into_owned();
            (
                engine_module()?,
                vec![("SNAIL_MANIFEST".to_string(), manifest)],
            )
        } else {
            (path.to_path_buf(), Vec::new())
        };
        Ok(Payload {
            module: compile_module(engine, &file)?,
            store: file.parent().unwrap_or(Path::new("")).join("store"),
            environment,
            engine: is_manifest(path),
        })
    }
}

// The engine's module: SNAIL_ENGINE_MODULE, or the command line in the
// build directory this executable was built into, as machine code when
// stage 0 has precompiled the current one.
fn engine_module() -> wasmtime::Result<PathBuf> {
    if let Some(path) = std::env::var_os("SNAIL_ENGINE_MODULE") {
        return Ok(PathBuf::from(path));
    }
    let executable = std::env::current_exe()?;
    let build = executable
        .ancestors()
        .find(|directory| directory.file_name().is_some_and(|name| name == "build"))
        .ok_or_else(|| format_err!("the engine's module is not found: set SNAIL_ENGINE_MODULE"))?;
    let module = build.join("bootstrap").join("snail-scheme.wasm");
    let code = module.with_extension("cwasm");
    let modified = |path: &Path| {
        std::fs::metadata(path)
            .and_then(|data| data.modified())
            .ok()
    };
    Ok(match (modified(&code), modified(&module)) {
        (Some(code_time), Some(module_time)) if code_time >= module_time => code,
        _ => module,
    })
}

fn is_manifest(path: &Path) -> bool {
    path.to_string_lossy().ends_with(".manifest.datum")
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
    store.data_mut().loading.set_loader(instance);
    call::<()>(&mut *store, &instance, "_initialize")?;
    Ok(Linked {
        runtime: instance,
        close: "close-resources",
    })
}

// ---- Programs this host does not run ----

/// The host modules only Node provides.
pub const NODE_ONLY: [&str; 2] = [
    "snail.runtime.native.socket",
    "snail.runtime.native.process",
];

/// The module in `file`, compiled. A `.cwasm` file is machine code
/// `snail precompile` wrote, as the command line's is.
pub fn compile_module(engine: &Engine, file: &Path) -> wasmtime::Result<Module> {
    if is_precompiled(file) {
        return load(engine, file);
    }
    Module::new(engine, read(file)?)
}

/// Each function `module` imports of what only Node provides, as one that
/// traps when it is called, saying so: the command line imports processes
/// for `run`, and its `compile` calls none,
/// so it compiles here. Stage 0 runs a program that does call them on
/// Node, having asked `snail imports`; a module loaded while the program
/// runs gets the same stand-ins (modules.rs).
fn define_node_only(linker: &mut Linker<Host>, module: &Module) -> wasmtime::Result<()> {
    for import in module.imports() {
        if !NODE_ONLY.contains(&import.module()) {
            continue;
        }
        if let ExternType::Func(ty) = import.ty() {
            let missing = format!("{} {} runs on Node", import.module(), import.name());
            linker.func_new(import.module(), import.name(), ty, move |_, _, _| {
                Err(format_err!("{missing}"))
            })?;
        }
    }
    Ok(())
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
    use crate::engine::precompile;
    use crate::engine::tests::module_file;

    // A program importing `imports` whose main is `main`, whose turns do
    // each of `turns` in turn and then answer -1, and whose resources close
    // with `close`. The scheduler counts its turns, and closing it checks
    // that the run took the turns it should have: none when main fails,
    // and otherwise the first turn and then each until the one that ends
    // driving, the turn answering -1 after the last when none does.
    fn program(imports: &str, main: &str, close: i32, turns: &[Turn]) -> String {
        let cases: String = turns
            .iter()
            .enumerate()
            .map(|(index, turn)| {
                let then = match turn {
                    Turn::Answer(answer) => format!("(return (i64.const {answer}))"),
                    Turn::Trap => "(unreachable)".to_string(),
                    Turn::Exit(status) => format!("(call $exit (i32.const {status}))"),
                };
                format!("(if (i32.eq (local.get $n) (i32.const {index})) (then {then}))")
            })
            .collect();
        let expected = turns
            .iter()
            .position(|turn| matches!(turn, Turn::Trap | Turn::Exit(_) | Turn::Answer(-2)))
            .map_or(turns.len().max(1) + 1, |index| index + 1);
        format!(
            r#"(module {imports}
                 (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
                 (memory (export "memory") 1)
                 (type $state (struct (field (mut i32))))
                 (global $closed (mut i32) (i32.const 0))
                 (func (export "_initialize"))
                 (func (export "main") (param $state (ref $state)) (result i32) {main})
                 (func (export "close-resources") (result i32)
                   (if (i32.ne (global.get $closed) (i32.const 1)) (then unreachable))
                   (i32.const {close}))
                 (func (export "tasks:create") (result (ref $state)) (struct.new $state (i32.const 0)))
                 (func (export "tasks:close") (param $state (ref $state))
                   (if (i32.and (i32.ne (struct.get $state 0 (local.get $state)) (i32.const {expected}))
                                (i32.ne (struct.get $state 0 (local.get $state)) (i32.const 0)))
                     (then unreachable))
                   (global.set $closed (i32.add (global.get $closed) (i32.const 1))))
                 (func (export "tasks:turn") (param $state (ref $state)) (param $now i64) (result i64) (local $n i32)
                   (local.set $n (struct.get $state 0 (local.get $state)))
                   (struct.set $state 0 (local.get $state) (i32.add (local.get $n) (i32.const 1)))
                   {cases}
                   (i64.const -1)))"#
        )
    }

    // What one turn of a test scheduler does.
    enum Turn {
        Answer(i64),
        Trap,
        Exit(i32),
    }

    fn status(name: &str, main: &str, close: i32, turns: &[Turn]) -> u8 {
        run(&module_file(name, &program("", main, close, turns)), &[])
    }

    #[test]
    fn a_run_whose_tasks_finish_is_status_0() {
        assert_eq!(status("finishes", "(i32.const 0)", 0, &[]), 0);
    }

    #[test]
    fn a_wasi_exit_is_its_own_status() {
        let exits = "(call $exit (i32.const 7)) (i32.const 0)";
        assert_eq!(status("exits", exits, 0, &[]), 7);
        assert_eq!(
            status("exits-first", "(i32.const 0)", 0, &[Turn::Exit(7)]),
            7
        );
    }

    #[test]
    fn a_trap_in_main_or_the_first_turn_is_status_2() {
        assert_eq!(status("traps", "(unreachable)", 0, &[]), 2);
        assert_eq!(status("traps-first", "(i32.const 0)", 0, &[Turn::Trap]), 2);
    }

    #[test]
    fn unclosed_resources_fail_only_a_successful_run() {
        assert_eq!(status("unclosed-run", "(i32.const 0)", 1, &[]), 1);
        let exits = "(call $exit (i32.const 4)) (i32.const 0)";
        assert_eq!(status("unclosed-failure", exits, 1, &[]), 4);
    }

    // A program may import sockets it never uses, as the command line's
    // compile does; one that calls them traps.
    #[test]
    fn a_program_that_calls_sockets_traps() {
        let imports =
            r#"(import "snail.runtime.native.socket" "start-read" (func $read (param i64)))"#;
        let unused = module_file("sockets-unused", &program(imports, "(i32.const 0)", 0, &[]));
        assert_eq!(run(&unused, &[]), 0);
        let called = "(call $read (i64.const 0)) (i32.const 0)";
        let file = module_file("sockets", &program(imports, called, 0, &[]));
        assert_eq!(run(&file, &[]), 2);
    }

    // The compiled compiler runs from its machine code, which says what it
    // imports only once it loads.
    #[test]
    fn a_precompiled_program_runs_as_its_module_does() {
        let precompiled = |name: &str, imports: &str, main: &str| {
            let source = module_file(name, &program(imports, main, 0, &[]));
            let output = source.replace(".wasm", ".cwasm");
            assert_eq!(precompile(&source, &output), 0);
            output
        };
        assert_eq!(
            run(
                &precompiled(
                    "precompiled-program",
                    "",
                    "(call $exit (i32.const 3)) (i32.const 0)"
                ),
                &[]
            ),
            3
        );
        let sockets =
            r#"(import "snail.runtime.native.socket" "start-read" (func $read (param i64)))"#;
        let called = precompiled(
            "precompiled-sockets",
            sockets,
            "(call $read (i64.const 0)) (i32.const 0)",
        );
        assert_eq!(run(&called, &[]), 2);
    }

    #[test]
    fn tasks_are_driven_until_none_is_live() {
        let file = module_file(
            "turns",
            &program(
                "",
                "(i32.const 0)",
                0,
                &[Turn::Answer(0), Turn::Answer(2), Turn::Answer(0)],
            ),
        );
        assert_eq!(run(&file, &[]), 0);
    }

    #[test]
    fn a_trapped_task_ends_driving_before_close() {
        let file = module_file(
            "trapped",
            &program(
                "",
                "(i32.const 0)",
                0,
                &[Turn::Answer(0), Turn::Trap, Turn::Answer(0)],
            ),
        );
        assert_eq!(run(&file, &[]), 1);
    }

    // A panic exits through WASI. In a task that ends the task, as a trap
    // does, so the run fails with 1 rather than ending with the exit's 7.
    #[test]
    fn a_task_that_exits_ends_driving_before_close() {
        let file = module_file(
            "exited",
            &program(
                "",
                "(i32.const 0)",
                0,
                &[Turn::Answer(0), Turn::Exit(7), Turn::Answer(0)],
            ),
        );
        assert_eq!(run(&file, &[]), 1);
    }

    // The first turn's answer is not read: driving turns again.
    #[test]
    fn tasks_waiting_on_tickets_end_the_run() {
        let file = module_file(
            "stuck",
            &program("", "(i32.const 0)", 0, &[Turn::Answer(0), Turn::Answer(-2)]),
        );
        assert_eq!(run(&file, &[]), 2);
    }

    #[test]
    fn imports_are_read_without_compiling() {
        let imports = r#"(import "snail.runtime.native.socket" "open" (func (result i32)))"#;
        let file = module_file("imports", &program(imports, "(i32.const 0)", 0, &[]));
        let read = program_imports(Path::new(&file)).unwrap();
        assert_eq!(
            read.into_iter().collect::<Vec<_>>(),
            ["snail.runtime.native.socket", "wasi_snapshot_preview1"]
        );
    }
}
