use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Descending summation ----

// Keep the descending arithmetic loop: a closed-form LLVM reduction would
// change this workload from linear to constant time.
fn run(mut n: i64) -> i64 {
    let mut sum = 0;
    while n >= 0 {
        sum = black_box(sum + n);
        n -= 1;
    }
    sum
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n, expected) = (values[0].number(), values[1].integer(), values[2].integer());
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run(black_box(n)));
    }
    assert_eq!(result, expected);
    report("sum", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn small_input() {
        assert_eq!(run(10), 55);
    }
}
