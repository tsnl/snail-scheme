use std::fmt::{self, Display};
use std::io::{self, Read};
use std::time::Instant;

pub mod boyer;
pub mod list;

// ---- Benchmark input ----

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Datum {
    Atom(String),
    String(String),
    List(Vec<Datum>),
    Dotted(Vec<Datum>, Box<Datum>),
    Vector(Vec<Datum>),
    Bytevector(Vec<u8>),
    Character(char),
}

impl Datum {
    pub fn atom(&self) -> &str {
        match self {
            Self::Atom(value) | Self::String(value) => value,
            _ => panic!("expected an atom or string"),
        }
    }

    pub fn number(&self) -> usize {
        self.atom().parse().expect("expected a nonnegative integer")
    }

    pub fn integer(&self) -> i64 {
        self.atom().parse().expect("expected an integer")
    }

    pub fn real(&self) -> f64 {
        self.atom().parse().expect("expected a real number")
    }

    pub fn list(&self) -> &[Datum] {
        match self {
            Self::List(values) | Self::Vector(values) => values,
            _ => panic!("expected a list or vector"),
        }
    }
}

pub fn input() -> io::Result<Vec<Datum>> {
    let mut source = String::new();
    io::stdin().read_to_string(&mut source)?;
    Ok(read_all(&source))
}

pub fn read_all(source: &str) -> Vec<Datum> {
    let mut reader = Reader::new(source);
    let mut values = Vec::new();
    while reader.skip_space() {
        values.push(reader.datum());
    }
    values
}

pub struct Reader {
    source: Vec<char>,
    position: usize,
}

impl Reader {
    pub fn new(source: &str) -> Self {
        Self {
            source: source.chars().collect(),
            position: 0,
        }
    }
    pub fn read(&mut self) -> Option<Datum> {
        if self.skip_space() {
            Some(self.datum())
        } else {
            None
        }
    }
    fn peek(&self) -> Option<char> {
        self.source.get(self.position).copied()
    }
    fn take(&mut self) -> char {
        let character = self.peek().expect("incomplete datum");
        self.position += 1;
        character
    }

    fn skip_space(&mut self) -> bool {
        loop {
            match self.peek() {
                Some(c) if c.is_whitespace() => {
                    self.take();
                }
                Some(';') => {
                    while self.peek().is_some_and(|c| c != '\n') {
                        self.take();
                    }
                }
                Some('#') if self.source.get(self.position + 1) == Some(&';') => {
                    self.position += 2;
                    self.datum();
                }
                Some('#') if self.source.get(self.position + 1) == Some(&'|') => {
                    self.block_comment()
                }
                other => return other.is_some(),
            }
        }
    }

    fn block_comment(&mut self) {
        self.position += 2;
        let mut depth = 1;
        while depth != 0 {
            let first = self.take();
            if first == '#' && self.peek() == Some('|') {
                self.take();
                depth += 1;
            }
            if first == '|' && self.peek() == Some('#') {
                self.take();
                depth -= 1;
            }
        }
    }

    // This exhaustive reader dispatch also accepts the upstream data files,
    // including vectors, escaped strings, abbreviation syntax and dotted lists.
    fn datum(&mut self) -> Datum {
        assert!(self.skip_space(), "incomplete datum");
        match self.take() {
            '(' => self.sequence(),
            ')' => panic!("unexpected closing parenthesis"),
            '"' => Datum::String(self.quoted('"')),
            '|' => Datum::Atom(self.quoted('|')),
            '\'' => self.abbreviation("quote"),
            '`' => self.abbreviation("quasiquote"),
            ',' if self.peek() == Some('@') => {
                self.take();
                self.abbreviation("unquote-splicing")
            }
            ',' => self.abbreviation("unquote"),
            '#' => self.sharp(),
            first => Datum::Atom(self.token(first)),
        }
    }

    fn abbreviation(&mut self, name: &str) -> Datum {
        Datum::List(vec![Datum::Atom(name.to_owned()), self.datum()])
    }

    fn sequence(&mut self) -> Datum {
        let mut values = Vec::new();
        loop {
            assert!(self.skip_space(), "unclosed list");
            if self.peek() == Some(')') {
                self.take();
                return Datum::List(values);
            }
            let value = self.datum();
            if value == Datum::Atom(".".to_owned()) {
                return self.dotted(values);
            }
            values.push(value);
        }
    }

    fn dotted(&mut self, values: Vec<Datum>) -> Datum {
        assert!(!values.is_empty(), "dotted list needs a head");
        let tail = self.datum();
        self.skip_space();
        assert_eq!(self.take(), ')', "dotted list has extra elements");
        Datum::Dotted(values, Box::new(tail))
    }

    fn sharp(&mut self) -> Datum {
        match self.peek() {
            Some('(') => {
                self.take();
                Datum::Vector(self.sequence().list().to_vec())
            }
            Some('\\') => {
                self.take();
                self.character()
            }
            Some('u')
                if self.source.get(self.position..self.position + 3) == Some(&['u', '8', '(']) =>
            {
                self.position += 3;
                Datum::Bytevector(
                    self.sequence()
                        .list()
                        .iter()
                        .map(|d| u8::try_from(d.number()).unwrap())
                        .collect(),
                )
            }
            _ => Datum::Atom(self.token('#')),
        }
    }

    fn character(&mut self) -> Datum {
        let first = self.take();
        let name = self.token(first);
        let character = match name.as_str() {
            "space" => ' ',
            "newline" => '\n',
            "tab" => '\t',
            "return" => '\r',
            "alarm" => '\u{7}',
            "backspace" => '\u{8}',
            "delete" => '\u{7f}',
            "null" => '\0',
            name if name.starts_with('x') && name.len() > 1 => {
                char::from_u32(u32::from_str_radix(&name[1..], 16).unwrap()).unwrap()
            }
            _ => {
                assert_eq!(name.chars().count(), 1, "unknown character name");
                first
            }
        };
        Datum::Character(character)
    }

    fn token(&mut self, first: char) -> String {
        let mut token = String::from(first);
        if first.is_whitespace() || "()\";".contains(first) {
            return token;
        }
        while self
            .peek()
            .is_some_and(|c| !c.is_whitespace() && !"()\";".contains(c))
        {
            token.push(self.take());
        }
        token
    }

    fn quoted(&mut self, delimiter: char) -> String {
        let mut value = String::new();
        loop {
            match self.take() {
                c if c == delimiter => return value,
                '\\' => value.push(self.escape()),
                character => value.push(character),
            }
        }
    }

    fn escape(&mut self) -> char {
        match self.take() {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'a' => '\u{7}',
            'b' => '\u{8}',
            'x' => {
                let mut hexadecimal = String::new();
                while self.peek() != Some(';') {
                    hexadecimal.push(self.take());
                }
                self.take();
                char::from_u32(u32::from_str_radix(&hexadecimal, 16).unwrap()).unwrap()
            }
            character => character,
        }
    }
}

impl Display for Datum {
    fn fmt(&self, output: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Atom(value) => write!(output, "{value}"),
            Self::String(value) => write!(output, "{value:?}"),
            Self::Character(c) => match c {
                '\n' => write!(output, "#\\newline"),
                ' ' => write!(output, "#\\space"),
                c => write!(output, "#\\{c}"),
            },
            Self::Bytevector(values) => {
                write!(output, "#u8(")?;
                for (i, v) in values.iter().enumerate() {
                    if i > 0 {
                        write!(output, " ")?;
                    }
                    write!(output, "{v}")?;
                }
                write!(output, ")")
            }
            Self::List(values) => write_sequence(output, "(", values, None),
            Self::Vector(values) => write_sequence(output, "#(", values, None),
            Self::Dotted(values, tail) => write_sequence(output, "(", values, Some(tail)),
        }
    }
}

fn write_sequence(
    output: &mut fmt::Formatter<'_>,
    prefix: &str,
    values: &[Datum],
    tail: Option<&Datum>,
) -> fmt::Result {
    write!(output, "{prefix}")?;
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            write!(output, " ")?;
        }
        write!(output, "{value}")?;
    }
    if let Some(tail) = tail {
        write!(output, " . {tail}")?;
    }
    write!(output, ")")
}

// ---- Character input ----

// The pinned bib fixture is ASCII. Decode UTF-8 as well so each call still
// denotes one character, and cat writes that character rather than a block.
pub fn read_char(input: &mut impl Read) -> io::Result<Option<char>> {
    let mut bytes = [0; 4];
    if input.read(&mut bytes[..1])? == 0 {
        return Ok(None);
    }
    let width = match bytes[0] {
        0..=0x7f => 1,
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => return Err(io::ErrorKind::InvalidData.into()),
    };
    input.read_exact(&mut bytes[1..width])?;
    let text = std::str::from_utf8(&bytes[..width]).map_err(|_| io::ErrorKind::InvalidData)?;
    Ok(text.chars().next())
}

// ---- Measurement output ----

pub fn report(name: &str, count: impl Display, start: Instant, result: impl Display) {
    let seconds = start.elapsed().as_secs_f64();
    println!("Result: {result}");
    println!("+!CSVLINE!+rust-wasm,{name}:{count},{seconds:.9}");
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn comments_and_compound_datums() {
        let values = read_all(
            "; header\n#| outer #| inner |# |# #;(ignored) '#(1 \"a b\\n\" #\\space) (x . y) #u8(0 255)",
        );
        assert_eq!(values[0].to_string(), "(quote #(1 \"a b\\n\" #\\space))");
        assert_eq!(values[1].to_string(), "(x . y)");
        assert_eq!(values[2].to_string(), "#u8(0 255)");
    }
    #[test]
    #[should_panic(expected = "unclosed list")]
    fn rejects_unclosed_lists() {
        read_all("(1");
    }
}
