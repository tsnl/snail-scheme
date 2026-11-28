//! Unicode properties and case mapping for `(snail shell text)`, as ICU4X
//! computes them from its compiled Unicode data. A program that imports the
//! library is linked with the runtime built with the `unicode` feature
//! (`(snail shell project build)`, "Programs").
//!
//! A character crosses as its scalar, and a string as the compiler stages it
//! (`io::staged_text`); a mapped string is the reply (`paths::set_reply`),
//! which `snail-scheme` reads a scalar at a time. Nothing here holds state.

use crate::{fail_message, io::staged_text, paths::set_reply};
use icu_casemap::{CaseMapper, CaseMapperBorrowed};
use icu_locale_core::LanguageIdentifier;
use icu_properties::{
    CodePointMapData, CodePointSetData,
    props::{Alphabetic, GeneralCategory, Lowercase, Uppercase, WhiteSpace},
};

// ---- Characters ----

// A scalar from `snail-scheme` is always one; anything else maps to itself.
fn scalar(code: u32) -> char {
    char::from_u32(code).unwrap_or(char::REPLACEMENT_CHARACTER)
}

/// Simple case mapping, one scalar to one scalar.
#[unsafe(export_name = "snail:text/simple-upper")]
pub extern "C" fn simple_upper(code: u32) -> u32 {
    u32::from(CaseMapper::new().simple_uppercase(scalar(code)))
}

#[unsafe(export_name = "snail:text/simple-lower")]
pub extern "C" fn simple_lower(code: u32) -> u32 {
    u32::from(CaseMapper::new().simple_lowercase(scalar(code)))
}

#[unsafe(export_name = "snail:text/simple-fold")]
pub extern "C" fn simple_fold(code: u32) -> u32 {
    u32::from(CaseMapper::new().simple_fold(scalar(code)))
}

/// The binary properties as bits: 1 Alphabetic, 2 White_Space, 4 Lowercase
/// and 8 Uppercase.
#[unsafe(export_name = "snail:text/properties")]
pub extern "C" fn properties(code: u32) -> u32 {
    let char = scalar(code);
    [
        CodePointSetData::new::<Alphabetic>().contains(char),
        CodePointSetData::new::<WhiteSpace>().contains(char),
        CodePointSetData::new::<Lowercase>().contains(char),
        CodePointSetData::new::<Uppercase>().contains(char),
    ]
    .iter()
    .enumerate()
    .map(|(bit, set)| u32::from(*set) << bit)
    .sum()
}

/// A decimal digit's value in any script, or -1. Unicode encodes every
/// decimal digit in runs from 0 to 9 (its stability policy), so a digit's
/// value is how many digits precede it in its run, modulo 10: some runs
/// hold several sets, as the mathematical digits do.
#[unsafe(export_name = "snail:text/digit-value")]
pub extern "C" fn digit_value(code: u32) -> i32 {
    let digit = |code: u32| {
        char::from_u32(code).is_some_and(|char| {
            CodePointMapData::<GeneralCategory>::new().get(char) == GeneralCategory::DecimalNumber
        })
    };
    if !digit(code) {
        return -1;
    }
    let before = (1..=code).take_while(|back| digit(code - back)).count();
    (before % 10) as i32
}

// ---- Strings ----

// Full case mapping, which may expand one scalar into several, as "ß" into
// "SS", in the root locale; folded strings compare equal ignoring case.
fn mapped(count: u32, map: impl Fn(CaseMapperBorrowed<'static>, &str) -> String) -> i32 {
    let text = staged_text(count).unwrap_or_else(|error| fail_message(&error));
    let mapped = map(CaseMapper::new(), &text);
    set_reply(&mapped).unwrap_or_else(|| fail_message("a mapped string longer than an i32 counts"))
}

#[unsafe(export_name = "snail:text/upcase")]
pub extern "C" fn upcase(count: u32) -> i32 {
    mapped(count, |mapper, text| {
        mapper
            .uppercase_to_string(text, &LanguageIdentifier::UNKNOWN)
            .into_owned()
    })
}

#[unsafe(export_name = "snail:text/downcase")]
pub extern "C" fn downcase(count: u32) -> i32 {
    mapped(count, |mapper, text| {
        mapper
            .lowercase_to_string(text, &LanguageIdentifier::UNKNOWN)
            .into_owned()
    })
}

#[unsafe(export_name = "snail:text/foldcase")]
pub extern "C" fn foldcase(count: u32) -> i32 {
    mapped(count, |mapper, text| mapper.fold_string(text).into_owned())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simple_mappings_keep_one_scalar() {
        assert_eq!(simple_upper(u32::from('ß')), u32::from('ß'));
        assert_eq!(simple_upper(u32::from('λ')), u32::from('Λ'));
        assert_eq!(simple_lower(u32::from('İ')), u32::from('i'));
        assert_eq!(simple_fold(u32::from('ς')), u32::from('σ'));
    }

    #[test]
    fn properties_and_digits_cover_other_scripts() {
        assert_eq!(properties(u32::from('λ')), 1 | 4);
        assert_eq!(properties(u32::from('Λ')), 1 | 8);
        assert_eq!(properties(0x3000), 2);
        assert_eq!(digit_value(u32::from('٣')), 3);
        assert_eq!(digit_value(u32::from('9')), 9);
        assert_eq!(digit_value(0x1D7D8), 0);
        assert_eq!(digit_value(u32::from('Ⅷ')), -1);
        assert_eq!(digit_value(u32::from('²')), -1);
    }
}
