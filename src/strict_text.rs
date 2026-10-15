//! Unicode scalar services with identical C signatures on Wasm and native.
//! These calls retain no Scheme values, roots or callback state. Malformed raw
//! scalars take the ordinary terminal cleanup path before reporting an error.

use crate::unicode;

// ---- Scalar validation precedes Unicode property and casing operations ----

fn character(code: u32) -> char {
    char::from_u32(code).unwrap_or_else(|| {
        crate::strict_io::close_all();
        crate::fail_message("invalid Unicode scalar")
    })
}

#[unsafe(export_name = "snail:text/downcase")]
pub extern "C" fn downcase(code: u32) -> u32 {
    unicode::lowercase(character(code)) as u32
}

#[unsafe(export_name = "snail:text/alphabetic")]
pub extern "C" fn alphabetic(code: u32) -> i32 {
    i32::from(character(code).is_alphabetic())
}

#[unsafe(export_name = "snail:text/numeric")]
pub extern "C" fn numeric(code: u32) -> i32 {
    i32::from(unicode::digit_value(character(code)).is_some())
}
