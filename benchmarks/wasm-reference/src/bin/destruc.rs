use r7rs_wasm_reference::{Datum, input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Destructively split and joined list cells ----

type Link = Option<Box<Cell>>;
struct Cell {
    value: Option<usize>,
    rest: Link,
}

fn empty_cells(n: usize) -> Link {
    (0..n).fold(None, |rest, _| Some(Box::new(Cell { value: None, rest })))
}
fn length(list: &Link) -> usize {
    let (mut rest, mut n) = (list.as_deref(), 0);
    while let Some(cell) = rest {
        n += 1;
        rest = cell.rest.as_deref();
    }
    n
}
fn append(list: &mut Link, suffix: Link) {
    let mut tail = list;
    while let Some(cell) = tail {
        tail = &mut cell.rest;
    }
    *tail = suffix;
}

// A split changes the existing cells. The suffix is transferred without
// copying, so the next join preserves the original cell identities.
fn split(list: &mut Link, half: usize, value: usize) -> Link {
    if half == 0 {
        *list = None;
        return None;
    }
    let mut cursor = list.as_deref_mut().unwrap();
    for _ in 1..half {
        cursor.value = Some(value);
        cursor = cursor.rest.as_deref_mut().unwrap();
    }
    cursor.rest.take()
}
fn join(list: &mut Link, half: usize, value: usize, suffix: Link) {
    let mut cursor = list.as_deref_mut().unwrap();
    for _ in 0..half {
        cursor.value = Some(value);
        cursor = cursor.rest.as_deref_mut().unwrap();
    }
    cursor.rest = suffix;
}

fn destructive(n: usize, m: usize) -> Vec<Link> {
    let mut lists: Vec<Link> = (0..10).map(|_| None).collect();
    for i in (1..=n).rev() {
        if lists[0].is_none() {
            for list in &mut lists {
                if list.is_none() {
                    *list = empty_cells(1);
                }
                append(list, empty_cells(m));
            }
        } else {
            for j in 0..9 {
                let (half1, half2) = (length(&lists[j]) / 2, length(&lists[j + 1]) / 2);
                let suffix = split(&mut lists[j], half1, i);
                join(&mut lists[j + 1], half2, i, suffix);
            }
        }
    }
    lists
}

fn datum(lists: &[Link]) -> Datum {
    Datum::List(
        lists
            .iter()
            .map(|list| {
                let (mut values, mut rest) = (Vec::new(), list.as_deref());
                while let Some(cell) = rest {
                    values.push(
                        cell.value
                            .map_or(Datum::List(Vec::new()), |n| Datum::Atom(n.to_string())),
                    );
                    rest = cell.rest.as_deref();
                }
                Datum::List(values)
            })
            .collect(),
    )
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n, m) = (values[0].number(), values[1].number(), values[2].number());
    let (start, mut result) = (Instant::now(), Vec::new());
    for _ in 0..count {
        result = black_box(destructive(black_box(n), black_box(m)));
    }
    let result = datum(&result);
    assert_eq!(result, values[3]);
    report("destruc", count, start, &result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn transfers_actual_suffix_cells() {
        let mut list = empty_cells(4);
        let original = list
            .as_ref()
            .unwrap()
            .rest
            .as_ref()
            .unwrap()
            .rest
            .as_ref()
            .unwrap()
            .as_ref() as *const Cell;
        let suffix = split(&mut list, 2, 7);
        assert_eq!(suffix.as_ref().unwrap().as_ref() as *const Cell, original);
        assert_eq!(length(&list), 2);
        assert_eq!(length(&suffix), 2);
    }
}
