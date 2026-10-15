use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Persistent row lists ----

type Link = Option<Rc<Cell>>;
struct Cell {
    row: i64,
    rest: Link,
}
fn cons(row: i64, rest: Link) -> Link {
    Some(Rc::new(Cell { row, rest }))
}

// Append copies the first list and shares the second, including the deferred
// choices accumulated while rejecting earlier rows. Placements share suffixes.
fn append(first: &Link, second: &Link) -> Link {
    match first {
        None => second.clone(),
        Some(cell) => cons(cell.row, append(&cell.rest, second)),
    }
}

// ---- Exhaustive queen placement ----

fn safe(row: i64, distance: i64, placed: &Link) -> bool {
    match placed {
        None => true,
        Some(cell) => {
            cell.row != row + distance
                && cell.row != row - distance
                && safe(row, distance + 1, &cell.rest)
        }
    }
}

fn choices(x: &Link, y: &Link, z: &Link) -> usize {
    match x {
        None => usize::from(y.is_none()),
        Some(cell) => {
            let placed = if safe(cell.row, 1, z) {
                choices(&append(&cell.rest, y), &None, &cons(cell.row, z.clone()))
            } else {
                0
            };
            placed + choices(&cell.rest, &cons(cell.row, y.clone()), z)
        }
    }
}

fn nqueens(n: i64) -> usize {
    let rows = (1..=n).rev().fold(None, |rest, row| cons(row, rest));
    choices(&rows, &None, &None)
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].integer());
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(nqueens(black_box(n)));
    }
    assert_eq!(result, values[2].number());
    report("nqueens", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn known_small_queen_counts() {
        assert_eq!(
            (nqueens(0), nqueens(1), nqueens(4), nqueens(8)),
            (1, 1, 2, 92)
        );
    }
    #[test]
    fn append_shares_the_deferred_suffix() {
        let tail = cons(7, None);
        let appended = append(&cons(3, None), &tail).unwrap();
        assert!(Rc::ptr_eq(
            appended.rest.as_ref().unwrap(),
            tail.as_ref().unwrap()
        ));
    }
}
