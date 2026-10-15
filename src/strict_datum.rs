//! Root-free scalar services for strict Scheme datums. Scheme owns syntax and
//! datum allocation. Rust owns temporary text/number handles and symbol names.

use crate::datum::{Number, Scalar};
use crate::symbols::Symbols;
use std::{
    cell::RefCell,
    collections::BTreeMap,
    sync::{Mutex, OnceLock},
};

// ---- Owned text transitions once to a parsed numeric result ----

enum Token {
    Text(String),
    Parsed {
        text: String,
        result: Result<Option<Number>, String>,
    },
}

#[derive(Default)]
struct Tokens {
    next: u32,
    live: BTreeMap<u32, Token>,
}

impl Tokens {
    fn open(&mut self) -> Result<u32, String> {
        let id = self.next;
        self.next = id
            .checked_add(1)
            .filter(|&next| next <= i32::MAX as u32)
            .ok_or("token handle space exhausted")?;
        self.live.insert(id, Token::Text(String::new()));
        Ok(id)
    }

    fn get(&self, id: u32) -> Result<&Token, String> {
        self.live
            .get(&id)
            .ok_or_else(|| "invalid or closed token handle".into())
    }

    fn take(&mut self, id: u32) -> Result<Token, String> {
        self.live
            .remove(&id)
            .ok_or_else(|| "invalid or closed token handle".into())
    }

    // Removal consumes the handle on both success and rejection. Only a
    // nonnumber parse may reuse its retained text; numbers/errors stay invalid.
    fn take_symbol_text(&mut self, id: u32) -> Result<String, String> {
        match self.take(id)? {
            Token::Text(text)
            | Token::Parsed {
                text,
                result: Ok(None),
            } => Ok(text),
            Token::Parsed { .. } => Err("symbol interning requires an unparsed text handle".into()),
        }
    }

    fn append(&mut self, id: u32, code: u32) -> Result<(), String> {
        let character = char::from_u32(code).ok_or("invalid Unicode scalar")?;
        match self.live.get_mut(&id) {
            Some(Token::Text(text)) => {
                text.push(character);
                Ok(())
            }
            Some(Token::Parsed { .. }) => Err("token has already been parsed".into()),
            None => Err("invalid or closed token handle".into()),
        }
    }

    fn parse(&mut self, id: u32) -> Result<i32, String> {
        let Token::Text(text) = self.take(id)? else {
            return Err("token has already been parsed".into());
        };
        let result = parse_number(&text).map(normalize_number);
        let tag = match &result {
            Ok(None) => 0,
            Ok(Some(Number::Integer(_))) => 1,
            Ok(Some(Number::Real(_))) => 2,
            Ok(Some(Number::Complex(..))) => 3,
            Err(_) => 4,
        };
        self.live.insert(id, Token::Parsed { text, result });
        Ok(tag)
    }
}

fn parse_number(text: &str) -> Result<Option<Number>, String> {
    let result = match text.split_once('@') {
        Some((radius, angle)) => polar_number(text, radius, angle)?,
        None => crate::datum::number(text, 10)?,
    };
    if result.is_none() && rational_token(text) {
        return Err("rational numbers are not supported".into());
    }
    Ok(result)
}

// Apply the shared scalar grammar and exactness before testing the polar axes.
// Exact zero magnitude gives exact zero; exact zero angle preserves magnitude.
// Other polar forms retain the legacy helper's checked trigonometric boundary.
fn polar_number(text: &str, radius: &str, angle: &str) -> Result<Option<Number>, String> {
    let prefix_length = radius
        .as_bytes()
        .chunks_exact(2)
        .take_while(|pair| pair[0] == b'#')
        .count()
        * 2;
    if angle.starts_with('#') {
        return Ok(None);
    }
    let magnitude = crate::datum::number(radius, 10)?;
    let angle = crate::datum::number(&format!("{}{angle}", &radius[..prefix_length]), 10)?;
    match (magnitude, angle) {
        (Some(Number::Integer(0)), Some(Number::Integer(_) | Number::Real(_))) => {
            Ok(Some(Number::Integer(0)))
        }
        (Some(magnitude @ (Number::Integer(_) | Number::Real(_))), Some(Number::Integer(0))) => {
            Ok(Some(magnitude))
        }
        (
            Some(Number::Integer(_) | Number::Real(_)),
            Some(Number::Integer(_) | Number::Real(_)),
        ) => crate::datum::number(text, 10),
        _ => Ok(None),
    }
}

fn rational_token(mut text: &str) -> bool {
    let mut radix = 10;
    while text.starts_with('#') && text.len() >= 2 {
        radix = match text.as_bytes()[1].to_ascii_lowercase() {
            b'b' => 2,
            b'o' => 8,
            b'x' => 16,
            b'd' => 10,
            b'e' | b'i' => radix,
            _ => return false,
        };
        text = &text[2..];
    }
    text.split_once('/').is_some_and(|(first, last)| {
        [first, last].iter().all(|part| {
            let digits = part.trim_start_matches(['+', '-']);
            !digits.is_empty() && digits.chars().all(|c| c.to_digit(radix).is_some())
        })
    })
}

// An exact imaginary zero has the same canonical scalar value as Chez/R7RS.
// An inexact zero remains a complex component, retaining its exactness/sign.
fn normalize_number(number: Option<Number>) -> Option<Number> {
    number.map(|number| match number {
        Number::Complex(real, Scalar::Integer(0)) => Number::from(real),
        Number::Complex(real, imag)
            if matches!((&real, &imag), (Scalar::Real(_), _) | (_, Scalar::Real(_))) =>
        {
            Number::Complex(
                Scalar::Real(real_value(real)),
                Scalar::Real(real_value(imag)),
            )
        }
        other => other,
    })
}

fn real_value(number: Scalar) -> f64 {
    match number {
        Scalar::Integer(value) => value as f64,
        Scalar::Real(value) => value,
    }
}

impl Token {
    fn text(&self) -> &str {
        match self {
            Self::Text(text) | Self::Parsed { text, .. } => text,
        }
    }

    fn number(&self) -> Result<&Number, String> {
        match self {
            Self::Parsed {
                result: Ok(Some(number)),
                ..
            } => Ok(number),
            _ => Err("token has no successful numeric result".into()),
        }
    }

    fn error(&self) -> Result<&str, String> {
        match self {
            Self::Parsed {
                result: Err(error), ..
            } => Ok(error),
            _ => Err("token has no numeric error".into()),
        }
    }
}

thread_local! { static TOKENS: RefCell<Tokens> = RefCell::new(Tokens::default()); }

// IDs are never reused, even after terminal cleanup. Each operation ends its
// RefCell borrow before reporting a fatal error; no temporary stores Scheme
// roots or invokes Scheme callbacks. Independent IDs may be interleaved.
pub(crate) fn close_all() {
    TOKENS.with_borrow_mut(|tokens| tokens.live.clear());
}

fn checked<T>(result: Result<T, String>) -> T {
    result.unwrap_or_else(|error| {
        crate::strict_io::close_all();
        crate::fail_message(&error)
    })
}

#[unsafe(export_name = "snail:datum/token-open")]
pub extern "C" fn token_open() -> u32 {
    checked(TOKENS.with_borrow_mut(Tokens::open))
}

#[unsafe(export_name = "snail:datum/token-character")]
pub extern "C" fn token_character(id: u32, code: u32) {
    checked(TOKENS.with_borrow_mut(|tokens| tokens.append(id, code)));
}

#[unsafe(export_name = "snail:datum/token-close")]
pub extern "C" fn token_close(id: u32) {
    drop(checked(TOKENS.with_borrow_mut(|tokens| tokens.take(id))));
}

#[unsafe(export_name = "snail:datum/token-parse")]
pub extern "C" fn token_parse(id: u32) -> i32 {
    checked(TOKENS.with_borrow_mut(|tokens| tokens.parse(id)))
}

#[unsafe(export_name = "snail:datum/token-identifier")]
pub extern "C" fn token_identifier(id: u32) -> i32 {
    checked(
        TOKENS
            .with_borrow(|tokens| Ok(i32::from(crate::datum::identifier(tokens.get(id)?.text())))),
    )
}

// ---- Typed scalar result access; a failed parse has no numeric fields ----

fn component(number: &Number, part: u32) -> Result<Scalar, String> {
    match (number, part) {
        (Number::Integer(value), 0) => Ok(Scalar::Integer(*value)),
        (Number::Real(value), 0) => Ok(Scalar::Real(*value)),
        (Number::Complex(real, _), 0) | (Number::Complex(_, real), 1) => match real {
            Scalar::Integer(value) => Ok(Scalar::Integer(*value)),
            Scalar::Real(value) => Ok(Scalar::Real(*value)),
        },
        _ => Err("numeric component index out of range".into()),
    }
}

fn token_component(id: u32, part: u32) -> Result<Scalar, String> {
    TOKENS.with_borrow(|tokens| component(tokens.get(id)?.number()?, part))
}

#[unsafe(export_name = "snail:datum/number-kind")]
pub extern "C" fn number_kind(id: u32, part: u32) -> i32 {
    match checked(token_component(id, part)) {
        Scalar::Integer(_) => 1,
        Scalar::Real(_) => 2,
    }
}

#[unsafe(export_name = "snail:datum/number-integer")]
pub extern "C" fn number_integer(id: u32, part: u32) -> i64 {
    checked(token_component(id, part).and_then(|number| match number {
        Scalar::Integer(value) => Ok(value),
        _ => Err("numeric component is not exact".into()),
    }))
}

#[unsafe(export_name = "snail:datum/number-real")]
pub extern "C" fn number_real(id: u32, part: u32) -> f64 {
    checked(token_component(id, part).and_then(|number| match number {
        Scalar::Real(value) => Ok(value),
        _ => Err("numeric component is not inexact".into()),
    }))
}

#[unsafe(export_name = "snail:datum/error-length")]
pub extern "C" fn error_length(id: u32) -> u32 {
    checked(TOKENS.with_borrow(|tokens| Ok(tokens.get(id)?.error()?.chars().count() as u32)))
}

#[unsafe(export_name = "snail:datum/error-character")]
pub extern "C" fn error_character(id: u32, index: u32) -> u32 {
    checked(TOKENS.with_borrow(|tokens| {
        tokens
            .get(id)?
            .error()?
            .chars()
            .nth(index as usize)
            .map(u32::from)
            .ok_or_else(|| "error character index out of range".into())
    }))
}

#[unsafe(export_name = "snail:datum/fail")]
pub extern "C" fn fail(id: u32) {
    let message = checked(TOKENS.with_borrow_mut(|tokens| tokens.take(id)))
        .text()
        .to_owned();
    crate::strict_io::close_all();
    crate::fail_message(&message);
}

#[unsafe(export_name = "snail:datum/real-equivalent")]
pub extern "C" fn real_equivalent(left: f64, right: f64) -> i32 {
    i32::from(left.to_bits() == right.to_bits() || (left.is_nan() && right.is_nan()))
}

#[unsafe(export_name = "snail:datum/whitespace")]
pub extern "C" fn whitespace(code: u32) -> i32 {
    i32::from(
        checked(char::from_u32(code).ok_or_else(|| "invalid Unicode scalar".into()))
            .is_whitespace(),
    )
}

// ---- Interned strict symbols have no dependency on legacy literal roots ----

static SYMBOLS: OnceLock<Mutex<Symbols>> = OnceLock::new();

fn with_symbols<T>(operation: impl FnOnce(&mut Symbols) -> Result<T, String>) -> Result<T, String> {
    let mut symbols = SYMBOLS
        .get_or_init(|| Mutex::new(Symbols::default()))
        .lock()
        .map_err(|_| "strict symbol table lock poisoned")?;
    operation(&mut symbols)
}

#[unsafe(export_name = "snail:datum/token-intern")]
pub extern "C" fn token_intern(id: u32) -> u32 {
    let text = checked(TOKENS.with_borrow_mut(|tokens| tokens.take_symbol_text(id)));
    checked(with_symbols(|symbols| symbols.intern(text)))
}

#[unsafe(export_name = "snail:datum/symbol-length")]
pub extern "C" fn symbol_length(id: u32) -> u64 {
    u64::from(checked(with_symbols(|symbols| symbols.length(id))))
}

#[unsafe(export_name = "snail:datum/symbol-character")]
pub extern "C" fn symbol_character(id: u32, index: u32) -> u32 {
    checked(with_symbols(|symbols| symbols.character(id, index)))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    fn staged(tokens: &mut Tokens, text: &str) -> u32 {
        let id = tokens.open().unwrap();
        for character in text.chars() {
            tokens.append(id, character as u32).unwrap();
        }
        id
    }

    #[test]
    fn independent_handles_never_expose_stale_numbers() {
        let mut tokens = Tokens::default();
        let first = staged(&mut tokens, "42");
        let second = staged(&mut tokens, "#e1.5");
        assert_eq!(tokens.parse(first).unwrap(), 1);
        assert_eq!(tokens.parse(second).unwrap(), 4);
        assert!(tokens.get(second).unwrap().number().is_err());
        assert_eq!(
            tokens.get(first).unwrap().number().unwrap(),
            &Number::Integer(42)
        );
        assert!(tokens.append(first, 65).is_err());
        tokens.take(first).unwrap();
        assert!(tokens.get(first).is_err());
        assert!(tokens.open().unwrap() > second);
    }

    #[test]
    fn symbol_text_consumes_unparsed_or_nonnumeric_handles_once() {
        let mut tokens = Tokens::default();
        let mut symbols = Symbols::default();
        let quoted = staged(&mut tokens, "123abc");
        assert_eq!(tokens.take_symbol_text(quoted).unwrap(), "123abc");
        let mut identities = Vec::new();
        for _ in 0..2 {
            let id = staged(&mut tokens, "same");
            assert_eq!(tokens.parse(id).unwrap(), 0);
            identities.push(
                symbols
                    .intern(tokens.take_symbol_text(id).unwrap())
                    .unwrap(),
            );
            assert!(tokens.get(id).is_err());
            assert!(tokens.take_symbol_text(id).is_err());
        }
        assert_eq!(identities[0], identities[1]);
        assert!(tokens.live.is_empty());
    }

    #[test]
    fn symbol_text_rejects_and_consumes_numeric_and_error_handles() {
        let mut tokens = Tokens::default();
        let survivor = staged(&mut tokens, "still owned");
        for (text, kind) in [("42", 1), ("1.0", 2), ("1+2i", 3), ("1/2", 4), ("#e1.5", 4)] {
            let id = staged(&mut tokens, text);
            assert_eq!(tokens.parse(id).unwrap(), kind);
            assert_eq!(
                tokens.take_symbol_text(id).unwrap_err(),
                "symbol interning requires an unparsed text handle"
            );
            assert!(tokens.get(id).is_err());
            assert!(tokens.get(survivor).is_ok());
        }
        assert_eq!(tokens.take_symbol_text(survivor).unwrap(), "still owned");
        assert!(tokens.live.is_empty());
    }

    #[test]
    fn normalization_and_equivalence_keep_exactness_and_zero_signs() {
        assert_eq!(
            normalize_number(crate::datum::number("1+0i", 10).unwrap()),
            Some(Number::Integer(1))
        );
        assert!(matches!(
            normalize_number(crate::datum::number("1.0+0.0i", 10).unwrap()),
            Some(Number::Complex(..))
        ));
        assert_eq!(real_equivalent(0.0, -0.0), 0);
        assert_eq!(real_equivalent(f64::NAN, -f64::NAN), 1);
        assert_eq!(real_equivalent(f64::INFINITY, f64::INFINITY), 1);
    }

    #[test]
    fn polar_axes_apply_exactness_before_zero_normalization() {
        for text in ["1@0", "#e1@0.0", "#x1@-0"] {
            assert_eq!(
                parse_number(text).unwrap(),
                Some(Number::Integer(1)),
                "{text}"
            );
        }
        for text in ["0@1", "0@1.0", "#e0@1", "0@+inf.0", "0@+nan.0"] {
            assert_eq!(
                parse_number(text).unwrap(),
                Some(Number::Integer(0)),
                "{text}"
            );
        }
        assert_eq!(parse_number("1.0@0").unwrap(), Some(Number::Real(1.0)));
        for text in ["#i1@0", "#x#i1@0", "#i#x1@0", "1@0.0", "0.0@1"] {
            assert!(
                matches!(parse_number(text).unwrap(), Some(Number::Complex(..))),
                "{text}"
            );
        }
        let Some(Number::Complex(Scalar::Real(real), Scalar::Real(imaginary))) =
            parse_number("1@-0.0").unwrap()
        else {
            panic!("expected inexact complex value")
        };
        assert_eq!(real.to_bits(), 1.0f64.to_bits());
        assert_eq!(imaginary.to_bits(), (-0.0f64).to_bits());
        for text in ["1@#i0", "1@2@0", "+i@0", "#i#e0@1"] {
            assert_eq!(parse_number(text).unwrap(), None, "{text}");
        }
    }

    #[test]
    fn strict_names_do_not_initialize_the_legacy_table() {
        let mut symbols = Symbols::default();
        let first = symbols.intern("λ😀\0".into()).unwrap();
        assert_eq!(first, symbols.intern("λ😀\0".into()).unwrap());
        assert_ne!(first, symbols.intern("Λ😀\0".into()).unwrap());
        assert_eq!(symbols.length(first).unwrap(), 3);
        assert_eq!(symbols.character(first, 1).unwrap(), 0x1f600);
        assert!(symbols.character(first, 3).is_err());
    }

    #[test]
    fn numeric_boundaries_never_round_an_explicit_exact_value() {
        for (text, expected) in [
            ("#e9007199254740993.0", 9007199254740993),
            ("#e-9223372036854775808.0", i64::MIN),
            ("9223372036854775807", i64::MAX),
            ("#e12000e-3", 12),
        ] {
            assert_eq!(parse_number(text).unwrap(), Some(Number::Integer(expected)));
        }
        for text in [
            "#e9007199254740993.1",
            "#e1.5",
            "9223372036854775808",
            "-9223372036854775809",
            "#e1e999",
            "#e1@1",
            "1/2",
            "4/2",
            "#i1/2",
            "#xA/B",
        ] {
            assert!(parse_number(text).is_err(), "{text}");
        }
        for text in ["123abc", "+2oops", "#e#e1", "#x#b10", "1e"] {
            assert!(parse_number(text).unwrap().is_none(), "{text}");
            assert!(!crate::datum::identifier(text), "{text}");
        }
        assert_eq!(parse_number("a/b").unwrap(), None);
        assert!(crate::datum::identifier("a/b"));
    }

    #[test]
    fn failed_reparse_consumes_the_previous_result_and_cleanup_keeps_ids_monotonic() {
        let mut tokens = Tokens::default();
        let first = staged(&mut tokens, "1");
        tokens.parse(first).unwrap();
        assert!(tokens.parse(first).is_err());
        assert!(tokens.get(first).is_err());
        for _ in 0..10000 {
            let id = staged(&mut tokens, "12.5");
            tokens.parse(id).unwrap();
            tokens.take(id).unwrap();
        }
        assert!(tokens.live.is_empty());
        let last = staged(&mut tokens, "unfinished");
        TOKENS.with_borrow_mut(|active| *active = tokens);
        close_all();
        TOKENS.with_borrow_mut(|active| {
            assert!(active.live.is_empty());
            assert!(active.open().unwrap() > last);
        });
        close_all();
    }
}
