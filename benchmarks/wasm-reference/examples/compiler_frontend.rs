// A one-pass intermediate probe; this is not the canonical Compiler workload.
#[path = "../src/compiler.rs"]
mod compiler;

fn main() {
    compiler::frontend_main();
}
