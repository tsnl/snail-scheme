//! Writes `(snail shell text unicode)`, the tables `(snail shell text)`
//! reads every Unicode property and case mapping from:
//!
//!   make unicode-tables
//!
//! which formats what this prints with `snail-scheme format`, and which
//! `make check` runs to see the checked-in file is current.
//!
//! Each scalar's properties are Rust's, through the exceptions beside this
//! file, gathered into a record: four flags, a decimal digit's value, and
//! the deltas of its simple upper, lower and folded case. A scalar finds its
//! record through two stages: its block, the scalar shifted right, names a
//! run of the block's record numbers, and blocks with the same run share it.
//! A scalar whose full folding is not its simple folding is listed apart.

mod exceptions;

use std::collections::HashMap;
use std::fmt::Write;

// ---- Records ----

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
struct Record {
    flags: i64,
    digit: i64,
    upper: i64,
    lower: i64,
    fold: i64,
}

const ALPHABETIC: i64 = 1;
const WHITESPACE: i64 = 2;
const LOWERCASE: i64 = 4;
const UPPERCASE: i64 = 8;

// A surrogate is no scalar; it takes the record of none.
fn record(point: u32) -> Record {
    let Some(character) = char::from_u32(point) else {
        return Record {
            flags: 0,
            digit: -1,
            upper: 0,
            lower: 0,
            fold: 0,
        };
    };
    let delta = |mapped: char| mapped as i64 - point as i64;
    let flag = |set: bool, bit: i64| if set { bit } else { 0 };
    Record {
        flags: flag(character.is_alphabetic(), ALPHABETIC)
            | flag(character.is_whitespace(), WHITESPACE)
            | flag(character.is_lowercase(), LOWERCASE)
            | flag(character.is_uppercase(), UPPERCASE),
        digit: exceptions::digit_value(character).map_or(-1, i64::from),
        upper: delta(exceptions::uppercase(character)),
        lower: delta(exceptions::lowercase(character)),
        fold: delta(exceptions::fold_character(character)),
    }
}

// ---- Two stages ----

const SCALARS: u32 = 0x110000;

struct Stages {
    shift: u32,
    blocks: Vec<i64>,
    runs: Vec<i64>,
}

// The stages at `shift`: each block's run of record numbers, shared by
// every block whose run is the same.
fn stages(numbers: &[i64], shift: u32) -> Stages {
    let size = 1usize << shift;
    let mut first: HashMap<&[i64], i64> = HashMap::new();
    let mut runs = Vec::new();
    let blocks = numbers
        .chunks(size)
        .map(|run| {
            *first.entry(run).or_insert_with(|| {
                runs.extend_from_slice(run);
                (runs.len() / size - 1) as i64
            })
        })
        .collect();
    Stages {
        shift,
        blocks,
        runs,
    }
}

// Block and record numbers are bytes, as (snail shell text) reads them.
fn bytes(stages: &Stages) -> usize {
    stages.blocks.len() + stages.runs.len()
}

// ---- Checksum ----

// Every function's answer for every scalar, folded into one number a test
// recomputes through (snail shell text): its upper, lower and folded case,
// its flags, its digit's value plus one or zero, and its full folding's
// length and scalars, each mixed in as h = (31h + v) mod 2^31 - 1.
fn checksum() -> i64 {
    let mix = |hash: i64, value: i64| (hash * 31 + value) % 2147483647;
    (0..SCALARS)
        .filter_map(char::from_u32)
        .fold(0, |hash, character| {
            let record = record(character as u32);
            let point = character as i64;
            let full = exceptions::full_fold(character);
            let hash = [
                point + record.upper,
                point + record.lower,
                point + record.fold,
                record.flags,
                record.digit + 1,
                full.len as i64,
            ]
            .into_iter()
            .fold(hash, mix);
            full.scalars[..full.len]
                .iter()
                .fold(hash, |hash, scalar| mix(hash, *scalar as i64))
        })
}

// ---- Output ----

// A table of `element`, U8 or I32, whose every value must fit it.
fn table(out: &mut String, name: &str, element: &str, values: &[i64]) {
    let range = if element == "U8" {
        0..=255
    } else {
        i32::MIN as i64..=i32::MAX as i64
    };
    assert!(
        values.iter().all(|value| range.contains(value)),
        "{name} does not fit {element}"
    );
    writeln!(out, "\n    (define {name} (→ (ConstantArray {element}))").unwrap();
    write!(
        out,
        "      (constant-array {element}\n                       ("
    )
    .unwrap();
    let mut column = 24;
    for (index, value) in values.iter().enumerate() {
        let text = value.to_string();
        if index > 0 && column + 1 + text.len() > 100 {
            write!(out, "\n                        ").unwrap();
            column = 24;
        } else if index > 0 {
            out.push(' ');
            column += 1;
        }
        out.push_str(&text);
        column += text.len();
    }
    out.push_str(")))\n");
}

fn main() {
    let records: Vec<Record> = (0..SCALARS).map(record).collect();
    let mut numbered: HashMap<Record, i64> = HashMap::new();
    let mut distinct = Vec::new();
    let numbers: Vec<i64> = records
        .iter()
        .map(|record| {
            *numbered.entry(*record).or_insert_with(|| {
                distinct.push(*record);
                distinct.len() as i64 - 1
            })
        })
        .collect();
    let stages = (4..=10)
        .map(|shift| stages(&numbers, shift))
        .min_by_key(bytes)
        .unwrap();
    let folds: Vec<(u32, Vec<char>)> = (0..SCALARS)
        .filter_map(|point| {
            let character = char::from_u32(point)?;
            let full = exceptions::full_fold(character);
            let full = full.scalars[..full.len].to_vec();
            (full != [exceptions::fold_character(character)]).then_some((point, full))
        })
        .collect();
    let mut starts = vec![0];
    for (_, scalars) in &folds {
        starts.push(starts.last().unwrap() + scalars.len() as i64);
    }
    let field = |get: fn(&Record) -> i64| distinct.iter().map(get).collect::<Vec<i64>>();

    let mut out = String::new();
    out.push_str(";; Generated by crates/snail-scheme-support/examples/unicode-tables from\n");
    out.push_str(";; Rust's Unicode ");
    let (major, minor, update) = char::UNICODE_VERSION;
    writeln!(out, "{major}.{minor}.{update} properties; do not edit.").unwrap();
    out.push_str(";; Unicode data © Unicode, Inc.; https://www.unicode.org/license.txt\n");
    out.push_str("(define-library (snail shell text unicode)\n  (export\n");
    for name in [
        "unicode-shift",
        "unicode-blocks",
        "unicode-runs",
        "unicode-flags",
        "unicode-digits",
        "unicode-upper",
        "unicode-lower",
        "unicode-fold",
        "unicode-fold-points",
        "unicode-fold-starts",
        "unicode-fold-scalars",
        "unicode-checksum",
    ] {
        writeln!(out, "   {name}").unwrap();
    }
    out.push_str("   )\n  (import\n   (snail core base))\n  (begin\n");
    writeln!(out, "\n    (define unicode-shift (→ I64) {})", stages.shift).unwrap();
    writeln!(
        out,
        "\n    (define unicode-checksum (→ I64) {})",
        checksum()
    )
    .unwrap();
    table(&mut out, "unicode-blocks", "U8", &stages.blocks);
    table(&mut out, "unicode-runs", "U8", &stages.runs);
    table(
        &mut out,
        "unicode-flags",
        "U8",
        &field(|record| record.flags),
    );
    table(
        &mut out,
        "unicode-digits",
        "I32",
        &field(|record| record.digit),
    );
    table(
        &mut out,
        "unicode-upper",
        "I32",
        &field(|record| record.upper),
    );
    table(
        &mut out,
        "unicode-lower",
        "I32",
        &field(|record| record.lower),
    );
    table(
        &mut out,
        "unicode-fold",
        "I32",
        &field(|record| record.fold),
    );
    table(
        &mut out,
        "unicode-fold-points",
        "I32",
        &folds
            .iter()
            .map(|(point, _)| *point as i64)
            .collect::<Vec<_>>(),
    );
    table(&mut out, "unicode-fold-starts", "I32", &starts);
    let scalars: Vec<i64> = folds
        .iter()
        .flat_map(|(_, scalars)| scalars.iter().map(|c| *c as i64))
        .collect();
    table(&mut out, "unicode-fold-scalars", "I32", &scalars);
    out.push_str("\n    ))\n");
    print!("{out}");
    eprintln!(
        "shift {}, {} records, {} blocks, {} runs, {} bytes, {} full folds",
        stages.shift,
        distinct.len(),
        stages.blocks.len(),
        stages.runs.len(),
        bytes(&stages),
        folds.len()
    );
}
