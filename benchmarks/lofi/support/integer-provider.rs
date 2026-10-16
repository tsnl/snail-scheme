//! Input transport owns decimal bytes; the guest performs all arithmetic.

use std::io::{self, Write};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU64, Ordering};

include!("integer-config.rs");

struct Input {
    values: [i64; 3],
    expected: Vec<String>,
}

static INPUT: OnceLock<Input> = OnceLock::new();
static BARRIERS: AtomicU64 = AtomicU64::new(0);

// ---- Exact decimal fixtures become owned, checked input ----

fn parse_input(text: &str) -> (i64, Input) {
    let mut lines = text.lines();
    let header: Vec<i64> = lines
        .next()
        .expect("input header")
        .split_whitespace()
        .map(|part| part.parse().expect("integer input"))
        .collect();
    assert_eq!(header.len(), 5);
    let expected: Vec<String> = lines.map(str::to_owned).collect();
    assert_eq!(i64::try_from(expected.len()).unwrap(), header[4]);
    (
        header[0],
        Input {
            values: [header[1], header[2], header[3]],
            expected,
        },
    )
}

/// The entry owns the UTF-8 pathname until this call returns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn benchmark_load_input(path: *const u8, length: usize) -> i64 {
    let path = std::str::from_utf8(unsafe { std::slice::from_raw_parts(path, length) }).unwrap();
    let text = std::fs::read_to_string(path).expect("decimal input fixture");
    let (count, input) = parse_input(&text);
    assert!(INPUT.set(input).is_ok(), "input initialized once");
    count
}

// Input remains owned until process exit. Its strings never enter guest GC data.
// This ownership is outside all workload clocks and avoids foreign raw pointers.
fn input() -> &'static Input {
    INPUT.get().expect("initialized decimal fixture")
}

#[unsafe(export_name = "input_i64")]
pub extern "C" fn input_i64(index: i32) -> i64 {
    input().values[index as usize]
}

#[unsafe(export_name = "expected_count")]
pub extern "C" fn expected_count() -> i64 {
    input().expected.len() as i64
}

#[unsafe(export_name = "expected_length")]
pub extern "C" fn expected_length(index: i64) -> i64 {
    input().expected[index as usize].len() as i64
}

#[unsafe(export_name = "expected_character")]
pub extern "C" fn expected_character(index: i64, at: i64) -> u32 {
    input().expected[index as usize].as_bytes()[at as usize] as u32
}

#[unsafe(export_name = "hide_i64")]
pub extern "C" fn hide_i64(value: i64) -> i64 {
    if OBSERVE_BARRIERS {
        BARRIERS.fetch_add(1, Ordering::Relaxed);
    }
    value
}

#[unsafe(no_mangle)]
pub extern "C" fn barrier_count() -> u64 {
    BARRIERS.load(Ordering::Relaxed)
}

#[unsafe(export_name = "emit_character")]
pub extern "C" fn emit_character(scalar: u32) {
    assert!(scalar < 128);
    io::stdout()
        .lock()
        .write_all(&[scalar as u8])
        .expect("stdout");
}
