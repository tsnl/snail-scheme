//! Scalar services for Lofi's real-number text. Lofi parses integers and
//! ratios itself; Rust owns temporary text handles: tokens to parse as reals,
//! with correct rounding, and formatted floats to copy out.

use std::{cell::RefCell, collections::BTreeMap};

// ---- Owned text transitions once to a parsed numeric result ----

enum Token {
    Text(String),
    Parsed { text: String, real: Option<f64> },
}

#[derive(Default)]
struct Tokens {
    next: u32,
    live: BTreeMap<u32, Token>,
}

impl Tokens {
    // IDs increase to i32::MAX, then wrap to zero, skipping live handles. A
    // closed handle stays invalid until its ID comes around again, so a long
    // run never exhausts the space while fewer than 2^31 handles are open.
    fn open(&mut self) -> Result<u32, String> {
        if self.live.len() > i32::MAX as usize {
            return Err("token handle space exhausted".into());
        }
        let mut id = self.next;
        while self.live.contains_key(&id) {
            id = Self::after(id);
        }
        self.next = Self::after(id);
        self.live.insert(id, Token::Text(String::new()));
        Ok(id)
    }

    fn after(id: u32) -> u32 {
        if id >= i32::MAX as u32 { 0 } else { id + 1 }
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

    // 1 if the text is a real number, otherwise 0.
    fn parse(&mut self, id: u32) -> Result<i32, String> {
        let Token::Text(text) = self.take(id)? else {
            return Err("token has already been parsed".into());
        };
        let real = crate::parse_float(&text);
        let tag = i32::from(real.is_some());
        self.live.insert(id, Token::Parsed { text, real });
        Ok(tag)
    }
}

impl Token {
    fn text(&self) -> &str {
        match self {
            Self::Text(text) | Self::Parsed { text, .. } => text,
        }
    }

    fn real(&self) -> Result<f64, String> {
        match self {
            Self::Parsed {
                real: Some(value), ..
            } => Ok(*value),
            _ => Err("token is not a parsed real number".into()),
        }
    }
}

thread_local! { static TOKENS: RefCell<Tokens> = RefCell::new(Tokens::default()); }

// IDs are reused only after wrapping around (see Tokens::open). Each operation
// ends its RefCell borrow before reporting a fatal error; no temporary stores managed
// references or invokes guest callbacks. Independent IDs may be interleaved.
pub(crate) fn close_all() {
    TOKENS.with_borrow_mut(|tokens| tokens.live.clear());
}

fn checked<T>(result: Result<T, String>) -> T {
    result.unwrap_or_else(|error| {
        crate::io::close_all();
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

// ---- Typed scalar result access; a failed parse has no numeric fields ----

fn checked_text_length(count: usize) -> Result<u32, String> {
    i32::try_from(count)
        .map(|count| count as u32)
        .map_err(|_| "token text exceeds scalar index range".into())
}

#[unsafe(export_name = "snail:datum/number-real")]
pub extern "C" fn number_real(id: u32) -> f64 {
    checked(TOKENS.with_borrow(|tokens| tokens.get(id)?.real()))
}

// Formatting owns only Rust text. Lofi copies it before consuming the handle.
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

#[unsafe(export_name = "snail:datum/whitespace")]
pub extern "C" fn whitespace(code: u32) -> i32 {
    i32::from(
        checked(char::from_u32(code).ok_or_else(|| "invalid Unicode scalar".into()))
            .is_whitespace(),
    )
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_ids_wrap_and_skip_live_handles() {
        let mut tokens = Tokens {
            next: i32::MAX as u32,
            ..Tokens::default()
        };
        assert_eq!(tokens.open(), Ok(i32::MAX as u32));
        tokens.live.insert(0, Token::Text(String::new()));
        assert_eq!(tokens.open(), Ok(1));
        assert_eq!(tokens.next, 2);
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
        assert_eq!(tokens.parse(first).unwrap(), 0);
        assert_eq!(tokens.parse(second).unwrap(), 0);
        assert!(tokens.get(second).unwrap().real().is_err());
        let third = staged(&mut tokens, "4.5e1");
        assert_eq!(tokens.parse(third).unwrap(), 1);
        assert_eq!(tokens.get(third).unwrap().real().unwrap(), 45.0);
        assert!(tokens.append(first, 65).is_err());
        tokens.take(first).unwrap();
        assert!(tokens.get(first).is_err());
        assert!(tokens.open().unwrap() > second);
    }

    #[test]
    fn text_lengths_fit_the_signed_scheme_index() {
        assert_eq!(checked_text_length(i32::MAX as usize), Ok(i32::MAX as u32));
        assert!(checked_text_length(i32::MAX as usize + 1).is_err());
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
