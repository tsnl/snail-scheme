//! Scalar services for SFIR datums. The SFIR library owns reading and allocation.
//! Rust owns temporary text/number handles and symbol names.

use crate::strict_number::{Number, Scalar};
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

    fn exact_text(&self, id: u32, part: u32, term: u32) -> Result<&str, String> {
        self.get(id)?.number()?.component(part)?.exact()?.text(term)
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

    fn parse(&mut self, id: u32, radix: u32) -> Result<i32, String> {
        let Token::Text(text) = self.take(id)? else {
            return Err("token has already been parsed".into());
        };
        let result = crate::strict_number::parse(&text, radix);
        let tag = match &result {
            Ok(None) => 0,
            Ok(Some(number)) => number.kind(),
            Err(_) => 4,
        };
        self.live.insert(id, Token::Parsed { text, result });
        Ok(tag)
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
// RefCell borrow before reporting a fatal error; no temporary stores managed
// references or invokes guest callbacks. Independent IDs may be interleaved.
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
    checked(TOKENS.with_borrow_mut(|tokens| tokens.parse(id, 10)))
}

#[unsafe(export_name = "snail:datum/token-parse-radix")]
pub extern "C" fn token_parse_radix(id: u32, radix: u32) -> i32 {
    checked(TOKENS.with_borrow_mut(|tokens| tokens.parse(id, radix)))
}

#[unsafe(export_name = "snail:datum/token-identifier")]
pub extern "C" fn token_identifier(id: u32) -> i32 {
    checked(TOKENS.with_borrow(|tokens| Ok(i32::from(identifier(tokens.get(id)?.text())))))
}

// ---- Identifier grammar for the SFIR datum reader ----

fn identifier_initial(character: char) -> bool {
    character.is_alphabetic() || "!$%&*/:<=>?^_~@".contains(character)
}

// The sign and dot forms are peculiar identifiers only when their next
// character satisfies the grammar. Thus +x is a symbol, but +2oops is not.
fn identifier(text: &str) -> bool {
    let mut characters = text.chars();
    let sign_next = |c| identifier_initial(c) || matches!(c, '+' | '-');
    let dot_next = |c| sign_next(c) || c == '.';
    let valid_start = match characters.next() {
        Some('+' | '-') => match characters.next() {
            None => true,
            Some('.') => characters.next().is_some_and(dot_next),
            Some(c) => sign_next(c),
        },
        Some('.') => characters.next().is_some_and(dot_next),
        Some(c) => identifier_initial(c),
        None => false,
    };
    valid_start
        && characters.all(|c| identifier_initial(c) || c.is_ascii_digit() || "+-.".contains(c))
}

// ---- Typed scalar result access; a failed parse has no numeric fields ----

fn checked_text_length(count: usize) -> Result<u32, String> {
    i32::try_from(count)
        .map(|count| count as u32)
        .map_err(|_| "token text exceeds scalar index range".into())
}

#[unsafe(export_name = "snail:datum/number-kind")]
pub extern "C" fn number_kind(id: u32, part: u32) -> i32 {
    checked(TOKENS.with_borrow(|tokens| Ok(tokens.get(id)?.number()?.component(part)?.kind())))
}

#[unsafe(export_name = "snail:datum/number-integer")]
pub extern "C" fn number_integer(id: u32, part: u32) -> i64 {
    checked(
        TOKENS.with_borrow(|tokens| match tokens.get(id)?.number()?.component(part)? {
            Scalar::Integer(value) => Ok(*value),
            _ => Err("numeric component is not a machine integer".into()),
        }),
    )
}

#[unsafe(export_name = "snail:datum/number-real")]
pub extern "C" fn number_real(id: u32, part: u32) -> f64 {
    checked(
        TOKENS.with_borrow(|tokens| match tokens.get(id)?.number()?.component(part)? {
            Scalar::Real(value) => Ok(*value),
            _ => Err("numeric component is not inexact".into()),
        }),
    )
}

#[unsafe(export_name = "snail:datum/number-radix")]
pub extern "C" fn number_radix(id: u32, part: u32) -> u32 {
    checked(
        TOKENS.with_borrow(|tokens| Ok(tokens.get(id)?.number()?.component(part)?.exact()?.radix)),
    )
}

#[unsafe(export_name = "snail:datum/number-scale")]
pub extern "C" fn number_scale(id: u32, part: u32) -> i64 {
    checked(
        TOKENS.with_borrow(|tokens| Ok(tokens.get(id)?.number()?.component(part)?.exact()?.scale)),
    )
}

#[unsafe(export_name = "snail:datum/number-text-length")]
pub extern "C" fn number_text_length(id: u32, part: u32, term: u32) -> u32 {
    checked(
        TOKENS.with_borrow(|tokens| checked_text_length(tokens.exact_text(id, part, term)?.len())),
    )
}

#[unsafe(export_name = "snail:datum/number-text-character")]
pub extern "C" fn number_text_character(id: u32, part: u32, term: u32, index: u32) -> u32 {
    checked(TOKENS.with_borrow(|tokens| {
        tokens
            .exact_text(id, part, term)?
            .as_bytes()
            .get(index as usize)
            .copied()
            .map(u32::from)
            .ok_or_else(|| "exact numeric digit index out of range".into())
    }))
}

// Formatting owns only Rust text. Scheme copies it before consuming the handle.
#[unsafe(export_name = "snail:datum/real-text")]
pub extern "C" fn real_text(value: f64) -> u32 {
    checked(TOKENS.with_borrow_mut(|tokens| {
        let id = tokens.open()?;
        tokens
            .live
            .insert(id, Token::Text(crate::float_text(value)));
        Ok(id)
    }))
}

#[unsafe(export_name = "snail:datum/token-text-length")]
pub extern "C" fn token_text_length(id: u32) -> u32 {
    checked(
        TOKENS.with_borrow(|tokens| checked_text_length(tokens.get(id)?.text().chars().count())),
    )
}

#[unsafe(export_name = "snail:datum/token-text-character")]
pub extern "C" fn token_text_character(id: u32, index: u32) -> u32 {
    checked(TOKENS.with_borrow(|tokens| {
        tokens
            .get(id)?
            .text()
            .chars()
            .nth(index as usize)
            .map(u32::from)
            .ok_or_else(|| "token character index out of range".into())
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

// ---- Interned symbols share one stable scalar namespace ----

static SYMBOLS: OnceLock<Mutex<Symbols>> = OnceLock::new();

fn with_symbols<T>(operation: impl FnOnce(&mut Symbols) -> Result<T, String>) -> Result<T, String> {
    let mut symbols = SYMBOLS
        .get_or_init(|| Mutex::new(Symbols::default()))
        .lock()
        .map_err(|_| "symbol table lock poisoned")?;
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

    #[test]
    fn identifiers_follow_the_sign_and_dot_grammar() {
        for text in ["+", "-", "...", "+x", "+.x", ".+", "λ-2", "@x"] {
            assert!(identifier(text), "{text}");
        }
        for text in ["", ".", "+.", "+2oops", "1x", "a#b", "a\\b", "x y"] {
            assert!(!identifier(text), "{text}");
        }
    }

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
        let second = staged(&mut tokens, "1/0");
        assert_eq!(tokens.parse(first, 10).unwrap(), 1);
        assert_eq!(tokens.parse(second, 10).unwrap(), 4);
        assert!(tokens.get(second).unwrap().number().is_err());
        assert_eq!(
            tokens.get(first).unwrap().number().unwrap(),
            &Number::Scalar(Scalar::Integer(42))
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
            assert_eq!(tokens.parse(id, 10).unwrap(), 0);
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
        for (text, kind) in [
            ("42", 1),
            ("1.0", 2),
            ("1+2i", 3),
            ("1/2", 5),
            ("#e1.5", 5),
            ("1/0", 4),
        ] {
            let id = staged(&mut tokens, text);
            assert_eq!(tokens.parse(id, 10).unwrap(), kind);
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
    fn real_equivalence_preserves_zero_sign_and_equates_nans() {
        assert_eq!(real_equivalent(0.0, -0.0), 0);
        assert_eq!(real_equivalent(f64::NAN, -f64::NAN), 1);
        assert_eq!(real_equivalent(f64::INFINITY, f64::INFINITY), 1);
    }

    #[test]
    fn text_lengths_fit_the_signed_scheme_index() {
        assert_eq!(checked_text_length(i32::MAX as usize), Ok(i32::MAX as u32));
        assert!(checked_text_length(i32::MAX as usize + 1).is_err());
    }

    #[test]
    fn symbol_services_share_names_and_scalar_indices() {
        let mut symbols = Symbols::default();
        let first = symbols.intern("λ😀\0".into()).unwrap();
        assert_eq!(first, symbols.intern("λ😀\0".into()).unwrap());
        assert_ne!(first, symbols.intern("Λ😀\0".into()).unwrap());
        assert_eq!(symbols.length(first).unwrap(), 3);
        assert_eq!(symbols.character(first, 1).unwrap(), 0x1f600);
        assert!(symbols.character(first, 3).is_err());
    }

    #[test]
    fn failed_reparse_consumes_the_previous_result_and_cleanup_keeps_ids_monotonic() {
        let mut tokens = Tokens::default();
        let first = staged(&mut tokens, "1");
        tokens.parse(first, 10).unwrap();
        assert!(tokens.parse(first, 10).is_err());
        assert!(tokens.get(first).is_err());
        for _ in 0..10000 {
            let id = staged(&mut tokens, "12.5");
            tokens.parse(id, 10).unwrap();
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
