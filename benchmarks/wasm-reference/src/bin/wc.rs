use r7rs_wasm_reference::{input, read_char, report};
use std::fs::File;
use std::hint::black_box;
use std::io::{self, BufReader};
use std::time::Instant;

// ---- Character classification ----

fn word_count(filename: &str) -> io::Result<[usize; 3]> {
    let mut input = BufReader::new(File::open(filename)?);
    let (mut lines, mut words, mut characters, mut in_word) = (0, 0, 0, false);
    while let Some(character) = read_char(&mut input)? {
        characters += 1;
        lines += usize::from(character == '\n');
        let separator = character == ' ' || character == '\n';
        words += usize::from(!separator && !in_word);
        in_word = !separator;
    }
    Ok([lines, words, characters])
}

// ---- Benchmark driver ----

fn main() -> io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let expected: Vec<_> = values[2]
        .list()
        .iter()
        .map(|value| value.number())
        .collect();
    let (start, mut result) = (Instant::now(), [0; 3]);
    for _ in 0..count {
        result = black_box(word_count(black_box(values[1].atom()))?);
    }
    assert_eq!(result.as_slice(), expected);
    report(
        "wc",
        count,
        start,
        format!("({} {} {})", result[0], result[1], result[2]),
    );
    Ok(())
}
