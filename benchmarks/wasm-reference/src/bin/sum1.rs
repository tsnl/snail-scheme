use r7rs_wasm_reference::{input, read_char, report};
use std::fs::File;
use std::hint::black_box;
use std::io::{self, BufReader};
use std::time::Instant;

// ---- Streaming numeric input ----

fn read_number(port: &mut BufReader<File>) -> io::Result<Option<f64>> {
    let mut text = String::new();
    while let Some(character) = read_char(port)? {
        if character.is_whitespace() {
            if !text.is_empty() {
                break;
            }
        } else {
            text.push(character);
        }
    }
    Ok(if text.is_empty() {
        None
    } else {
        Some(text.parse().expect("numeric file datum"))
    })
}

fn sum_file(filename: &str) -> io::Result<f64> {
    let (mut port, mut sum) = (BufReader::new(File::open(filename)?), 0.0);
    while let Some(value) = read_number(&mut port)? {
        sum += value;
    }
    Ok(sum)
}

// ---- Benchmark driver ----

fn main() -> io::Result<()> {
    let values = input()?;
    let (count, filename, expected) = (values[0].number(), values[1].atom(), values[2].real());
    let (start, mut result) = (Instant::now(), 0.0);
    for _ in 0..count {
        result = black_box(sum_file(black_box(filename))?);
    }
    assert!((result - expected).abs() <= 1e-9);
    report("sum1", count, start, result);
    Ok(())
}
