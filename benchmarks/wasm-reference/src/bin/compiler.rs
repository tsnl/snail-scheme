#[path = "../compiler.rs"]
mod compiler;

fn main() -> std::io::Result<()> {
    compiler::benchmark_main()
}
