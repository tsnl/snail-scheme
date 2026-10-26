//! Unicode scalar services with scalar C signatures for Wasm.
//! These calls retain no Lofi values, roots or callback state. Malformed raw
//! scalars take the ordinary terminal cleanup path before reporting an error.

use crate::unicode;

// ---- Scalar validation precedes Unicode property and casing operations ----

fn character(code: u32) -> char {
    char::from_u32(code).unwrap_or_else(|| {
        crate::io::close_all();
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

#[unsafe(export_name = "snail:text/full-fold-length")]
pub extern "C" fn full_fold_length(code: u32) -> u32 {
    unicode::full_fold(character(code)).len as u32
}

#[unsafe(export_name = "snail:text/full-fold-scalar")]
pub extern "C" fn full_fold_scalar(code: u32, index: u32) -> u32 {
    let folded = unicode::full_fold(character(code));
    if index as usize >= folded.len {
        crate::io::close_all();
        crate::fail_message("full case-fold component index out of range")
    }
    folded.scalars[index as usize] as u32
}

#[unsafe(export_name = "snail:text/lowercase")]
pub extern "C" fn lowercase(code: u32) -> i32 {
    i32::from(character(code).is_lowercase())
}

#[unsafe(export_name = "snail:text/uppercase")]
pub extern "C" fn uppercase(code: u32) -> i32 {
    i32::from(character(code).is_uppercase())
}

// The digit's value, or -1 when the character is not a decimal digit: Lofi
// reads the tag rather than a sentinel it could confuse with a value.
#[unsafe(export_name = "snail:text/digit-value")]
pub extern "C" fn digit_value(code: u32) -> i32 {
    match unicode::digit_value(character(code)) {
        Some(value) => i32::from(value),
        None => -1,
    }
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

    #[test]
    fn full_case_mapping_preserves_nul_and_expands_scalars() {
        for (source, expected) in [
            ('ß', "ss"),
            ('ΐ', "ι\u{308}\u{301}"),
            ('İ', "i\u{307}"),
            ('ﬃ', "ffi"),
            ('Ꭰ', "Ꭰ"),
            ('\0', "\0"),
        ] {
            assert_eq!(
                full_fold_length(source as u32) as usize,
                expected.chars().count()
            );
            for (index, character) in expected.chars().enumerate() {
                assert_eq!(
                    full_fold_scalar(source as u32, index as u32),
                    character as u32
                );
            }
        }
    }
}
