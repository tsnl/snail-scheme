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

#[unsafe(export_name = "snail:text/upcase")]
pub extern "C" fn upcase(code: u32) -> u32 {
    unicode::uppercase(character(code)) as u32
}

#[unsafe(export_name = "snail:text/foldcase")]
pub extern "C" fn foldcase(code: u32) -> u32 {
    unicode::fold_character(character(code)) as u32
}

#[unsafe(export_name = "snail:text/lowercase")]
pub extern "C" fn lowercase(code: u32) -> i32 {
    i32::from(character(code).is_lowercase())
}

#[unsafe(export_name = "snail:text/alphabetic")]
pub extern "C" fn alphabetic(code: u32) -> i32 {
    i32::from(character(code).is_alphabetic())
}

#[unsafe(export_name = "snail:text/numeric")]
pub extern "C" fn numeric(code: u32) -> i32 {
    i32::from(unicode::digit_value(character(code)).is_some())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simple_case_mapping_preserves_single_scalars() {
        assert_eq!(upcase('λ' as u32), 'Λ' as u32);
        assert_eq!(upcase('ß' as u32), 'ß' as u32);
        assert_eq!(foldcase('ς' as u32), 'σ' as u32);
        assert_eq!(foldcase('ſ' as u32), 's' as u32);
        assert_eq!(lowercase('λ' as u32), 1);
        assert_eq!(lowercase('Λ' as u32), 0);
        assert_eq!(lowercase('😀' as u32), 0);
    }
}
