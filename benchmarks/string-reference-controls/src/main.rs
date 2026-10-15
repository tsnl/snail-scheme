use r7rs_wasm_reference::{Datum, input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Four fresh byte buffers ----

// ZEROED selects an allocation policy at compilation, rather than adding a
// branch to each copy. Clearing a zeroed Vec keeps its initialized storage but
// lets the same complete append operations populate both policies safely.
// Source syntax alone does not establish that optimized zero writes survive.
fn fresh_bytes<const ZEROED: bool>(length: usize) -> Vec<u8> {
    if !ZEROED {
        return Vec::with_capacity(length);
    }
    let mut buffer = vec![0; length];
    buffer.clear();
    buffer
}

fn first_bytes<const ZEROED: bool>(old: &[u8]) -> Vec<u8> {
    let mut first = fresh_bytes::<ZEROED>(2 * old.len() + 9);
    first.extend_from_slice(b"123");
    first.extend_from_slice(old);
    first.extend_from_slice(b"456");
    first.extend_from_slice(old);
    first.extend_from_slice(b"789");
    first
}

fn copy_bytes<const ZEROED: bool>(source: &[u8]) -> Vec<u8> {
    let mut copy = fresh_bytes::<ZEROED>(source.len());
    copy.extend_from_slice(source);
    copy
}

fn append_bytes<const ZEROED: bool>(back: &[u8], front: &[u8]) -> Vec<u8> {
    let mut result = fresh_bytes::<ZEROED>(back.len() + front.len());
    result.extend_from_slice(back);
    result.extend_from_slice(front);
    result
}

fn grow_bytes<const ZEROED: bool>(old: Vec<u8>) -> Vec<u8> {
    let first = first_bytes::<ZEROED>(&old);
    drop(old); // The first Scheme assignment replaces the old root here.
    let middle = first.len() / 2;
    let back = copy_bytes::<ZEROED>(&first[middle..]);
    let front = copy_bytes::<ZEROED>(&first[..middle + 1]);
    let result = append_bytes::<ZEROED>(&back, &front);
    drop((first, back, front)); // All three survive until final construction.
    result
}

fn trial_bytes<const ZEROED: bool>(threshold: usize) -> Vec<u8> {
    let mut current = copy_bytes::<ZEROED>(b"abcdef");
    while current.len() <= threshold {
        current = grow_bytes::<ZEROED>(current);
    }
    current
}

fn run_bytes<const ZEROED: bool>(threshold: usize) -> usize {
    let mut length = 0;
    for _ in 0..10 {
        length = black_box(trial_bytes::<ZEROED>(threshold)).len();
    }
    length
}

// ---- Four fresh u32 buffers ----

const WORD_SEED: &[u32] = &[97, 98, 99, 100, 101, 102];

fn fresh_words<const ZEROED: bool>(length: usize) -> Vec<u32> {
    if !ZEROED {
        return Vec::with_capacity(length);
    }
    let mut buffer = vec![0; length];
    buffer.clear();
    buffer
}

fn first_words<const ZEROED: bool>(old: &[u32]) -> Vec<u32> {
    let mut first = fresh_words::<ZEROED>(2 * old.len() + 9);
    first.extend_from_slice(&[49, 50, 51]);
    first.extend_from_slice(old);
    first.extend_from_slice(&[52, 53, 54]);
    first.extend_from_slice(old);
    first.extend_from_slice(&[55, 56, 57]);
    first
}

fn copy_words<const ZEROED: bool>(source: &[u32]) -> Vec<u32> {
    let mut copy = fresh_words::<ZEROED>(source.len());
    copy.extend_from_slice(source);
    copy
}

fn append_words<const ZEROED: bool>(back: &[u32], front: &[u32]) -> Vec<u32> {
    let mut result = fresh_words::<ZEROED>(back.len() + front.len());
    result.extend_from_slice(back);
    result.extend_from_slice(front);
    result
}

fn grow_words<const ZEROED: bool>(old: Vec<u32>) -> Vec<u32> {
    let first = first_words::<ZEROED>(&old);
    drop(old);
    let middle = first.len() / 2;
    let back = copy_words::<ZEROED>(&first[middle..]);
    let front = copy_words::<ZEROED>(&first[..middle + 1]);
    let result = append_words::<ZEROED>(&back, &front);
    drop((first, back, front));
    result
}

fn trial_words<const ZEROED: bool>(threshold: usize) -> Vec<u32> {
    let mut current = copy_words::<ZEROED>(WORD_SEED);
    while current.len() <= threshold {
        current = grow_words::<ZEROED>(current);
    }
    current
}

fn run_words<const ZEROED: bool>(threshold: usize) -> usize {
    let mut length = 0;
    for _ in 0..10 {
        length = black_box(trial_words::<ZEROED>(threshold)).len();
    }
    length
}

// ---- Separate complete-payload audits ----

// These diagnostics retain the intermediate buffers for observation. They run
// after report captures the clock, and therefore have a different peak lifetime
// from the timed grow. Timed grows return only their final buffer.
fn audit_bytes<const ZEROED: bool>(threshold: usize) {
    let first = first_bytes::<ZEROED>(b"abcdef");
    let middle = first.len() / 2;
    let back = copy_bytes::<ZEROED>(&first[middle..]);
    let front = copy_bytes::<ZEROED>(&first[..middle + 1]);
    let result = append_bytes::<ZEROED>(&back, &front);
    let trial = trial_bytes::<ZEROED>(threshold);
    println!(
        "Audit: {{\"first\":{first:?},\"back\":{back:?},\"front\":{front:?},\"final\":{result:?},\"trial\":{trial:?}}}"
    );
}

fn audit_words<const ZEROED: bool>(threshold: usize) {
    let first = first_words::<ZEROED>(WORD_SEED);
    let middle = first.len() / 2;
    let back = copy_words::<ZEROED>(&first[middle..]);
    let front = copy_words::<ZEROED>(&first[..middle + 1]);
    let result = append_words::<ZEROED>(&back, &front);
    let trial = trial_words::<ZEROED>(threshold);
    println!(
        "Audit: {{\"first\":{first:?},\"back\":{back:?},\"front\":{front:?},\"final\":{result:?},\"trial\":{trial:?}}}"
    );
}

// ---- Benchmark driver ----

fn benchmark_bytes<const ZEROED: bool>(count: usize, n: usize, expected: &Datum, audit: bool) {
    let name = if ZEROED {
        "string-byte-zeroed"
    } else {
        "string-byte-four-buffer"
    };
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run_bytes::<ZEROED>(black_box(n)));
    }
    assert_eq!(result, expected.number());
    report(name, count, start, result);
    if audit {
        audit_bytes::<ZEROED>(n);
    }
}

fn benchmark_words<const ZEROED: bool>(count: usize, n: usize, expected: &Datum, audit: bool) {
    let name = if ZEROED {
        "string-u32-zeroed"
    } else {
        "string-u32-four-buffer"
    };
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run_words::<ZEROED>(black_box(n)));
    }
    assert_eq!(result, expected.number());
    report(name, count, start, result);
    if audit {
        audit_words::<ZEROED>(n);
    }
}

// This bounded exhaustive CLI dispatch keeps all four controls visible. The
// canonical57 sources, binaries and suite selection are never modified.
fn main() -> std::io::Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    assert!(args.len() == 1 || (args.len() == 2 && args[1] == "--audit"));
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].number());
    let audit = args.len() == 2;
    match args[0].as_str() {
        "byte" => benchmark_bytes::<false>(count, n, &values[2], audit),
        "u32" => benchmark_words::<false>(count, n, &values[2], audit),
        "byte-zeroed" => benchmark_bytes::<true>(count, n, &values[2], audit),
        "u32-zeroed" => benchmark_words::<true>(count, n, &values[2], audit),
        _ => panic!("expected byte, u32, byte-zeroed or u32-zeroed"),
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    // Derived from the original Scheme operations, including the duplicated5.
    const FIRST: &[u8] = b"123abcdef456abcdef789";
    const BACK: &[u8] = b"56abcdef789";
    const FRONT: &[u8] = b"123abcdef45";
    const FINAL: &[u8] = b"56abcdef789123abcdef45";

    #[test]
    fn complete_byte_stages_and_timed_grow() {
        let first = first_bytes::<false>(b"abcdef");
        let back = copy_bytes::<false>(&first[first.len() / 2..]);
        let front = copy_bytes::<false>(&first[..first.len() / 2 + 1]);
        assert_eq!((&first[..], &back[..], &front[..]), (FIRST, BACK, FRONT));
        assert_eq!(append_bytes::<false>(&back, &front), FINAL);
        assert_eq!(grow_bytes::<false>(b"abcdef".to_vec()), FINAL);
        assert_eq!(grow_bytes::<true>(b"abcdef".to_vec()), FINAL);
    }

    #[test]
    fn complete_word_stages_and_timed_grow() {
        let first = first_words::<false>(WORD_SEED);
        let back = copy_words::<false>(&first[first.len() / 2..]);
        let front = copy_words::<false>(&first[..first.len() / 2 + 1]);
        assert!(
            first
                .iter()
                .copied()
                .eq(FIRST.iter().map(|&b| u32::from(b)))
        );
        assert!(back.iter().copied().eq(BACK.iter().map(|&b| u32::from(b))));
        assert!(
            front
                .iter()
                .copied()
                .eq(FRONT.iter().map(|&b| u32::from(b)))
        );
        let expected: Vec<_> = FINAL.iter().map(|&b| u32::from(b)).collect();
        assert_eq!(append_words::<false>(&back, &front), expected);
        assert_eq!(grow_words::<false>(WORD_SEED.to_vec()), expected);
        assert_eq!(grow_words::<true>(WORD_SEED.to_vec()), expected);
    }

    #[test]
    fn source_and_four_byte_buffers_are_independent() {
        let mut old = b"abcdef".to_vec();
        let mut first = first_bytes::<false>(&old);
        let mut back = copy_bytes::<false>(&first[first.len() / 2..]);
        let mut front = copy_bytes::<false>(&first[..first.len() / 2 + 1]);
        let mut result = append_bytes::<false>(&back, &front);
        old[0] = b'x';
        assert_eq!(first, FIRST);
        first[0] = b'x';
        assert_eq!((&back[..], &front[..]), (BACK, FRONT));
        back[0] = b'x';
        front[0] = b'y';
        assert_eq!(result, FINAL);
        result[0] = b'z';
        assert_eq!(
            (first[0], back[0], front[0], old[0]),
            (b'x', b'x', b'y', b'x')
        );
    }

    #[test]
    fn source_and_four_word_buffers_are_independent() {
        let mut old = WORD_SEED.to_vec();
        let mut first = first_words::<true>(&old);
        let mut back = copy_words::<true>(&first[first.len() / 2..]);
        let mut front = copy_words::<true>(&first[..first.len() / 2 + 1]);
        let mut result = append_words::<true>(&back, &front);
        let original = result.clone();
        old[0] = 0x1f600;
        assert_eq!(first[3], 97);
        let middle = first.len() / 2;
        first[middle] = 0x1f601;
        assert_eq!((back[0], *front.last().unwrap()), (53, 53));
        back[0] = 0x1f602;
        front[0] = 0x1f603;
        assert_eq!(result, original);
        result[0] = 0x1f604;
        assert_eq!((back[0], front[0]), (0x1f602, 0x1f603));
    }

    #[test]
    fn threshold_edges_and_complete_trial_contents() {
        for (threshold, length) in [(0, 6), (5, 6), (6, 22), (21, 22), (22, 54), (30, 54)] {
            let bytes = trial_bytes::<false>(threshold);
            let words = trial_words::<false>(threshold);
            assert_eq!(bytes.len(), length);
            assert!(
                words
                    .iter()
                    .copied()
                    .eq(bytes.iter().map(|&b| u32::from(b)))
            );
            assert_eq!(trial_bytes::<true>(threshold), bytes);
            assert_eq!(trial_words::<true>(threshold), words);
        }
        assert_eq!(run_bytes::<false>(30), 54);
        assert_eq!(run_words::<true>(30), 54);
    }
}
