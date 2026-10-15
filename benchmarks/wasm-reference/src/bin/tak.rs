use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Takeuchi recursion ----

fn tak(x: i64, y: i64, z: i64) -> i64 {
    if y >= x {
        z
    } else {
        tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y))
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, x, y, z) = (
        values[0].number(),
        values[1].integer(),
        values[2].integer(),
        values[3].integer(),
    );
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(tak(black_box(x), black_box(y), black_box(z)));
    }
    assert_eq!(result, values[4].integer());
    report("tak", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn base_and_nested_calls() {
        assert_eq!(tak(1, 2, 3), 3);
        assert_eq!(tak(6, 4, 2), 3);
    }
}
