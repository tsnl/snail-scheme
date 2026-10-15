use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Recursive Fibonacci ----

fn run(n: f64) -> f64 {
    if n < 2.0 {
        n
    } else {
        run(n - 1.0) + run(n - 2.0)
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n, expected) = (values[0].number(), values[1].real(), values[2].real());
    let (start, mut result) = (Instant::now(), 0.0);
    for _ in 0..count {
        result = black_box(run(black_box(n)));
    }
    assert_eq!(result, expected);
    report("fibfp", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn small_input() {
        assert_eq!(run(10.0), 55.0);
    }
}
