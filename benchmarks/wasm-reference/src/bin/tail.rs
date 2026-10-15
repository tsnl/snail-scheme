use r7rs_wasm_reference::{input, report};
use std::fs::{File, remove_file};
use std::hint::black_box;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::time::Instant;

// ---- Read every line before reversing the output ----

fn reverse_lines(input: &str, output: &str) -> io::Result<()> {
    let port = BufReader::new(File::open(input)?);
    if std::path::Path::new(output).exists() {
        remove_file(output)?;
    }
    let mut out = BufWriter::new(File::create(output)?);
    let lines: Vec<_> = port.lines().collect::<io::Result<_>>()?;
    for line in lines.iter().rev() {
        writeln!(out, "{line}")?;
    }
    out.flush()
}

// ---- Benchmark driver ----

fn main() -> io::Result<()> {
    let values = input()?;
    let (count, source, target) = (values[0].number(), values[1].atom(), values[2].atom());
    let start = Instant::now();
    for _ in 0..count {
        reverse_lines(black_box(source), black_box(target))?;
    }
    report("tail", count, start, "ignored");
    Ok(())
}
