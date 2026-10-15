use r7rs_wasm_reference::{input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Shared inner lists and owned outer lists ----

type Link = Option<Rc<Cell>>;
struct Cell {
    first: usize,
    rest: Link,
}
struct Row {
    first: Link,
    rest: Option<Box<Row>>,
}
struct Permutations {
    rows: Option<Box<Row>>,
}

fn cons(first: usize, rest: Link) -> Link {
    Some(Rc::new(Cell { first, rest }))
}
fn one_to_n(n: usize) -> Link {
    (1..=n).rev().fold(None, |rest, first| cons(first, rest))
}

impl Permutations {
    fn empty() -> Self {
        Self { rows: None }
    }
    fn prepend(&mut self, first: Link) {
        self.rows = Some(Box::new(Row {
            first,
            rest: self.rows.take(),
        }));
    }
}

// The outer list can have millions of cells. Reclaim it iteratively; inner
// suffixes stay shared until their last owning permutation is released.
impl Drop for Permutations {
    fn drop(&mut self) {
        let mut rest = self.rows.take();
        while let Some(mut row) = rest {
            rest = row.rest.take();
        }
    }
}

fn list_tail(mut list: Link, n: usize) -> Link {
    for _ in 0..n {
        list = list.as_ref().unwrap().rest.clone();
    }
    list
}

fn reverse_prefix(list: &Link, n: usize) -> Link {
    let mut result = list_tail(list.clone(), n);
    let mut rest = list.as_deref();
    for _ in 0..n {
        let cell = rest.unwrap();
        result = cons(cell.first, result);
        rest = cell.rest.as_deref();
    }
    result
}

// ---- Zaks pancake-flip permutation generation ----

struct Generator {
    current: Link,
    permutations: Permutations,
}
impl Generator {
    fn flip(&mut self, n: usize) {
        self.current = reverse_prefix(&self.current, n);
        self.permutations.prepend(self.current.clone());
    }
    fn generate(&mut self, n: usize) {
        if n <= 1 {
            return;
        }
        for _ in 0..n - 1 {
            self.generate(n - 1);
            self.flip(n);
        }
        self.generate(n - 1);
    }
}

fn permutations(n: usize) -> Permutations {
    let mut generator = Generator {
        current: one_to_n(n),
        permutations: Permutations::empty(),
    };
    generator.permutations.prepend(generator.current.clone());
    generator.generate(n);
    generator.permutations
}

// ---- Queue rotation and original result predicate ----

fn fill_queue(queue: &mut [Option<Rc<Permutations>>], n: usize) {
    for item in queue {
        *item = Some(Rc::new(permutations(n)));
    }
}
fn flush_queue(queue: &mut [Option<Rc<Permutations>>], ell: usize) {
    for i in 0..queue.len() {
        queue[i] = queue.get(i + ell).cloned().flatten();
    }
}
fn sum_lists(permutations: &Permutations) -> usize {
    let (mut rows, mut sum) = (permutations.rows.as_deref(), 0);
    while let Some(row) = rows {
        let mut list = row.first.as_deref();
        while let Some(cell) = list {
            sum += cell.first;
            list = cell.rest.as_deref();
        }
        rows = row.rest.as_deref();
    }
    sum
}
fn same_list(mut first: &Link, mut second: &Link) -> bool {
    loop {
        match (first, second) {
            (None, None) => return true,
            (Some(a), Some(b)) if a.first == b.first => {
                first = &a.rest;
                second = &b.rest;
            }
            _ => return false,
        }
    }
}
fn check_result(queue: &[Option<Rc<Permutations>>], n: usize, ell: usize) -> usize {
    let (first, other) = (&queue[0], &queue[(queue.len() - ell).saturating_sub(1)]);
    let sum = match (first, other) {
        (None, None) => 0,
        (Some(first), Some(other)) => {
            assert!(same_list(
                &first.rows.as_ref().unwrap().first,
                &other.rows.as_ref().unwrap().first
            ));
            sum_lists(first)
        }
        _ => panic!("queue heads disagree"),
    };
    let factorial: usize = (1..=n).product();
    assert_eq!(sum, n * (n + 1) * factorial / 2);
    sum
}

// ---- Untimed complete permutation audit ----

impl Display for Permutations {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut rows = self.rows.as_deref();
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

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (m, n, k, ell) = (
        values[0].number(),
        values[1].number(),
        values[2].number(),
        values[3].number(),
    );
    assert!(n > 0 && k > 0 && ell <= k);
    let mut queue: Vec<Option<Rc<Permutations>>> = vec![None; k];
    fill_queue(&mut queue[..k - ell], n); // Original preparation occurs before timing.
    let start = Instant::now();
    for _ in 0..m {
        fill_queue(black_box(&mut queue[k - ell..]), black_box(n));
        flush_queue(&mut queue, ell);
    }
    let sum = check_result(&queue, n, ell); // Traverse every integer of every retained permutation.
    report("mperm", m, start, sum);
    if std::env::args().any(|a| a == "--dump") {
        println!("Audit: {}", queue[0].as_ref().unwrap());
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    fn rows(permutations: &Permutations) -> Vec<Vec<usize>> {
        let (mut rest, mut result) = (permutations.rows.as_deref(), Vec::new());
        while let Some(row) = rest {
            let (mut list, mut values) = (row.first.as_deref(), Vec::new());
            while let Some(cell) = list {
                values.push(cell.first);
                list = cell.rest.as_deref();
            }
            result.push(values);
            rest = row.rest.as_deref();
        }
        result
    }
    #[test]
    fn every_permutation_in_original_gray_code_order() {
        assert_eq!(
            rows(&permutations(3)),
            vec![
                vec![3, 2, 1],
                vec![2, 3, 1],
                vec![1, 3, 2],
                vec![3, 1, 2],
                vec![2, 1, 3],
                vec![1, 2, 3]
            ]
        );
    }
    #[test]
    fn prefix_flip_shares_its_original_suffix() {
        let list = one_to_n(4);
        let flipped = reverse_prefix(&list, 2);
        assert!(Rc::ptr_eq(
            list_tail(list, 2).as_ref().unwrap(),
            list_tail(flipped, 2).as_ref().unwrap()
        ));
    }
    #[test]
    fn queue_rotation_preserves_the_retained_copy() {
        let mut queue = vec![
            Some(Rc::new(permutations(3))),
            Some(Rc::new(permutations(3))),
        ];
        let survivor = queue[1].clone().unwrap();
        flush_queue(&mut queue, 1);
        assert!(Rc::ptr_eq(queue[0].as_ref().unwrap(), &survivor));
        assert!(queue[1].is_none());
        assert_eq!(check_result(&queue, 3, 1), 36);
    }
}
