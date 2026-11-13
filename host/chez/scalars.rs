//! Stage-zero Unicode operations use the same pinned Rust tables as Wasm.
//! This boundary has only scalar inputs and results; it owns no runtime state.
#[path = "../../crates/snail-core-support/src/unicode.rs"]
mod unicode;

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_upcase(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    unicode::uppercase(character) as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_downcase(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    unicode::lowercase(character) as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_foldcase(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    unicode::fold_character(character) as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_lowercase(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    i32::from(character.is_lowercase())
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_uppercase(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    i32::from(character.is_uppercase())
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_digit_value(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    unicode::digit_value(character).map(i32::from).unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_alphabetic(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    i32::from(character.is_alphabetic())
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_numeric(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    i32::from(unicode::digit_value(character).is_some())
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_whitespace(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    i32::from(character.is_whitespace())
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_full_fold_length(code: u32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    unicode::full_fold(character).len as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_bootstrap_full_fold_scalar(code: u32, index: i32) -> i32 {
    let character = char::from_u32(code).expect("checked Unicode scalar");
    {
        let folded = unicode::full_fold(character);
        assert!((index as usize) < folded.len);
        folded.scalars[index as usize] as i32
    }
}
