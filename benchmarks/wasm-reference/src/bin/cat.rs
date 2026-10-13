use r7rs_wasm_reference::{input, read_char, report};
use std::fs::{File, remove_file};
use std::hint::black_box;
use std::io::{self, BufReader, BufWriter, Write};
use std::time::Instant;

// ---- Character copy ----

fn copy_characters(input: &str, output: &str) -> io::Result<()> {
    if std::fs::exists(output)? {
        remove_file(output)?;
    }
    let mut input = BufReader::new(File::open(input)?);
    let mut output = BufWriter::new(File::create(output)?);
    let mut encoded = [0; 4];
    while let Some(character) = read_char(&mut input)? {
        output.write_all(character.encode_utf8(&mut encoded).as_bytes())?;
    }
    output.flush()
}

// ---- Benchmark driver ----

fn main() -> io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let start = Instant::now();
    for _ in 0..count {
        copy_characters(black_box(values[1].atom()), black_box(values[2].atom()))?;
    }
    report("cat", count, start, "copied");
    Ok(())
}
