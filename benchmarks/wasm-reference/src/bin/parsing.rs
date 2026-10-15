// Copyright 2006 William D Clinger.
//
// Permission to copy this software, in whole or in part, to use this
// software for any lawful purpose, and to redistribute this software
// is granted subject to the restriction that all copies made of this
// software must include this copyright notice in full.
//
// I also request that you send me a copy of any improvements that you
// make to this software so that they may be incorporated within it to
// the benefit of the Scheme community.

use r7rs_wasm_reference::{Datum, input, read_char, report};
use std::collections::{HashMap, LinkedList};
use std::fmt::{self, Display};
use std::fs::File;
use std::hint::black_box;
use std::io::{self, BufReader};
use std::rc::Rc;
use std::time::Instant;

// ---- Parsed values with separately allocated list cells ----

#[derive(Clone, Debug, PartialEq)]
enum Numeric {
    Integer(i64),
    Rational(i64, i64),
    Real(f64),
}
#[derive(Clone, Debug, PartialEq)]
enum Value {
    Empty,
    Pair(Rc<Pair>),
    Vector(Rc<Vec<Value>>),
    Symbol(Rc<str>),
    String(Rc<str>),
    Character(char),
    Boolean(bool),
    Number(Numeric),
}
#[derive(Debug, PartialEq)]
struct Pair {
    first: Value,
    rest: Value,
}
fn cons(first: Value, rest: Value) -> Value {
    Value::Pair(Rc::new(Pair { first, rest }))
}
fn abbreviation(name: Value, value: Value) -> Value {
    cons(name, cons(value, Value::Empty))
}
fn pseudo_append(values: &Value, terminus: Value) -> Result<Value, ParseError> {
    match values {
        Value::Empty => Ok(terminus),
        Value::Pair(cell) => Ok(cons(
            cell.first.clone(),
            pseudo_append(&cell.rest, terminus)?,
        )),
        _ => Err(ParseError {
            line: 0,
            message: "improper pseudo-append input",
        }),
    }
}
fn vector_values(mut values: &Value) -> Vec<Value> {
    let mut result = Vec::new();
    while let Value::Pair(cell) = values {
        result.push(cell.first.clone());
        values = &cell.rest;
    }
    assert!(matches!(values, Value::Empty));
    result
}
fn rational(numerator: i64, denominator: i64) -> Option<Numeric> {
    if denominator == 0 {
        return None;
    }
    let (mut a, mut b) = (numerator.abs(), denominator.abs());
    while b != 0 {
        (a, b) = (b, a % b);
    }
    let divisor = a * denominator.signum();
    let (n, d) = (numerator / divisor, denominator / divisor);
    Some(if d == 1 {
        Numeric::Integer(n)
    } else {
        Numeric::Rational(n, d)
    })
}
fn number(text: &str) -> Option<Numeric> {
    if let Ok(n) = text.parse() {
        return Some(Numeric::Integer(n));
    }
    let normalized: String = text
        .chars()
        .map(|c| match c {
            '#' => '0',
            's' | 'f' | 'd' | 'l' => 'e',
            _ => c,
        })
        .collect();
    if let Some((n, d)) = normalized.split_once('/') {
        if text.contains('#') {
            return Some(Numeric::Real(
                n.parse::<f64>().ok()? / d.parse::<f64>().ok()?,
            ));
        }
        return rational(n.parse().ok()?, d.parse().ok()?);
    }
    if text.contains(['.', '#', 'e', 's', 'f', 'd', 'l']) {
        return normalized.parse().ok().map(Numeric::Real);
    }
    None
}
#[derive(Default)]
struct Symbols {
    names: HashMap<String, Rc<str>>,
}
impl Symbols {
    fn get(&mut self, name: &str) -> Value {
        Value::Symbol(
            self.names
                .entry(name.to_owned())
                .or_insert_with(|| Rc::from(name))
                .clone(),
        )
    }
    fn datum(&mut self, datum: &Datum) -> Value {
        match datum {
            Datum::Atom(s) if s == "#t" || s == "#f" => Value::Boolean(s == "#t"),
            Datum::Atom(s) => number(s).map(Value::Number).unwrap_or_else(|| self.get(s)),
            Datum::String(s) => Value::String(Rc::from(s.as_str())),
            Datum::Character(c) => Value::Character(*c),
            Datum::List(values) => values
                .iter()
                .rev()
                .fold(Value::Empty, |tail, d| cons(self.datum(d), tail)),
            Datum::Dotted(values, tail) => {
                let mut tail = self.datum(tail);
                for value in values.iter().rev() {
                    tail = cons(self.datum(value), tail);
                }
                tail
            }
            Datum::Vector(values) => {
                Value::Vector(Rc::new(values.iter().map(|d| self.datum(d)).collect()))
            }
            _ => panic!("datum outside the source parser's grammar"),
        }
    }
}

// ---- Original one-character and one-token buffers ----

const EOF: char = '~';
const MAX_TOKEN: usize = 1024;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Token {
    End,
    Quote,
    Backquote,
    Comma,
    Splicing,
    Left,
    Right,
    Period,
    Vector,
    Boolean,
    Character,
    Number,
    String,
    Identifier,
}
impl Token {
    fn simple(self) -> bool {
        matches!(
            self,
            Self::Boolean | Self::Character | Self::Number | Self::String | Self::Identifier
        )
    }
    fn datum(self) -> bool {
        self.simple()
            || matches!(
                self,
                Self::Quote
                    | Self::Backquote
                    | Self::Comma
                    | Self::Splicing
                    | Self::Left
                    | Self::Vector
            )
    }
}
#[derive(Clone, Copy)]
enum State {
    Initial,
    Comma,
    String,
    Hash,
    Character,
    CharacterName { suffix: &'static [u8], index: usize },
    Identifier,
    Dot,
    TwoDots,
    Signed,
    DecimalFirst,
    Integer,
    IntegerHashes,
    DecimalDigits,
    DecimalHashes,
    DenominatorFirst,
    DenominatorDigits,
    DenominatorHashes,
    ExponentFirst,
    ExponentDigitFirst,
    ExponentDigits,
    Comment,
    Whitespace,
}
#[derive(Debug)]
struct ParseError {
    line: usize,
    message: &'static str,
}
impl Display for ParseError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "{} in line {}", self.message, self.line)
    }
}
impl std::error::Error for ParseError {}
struct Parser<'a> {
    input: &'a [char],
    index: usize,
    character: Option<char>,
    token: Option<Token>,
    accumulator: Vec<char>,
    token_value: String,
    line: usize,
    symbols: &'a mut Symbols,
}
impl<'a> Parser<'a> {
    fn new(input: &'a [char], symbols: &'a mut Symbols) -> Self {
        Self {
            input,
            index: 0,
            character: None,
            token: None,
            accumulator: Vec::with_capacity(MAX_TOKEN),
            token_value: String::new(),
            line: 1,
            symbols,
        }
    }
    fn error(&self, message: &'static str) -> ParseError {
        ParseError {
            line: self.line,
            message,
        }
    }
    fn scan_character(&mut self) -> char {
        if let Some(character) = self.character {
            return character;
        }
        let character = if self.index < self.input.len() {
            let character = self.input[self.index];
            self.index += 1;
            character
        } else {
            EOF
        };
        self.character = Some(character);
        character
    }
    fn consume_character(&mut self) -> Result<(), ParseError> {
        let character = self.scan_character();
        if self.accumulator.len() == MAX_TOKEN {
            return Err(self.error("amazingly long token"));
        }
        self.character = None;
        self.line += usize::from(character == '\n');
        self.accumulator.push(character);
        Ok(())
    }
    fn accept(&mut self, token: Token) -> Token {
        if token.simple() {
            self.token_value = self.accumulator.iter().collect();
        }
        token
    }
    fn consume_accept(&mut self, token: Token) -> Result<Token, ParseError> {
        self.consume_character()?;
        Ok(self.accept(token))
    }
    fn next_token(&mut self) -> Result<Token, ParseError> {
        if let Some(token) = self.token {
            return Ok(token);
        }
        self.accumulator.clear();
        let token = self.scan_token()?;
        self.token = Some(token);
        Ok(token)
    }
    fn consume_token(&mut self) {
        self.token = None;
    }

    // ---- Direct LexGen state transitions ----

    // This exhaustive transition table keeps every source grammar decision
    // together. Character-name chains are represented by their remaining text;
    // the generated terminal-forwarding states have no additional behavior.
    fn scan_token(&mut self) -> Result<Token, ParseError> {
        while self.scan_character().is_whitespace() {
            self.consume_character()?;
            self.accumulator.clear();
        }
        if self.scan_character() == EOF {
            return Ok(self.accept(Token::End));
        }
        let mut state = State::Initial;
        loop {
            let c = self.scan_character();
            state = match state {
                State::Initial => match c {
                    '`' => return self.consume_accept(Token::Backquote),
                    '\'' => return self.consume_accept(Token::Quote),
                    ')' => return self.consume_accept(Token::Right),
                    '(' => return self.consume_accept(Token::Left),
                    ';' => {
                        self.consume_character()?;
                        State::Comment
                    }
                    '+' | '-' => {
                        self.consume_character()?;
                        State::Signed
                    }
                    '0'..='9' => {
                        self.consume_character()?;
                        State::Integer
                    }
                    '.' => {
                        self.consume_character()?;
                        State::Dot
                    }
                    '#' => {
                        self.consume_character()?;
                        State::Hash
                    }
                    '"' => {
                        self.consume_character()?;
                        State::String
                    }
                    ',' => {
                        self.consume_character()?;
                        State::Comma
                    }
                    _ if identifier_initial(c) => {
                        self.consume_character()?;
                        State::Identifier
                    }
                    _ if c.is_whitespace() => {
                        self.consume_character()?;
                        State::Whitespace
                    }
                    _ => return Err(self.error("incomplete token")),
                },
                State::Comma => {
                    if c == '@' {
                        return self.consume_accept(Token::Splicing);
                    } else {
                        return Ok(self.accept(Token::Comma));
                    }
                }
                State::String => {
                    if c == '"' {
                        return self.consume_accept(Token::String);
                    } else {
                        self.consume_character()?;
                        State::String
                    }
                }
                State::Hash => match c {
                    '(' => return self.consume_accept(Token::Vector),
                    't' | 'f' => return self.consume_accept(Token::Boolean),
                    '\\' => {
                        self.consume_character()?;
                        State::Character
                    }
                    _ => return Err(self.error("incomplete token")),
                },
                State::Character => match c {
                    's' => {
                        self.consume_character()?;
                        State::CharacterName {
                            suffix: b"pace",
                            index: 0,
                        }
                    }
                    'n' => {
                        self.consume_character()?;
                        State::CharacterName {
                            suffix: b"ewline",
                            index: 0,
                        }
                    }
                    _ => return self.consume_accept(Token::Character),
                },
                State::CharacterName { suffix, index } => {
                    if c != suffix[index] as char {
                        return Err(self.error("incomplete token"));
                    }
                    self.consume_character()?;
                    if index + 1 == suffix.len() {
                        return Ok(self.accept(Token::Character));
                    }
                    State::CharacterName {
                        suffix,
                        index: index + 1,
                    }
                }
                State::Identifier => {
                    if identifier_subsequent(c) {
                        self.consume_character()?;
                        State::Identifier
                    } else {
                        return Ok(self.accept(Token::Identifier));
                    }
                }
                State::Dot => match c {
                    '0'..='9' => {
                        self.consume_character()?;
                        State::DecimalDigits
                    }
                    '.' => {
                        self.consume_character()?;
                        State::TwoDots
                    }
                    _ => return Ok(self.accept(Token::Period)),
                },
                State::TwoDots => {
                    if c == '.' {
                        return self.consume_accept(Token::Identifier);
                    } else {
                        return Err(self.error("incomplete token"));
                    }
                }
                State::Signed => match c {
                    '0'..='9' => {
                        self.consume_character()?;
                        State::Integer
                    }
                    '.' => {
                        self.consume_character()?;
                        State::DecimalFirst
                    }
                    _ => return Ok(self.accept(Token::Identifier)),
                },
                State::DecimalFirst => {
                    if c.is_ascii_digit() {
                        self.consume_character()?;
                        State::DecimalDigits
                    } else {
                        return Err(self.error("incomplete token"));
                    }
                }
                State::Integer => match c {
                    '0'..='9' => {
                        self.consume_character()?;
                        State::Integer
                    }
                    '#' => {
                        self.consume_character()?;
                        State::IntegerHashes
                    }
                    '/' => {
                        self.consume_character()?;
                        State::DenominatorFirst
                    }
                    '.' => {
                        self.consume_character()?;
                        State::DecimalDigits
                    }
                    _ if exponent_marker(c) => {
                        self.consume_character()?;
                        State::ExponentFirst
                    }
                    _ => return Ok(self.accept(Token::Number)),
                },
                State::IntegerHashes => match c {
                    '#' => {
                        self.consume_character()?;
                        State::IntegerHashes
                    }
                    '/' => {
                        self.consume_character()?;
                        State::DenominatorFirst
                    }
                    '.' => {
                        self.consume_character()?;
                        State::DecimalHashes
                    }
                    _ if exponent_marker(c) => {
                        self.consume_character()?;
                        State::ExponentFirst
                    }
                    _ => return Ok(self.accept(Token::Number)),
                },
                State::DecimalDigits => match c {
                    '0'..='9' => {
                        self.consume_character()?;
                        State::DecimalDigits
                    }
                    '#' => {
                        self.consume_character()?;
                        State::DecimalHashes
                    }
                    _ if exponent_marker(c) => {
                        self.consume_character()?;
                        State::ExponentFirst
                    }
                    _ => return Ok(self.accept(Token::Number)),
                },
                State::DecimalHashes => match c {
                    '#' => {
                        self.consume_character()?;
                        State::DecimalHashes
                    }
                    _ if exponent_marker(c) => {
                        self.consume_character()?;
                        State::ExponentFirst
                    }
                    _ => return Ok(self.accept(Token::Number)),
                },
                State::DenominatorFirst => {
                    if c.is_ascii_digit() {
                        self.consume_character()?;
                        State::DenominatorDigits
                    } else {
                        return Err(self.error("incomplete token"));
                    }
                }
                State::DenominatorDigits => match c {
                    '0'..='9' => {
                        self.consume_character()?;
                        State::DenominatorDigits
                    }
                    '#' => {
                        self.consume_character()?;
                        State::DenominatorHashes
                    }
                    _ => return Ok(self.accept(Token::Number)),
                },
                State::DenominatorHashes => {
                    if c == '#' {
                        self.consume_character()?;
                        State::DenominatorHashes
                    } else {
                        return Ok(self.accept(Token::Number));
                    }
                }
                State::ExponentFirst => match c {
                    '+' | '-' => {
                        self.consume_character()?;
                        State::ExponentDigitFirst
                    }
                    '0'..='9' => {
                        self.consume_character()?;
                        State::ExponentDigits
                    }
                    _ => return Err(self.error("incomplete token")),
                },
                State::ExponentDigitFirst => {
                    if c.is_ascii_digit() {
                        self.consume_character()?;
                        State::ExponentDigits
                    } else {
                        return Err(self.error("incomplete token"));
                    }
                }
                State::ExponentDigits => {
                    if c.is_ascii_digit() {
                        self.consume_character()?;
                        State::ExponentDigits
                    } else {
                        return Ok(self.accept(Token::Number));
                    }
                }
                State::Comment => {
                    self.consume_character()?;
                    if c == '\n' {
                        self.accumulator.clear();
                        State::Initial
                    } else {
                        State::Comment
                    }
                }
                State::Whitespace => {
                    if c.is_whitespace() {
                        self.consume_character()?;
                        State::Whitespace
                    } else {
                        self.accumulator.clear();
                        State::Initial
                    }
                }
            };
        }
    }

    // ---- The original strong LL(1) parser and list-tail copy ----

    fn syntax_error(&mut self) -> Result<Value, ParseError> {
        if self.next_token()? == Token::End {
            Ok(self.symbols.get("eof"))
        } else {
            Err(self.error("syntax error"))
        }
    }
    fn parse_datum(&mut self) -> Result<Value, ParseError> {
        match self.next_token()? {
            token if token.simple() => self.parse_simple(token),
            Token::Left => {
                self.consume_token();
                self.parse_list2()
            }
            Token::Vector => self.parse_vector(),
            Token::Quote | Token::Backquote | Token::Comma | Token::Splicing => {
                self.parse_abbreviation()
            }
            _ => self.syntax_error(),
        }
    }
    fn parse_simple(&mut self, token: Token) -> Result<Value, ParseError> {
        self.consume_token();
        Ok(match token {
            Token::Identifier => self.symbols.get(&self.token_value),
            Token::Boolean => Value::Boolean(self.token_value == "#t"),
            Token::Number => number(&self.token_value)
                .map(Value::Number)
                .unwrap_or(Value::Boolean(false)),
            // The source action reads character zero of the entire token.
            Token::Character => Value::Character(self.token_value.chars().next().unwrap()),
            Token::String => {
                Value::String(Rc::from(&self.token_value[1..self.token_value.len() - 1]))
            }
            _ => unreachable!(),
        })
    }
    fn parse_list2(&mut self) -> Result<Value, ParseError> {
        match self.next_token()? {
            Token::Right => {
                self.consume_token();
                Ok(Value::Empty)
            }
            token if token.datum() => {
                let first = self.parse_datum()?;
                Ok(cons(first, self.parse_list3()?))
            }
            _ => self.syntax_error(),
        }
    }
    fn parse_list3(&mut self) -> Result<Value, ParseError> {
        let token = self.next_token()?;
        if !token.datum() && token != Token::Right && token != Token::Period {
            return self.syntax_error();
        }
        let values = self.parse_data()?;
        let terminus = self.parse_list4()?;
        pseudo_append(&values, terminus)
    }
    fn parse_list4(&mut self) -> Result<Value, ParseError> {
        match self.next_token()? {
            Token::Right => {
                self.consume_token();
                Ok(Value::Empty)
            }
            Token::Period => {
                self.consume_token();
                let tail = self.parse_datum()?;
                if self.next_token()? != Token::Right {
                    return self.syntax_error();
                }
                self.consume_token();
                Ok(tail)
            }
            _ => self.syntax_error(),
        }
    }
    fn parse_data(&mut self) -> Result<Value, ParseError> {
        match self.next_token()? {
            Token::Right | Token::Period => Ok(Value::Empty),
            token if token.datum() => {
                let first = self.parse_datum()?;
                Ok(cons(first, self.parse_data()?))
            }
            _ => self.syntax_error(),
        }
    }
    fn parse_vector(&mut self) -> Result<Value, ParseError> {
        self.consume_token();
        let data = self.parse_data()?;
        if self.next_token()? != Token::Right {
            return self.syntax_error();
        }
        self.consume_token();
        Ok(Value::Vector(Rc::new(vector_values(&data))))
    }
    fn parse_abbreviation(&mut self) -> Result<Value, ParseError> {
        let name = match self.next_token()? {
            Token::Quote => "quote",
            Token::Backquote => "quasiquote",
            Token::Comma => "unquote",
            Token::Splicing => "unquote-splicing",
            _ => unreachable!(),
        };
        self.consume_token();
        let name = self.symbols.get(name);
        Ok(abbreviation(name, self.parse_datum()?))
    }
    fn parse_string(&mut self) -> Result<Value, ParseError> {
        let mut current = self.parse_datum()?;
        let mut previous = self.symbols.get("eof");
        loop {
            if matches!(&current, Value::Symbol(s) if s.as_ref() == "eof") {
                return Ok(previous);
            }
            // Both source do-loop values remain alive while the next datum is
            // parsed; dropping the previous datum before this call changes that.
            let next = self.parse_datum()?;
            previous = current;
            current = next;
        }
    }
}
fn identifier_initial(character: char) -> bool {
    character.is_ascii_alphabetic() || "!$%&*/:<=>?^_~".contains(character)
}
fn identifier_subsequent(character: char) -> bool {
    identifier_initial(character) || character.is_ascii_digit() || "+-.@".contains(character)
}
fn exponent_marker(character: char) -> bool {
    "esfdl".contains(character)
}

// ---- Character-list file loading and the original inner repetition count ----

fn read_file(path: &str) -> io::Result<Vec<char>> {
    let mut port = BufReader::new(File::open(path)?);
    let mut characters = LinkedList::new();
    while let Some(character) = read_char(&mut port)? {
        characters.push_front(character);
    }
    let reversed: LinkedList<_> = characters.iter().rev().copied().collect();
    Ok(reversed.iter().copied().collect())
}
fn benchmark(n: usize, path: &str, symbols: &mut Symbols) -> io::Result<Value> {
    let input = read_file(path)?;
    let mut result = Value::Boolean(false);
    for _ in 0..n {
        result = black_box(
            Parser::new(black_box(&input), symbols)
                .parse_string()
                .map_err(io::Error::other)?,
        );
    }
    Ok(result)
}
impl Display for Value {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => write!(out, "()"),
            Self::Pair(_) => write_list(self, out),
            Self::Symbol(s) => write!(out, "{s}"),
            Self::String(s) => write!(out, "{s:?}"),
            Self::Boolean(b) => write!(out, "#{}", if *b { "t" } else { "f" }),
            Self::Character(c) => write!(out, "{}", Datum::Character(*c)),
            Self::Number(Numeric::Integer(n)) => write!(out, "{n}"),
            Self::Number(Numeric::Rational(n, d)) => write!(out, "{n}/{d}"),
            Self::Number(Numeric::Real(n)) => write!(out, "{n:?}"),
            Self::Vector(values) => {
                write!(out, "#(")?;
                for (i, value) in values.iter().enumerate() {
                    if i > 0 {
                        write!(out, " ")?;
                    }
                    write!(out, "{value}")?;
                }
                write!(out, ")")
            }
        }
    }
}
fn write_list(mut list: &Value, out: &mut fmt::Formatter<'_>) -> fmt::Result {
    write!(out, "(")?;
    let mut first = true;
    while let Value::Pair(cell) = list {
        if !first {
            write!(out, " ")?;
        }
        write!(out, "{}", cell.first)?;
        list = &cell.rest;
        first = false;
    }
    if !matches!(list, Value::Empty) {
        write!(out, " . {list}")?;
    }
    write!(out, ")")
}
fn main() -> io::Result<()> {
    let values = input()?;
    let n = values[0].number();
    let mut symbols = Symbols::default();
    let expected = symbols.datum(&values[2]);
    let start = Instant::now();
    let result = black_box(benchmark(black_box(n), values[1].atom(), &mut symbols)?);
    assert_eq!(result, expected);
    report("parsing", n, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use r7rs_wasm_reference::read_all;
    fn parsed(text: &str) -> Result<Value, ParseError> {
        Parser::new(&text.chars().collect::<Vec<_>>(), &mut Symbols::default()).parse_string()
    }
    fn expected(text: &str) -> Value {
        Symbols::default().datum(&read_all(text)[0])
    }
    #[test]
    fn complete_lists_vectors_abbreviations_and_source_actions() {
        let actual =
            parsed("old '(a . b) (last #(1 2) (a . b) \"raw\\n\" #\\space 3/2 -.5)").unwrap();
        assert_eq!(
            actual,
            expected("(last #(1 2) (a . b) \"raw\\\\n\" #\\# 3/2 -0.5)")
        );
        assert_eq!(
            parsed("`(,a ,@b)").unwrap(),
            expected("(quasiquote ((unquote a) (unquote-splicing b)))")
        );
    }
    #[test]
    fn source_eof_sentinel_and_recovery_are_preserved() {
        assert_eq!(parsed("x eof y").unwrap(), expected("x"));
        assert_eq!(parsed("x (").unwrap(), expected("x"));
        assert_eq!(parsed("(x ").unwrap(), expected("(x . eof)"));
        assert!(parsed("(x").is_err());
        assert_eq!(parsed("'").unwrap(), expected("(quote eof)"));
    }
    #[test]
    fn lexer_limits_and_syntax_errors_remain_visible() {
        assert!(parsed("(a . b c)").is_err());
        assert!(parsed("#\\n").is_err());
        assert!(parsed("\"unclosed").is_err());
        assert!(parsed(&format!("{} ", "a".repeat(MAX_TOKEN + 1))).is_err());
        assert!(parsed("; comment at eof").is_err());
    }
    #[test]
    fn pseudo_append_copies_prefix_and_shares_actual_terminus() {
        let suffix = cons(Value::Boolean(true), Value::Empty);
        let input = cons(Value::Boolean(false), Value::Empty);
        let result = pseudo_append(&input, suffix.clone()).unwrap();
        let (Value::Pair(result), Value::Pair(suffix), Value::Pair(input)) =
            (result, suffix, input)
        else {
            unreachable!()
        };
        assert!(!Rc::ptr_eq(&result, &input));
        let Value::Pair(tail) = &result.rest else {
            unreachable!()
        };
        assert!(Rc::ptr_eq(tail, &suffix));
    }
}
