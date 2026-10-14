use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- String growth and overlapping rotation ----

fn grow(s: &str) -> String {
    let joined = format!("123{s}456{s}789");
    let middle = joined.len() / 2;
    let back = joined[middle..].to_owned();
    let front = joined[..middle + 1].to_owned();
    back + &front
}

fn trial(n: usize) -> String {
    let mut s = "abcdef".to_owned();
    while s.len() <= n {
        s = grow(&s);
    }
    s
}

fn run(n: usize) -> usize {
    let mut length = 0;
    for _ in 0..10 {
        length = black_box(trial(n)).len();
    }
    length
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].number());
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run(black_box(n)));
    }
    assert_eq!(result, values[2].number());
    report("string", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_overlapping_rotation() {
        assert_eq!(grow("abcdef"), "56abcdef789123abcdef45");
        assert_eq!(trial(0), "abcdef");
        assert_eq!(run(30), 54);
    }
}
