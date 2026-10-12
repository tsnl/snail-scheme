//! Native Unicode transformations and ordered text comparisons.

use crate::{
    arguments,
    awi::{Arguments, Root},
    finish, string_text, unicode,
};
use std::cmp::Ordering;

pub(crate) use crate::unicode::fold_character;

// ---- Case transformations ----

pub(crate) fn fold_string(text: &str) -> String {
    let mut result = String::new();
    for character in text.chars() {
        unicode::fold_into(character, &mut result);
    }
    result
}

#[unsafe(export_name = "snail:char-upcase")]
pub extern "C" fn char_upcase(raw: u32) -> u32 {
    let args = arguments(raw, "char-upcase", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| value.as_character())
            .map(|character| Root::character(unicode::uppercase(character))),
    )
}

#[unsafe(export_name = "snail:char-downcase")]
pub extern "C" fn char_downcase(raw: u32) -> u32 {
    let args = arguments(raw, "char-downcase", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| value.as_character())
            .map(|character| Root::character(unicode::lowercase(character))),
    )
}

#[unsafe(export_name = "snail:char-foldcase")]
pub extern "C" fn char_foldcase(raw: u32) -> u32 {
    let args = arguments(raw, "char-foldcase", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| value.as_character())
            .map(|character| Root::character(fold_character(character))),
    )
}

#[unsafe(export_name = "snail:char-upper-case?")]
pub extern "C" fn char_upper_case(raw: u32) -> u32 {
    let args = arguments(raw, "char-upper-case?", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| value.as_character())
            .map(|character| Root::boolean(character.is_uppercase())),
    )
}

#[unsafe(export_name = "snail:char-lower-case?")]
pub extern "C" fn char_lower_case(raw: u32) -> u32 {
    let args = arguments(raw, "char-lower-case?", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| value.as_character())
            .map(|character| Root::boolean(character.is_lowercase())),
    )
}

#[unsafe(export_name = "snail:digit-value")]
pub extern "C" fn digit_value(raw: u32) -> u32 {
    let args = arguments(raw, "digit-value", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| value.as_character())
            .map(|character| {
                unicode::digit_value(character)
                    .map(|digit| Root::integer(digit as i64))
                    .unwrap_or_else(|| Root::boolean(false))
            }),
    )
}

#[unsafe(export_name = "snail:string-upcase")]
pub extern "C" fn string_upcase(raw: u32) -> u32 {
    let args = arguments(raw, "string-upcase", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| string_text(&value))
            .map(|text| Root::string(&text.to_uppercase())),
    )
}

#[unsafe(export_name = "snail:string-downcase")]
pub extern "C" fn string_downcase(raw: u32) -> u32 {
    let args = arguments(raw, "string-downcase", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| string_text(&value))
            .map(|text| Root::string(&text.to_lowercase())),
    )
}

#[unsafe(export_name = "snail:string-foldcase")]
pub extern "C" fn string_foldcase(raw: u32) -> u32 {
    let args = arguments(raw, "string-foldcase", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| string_text(&value))
            .map(|text| Root::string(&fold_string(&text))),
    )
}

// ---- Ordered comparisons ----

enum Comparison {
    Equal,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
}

impl Comparison {
    fn accepts(&self, order: Ordering) -> bool {
        match self {
            Self::Equal => order == Ordering::Equal,
            Self::Less => order == Ordering::Less,
            Self::LessEqual => order != Ordering::Greater,
            Self::Greater => order == Ordering::Greater,
            Self::GreaterEqual => order != Ordering::Less,
        }
    }
}

fn compare_chars(args: &Arguments, comparison: Comparison) -> Result<Root, String> {
    let mut previous = fold_character(args.get(0)?.as_character()?);
    let mut result = true;
    for index in 1..args.len() {
        let current = fold_character(args.get(index)?.as_character()?);
        result &= comparison.accepts(previous.cmp(&current));
        previous = current;
    }
    Ok(Root::boolean(result))
}

fn compare_strings(args: &Arguments, comparison: Comparison, folded: bool) -> Result<Root, String> {
    let normalize = |value: Root| {
        string_text(&value).map(|text| if folded { fold_string(&text) } else { text })
    };
    let mut previous = normalize(args.get(0)?)?;
    let mut result = true;
    for index in 1..args.len() {
        let current = normalize(args.get(index)?)?;
        result &= comparison.accepts(previous.cmp(&current));
        previous = current;
    }
    Ok(Root::boolean(result))
}

#[unsafe(export_name = "snail:string-ci=?")]
pub extern "C" fn string_ci_equal(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string-ci=?", 2, usize::MAX),
        Comparison::Equal,
        true,
    ))
}

#[unsafe(export_name = "snail:char-ci<?")]
pub extern "C" fn char_ci_less(raw: u32) -> u32 {
    finish(compare_chars(
        &arguments(raw, "char-ci<?", 2, usize::MAX),
        Comparison::Less,
    ))
}

#[unsafe(export_name = "snail:string<?")]
pub extern "C" fn string_less(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string<?", 2, usize::MAX),
        Comparison::Less,
        false,
    ))
}

#[unsafe(export_name = "snail:string-ci<?")]
pub extern "C" fn string_ci_less(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string-ci<?", 2, usize::MAX),
        Comparison::Less,
        true,
    ))
}

#[unsafe(export_name = "snail:char-ci<=?")]
pub extern "C" fn char_ci_less_equal(raw: u32) -> u32 {
    finish(compare_chars(
        &arguments(raw, "char-ci<=?", 2, usize::MAX),
        Comparison::LessEqual,
    ))
}

#[unsafe(export_name = "snail:string<=?")]
pub extern "C" fn string_less_equal(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string<=?", 2, usize::MAX),
        Comparison::LessEqual,
        false,
    ))
}

#[unsafe(export_name = "snail:string-ci<=?")]
pub extern "C" fn string_ci_less_equal(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string-ci<=?", 2, usize::MAX),
        Comparison::LessEqual,
        true,
    ))
}

#[unsafe(export_name = "snail:char-ci>?")]
pub extern "C" fn char_ci_greater(raw: u32) -> u32 {
    finish(compare_chars(
        &arguments(raw, "char-ci>?", 2, usize::MAX),
        Comparison::Greater,
    ))
}

#[unsafe(export_name = "snail:string>?")]
pub extern "C" fn string_greater(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string>?", 2, usize::MAX),
        Comparison::Greater,
        false,
    ))
}

#[unsafe(export_name = "snail:string-ci>?")]
pub extern "C" fn string_ci_greater(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string-ci>?", 2, usize::MAX),
        Comparison::Greater,
        true,
    ))
}

#[unsafe(export_name = "snail:char-ci>=?")]
pub extern "C" fn char_ci_greater_equal(raw: u32) -> u32 {
    finish(compare_chars(
        &arguments(raw, "char-ci>=?", 2, usize::MAX),
        Comparison::GreaterEqual,
    ))
}

#[unsafe(export_name = "snail:string>=?")]
pub extern "C" fn string_greater_equal(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string>=?", 2, usize::MAX),
        Comparison::GreaterEqual,
        false,
    ))
}

#[unsafe(export_name = "snail:string-ci>=?")]
pub extern "C" fn string_ci_greater_equal(raw: u32) -> u32 {
    finish(compare_strings(
        &arguments(raw, "string-ci>=?", 2, usize::MAX),
        Comparison::GreaterEqual,
        true,
    ))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn case_folding_distinguishes_characters_from_strings() {
        assert_eq!(fold_character('ς'), 'σ');
        assert_eq!(fold_character('ß'), 'ß');
        assert_eq!(fold_character('İ'), 'İ');
        assert_eq!(fold_string("StraßeΣςİ"), "strasseσσi\u{307}");
    }
}
