//! Stage 0's file boundary for the same assembler/linker compiled tools use.

use snail_core_support::assembler::{assemble, link};

pub fn run(input: &str, output: &str, runtime: Option<&str>) -> u8 {
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
    runtime: Option<&str>,
) -> Result<(), Box<dyn std::error::Error>> {
    let text = std::fs::read_to_string(input)?;
    let module = match runtime {
        Some(path) => link(&text, &std::fs::read(path)?)?,
        None => assemble(&text)?,
    };
    Ok(std::fs::write(output, module)?)
}
