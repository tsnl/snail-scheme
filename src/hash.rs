//! Hashing reads owned AWI roots; tables and their entries stay in the GC heap.
//! Structural hashing bounds its unfolding, so cyclic equal? keys terminate.

use crate::{Kind, Root, arguments, finish};

// ---- Scalar and structural hashes ----

fn mix(hash: u32, value: u64) -> u32 {
    let folded = (value as u32) ^ ((value >> 32) as u32);
    hash.wrapping_mul(16777619) ^ folded
}

fn eqv_hash(value: &Root) -> Result<u32, String> {
    let scalar = match value.kind() {
        Kind::Integer => value.as_integer()? as u64,
        Kind::Real => real_bits(value.as_real()?),
        Kind::Character => value.as_character()? as u64,
        Kind::Boolean => u64::from(value.as_bool()?),
        Kind::Nil | Kind::Eof | Kind::Unspecified => 0,
        _ => return Ok(value.identity_hash()),
    };
    Ok(mix(value.kind() as u32, scalar))
}

fn real_bits(value: f64) -> u64 {
    // Snail's eqv? identifies both zero signs. NaNs may collide freely.
    if value == 0.0 { 0 } else { value.to_bits() }
}

fn text_hash(value: &Root, fold_case: bool) -> Result<u32, String> {
    let mut hash = 2166136261;
    for index in 0..value.len()? {
        let character = value.char_at(index)?;
        if fold_case {
            for folded in character.to_lowercase() {
                hash = mix(hash, folded as u64);
            }
        } else {
            hash = mix(hash, character as u64);
        }
    }
    Ok(hash)
}

fn equal_hash(value: &Root, depth: u32, budget: &mut u32) -> Result<u32, String> {
    if depth == 0 || *budget == 0 {
        return Ok(0);
    }
    *budget -= 1;
    let mut hash = value.kind() as u32;
    match value.kind() {
        Kind::Pair => {
            hash = mix(hash, equal_hash(&value.car()?, depth - 1, budget)? as u64);
            Ok(mix(
                hash,
                equal_hash(&value.cdr()?, depth - 1, budget)? as u64,
            ))
        }
        Kind::Vector => {
            hash = mix(hash, value.len()? as u64);
            for index in 0..value.len()? {
                if *budget == 0 {
                    break;
                }
                hash = mix(
                    hash,
                    equal_hash(&value.at(index)?, depth - 1, budget)? as u64,
                );
            }
            Ok(hash)
        }
        Kind::String => text_hash(value, false),
        Kind::Bytevector => {
            for index in 0..value.len()? {
                hash = mix(hash, value.byte_at(index)? as u64);
            }
            Ok(hash)
        }
        _ => eqv_hash(value),
    }
}

// ---- Scheme procedure boundaries ----

fn result(hash: Result<u32, String>) -> u32 {
    finish(hash.map(|value| Root::integer(i64::from(value & 0x3fffffff))))
}

#[unsafe(export_name = "snail:%eqv-hash")]
pub extern "C" fn scheme_eqv_hash(raw: u32) -> u32 {
    result(
        arguments(raw, "eqv-hash", 1, 1)
            .get(0)
            .and_then(|value| eqv_hash(&value)),
    )
}

#[unsafe(export_name = "snail:%equal-hash")]
pub extern "C" fn scheme_equal_hash(raw: u32) -> u32 {
    result(
        arguments(raw, "hash", 1, 1)
            .get(0)
            .and_then(|value| equal_hash(&value, 16, &mut 256)),
    )
}

fn string_hash(raw: u32, fold_case: bool) -> u32 {
    result(
        arguments(raw, "string-hash", 1, 1)
            .get(0)
            .and_then(|value| {
                if value.kind() == Kind::String {
                    text_hash(&value, fold_case)
                } else {
                    Err("string-hash: expected a string".into())
                }
            }),
    )
}

#[unsafe(export_name = "snail:%string-hash")]
pub extern "C" fn scheme_string_hash(raw: u32) -> u32 {
    string_hash(raw, false)
}

#[unsafe(export_name = "snail:%string-ci-hash")]
pub extern "C" fn scheme_string_ci_hash(raw: u32) -> u32 {
    string_hash(raw, true)
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn real_hashing_agrees_with_numeric_zero_equality() {
        assert_eq!(real_bits(0.0), real_bits(-0.0));
        assert_ne!(real_bits(1.0), real_bits(-1.0));
    }
}
