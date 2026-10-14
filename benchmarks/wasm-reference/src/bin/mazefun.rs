use r7rs_wasm_reference::{Datum, input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Persistent matrix lists ----

type List<T> = Option<Rc<Cell<T>>>;
#[derive(Debug, PartialEq, Eq)]
struct Cell<T> {
    first: T,
    rest: List<T>,
}
type Position = (usize, usize);
type Row = List<Option<Position>>;
type Cave = List<Row>;
type Maze = List<List<char>>;

// Nodes are immutable. A write copies its changed prefix and keeps owned Rc
// references to shared tails; dropping a version can reclaim it inside timing.
fn cons<T>(first: T, rest: List<T>) -> List<T> {
    Some(Rc::new(Cell { first, rest }))
}
fn list<T>(values: impl DoubleEndedIterator<Item = T>) -> List<T> {
    values.rev().fold(None, |rest, first| cons(first, rest))
}
fn length<T>(mut list: &List<T>) -> usize {
    let mut n = 0;
    while let Some(cell) = list {
        n += 1;
        list = &cell.rest;
    }
    n
}
fn read<T>(mut list: &List<T>, i: usize) -> &T {
    for _ in 0..i {
        list = &list.as_ref().unwrap().rest;
    }
    &list.as_ref().unwrap().first
}
fn write<T: Clone>(cells: &List<T>, i: usize, value: T) -> List<T> {
    let cell = cells.as_ref().unwrap();
    if i == 0 {
        cons(value, cell.rest.clone())
    } else {
        cons(cell.first.clone(), write(&cell.rest, i - 1, value))
    }
}
fn remove<T: Clone>(cells: &List<T>, i: usize) -> List<T> {
    let cell = cells.as_ref().unwrap();
    if i == 0 {
        cell.rest.clone()
    } else {
        cons(cell.first.clone(), remove(&cell.rest, i - 1))
    }
}
fn matrix_read(cave: &Cave, (i, j): Position) -> Option<Position> {
    *read(read(cave, i), j)
}
fn matrix_write(cave: &Cave, (i, j): Position, value: Position) -> Cave {
    write(cave, i, write(read(cave, i), j, Some(value)))
}

// ---- Original deterministic shuffle ----

fn shuffle(cells: &List<Position>, random: usize) -> List<Position> {
    if cells.is_none() {
        return None;
    }
    let next = (random * 3581 + 12751) % 131072;
    let index = next % length(cells);
    cons(*read(cells, index), shuffle(&remove(cells, index), next))
}

// ---- Cavity flood fill and hole piercing ----

fn neighbors(cave: &Cave, (i, j): Position) -> Vec<Position> {
    let (n, m) = (length(cave), length(&cave.as_ref().unwrap().first));
    let positions = [
        i.checked_sub(1).map(|x| (x, j)),
        (i + 1 < n).then_some((i + 1, j)),
        j.checked_sub(1).map(|y| (i, y)),
        (j + 1 < m).then_some((i, j + 1)),
    ];
    positions
        .into_iter()
        .flatten()
        .filter(|&p| matrix_read(cave, p).is_some())
        .collect()
}

fn change_cavity(cave: &Cave, position: Position, new: Position, old: Option<Position>) -> Cave {
    if matrix_read(cave, position) != old {
        return cave.clone();
    }
    let mut changed = matrix_write(cave, position, new);
    // Snapshot neighbors from the incoming cave, then carry each updated cave.
    for next in neighbors(cave, position) {
        changed = change_cavity(&changed, next, new, old);
    }
    changed
}

fn try_to_pierce(cave: &Cave, hole: Position) -> Cave {
    let neighbors = neighbors(cave, hole);
    let ids: Vec<_> = neighbors.iter().map(|&p| matrix_read(cave, p)).collect();
    if ids
        .iter()
        .enumerate()
        .any(|(i, id)| ids[i + 1..].contains(id))
    {
        return cave.clone();
    }
    let mut changed = cave.clone();
    // Distinct labels belong to disjoint components. Read each old label from
    // the current cave, just as the original left fold does before its flood.
    for neighbor in neighbors {
        let old = matrix_read(&changed, neighbor);
        changed = change_cavity(&changed, neighbor, hole, old);
    }
    matrix_write(&changed, hole, hole)
}

fn cave_to_maze(cave: &Cave) -> Maze {
    let (mut rows, mut result) = (Vec::new(), cave.as_deref());
    while let Some(row) = result {
        let (mut cells, mut rest) = (Vec::new(), row.first.as_deref());
        while let Some(cell) = rest {
            cells.push(if cell.first.is_some() { '_' } else { '*' });
            rest = cell.rest.as_deref();
        }
        rows.push(list(cells.into_iter()));
        result = row.rest.as_deref();
    }
    list(rows.into_iter())
}

fn make_maze_grid(n: usize, m: usize) -> Maze {
    let mut cave = list((0..n).map(|i| {
        list((0..m).map(|j| {
            if i % 2 == 0 && j % 2 == 0 {
                Some((i, j))
            } else {
                None
            }
        }))
    }));
    let holes: Vec<_> = (0..n)
        .flat_map(|i| (0..m).filter_map(move |j| (i % 2 != j % 2).then_some((i, j))))
        .collect();
    let shuffled = shuffle(&list(holes.into_iter()), 0);
    let mut rest = shuffled.as_deref();
    while let Some(hole) = rest {
        cave = try_to_pierce(&cave, hole.first);
        rest = hole.rest.as_deref();
    }
    cave_to_maze(&cave)
}

// ---- Benchmark results and complete supplied predicate ----

enum MazeResult {
    False,
    Error,
    Grid(Maze),
}

fn make_maze(n: i64, m: i64) -> MazeResult {
    if n % 2 == 0 || m % 2 == 0 {
        return MazeResult::Error;
    }
    // Original increasing construction visits no cells in a negative extent.
    let n = usize::try_from(n.max(0)).expect("maze rows exceed the indexing domain");
    let m = usize::try_from(m.max(0)).expect("maze columns exceed the indexing domain");
    MazeResult::Grid(make_maze_grid(n, m))
}

fn row_matches(row: &List<char>, expected: &[Datum]) -> bool {
    match (row, expected.split_first()) {
        (None, None) => true,
        (Some(cell), Some((Datum::Atom(mark), rest))) => {
            // Output marks are ASCII symbols; strings and longer spellings fail.
            mark.as_bytes() == [cell.first as u8] && row_matches(&cell.rest, rest)
        }
        _ => false,
    }
}

fn grid_matches(rows: &Maze, expected: &[Datum]) -> bool {
    match (rows, expected.split_first()) {
        (None, None) => true,
        (Some(row), Some((Datum::List(cells), rest))) => {
            row_matches(&row.first, cells) && grid_matches(&row.rest, rest)
        }
        _ => false,
    }
}

fn matches_result(result: &MazeResult, expected: &Datum) -> bool {
    match (result, expected) {
        (MazeResult::False, Datum::Atom(value)) => value == "#f",
        (MazeResult::Error, Datum::Atom(value)) => value == "error",
        (MazeResult::Grid(rows), Datum::List(expected)) => grid_matches(rows, expected),
        _ => false,
    }
}

fn signed_integer(datum: &Datum) -> i64 {
    match datum {
        Datum::Atom(value) => value.parse().expect("expected a signed 64-bit integer"),
        _ => panic!("expected a signed 64-bit integer"),
    }
}

// ---- Complete maze serialization ----

struct DisplayMaze<'a>(&'a Maze);
impl Display for DisplayMaze<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut rows = self.0.as_deref();
        write!(out, "(")?;
        while let Some(row) = rows {
            write!(out, "(")?;
            let mut cells = row.first.as_deref();
            while let Some(cell) = cells {
                write!(out, "{}", cell.first)?;
                if cell.rest.is_some() {
                    write!(out, " ")?;
                }
                cells = cell.rest.as_deref();
            }
            write!(out, ")")?;
            if row.rest.is_some() {
                write!(out, " ")?;
            }
            rows = row.rest.as_deref();
        }
        write!(out, ")")
    }
}

impl Display for MazeResult {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::False => write!(out, "#f"),
            Self::Error => write!(out, "error"),
            Self::Grid(maze) => DisplayMaze(maze).fmt(out),
        }
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n, m) = (
        signed_integer(&values[0]),
        signed_integer(&values[1]),
        signed_integer(&values[2]),
    );
    let start = Instant::now();
    let mut result = MazeResult::False;
    for _ in 0..count {
        result = black_box(make_maze(black_box(n), black_box(m)));
    }
    assert!(matches_result(&result, &values[3]), "incorrect maze result");
    report("mazefun", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn writing_copies_prefix_and_shares_unmodified_suffix() {
        let row = list([0, 1, 2, 3].into_iter());
        let changed = write(&row, 1, 7);
        assert_eq!(*read(&row, 1), 1);
        assert_eq!(*read(&changed, 1), 7);
        assert!(Rc::ptr_eq(
            &row.as_ref()
                .unwrap()
                .rest
                .as_ref()
                .unwrap()
                .rest
                .as_ref()
                .unwrap(),
            &changed
                .as_ref()
                .unwrap()
                .rest
                .as_ref()
                .unwrap()
                .rest
                .as_ref()
                .unwrap()
        ));
    }
    #[test]
    fn one_cell_maze_and_complete_small_dimensions() {
        assert_eq!(make_maze(1, 1).to_string(), "((_))");
        let small = make_maze_grid(3, 3);
        assert_eq!(length(&small), 3);
        assert_eq!(length(&small.as_ref().unwrap().first), 3);
    }

    #[test]
    fn supplied_predicate_keeps_symbol_kinds_and_both_list_lengths() {
        let result = make_maze(1, 1);
        for (source, expected) in [
            ("((_))", true),
            ("((\"_\"))", false),
            ("((_tail))", false),
            ("#((_))", false),
            ("(#(_))", false),
            ("((_ _))", false),
            ("((_)( _))", false),
            ("(( _ . bad))", false),
            ("(())", false),
        ] {
            let datum = &r7rs_wasm_reference::read_all(source)[0];
            assert_eq!(matches_result(&result, datum), expected, "{source}");
        }
    }

    #[test]
    fn false_error_and_negative_odd_dimensions_keep_original_results() {
        assert!(matches_result(
            &MazeResult::False,
            &Datum::Atom("#f".into())
        ));
        assert!(!matches_result(
            &MazeResult::False,
            &Datum::String("#f".into())
        ));
        assert_eq!(make_maze(3, 2).to_string(), "error");
        assert_eq!(make_maze(-2, -1).to_string(), "error");
        assert_eq!(make_maze(-1, 3).to_string(), "()");
        assert_eq!(make_maze(3, -1).to_string(), "(() () ())");
    }
}
