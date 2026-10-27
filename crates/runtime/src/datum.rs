//! Synchronous real-number conversion. Snail-Core parses integers and ratios;
//! Rust supplies correctly rounded parsing and float formatting.

use std::cell::{Cell, RefCell};

// ---- Conversion scratch ----

// A runtime instance owns these results. The private Snail-Core wrappers read a
// successful parse or copy the entire formatted text before returning; neither
// operation invokes user code. No result needs a handle or resource cleanup.
thread_local! {
    static PARSED_REAL: Cell<f64> = const { Cell::new(0.0) };
    static REAL_TEXT: RefCell<String> = const { RefCell::new(String::new()) };
}

fn checked<T>(result: Result<T, String>) -> T {
    result.unwrap_or_else(|error| {
        crate::io::close_all();
        crate::fail_message(&error)
    })
}

// ---- Parsing ----

#[unsafe(export_name = "snail:datum/parse-real")]
pub extern "C" fn parse_real(count: u32) -> i32 {
    let text = checked(crate::io::staged_text(count));
    match crate::parse_float(&text) {
        Some(value) => {
            PARSED_REAL.set(value);
            1
        }
        None => 0,
    }
}

// Read only after parse-real returned 1. NaN is a successful numeric result,
// so success is a separate scalar rather than a sentinel floating-point value.
#[unsafe(export_name = "snail:datum/parsed-real")]
pub extern "C" fn parsed_real() -> f64 {
    PARSED_REAL.get()
}

// ---- Formatting ----

#[unsafe(export_name = "snail:datum/real-text")]
pub extern "C" fn real_text(value: f64) -> u32 {
    REAL_TEXT.with_borrow_mut(|text| {
        *text = crate::float_text(value);
        // A formatted F64 is bounded ASCII, so bytes are scalars and its
        // length fits the signed I32 index used by Snail-Core.
        text.len() as u32
    })
}

#[unsafe(export_name = "snail:datum/text-character")]
pub extern "C" fn text_character(index: u32) -> u32 {
    checked(REAL_TEXT.with_borrow(|text| {
        text.as_bytes()
            .get(index as usize)
            .copied()
            .map(u32::from)
            .ok_or_else(|| "real text character index out of range".into())
    }))
}

#[unsafe(export_name = "snail:datum/whitespace")]
pub extern "C" fn whitespace(code: u32) -> i32 {
    i32::from(
        checked(char::from_u32(code).ok_or_else(|| "invalid Unicode scalar".into()))
            .is_whitespace(),
    )
}
