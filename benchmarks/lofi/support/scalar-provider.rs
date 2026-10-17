//! Native benchmark inputs. The campaign supplies immutable case configuration.
//! Black-box returns keep imported values opaque when LTO sees this provider
//! together with the guest, including builds with observation counters disabled.

use std::hint::black_box;
use std::io::{self, Write};
use std::sync::atomic::{AtomicI64, Ordering};

include!("case-config.rs");

// ---- Scalar inputs and optional validation counters ----

static BARRIERS: AtomicI64 = AtomicI64::new(0);

fn observe_barrier() {
    if OBSERVE_BARRIERS {
        BARRIERS.fetch_add(1, Ordering::Relaxed);
    }
}

#[unsafe(export_name = "input_i64")]
pub extern "C" fn input_i64(index: i32) -> i64 {
    black_box(INPUT_INTEGERS[index as usize])
}

#[unsafe(export_name = "input_f64")]
pub extern "C" fn input_f64(index: i32) -> f64 {
    black_box(INPUT_REALS[index as usize])
}

#[unsafe(export_name = "vector_length")]
pub extern "C" fn vector_length(index: i32) -> i64 {
    black_box(VECTOR_SIZES[index as usize])
}

#[unsafe(export_name = "vector_i64")]
pub extern "C" fn vector_i64(index: i32, element: i64) -> i64 {
    black_box(VECTOR_INTEGERS[(VECTOR_OFFSETS[index as usize] + element) as usize])
}

#[unsafe(export_name = "vector_f64")]
pub extern "C" fn vector_f64(index: i32, element: i64) -> f64 {
    black_box(VECTOR_REALS[(VECTOR_OFFSETS[index as usize] + element) as usize])
}

#[unsafe(export_name = "expected_length")]
pub extern "C" fn expected_length() -> i64 {
    black_box(EXPECTED_SIZE)
}

#[unsafe(export_name = "expected_i64")]
pub extern "C" fn expected_i64(index: i64) -> i64 {
    black_box(EXPECTED_INTEGERS[index as usize])
}

#[unsafe(export_name = "expected_f64")]
pub extern "C" fn expected_f64(index: i64) -> f64 {
    black_box(EXPECTED_REALS[index as usize])
}

#[unsafe(export_name = "tolerance")]
pub extern "C" fn tolerance() -> f64 {
    black_box(EXPECTED_TOLERANCE)
}

#[unsafe(export_name = "count")]
pub extern "C" fn count() -> i64 {
    black_box(CONFIGURED_COUNT)
}

#[unsafe(export_name = "hide_i64")]
pub extern "C" fn hide_i64(value: i64) -> i64 {
    observe_barrier();
    black_box(value)
}

#[unsafe(export_name = "hide_f64")]
pub extern "C" fn hide_f64(value: f64) -> f64 {
    observe_barrier();
    black_box(value)
}

#[unsafe(export_name = "barrier")]
pub extern "C" fn barrier() -> i32 {
    observe_barrier();
    black_box(1)
}

#[unsafe(no_mangle)]
pub extern "C" fn benchmark_barriers() -> i64 {
    BARRIERS.load(Ordering::Relaxed)
}

#[unsafe(no_mangle)]
pub extern "C" fn benchmark_reset_barriers() {
    BARRIERS.store(0, Ordering::Relaxed);
}

// ---- Diagnostic text remains part of the workload ----

#[unsafe(export_name = "write_character")]
pub extern "C" fn write_character(value: u32) {
    let mut bytes = [0; 4];
    let text = char::from_u32(value)
        .expect("Unicode scalar")
        .encode_utf8(&mut bytes);
    io::stdout()
        .lock()
        .write_all(text.as_bytes())
        .expect("stdout");
}

#[unsafe(export_name = "write_char")]
pub extern "C" fn write_char(value: u32) {
    write_character(value);
}

#[unsafe(export_name = "print_text")]
pub extern "C" fn print_text(index: i64) {
    print!("{}", DIAGNOSTIC_TEXT[index as usize]);
}

#[unsafe(export_name = "print_size")]
pub extern "C" fn print_size(index: i64, value: i64) {
    print!(
        "{}{value}{}",
        DIAGNOSTIC_PREFIX[index as usize], DIAGNOSTIC_SUFFIX[index as usize]
    );
}

#[unsafe(export_name = "print_construction")]
pub extern "C" fn print_construction(iterations: i64, depth: i64) {
    print!("Creating {iterations} trees of depth {depth}");
}
