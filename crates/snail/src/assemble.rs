//! Stage 0's file boundary for the linker compiled tools use: the
//! compiler's text, assembled and fused with the scalar runtime.

use snail_scheme_support::assembler::link;

pub fn run(input: &str, output: &str, runtime: &str) -> u8 {
    match write_module(input, output, runtime) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("snail: {error}");
            2
        }
    }
}

fn write_module(
    input: &str,
    output: &str,
    runtime: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let text = std::fs::read_to_string(input)?;
    let module = link(&text, &std::fs::read(runtime)?)?;
    Ok(std::fs::write(output, module)?)
}
