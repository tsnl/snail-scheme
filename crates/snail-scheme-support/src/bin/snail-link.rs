//! Stage 0's linker: `snail-link INPUT.wat RUNTIME.wasm OUTPUT.wasm`
//! assembles the compiler's text and fuses it with the scalar runtime, as
//! the command line does for every program it builds once it exists. The
//! bootstrap links the command line itself with this.

use std::process::ExitCode;

use snail_scheme_support::assembler::link;

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().collect();
    let [_, input, runtime, output] = arguments.as_slice() else {
        eprintln!("usage: snail-link INPUT.wat RUNTIME.wasm OUTPUT.wasm");
        return ExitCode::from(2);
    };
    match write_module(input, runtime, output) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("snail-link: {error}");
            ExitCode::from(2)
        }
    }
}

fn write_module(
    input: &str,
    runtime: &str,
    output: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let text = std::fs::read_to_string(input)?;
    let module = link(&text, &std::fs::read(runtime)?)?;
    Ok(std::fs::write(output, module)?)
}
