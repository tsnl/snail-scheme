//! Native datum input. Parsing builds a compact graph of Rust-owned values;
//! only after its syntax is complete does AWI allocate the Scheme graph.
//! Every allocated object stays in an owned root until all edges are installed.

use crate::{awi::Root, host::TextInput};
use std::collections::BTreeMap;

// ---- Parsed values ----

#[derive(Debug, PartialEq)]
pub(crate) enum Number {
    Integer(i64),
    Real(f64),
    Complex(Scalar, Scalar),
}

impl Number {
    pub(crate) fn root(&self) -> Root {
        match self {
            Self::Integer(value) => Root::integer(*value),
            Self::Real(value) => Root::real(*value),
            Self::Complex(real, imag) => Root::complex(&real.root(), &imag.root()).unwrap(),
        }
    }
}

#[derive(Debug, PartialEq)]
pub(crate) enum Scalar {
    Integer(i64),
    Real(f64),
}

impl Scalar {
    fn value(&self) -> f64 {
        match self {
            Self::Integer(value) => *value as f64,
            Self::Real(value) => *value,
        }
    }

    fn root(&self) -> Root {
        match self {
            Self::Integer(value) => Root::integer(*value),
            Self::Real(value) => Root::real(*value),
        }
    }
}

impl From<Scalar> for Number {
    fn from(value: Scalar) -> Self {
        match value {
            Scalar::Integer(value) => Self::Integer(value),
            Scalar::Real(value) => Self::Real(value),
        }
    }
}

#[derive(Debug, PartialEq)]
enum Node {
    Nil,
    Boolean(bool),
    Number(Number),
    Character(char),
    String(String),
    Symbol(String),
    Pair(usize, usize),
    Vector(Vec<usize>),
    Bytes(Vec<u8>),
    Alias(usize),
    Pending,
}

pub(crate) struct Datum {
    nodes: Vec<Node>,
    // Construction resolves every label before Scheme allocation. These
    // immutable indices always identify concrete nodes, including in cycles.
    targets: Vec<usize>,
    root: usize,
}

impl Datum {
    fn new(nodes: Vec<Node>, root: usize) -> Result<Self, String> {
        let targets = alias_targets(&nodes)?;
        Ok(Self {
            nodes,
            targets,
            root,
        })
    }

    pub(crate) fn into_root(self) -> Result<Root, String> {
        let mut roots: Vec<_> = self.nodes.iter().map(allocate).collect();
        for (index, node) in self.nodes.iter().enumerate() {
            connect(node, roots[index].as_ref(), &roots, &self.targets)?;
        }
        Ok(roots[self.targets[self.root]].take().unwrap())
    }
}

fn alias_targets(nodes: &[Node]) -> Result<Vec<usize>, String> {
    let mut targets = vec![usize::MAX; nodes.len()];
    for index in 0..nodes.len() {
        let mut path = Vec::new();
        let mut current = index;
        while targets[current] == usize::MAX {
            targets[current] = current;
            path.push(current);
            match nodes[current] {
                Node::Alias(next) => current = next,
                Node::Pending => return Err("undefined datum label".into()),
                _ => break,
            }
        }
        if matches!(nodes[targets[current]], Node::Alias(_)) {
            return Err("datum label has no value".into());
        }
        for item in path {
            targets[item] = targets[current];
        }
    }
    Ok(targets)
}

fn allocate(node: &Node) -> Option<Root> {
    Some(match node {
        Node::Nil => Root::nil(),
        Node::Boolean(value) => Root::boolean(*value),
        Node::Number(value) => value.root(),
        Node::Character(value) => Root::character(*value),
        Node::String(value) => Root::string(value),
        Node::Symbol(value) => {
            crate::symbols::intern(value).unwrap_or_else(|error| crate::fail_message(&error))
        }
        Node::Pair(..) => Root::pair(&Root::nil(), &Root::nil()),
        Node::Vector(items) => Root::vector_sized(items.len()),
        Node::Bytes(bytes) => Root::bytevector(bytes),
        Node::Alias(_) | Node::Pending => return None,
    })
}

fn connect(
    node: &Node,
    root: Option<&Root>,
    roots: &[Option<Root>],
    targets: &[usize],
) -> Result<(), String> {
    let at = |index: usize| roots[targets[index]].as_ref().unwrap();
    match node {
        Node::Pair(car, cdr) => {
            root.unwrap().set_car(at(*car))?;
            root.unwrap().set_cdr(at(*cdr))?;
        }
        Node::Vector(items) => {
            for (index, item) in items.iter().enumerate() {
                root.unwrap().set_at(index, at(*item))?;
            }
        }
        _ => {}
    }
    Ok(())
}

// ---- Numeric tokens ----

pub(crate) fn number(text: &str, radix: u32) -> Result<Option<Number>, String> {
    let (text, radix, exactness) = number_prefixes(text, radix)?;
    if let Some(body) = text.strip_suffix(['i', 'I']) {
        return complex_number(body, radix, exactness);
    }
    if let Some((radius, angle)) = text.split_once('@') {
        return polar_number(radius, angle, radix, exactness);
    }
    Ok(real_number(text, radix, exactness)?.map(Number::from))
}

fn polar_number(
    radius: &str,
    angle: &str,
    radix: u32,
    exactness: Option<bool>,
) -> Result<Option<Number>, String> {
    let Some(radius) = real_number(radius, radix, exactness)? else {
        return Ok(None);
    };
    let Some(angle) = real_number(angle, radix, exactness)? else {
        return Ok(None);
    };
    if exactness == Some(true) {
        return if angle.value() == 0.0 {
            Ok(Some(radius.into()))
        } else {
            Err("exact polar number is not supported".into())
        };
    }
    let (radius, angle) = (radius.value(), angle.value());
    Ok(Some(Number::Complex(
        Scalar::Real(radius * angle.cos()),
        Scalar::Real(radius * angle.sin()),
    )))
}

fn complex_number(
    body: &str,
    radix: u32,
    exactness: Option<bool>,
) -> Result<Option<Number>, String> {
    let split = body.char_indices().rfind(|(index, character)| {
        *index > 0
            && matches!(character, '+' | '-')
            && !(radix == 10 && matches!(body.as_bytes()[index - 1], b'e' | b'E'))
    });
    let (real, imag) = split.map_or(("0", body), |(index, _)| body.split_at(index));
    if !imag.starts_with(['+', '-']) {
        return Ok(None);
    }
    let imag = match imag {
        "+" => "+1",
        "-" => "-1",
        _ => imag,
    };
    match (
        real_number(real, radix, exactness)?,
        real_number(imag, radix, exactness)?,
    ) {
        (Some(real), Some(imag)) => Ok(Some(Number::Complex(real, imag))),
        _ => Ok(None),
    }
}

fn real_number(text: &str, radix: u32, exactness: Option<bool>) -> Result<Option<Scalar>, String> {
    let integer = i64::from_str_radix(text, radix);
    if let Ok(integer) = integer {
        return Ok(Some(if exactness == Some(false) {
            Scalar::Real(if integer == 0 && text.starts_with('-') {
                -0.0
            } else {
                integer as f64
            })
        } else {
            Scalar::Integer(integer)
        }));
    }
    if radix == 10
        && let Some(real) = crate::parse_float(text)
    {
        return Ok(Some(if exactness == Some(true) {
            Scalar::Integer(exact_decimal(text)?)
        } else {
            Scalar::Real(real)
        }));
    }
    if integer.is_err_and(|error| {
        matches!(
            error.kind(),
            std::num::IntErrorKind::PosOverflow | std::num::IntErrorKind::NegOverflow
        ) && text
            .trim_start_matches(['+', '-'])
            .chars()
            .all(|c| c.to_digit(radix).is_some())
    }) {
        if exactness == Some(false) {
            return Ok(inexact_integer(text, radix).map(Scalar::Real));
        }
        return Err("integer overflow".into());
    }
    Ok(None)
}

fn inexact_integer(text: &str, radix: u32) -> Option<f64> {
    if radix == 10 {
        return text.parse().ok();
    }
    let digits = text.trim_start_matches(['+', '-']);
    let value = match u128::from_str_radix(digits, radix) {
        Ok(value) => value as f64,
        Err(_) => digits.chars().try_fold(0.0, |value, c| {
            c.to_digit(radix)
                .map(|digit| value * radix as f64 + digit as f64)
        })?,
    };
    Some(if text.starts_with('-') { -value } else { value })
}

fn number_prefixes(mut text: &str, mut radix: u32) -> Result<(&str, u32, Option<bool>), String> {
    let mut exactness = None;
    let mut radix_seen = false;
    while let Some([b'#', prefix]) = text.as_bytes().get(..2) {
        match prefix.to_ascii_lowercase() {
            b'e' | b'i' if exactness.is_none() => {
                exactness = Some(prefix.eq_ignore_ascii_case(&b'e'))
            }
            b'b' | b'o' | b'd' | b'x' if !radix_seen => {
                radix = match prefix.to_ascii_lowercase() {
                    b'b' => 2,
                    b'o' => 8,
                    b'x' => 16,
                    _ => 10,
                };
                radix_seen = true;
            }
            _ => return Ok((text, radix, exactness)),
        }
        text = &text[2..];
    }
    Ok((text, radix, exactness))
}

// Parse explicit exact decimals as digits, never through binary64: otherwise
// #e9007199254740993.0 silently loses an integer before exactness is applied.
fn exact_decimal(text: &str) -> Result<i64, String> {
    let unsigned = text.trim_start_matches(['+', '-']);
    let (mantissa, exponent) = unsigned.split_once(['e', 'E']).unwrap_or((unsigned, "0"));
    let mut digits = mantissa.replace('.', "");
    if digits.is_empty() || !digits.bytes().all(|c| c.is_ascii_digit()) {
        return Err("exact number outside supported integer range".into());
    }
    digits = digits.trim_start_matches('0').into();
    if digits.is_empty() {
        return Ok(0);
    }
    let fractional = mantissa.split_once('.').map_or(0, |(_, tail)| tail.len());
    let power = exponent
        .parse::<i64>()
        .ok()
        .and_then(|power| power.checked_sub(fractional as i64))
        .ok_or("exact number outside supported integer range")?;
    scale_decimal(&mut digits, power)?;
    if text.starts_with('-') {
        digits.insert(0, '-');
    }
    digits
        .parse()
        .map_err(|_| "exact number outside supported integer range".into())
}

fn scale_decimal(digits: &mut String, power: i64) -> Result<(), String> {
    if power < 0 {
        let zeros = digits.len() - digits.trim_end_matches('0').len();
        if power.unsigned_abs() > zeros as u64 {
            return Err("exact noninteger is not supported".into());
        }
        digits.truncate(digits.len() - power.unsigned_abs() as usize);
    } else {
        if power > 19 || digits.len() as i64 + power > 19 {
            return Err("exact number outside supported integer range".into());
        }
        digits.extend(std::iter::repeat_n('0', power as usize));
    }
    Ok(())
}

// ---- Parser frames ----

enum Tail {
    Proper,
    Waiting,
    Dotted(usize),
}

enum Frame {
    List(Vec<usize>, Tail),
    Vector(Vec<usize>),
    Bytes(Vec<u8>),
    Prefix(&'static str),
    Label(usize),
    Discard {
        start: usize,
        labels: BTreeMap<u64, usize>,
    },
}

enum Token {
    Value(Node),
    List,
    Vector,
    Bytes,
    Close,
    Dot,
    Prefix(&'static str),
    Label(u64),
    Reference(u64),
    Discard,
    Eof,
}

struct Reader<'a> {
    input: &'a mut TextInput,
    nodes: Vec<Node>,
    labels: BTreeMap<u64, usize>,
}

pub(crate) fn read(input: &mut TextInput) -> Result<Option<Datum>, String> {
    Reader {
        input,
        nodes: Vec::new(),
        labels: BTreeMap::new(),
    }
    .read()
    .map_err(|error| format!("read: {error}"))
}

impl Reader<'_> {
    fn push(&mut self, node: Node) -> usize {
        let index = self.nodes.len();
        self.nodes.push(node);
        index
    }

    // Frames hold unfinished containers and prefixes, so depth consumes heap
    // space rather than the Rust call stack. Flat lists use one frame.
    fn read(mut self) -> Result<Option<Datum>, String> {
        let mut frames = Vec::new();
        loop {
            let value = match self.token()? {
                Token::Eof if frames.is_empty() => return Ok(None),
                Token::Eof => return Err("unexpected end of input".into()),
                Token::Value(node) => Some(self.push(node)),
                Token::Close => Some(self.close(&mut frames)?),
                Token::Reference(label) => {
                    Some(*self.labels.get(&label).ok_or("undefined datum label")?)
                }
                token => {
                    self.open(token, &mut frames)?;
                    None
                }
            };
            if let Some(value) = value
                && let Some(root) = self.accept(value, &mut frames)?
            {
                return Datum::new(self.nodes, root).map(Some);
            }
        }
    }

    fn open(&mut self, token: Token, frames: &mut Vec<Frame>) -> Result<(), String> {
        match token {
            Token::List => frames.push(Frame::List(Vec::new(), Tail::Proper)),
            Token::Vector => frames.push(Frame::Vector(Vec::new())),
            Token::Bytes => frames.push(Frame::Bytes(Vec::new())),
            Token::Prefix(name) => frames.push(Frame::Prefix(name)),
            Token::Label(label) => {
                if self.labels.contains_key(&label) {
                    return Err("duplicate datum label".into());
                }
                let slot = self.push(Node::Pending);
                self.labels.insert(label, slot);
                frames.push(Frame::Label(slot));
            }
            Token::Discard => frames.push(Frame::Discard {
                start: self.nodes.len(),
                labels: std::mem::take(&mut self.labels),
            }),
            Token::Dot => match frames.last_mut() {
                Some(Frame::List(items, tail @ Tail::Proper)) if !items.is_empty() => {
                    *tail = Tail::Waiting
                }
                _ => return Err("unexpected dot".into()),
            },
            _ => unreachable!(),
        }
        Ok(())
    }

    fn close(&mut self, frames: &mut Vec<Frame>) -> Result<usize, String> {
        Ok(match frames.pop() {
            Some(Frame::List(items, Tail::Proper)) => {
                let nil = self.push(Node::Nil);
                self.list(items, nil)
            }
            Some(Frame::List(items, Tail::Dotted(tail))) => self.list(items, tail),
            Some(Frame::Vector(items)) => self.push(Node::Vector(items)),
            Some(Frame::Bytes(bytes)) => self.push(Node::Bytes(bytes)),
            _ => return Err("unexpected closing parenthesis".into()),
        })
    }

    fn list(&mut self, items: Vec<usize>, mut tail: usize) -> usize {
        for item in items.into_iter().rev() {
            tail = self.push(Node::Pair(item, tail));
        }
        tail
    }

    fn accept(
        &mut self,
        mut value: usize,
        frames: &mut Vec<Frame>,
    ) -> Result<Option<usize>, String> {
        loop {
            match frames.last_mut() {
                None => return Ok(Some(value)),
                Some(Frame::List(items, Tail::Proper) | Frame::Vector(items)) => items.push(value),
                Some(Frame::List(_, tail @ Tail::Waiting)) => *tail = Tail::Dotted(value),
                Some(Frame::List(_, Tail::Dotted(_))) => {
                    return Err("extra datum after dotted tail".into());
                }
                Some(Frame::Bytes(bytes)) => match self.nodes[value] {
                    Node::Number(Number::Integer(integer)) if (0..=255).contains(&integer) => {
                        bytes.push(integer as u8)
                    }
                    _ => return Err("bytevector requires exact bytes".into()),
                },
                Some(Frame::Discard { .. }) => {
                    if let Frame::Discard { start, labels } = frames.pop().unwrap() {
                        self.nodes.truncate(start);
                        self.labels = labels;
                    }
                    return Ok(None);
                }
                Some(_) => {
                    value = self.complete_prefix(value, frames.pop().unwrap())?;
                    continue;
                }
            }
            return Ok(None);
        }
    }

    fn complete_prefix(&mut self, value: usize, frame: Frame) -> Result<usize, String> {
        match frame {
            Frame::Prefix(name) => {
                let symbol = self.push(Node::Symbol(name.into()));
                let nil = self.push(Node::Nil);
                Ok(self.list(vec![symbol, value], nil))
            }
            Frame::Label(slot) => {
                self.nodes[slot] = Node::Alias(value);
                Ok(slot)
            }
            _ => unreachable!(),
        }
    }

    // ---- Tokens and comments ----

    fn token(&mut self) -> Result<Token, String> {
        loop {
            let Some(character) = self.input.read_char()? else {
                return Ok(Token::Eof);
            };
            match character {
                c if c.is_whitespace() => continue,
                ';' => {
                    self.input.read_line()?;
                }
                '(' => return Ok(Token::List),
                ')' => return Ok(Token::Close),
                '\'' => return Ok(Token::Prefix("quote")),
                '`' => return Ok(Token::Prefix("quasiquote")),
                ',' => {
                    return Ok(Token::Prefix(if self.take('@')? {
                        "unquote-splicing"
                    } else {
                        "unquote"
                    }));
                }
                '"' => return Ok(Token::Value(Node::String(self.escaped_text('"')?))),
                '|' => return Ok(Token::Value(Node::Symbol(self.escaped_text('|')?))),
                '#' => {
                    if let Some(token) = self.dispatch()? {
                        return Ok(token);
                    }
                }
                '[' | ']' | '{' | '}' => return Err("invalid datum character".into()),
                first => return self.atom(first),
            }
        }
    }

    fn dispatch(&mut self) -> Result<Option<Token>, String> {
        let next = self.input.read_char()?.ok_or("incomplete # syntax")?;
        Ok(Some(match next {
            '(' => Token::Vector,
            ';' => Token::Discard,
            '|' => {
                self.block_comment()?;
                return Ok(None);
            }
            '!' => {
                self.directive()?;
                return Ok(None);
            }
            '\\' => Token::Value(Node::Character(self.character()?)),
            'u' | 'U' => {
                if !self.take('8')? || !self.take('(')? {
                    return Err("invalid bytevector syntax".into());
                }
                Token::Bytes
            }
            '0'..='9' => self.label(next)?,
            first => {
                let text = format!("#{}", self.word(first)?);
                match text.to_ascii_lowercase().as_str() {
                    "#t" | "#true" => Token::Value(Node::Boolean(true)),
                    "#f" | "#false" => Token::Value(Node::Boolean(false)),
                    _ => Token::Value(Node::Number(number(&text, 10)?.ok_or("invalid # syntax")?)),
                }
            }
        }))
    }

    fn atom(&mut self, first: char) -> Result<Token, String> {
        let mut text = self.word(first)?;
        if text == "." {
            return Ok(Token::Dot);
        }
        if let Some(value) = number(&text, 10)? {
            return Ok(Token::Value(Node::Number(value)));
        }
        if !identifier(&text) {
            return Err("invalid numeric token or identifier".into());
        }
        if self.input.fold_case {
            text = crate::text::fold_string(&text);
        }
        Ok(Token::Value(Node::Symbol(text)))
    }

    fn word(&mut self, first: char) -> Result<String, String> {
        let mut text = String::from(first);
        while let Some(character) = self.input.peek_char()? {
            if delimiter(character) {
                break;
            }
            text.push(self.input.read_char()?.unwrap());
        }
        Ok(text)
    }

    fn take(&mut self, expected: char) -> Result<bool, String> {
        if self.input.peek_char()? != Some(expected) {
            return Ok(false);
        }
        self.input.read_char()?;
        Ok(true)
    }

    fn block_comment(&mut self) -> Result<(), String> {
        let mut depth = 1;
        while depth > 0 {
            match self
                .input
                .read_char()?
                .ok_or("unterminated block comment")?
            {
                '#' if self.take('|')? => depth += 1,
                '|' if self.take('#')? => depth -= 1,
                _ => {}
            }
        }
        Ok(())
    }

    fn directive(&mut self) -> Result<(), String> {
        let first = self
            .input
            .read_char()?
            .ok_or("incomplete reader directive")?;
        self.input.fold_case = match self.word(first)?.as_str() {
            "fold-case" => true,
            "no-fold-case" => false,
            _ => return Err("unknown reader directive".into()),
        };
        Ok(())
    }

    fn label(&mut self, first: char) -> Result<Token, String> {
        let mut digits = String::from(first);
        while let Some(character @ '0'..='9') = self.input.peek_char()? {
            digits.push(character);
            self.input.read_char()?;
        }
        let label = digits.parse().map_err(|_| "datum label is too large")?;
        match self.input.read_char()? {
            Some('=') => Ok(Token::Label(label)),
            Some('#') => Ok(Token::Reference(label)),
            _ => Err("invalid datum label".into()),
        }
    }

    // ---- Characters and escapes ----

    fn character(&mut self) -> Result<char, String> {
        let first = self
            .input
            .read_char()?
            .ok_or("incomplete character literal")?;
        if delimiter(first) {
            return Ok(first);
        }
        let text = self.word(first)?;
        if text.chars().count() == 1 {
            return Ok(first);
        }
        match text.to_ascii_lowercase().as_str() {
            "alarm" => Ok('\x07'),
            "backspace" => Ok('\x08'),
            "delete" => Ok('\x7f'),
            "escape" => Ok('\x1b'),
            "newline" => Ok('\n'),
            "null" => Ok('\0'),
            "return" => Ok('\r'),
            "space" => Ok(' '),
            "tab" => Ok('\t'),
            _ if text.starts_with(['x', 'X']) => unicode_hex(&text[1..]),
            _ => Err("unknown character literal".into()),
        }
    }

    fn escaped_text(&mut self, end: char) -> Result<String, String> {
        let mut text = String::new();
        loop {
            match self
                .input
                .read_char()?
                .ok_or("unterminated string or symbol")?
            {
                character if character == end => return Ok(text),
                '\\' => {
                    if let Some(character) = self.escape(end)? {
                        text.push(character);
                    }
                }
                '\r' if end == '"' => {
                    self.take('\n')?;
                    text.push('\n');
                }
                character => text.push(character),
            }
        }
    }

    fn escape(&mut self, end: char) -> Result<Option<char>, String> {
        Ok(Some(
            match self.input.read_char()?.ok_or("incomplete escape")? {
                'a' => '\x07',
                'b' => '\x08',
                't' => '\t',
                'n' => '\n',
                'r' => '\r',
                '"' => '"',
                '|' => '|',
                '\\' => '\\',
                'x' => self.hex_escape()?,
                c if end == '"' && matches!(c, ' ' | '\t' | '\n' | '\r') => {
                    self.line_continuation(c)?;
                    return Ok(None);
                }
                _ => return Err("unknown escape".into()),
            },
        ))
    }

    fn hex_escape(&mut self) -> Result<char, String> {
        let mut digits = String::new();
        loop {
            match self
                .input
                .read_char()?
                .ok_or("incomplete hexadecimal escape")?
            {
                ';' => return unicode_hex(&digits),
                c if c.is_ascii_hexdigit() => digits.push(c),
                _ => return Err("invalid hexadecimal escape".into()),
            }
        }
    }

    fn line_continuation(&mut self, mut character: char) -> Result<(), String> {
        while matches!(character, ' ' | '\t') {
            character = self
                .input
                .read_char()?
                .ok_or("incomplete line continuation")?;
        }
        if !matches!(character, '\r' | '\n') {
            return Err("expected newline in string escape".into());
        }
        if character == '\r' {
            self.take('\n')?;
        }
        while matches!(self.input.peek_char()?, Some(' ' | '\t')) {
            self.input.read_char()?;
        }
        Ok(())
    }
}

fn delimiter(character: char) -> bool {
    character.is_whitespace() || "()\";|'`,[]{}".contains(character)
}

fn identifier_initial(character: char) -> bool {
    character.is_alphabetic() || "!$%&*/:<=>?^_~@".contains(character)
}

// The sign and dot forms are peculiar identifiers only when their next
// character satisfies the grammar. Thus +x is a symbol, but +2oops is not.
pub(crate) fn identifier(text: &str) -> bool {
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

fn unicode_hex(digits: &str) -> Result<char, String> {
    u32::from_str_radix(digits, 16)
        .ok()
        .and_then(char::from_u32)
        .ok_or_else(|| "invalid Unicode scalar".into())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::Port;

    fn parse(text: &str) -> Datum {
        let mut port = Port::input_string(text.into());
        read(port.text_input().unwrap()).unwrap().unwrap()
    }

    #[test]
    fn numbers_preserve_radix_exactness_and_range() {
        assert_eq!(number("#i#x10", 10).unwrap(), Some(Number::Real(16.0)));
        assert!(
            matches!(number("#i-0", 10).unwrap(), Some(Number::Real(value)) if value.is_sign_negative())
        );
        assert_eq!(number("#e2.0", 10).unwrap(), Some(Number::Integer(2)));
        assert_eq!(
            number("#e9007199254740993.0", 10).unwrap(),
            Some(Number::Integer(9007199254740993))
        );
        assert_eq!(
            number("#e-9223372036854775808.0", 10).unwrap(),
            Some(Number::Integer(i64::MIN))
        );
        assert_eq!(number("#e12000e-3", 10).unwrap(), Some(Number::Integer(12)));
        assert_eq!(
            number("#i9223372036854775808", 10).unwrap(),
            Some(Number::Real(9223372036854775808.0))
        );
        assert_eq!(
            number("#i#x10000000000000000", 10).unwrap(),
            Some(Number::Real(18446744073709551616.0))
        );
        assert_eq!(number("#e1@0", 10).unwrap(), Some(Number::Integer(1)));
        assert!(number("#e1@1", 10).is_err());
        assert_eq!(
            number("#x-8000000000000000", 10).unwrap(),
            Some(Number::Integer(i64::MIN))
        );
        assert!(number("9223372036854775808", 10).is_err());
        assert_eq!(number("9223372036854775808oops", 10).unwrap(), None);
        assert!(number("#e1.5", 10).is_err());
        assert_eq!(number("hello", 10).unwrap(), None);
    }

    #[test]
    fn identifiers_follow_the_sign_and_dot_grammar() {
        for text in ["+", "-", "...", "+x", "+.x", ".+", "λ-2", "@x"] {
            assert!(identifier(text), "{text}");
        }
        for text in ["", ".", "+.", "+2oops", "1x", "a#b", "a\\b", "x y"] {
            assert!(!identifier(text), "{text}");
        }
    }

    #[test]
    fn one_datum_leaves_the_delimiter_for_character_input() {
        let mut port = Port::input_string("42 λ".into());
        let input = port.text_input().unwrap();
        let datum = read(input).unwrap().unwrap();
        assert_eq!(datum.nodes[datum.root], Node::Number(Number::Integer(42)));
        assert_eq!(input.peek_char().unwrap(), Some(' '));
        assert_eq!(input.read_char().unwrap(), Some(' '));
        assert!(read(input).unwrap().is_some());
        assert!(read(input).unwrap().is_none());
    }

    #[test]
    fn comments_prefixes_and_escapes_are_datums() {
        let datum = parse("#| outer #| inner |# |# '(a . #(\"λ\\x1f600;\" #\\space #u8(0 255)))");
        assert!(datum.nodes.contains(&Node::Symbol("quote".into())));
        assert!(datum.nodes.contains(&Node::String("λ😀".into())));
        assert!(datum.nodes.contains(&Node::Character(' ')));
        assert!(datum.nodes.contains(&Node::Bytes(vec![0, 255])));
        let datum = parse("|line\r\nend|");
        assert!(datum.nodes.contains(&Node::Symbol("line\r\nend".into())));
    }

    #[test]
    fn datum_comments_have_isolated_labels_and_nested_comments() {
        let datum = parse("#;#;a b (#;#1=(discarded . #1#) #1=kept #1#)");
        assert!(datum.nodes.contains(&Node::Symbol("kept".into())));
        assert!(!datum.nodes.contains(&Node::Symbol("discarded".into())));
        assert!(!datum.nodes.contains(&Node::Symbol("a".into())));
        assert!(!datum.nodes.contains(&Node::Symbol("b".into())));
    }

    #[test]
    fn labels_preserve_cycles_and_reject_unproductive_aliases() {
        let datum = parse("#1=(a . #1#)");
        let targets = &datum.targets;
        let root = targets[datum.root];
        assert!(matches!(datum.nodes[root], Node::Pair(_, tail) if targets[tail] == root));
        for source in [
            "#1=#1#",
            "#9#",
            "(#1=a #1=b)",
            "(a .)",
            "(a . b c)",
            "#u8(256)",
            "\"\\xd800;\"",
        ] {
            let mut port = Port::input_string(source.into());
            assert!(read(port.text_input().unwrap()).is_err(), "{source}");
        }
    }

    #[test]
    fn label_chains_resolve_without_recursion() {
        let mut source = String::new();
        for label in 0..10_000 {
            source.push_str(&format!("#{label}="));
        }
        source.push_str("42");
        let datum = parse(&source);
        let target = datum.targets[datum.root];
        assert_eq!(datum.nodes[target], Node::Number(Number::Integer(42)));
        assert_eq!(datum.targets.len(), datum.nodes.len());
        assert!(datum.targets.iter().all(|index| *index == target));
    }

    #[test]
    fn nesting_does_not_use_the_native_call_stack() {
        let source = format!("{}0{}", "(".repeat(10_000), ")".repeat(10_000));
        let datum = parse(&source);
        assert_eq!(datum.nodes.len(), 20_001);
    }
}
