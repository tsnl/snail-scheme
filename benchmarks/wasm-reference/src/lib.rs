use std::io::{self, Read};
use std::time::Instant;

// ---- Benchmark input ----

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Datum {
    Atom(String),
    List(Vec<Datum>),
}

impl Datum {
    pub fn atom(&self) -> &str {
        match self {
            Self::Atom(value) => value,
            Self::List(_) => panic!("expected an atom"),
        }
    }

    pub fn number(&self) -> usize {
        self.atom().parse().expect("expected a nonnegative integer")
    }

    pub fn list(&self) -> &[Datum] {
        match self {
            Self::List(values) => values,
            Self::Atom(_) => panic!("expected a list"),
        }
    }
}

pub fn input() -> io::Result<Vec<Datum>> {
    let mut source = String::new();
    io::stdin().read_to_string(&mut source)?;
    let spaced = source.replace('(', " ( ").replace(')', " ) ");
    let mut tokens = spaced.split_whitespace().peekable();
    let mut values = Vec::new();
    while tokens.peek().is_some() {
        values.push(read_datum(&mut tokens));
    }
    Ok(values)
}

fn read_datum<'a>(tokens: &mut std::iter::Peekable<impl Iterator<Item = &'a str>>) -> Datum {
    match tokens.next().expect("incomplete input") {
        "(" => {
            let mut values = Vec::new();
            while tokens.peek() != Some(&")") {
                values.push(read_datum(tokens));
            }
            tokens.next();
            Datum::List(values)
        }
        ")" => panic!("unexpected closing parenthesis"),
        value => Datum::Atom(value.trim_matches('"').to_owned()),
    }
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

pub fn report(name: &str, count: usize, start: Instant, result: impl std::fmt::Display) {
    let seconds = start.elapsed().as_secs_f64();
    println!("Result: {result}");
    println!("+!CSVLINE!+rust-wasm,{name}:{count},{seconds:.9}");
}
