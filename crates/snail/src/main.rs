//! `snail`: `snail-scheme`'s compiled Wasm on an embedded wasmtime engine.
//!
//! The subcommands are internal to the build driver and the tests:
//!
//! - `snail run-wasm PROGRAM ARGUMENT ...` runs a compiled program, one
//!   linked module, as host/native/run-snail.mjs does on Node, when it
//!   needs no sockets or processes (`program.rs`, with `links.rs` for the
//!   files it links and `modules.rs` for the modules it loads). The
//!   command line, `build/bootstrap/snail-scheme.wasm`, is one such program.
//! - `snail link INPUT RUNTIME OUTPUT` assembles the compiler's text and
//!   links the scalar runtime, using the same backend as compiled tools:
//!   the bootstrap links the command line with it.
//!
//! `engine.rs` holds what every subcommand shares: the engine's
//! configuration, the WASI context, and how a failure is told.

use std::process::ExitCode;

mod assemble;
mod async_files;
mod engine;
mod links;
mod modules;
mod program;

// ---- Command line ----

const USAGE: &str = "usage: snail run-wasm PROGRAM [ARGUMENT ...]
       snail link INPUT.wat RUNTIME.wasm OUTPUT.wasm";

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().collect();
    ExitCode::from(on_large_stack(move || dispatch(&arguments)))
}

fn dispatch(arguments: &[String]) -> u8 {
    match arguments {
        [_, command, input, runtime, output] if command == "link" => {
            assemble::run(input, output, runtime)
        }
        [_, command, program, rest @ ..] if command == "run-wasm" => program::run(program, rest),
        _ => {
            eprintln!("{USAGE}");
            2
        }
    }
}

// ---- Stack ----

// Compiler passes may recurse with source syntax depth. `snail-scheme` loops
// use Wasm tail calls and do not consume one native frame per iteration.
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
