// Derived from William D. Clinger's 2007 string/bytevector benchmark.
// Copyright 2007 William D Clinger.
// Permission to copy this software, in whole or in part, to use this software
// for any lawful purpose, and to redistribute this software is granted subject
// to the restriction that all copies include this copyright notice in full.
use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Original random byte stream ----

struct Random {
    x: usize,
}
impl Random {
    fn random14(&mut self, n: usize) -> usize {
        self.x = (701 * self.x + 743483) % 524288;
        (self.x / 8) % n
    }
    fn random(&mut self, n: usize) -> usize {
        if n < 16384 {
            return self.random14(n);
        }
        let (mut q, mut r) = (n / 16384, self.random14(16384));
        while q != 0 {
            q /= 16384;
            r = 16384 * r + self.random14(16384);
        }
        r % n
    }
    fn bytevector(&mut self, maximum: usize) -> Vec<u8> {
        let length = self.random(maximum);
        (0..length).map(|_| self.random(128) as u8).collect()
    }
}

// ---- UTF-8 allocation and round-trip comparisons ----

fn roundtrip(bytes: Vec<u8>) -> bool {
    // Conversion borrows its source and allocates a distinct output buffer.
    let first = std::str::from_utf8(&bytes).unwrap().to_owned();
    let copied = first.as_bytes().to_vec();
    let second = std::str::from_utf8(&copied).unwrap().to_owned();
    first == second
}

fn run(tests: usize, maximum: usize) -> usize {
    let mut random = Random { x: 1 };
    let mut failed = usize::from(!roundtrip(random.bytevector(10)));
    for _ in 0..tests {
        failed += usize::from(!roundtrip(random.bytevector(maximum)));
    }
    failed
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, tests, maximum) = (values[0].number(), values[1].number(), values[2].number());
    let (start, mut failed) = (Instant::now(), 0);
    for _ in 0..count {
        failed += black_box(run(black_box(tests), black_box(maximum)));
    }
    assert_eq!(failed, values[3].number());
    report("bv2string", count, start, failed);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn full_ascii_range_and_original_random_sequence() {
        assert!(roundtrip((0..128).collect()));
        let mut random = Random { x: 1 };
        assert_eq!(random.bytevector(10), vec![42, 16, 6, 43, 36, 0, 21]);
        assert_eq!(run(10, 20), 0);
    }
}
