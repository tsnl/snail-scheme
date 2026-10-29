//! `snail`: Snail-Core's compiled Wasm on an embedded wasmtime engine.
//!
//! The subcommands are internal to the build driver and the tests:
//!
//! - `snail run-compiler MODULE ARGUMENT ...` runs the compiled compiler,
//!   `build/compiler/snailc.wasm`, through its reactor protocol
//!   (`compiler.rs`).
//! - `snail precompile MODULE OUTPUT` writes Cranelift's machine code for a
//!   module as a `.cwasm` file, which `run-compiler` loads in place of
//!   compiling the module again (`engine.rs`).
//! - `snail run-wasm PROGRAM ARGUMENT ...` runs a compiled program, one
//!   linked module or a per-library build's modules.json, as
//!   host/native/run-snail.mjs does on Node, when it needs no sockets or
//!   processes (`program.rs`, with `links.rs` for the files it links and
//!   `modules.rs` for linking modules).
//! - `snail imports PROGRAM` lists the modules a program imports from, so
//!   the build driver can tell whether `run-wasm` runs it (`program.rs`).
//!
//! `engine.rs` holds what every subcommand shares: the engine's
//! configuration, loading a module, the WASI context, and how a failure
//! is told.

use std::process::ExitCode;

mod compiler;
mod engine;
mod links;
mod modules;
mod program;

// ---- Command line ----

const USAGE: &str = "usage: snail run-compiler MODULE [ARGUMENT ...]
       snail precompile MODULE OUTPUT
       snail run-wasm PROGRAM [ARGUMENT ...]
       snail imports PROGRAM";

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().collect();
    ExitCode::from(on_large_stack(move || dispatch(&arguments)))
}

fn dispatch(arguments: &[String]) -> u8 {
    match arguments {
        [_, command, module, rest @ ..] if command == "run-compiler" => compiler::run(module, rest),
        [_, command, module, output] if command == "precompile" => {
            engine::precompile(module, output)
        }
        [_, command, program, rest @ ..] if command == "run-wasm" => program::run(program, rest),
        [_, command, program] if command == "imports" => program::imports(program),
        _ => {
            eprintln!("{USAGE}");
            2
        }
    }
}

// ---- Stack ----

// The compiler recurses as deeply as the syntax it reads, and a Snail-Core
// loop is a tail call, so a deep stack is the only limit a program meets.
// Wasm runs on the calling thread's native stack, which must hold the Wasm
// limit (engine::WASM_STACK) and the host frames beneath it, so every
// subcommand runs on a thread whose stack is larger than the limit.
const THREAD_STACK: usize = 96 << 20;

fn on_large_stack(run: impl FnOnce() -> u8 + Send + 'static) -> u8 {
    let thread = std::thread::Builder::new()
        .stack_size(THREAD_STACK)
        .spawn(run);
    thread
        .expect("snail: cannot start the Wasm thread")
        .join()
        .unwrap_or(2)
}
