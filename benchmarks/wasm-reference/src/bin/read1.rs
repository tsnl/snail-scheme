use r7rs_wasm_reference::{Datum, Reader, input, report};
use std::fs;
use std::hint::black_box;
use std::time::Instant;

// ---- File datum reading ----

// Rust buffers the file text, then parses and releases one datum at a time.
// Parsed earlier datums do not remain live until the end of the file.
fn read_file(filename: &str) -> std::io::Result<Datum> {
    let text = fs::read_to_string(filename)?;
    let mut reader = Reader::new(&text);
    let mut result = Datum::Atom("#f".to_owned());
    while let Some(value) = reader.read() {
        result = value;
    }
    Ok(result)
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, filename) = (values[0].number(), values[1].atom());
    let (start, mut result) = (Instant::now(), Datum::Atom("#f".to_owned()));
    for _ in 0..count {
        result = black_box(read_file(black_box(filename))?);
    }
    assert_eq!(result, values[2]);
    report("read1", count, start, &result);
    Ok(())
}
