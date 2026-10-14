use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Ackermann recursion ----

// The outer call is a tail call in Scheme. Reuse this frame for that call;
// the inner Ackermann computation still recurses and performs the same work.
fn ack(mut m: i64, mut n: i64) -> i64 {
    while m != 0 {
        n = if n == 0 { 1 } else { ack(m, n - 1) };
        m -= 1;
    }
    n + 1
}

// The default native Wasm stack overflows for the canonical (3,12) input.
// This optional variant keeps precisely the pending outer calls on the heap;
// it performs the recurrence rather than replacing it with a closed formula.
fn heap_frames(mut m: i64, mut n: i64) -> i64 {
    let mut pending = Vec::new();
    loop {
        match (m, n) {
            (0, _) => {
                n += 1;
                match pending.pop() {
                    Some(next) => m = next,
                    None => return n,
                }
            }
            (_, 0) => {
                m -= 1;
                n = 1;
            }
            _ => {
                pending.push(m - 1);
                n -= 1;
            }
        }
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, m, n) = (values[0].number(), values[1].integer(), values[2].integer());
    let (start, mut result) = (Instant::now(), 0);
    let explicit = std::env::args().any(|argument| argument == "--heap-frames");
    for _ in 0..count {
        result = black_box(if explicit {
            heap_frames(black_box(m), black_box(n))
        } else {
            ack(black_box(m), black_box(n))
        });
    }
    assert_eq!(result, values[3].integer());
    report("ack", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn small_inputs() {
        assert_eq!(ack(0, 3), 4);
        assert_eq!(ack(3, 4), 125);
    }

    #[test]
    fn pending_calls_match_recursive_semantics() {
        for m in 0..=3 {
            for n in 0..=5 {
                assert_eq!(heap_frames(m, n), ack(m, n));
            }
        }
        assert_eq!(heap_frames(3, 12), 32765);
    }
}
