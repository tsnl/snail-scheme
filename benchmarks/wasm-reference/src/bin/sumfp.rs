use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Descending summation ----

fn run(mut n: f64) -> f64 {
    let mut sum = 0.0;
    while n >= 0.0 {
        sum += n;
        n -= 1.0;
    }
    sum
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
    report("sumfp", count, start, result);
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
