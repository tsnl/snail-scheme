use r7rs_wasm_reference::{Datum, input, report};
use std::collections::VecDeque;
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Shared numeric rows and persistent matrix lists ----

type Row = Option<Rc<Number>>;
#[derive(Debug, PartialEq, Eq)]
struct Number {
    first: i64,
    rest: Row,
}
type Matrix = Option<Rc<MatrixCell>>;
#[derive(Debug, PartialEq, Eq)]
struct MatrixCell {
    first: Row,
    rest: Matrix,
}
fn number(first: i64, rest: Row) -> Row {
    Some(Rc::new(Number { first, rest }))
}
fn matrix(first: Row, rest: Matrix) -> Matrix {
    Some(Rc::new(MatrixCell { first, rest }))
}
fn row_from(values: &[i64]) -> Row {
    values
        .iter()
        .rev()
        .fold(None, |rest, &first| number(first, rest))
}
fn matrix_length(mut rows: &Matrix) -> usize {
    let mut n = 0;
    while let Some(row) = rows {
        n += 1;
        rows = &row.rest;
    }
    n
}
fn reverse_matrix(rows: &Matrix) -> Matrix {
    let (mut result, mut rest) = (None, rows);
    while let Some(row) = rest {
        result = matrix(row.first.clone(), result);
        rest = &row.rest;
    }
    result
}
fn matrix_tails(rows: &Matrix) -> Matrix {
    match rows {
        None => None,
        Some(row) => matrix(
            row.first.as_ref().unwrap().rest.clone(),
            matrix_tails(&row.rest),
        ),
    }
}
fn prepend_column(value: i64, rows: &Matrix) -> Matrix {
    match rows {
        None => None,
        Some(row) => matrix(
            number(value, row.first.clone()),
            prepend_column(value, &row.rest),
        ),
    }
}

// ---- Modular coefficient field and exact inverse table ----

struct Field {
    modulus: i64,
    inverses: Vec<i64>,
}
fn inverse_coefficient(mut p: i64, mut q: i64) -> i64 {
    let (mut pa, mut qa) = (1, 0);
    while q != 0 {
        let multiplier = p.div_euclid(q);
        (p, q) = (q, p - multiplier * q);
        (pa, qa) = (qa, pa - multiplier * qa);
    }
    pa
}
fn find_prime(bound: i64) -> i64 {
    if 2 > bound {
        return 2;
    }
    let (mut primes, mut trial) = (vec![2], 3);
    loop {
        if next_prime(trial, &primes) {
            primes.push(trial);
            if trial > bound {
                return trial;
            }
        }
        trial += 2;
    }
}
fn next_prime(trial: i64, primes: &[i64]) -> bool {
    for &prime in primes {
        if trial < prime * prime {
            return true;
        }
        if trial % prime == 0 {
            return false;
        }
    }
    true
}
fn determinant_bound(size: usize) -> i64 {
    let main = (size as i64).pow((size / 2) as u32);
    if size.is_multiple_of(2) {
        return main;
    }
    let mut root = 0;
    while root * root < size as i64 {
        root += 1;
    }
    main * root
}
impl Field {
    fn new(inv_size: usize) -> Self {
        let modulus = find_prime(determinant_bound(inv_size));
        Self {
            modulus,
            inverses: (1..modulus)
                .map(|i| inverse_coefficient(i, modulus))
                .collect(),
        }
    }
    fn reduce(&self, value: i64) -> i64 {
        value.rem_euclid(self.modulus)
    }
    fn zero(&self, value: i64) -> bool {
        self.reduce(value) == 0
    }
    fn add(&self, a: i64, b: i64) -> i64 {
        self.reduce(a + b)
    }
    fn multiply(&self, a: i64, b: i64) -> i64 {
        self.reduce(a * b)
    }
    fn reciprocal(&self, value: i64) -> i64 {
        self.inverses[(self.reduce(value) - 1) as usize]
    }
}
fn scale(field: &Field, row: &Row, multiplier: i64) -> Row {
    match row {
        None => None,
        Some(cell) => number(
            field.multiply(multiplier, cell.first),
            scale(field, &cell.rest, multiplier),
        ),
    }
}
fn combine(field: &Field, row: &Row, zap: &Row, multiplier: i64) -> Row {
    match row {
        None => None,
        Some(cell) => {
            let zap = zap.as_ref().unwrap();
            number(
                field.add(cell.first, field.multiply(multiplier, zap.first)),
                combine(field, &cell.rest, &zap.rest, multiplier),
            )
        }
    }
}

// ---- Original column-first row reduction and row-space predicates ----

// Zero-prefix rows and remaining rows are prepended in the original order.
// Prefixing or trimming a column shares existing row suffixes.
fn row_reduce(field: &Field, mut rows: Matrix) -> Matrix {
    if rows.as_ref().is_none_or(|row| row.first.is_none()) {
        return None;
    }
    let mut out = None;
    while let Some(row) = rows {
        let pivot = row.first.as_ref().unwrap();
        rows = row.rest.clone();
        if field.zero(pivot.first) {
            out = matrix(pivot.rest.clone(), out);
        } else {
            let zap = scale(field, &pivot.rest, field.reciprocal(pivot.first));
            while let Some(row) = rows {
                let first = row.first.as_ref().unwrap();
                let tail = if field.zero(first.first) {
                    first.rest.clone()
                } else {
                    combine(field, &first.rest, &zap, -first.first)
                };
                out = matrix(tail, out);
                rows = row.rest.clone();
            }
            return matrix(number(1, zap), prepend_column(0, &row_reduce(field, out)));
        }
    }
    prepend_column(0, &row_reduce(field, out))
}
fn in_row_space(field: &Field, mut basis: Matrix, mut row: Row) -> bool {
    while let Some(first) = row {
        row = first.rest.clone();
        if field.zero(first.first) {
            if basis
                .as_ref()
                .is_some_and(|b| !field.zero(b.first.as_ref().unwrap().first))
            {
                basis = basis.as_ref().unwrap().rest.clone();
            }
            basis = matrix_tails(&basis);
        } else {
            let Some(zap) = basis else {
                return false;
            };
            let pivot = zap.first.as_ref().unwrap();
            if field.zero(pivot.first) {
                return false;
            }
            row = combine(field, &row, &pivot.rest, -first.first);
            basis = matrix_tails(&zap.rest);
        }
    }
    true
}

// ---- Original permutation cursors and partition refinement ----

struct Permutation {
    future: Matrix,
    past: Matrix,
}
impl Permutation {
    fn new(future: Matrix) -> Option<Self> {
        future.as_ref()?;
        Some(Self { future, past: None })
    }
    fn now(&self) -> &Row {
        &self.future.as_ref().unwrap().first
    }
    fn brother(&self) -> Option<Self> {
        let current = self.future.as_ref().unwrap();
        let past = matrix(current.first.clone(), self.past.clone());
        current.rest.as_ref()?;
        Some(Self {
            future: current.rest.clone(),
            past,
        })
    }
    fn child(&self) -> Option<Self> {
        let mut future = self.future.as_ref().unwrap().rest.clone();
        let mut past = &self.past;
        while let Some(row) = past {
            future = matrix(row.first.clone(), future);
            past = &row.rest;
        }
        Self::new(future)
    }
}
fn normalized(mut row: &Row, mut first: &Row, sign: i64) -> Vec<i64> {
    let mut values = Vec::new();
    while let Some(cell) = row {
        let origin = first.as_ref().unwrap();
        values.push(if origin.first == cell.first {
            sign
        } else {
            -sign
        });
        row = &cell.rest;
        first = &origin.rest;
    }
    values
}
enum Comparison {
    Less,
    Greater,
    Equal(Vec<Vec<usize>>),
}

// Refine each column class into reversed plus/minus lists. Equal classes
// continue into the remaining rows; strict comparison stops immediately.
fn compare_row(mut old: &Row, new: &[i64], partitions: &[Vec<usize>]) -> Comparison {
    let mut refined = Vec::new();
    for partition in partitions {
        let (mut plus, mut minus) = (Vec::new(), Vec::new());
        for &column in partition {
            if new[column] == 1 {
                let first = old.as_ref().unwrap();
                if first.first != 1 {
                    return Comparison::Less;
                }
                old = &first.rest;
                plus.push(column);
            } else {
                minus.push(column);
            }
        }
        for _ in &minus {
            let first = old.as_ref().unwrap();
            if first.first == 1 {
                return Comparison::Greater;
            }
            old = &first.rest;
        }
        plus.reverse();
        minus.reverse();
        if !plus.is_empty() {
            refined.push(plus);
        }
        if !minus.is_empty() {
            refined.push(minus);
        }
    }
    Comparison::Equal(refined)
}
fn zebra(
    mut cursor: Option<Permutation>,
    first: &Row,
    rows: &Matrix,
    partitions: &[Vec<usize>],
) -> bool {
    while let Some(permutation) = cursor {
        let old = rows.as_ref().unwrap();
        for sign in [1, -1] {
            match compare_row(
                &old.first,
                &normalized(permutation.now(), first, sign),
                partitions,
            ) {
                Comparison::Less => return false,
                Comparison::Greater => {}
                Comparison::Equal(refined) => {
                    if !zebra(permutation.child(), first, &old.rest, &refined) {
                        return false;
                    }
                }
            }
        }
        cursor = permutation.brother();
    }
    true
}
fn maximal(rows: &Matrix) -> bool {
    let mut cursor = Permutation::new(rows.clone());
    while let Some(first) = cursor {
        let columns = {
            let mut n = 0;
            let mut row = first.now();
            while let Some(cell) = row {
                n += 1;
                row = &cell.rest;
            }
            n
        };
        if !zebra(
            first.child(),
            first.now(),
            &rows.as_ref().unwrap().rest,
            &[(0..columns).collect()],
        ) {
            return false;
        }
        cursor = first.brother();
    }
    true
}

// ---- Row enumeration and subset row-space tests ----

fn generate_tails(columns: usize, prefix: &mut Vec<i64>, rows: &mut Matrix) {
    if columns == 0 {
        *rows = matrix(row_from(prefix), rows.take());
        return;
    }
    for value in [1, -1] {
        prefix.push(value);
        generate_tails(columns - 1, prefix, rows);
        prefix.pop();
    }
}
fn all_rows(columns: usize) -> Matrix {
    let mut generated = None;
    generate_tails(columns - 1, &mut Vec::new(), &mut generated);
    let (mut rows, mut rest) = (None, &generated);
    while let Some(row) = rest {
        rows = matrix(number(1, row.first.clone()), rows);
        rest = &row.rest;
    }
    rows
}
enum Tester {
    Space(Matrix),
    Subsets(VecDeque<Matrix>),
}
impl Tester {
    fn contains(&self, field: &Field, row: &Row) -> bool {
        match self {
            Self::Space(basis) => in_row_space(field, basis.clone(), row.clone()),
            Self::Subsets(tests) => tests
                .iter()
                .any(|basis| in_row_space(field, basis.clone(), row.clone())),
        }
    }
}
fn collect_tests(
    field: &Field,
    new: &Row,
    universe: &Matrix,
    needed: usize,
    remaining: usize,
    prefix: &mut Vec<Row>,
    tests: &mut VecDeque<Matrix>,
) {
    if remaining < needed {
        return;
    }
    if needed == 0 || remaining == needed {
        let suffix = if remaining == needed {
            universe.clone()
        } else {
            None
        };
        let subset = prefix
            .iter()
            .rev()
            .fold(suffix, |rest, row| matrix(row.clone(), rest));
        tests.push_front(row_reduce(field, matrix(new.clone(), subset)));
        return;
    }
    let first = universe.as_ref().unwrap();
    prefix.push(first.first.clone());
    collect_tests(
        field,
        new,
        &first.rest,
        needed - 1,
        remaining - 1,
        prefix,
        tests,
    );
    prefix.pop();
    collect_tests(
        field,
        new,
        &first.rest,
        needed,
        remaining - 1,
        prefix,
        tests,
    );
}
fn make_tester(field: &Field, rows: &Matrix, count: usize, inv_size: usize) -> Tester {
    if count < inv_size {
        return Tester::Space(row_reduce(field, rows.clone()));
    }
    let first = rows.as_ref().unwrap();
    let mut tests = VecDeque::new();
    collect_tests(
        field,
        &first.first,
        &first.rest,
        inv_size - 2,
        matrix_length(&first.rest),
        &mut Vec::new(),
        &mut tests,
    );
    Tester::Subsets(tests)
}
fn remove_dependent(field: &Field, tester: &Tester, mut rows: &Matrix) -> Matrix {
    let mut reversed = None;
    while let Some(row) = rows {
        if !tester.contains(field, &row.first) {
            reversed = matrix(row.first.clone(), reversed);
        }
        rows = &row.rest;
    }
    reverse_matrix(&reversed)
}

// ---- Search and complete maximal-result materialization ----

#[derive(Debug, PartialEq, Eq)]
enum Answer {
    Matrix(Matrix),
    Ellipsis,
}
struct Best {
    size: i64,
    count: usize,
    answers: VecDeque<Answer>,
}
impl Best {
    fn consider(&mut self, rows: Matrix) {
        let size = matrix_length(&rows) as i64;
        if size < self.size {
            return;
        }
        if size > self.size {
            self.size = size;
            self.count = 1;
            self.answers = VecDeque::from([Answer::Matrix(rows)]);
        } else {
            self.count += 1;
            if self.count < 3000 {
                self.answers.push_front(Answer::Matrix(rows));
            } else if self.count == 3000 {
                self.answers.push_front(Answer::Ellipsis);
            }
        }
    }
}
fn search(
    field: &Field,
    inv_size: usize,
    count: usize,
    rows: Matrix,
    future: Matrix,
    best: &mut Best,
) {
    let tester = make_tester(field, &rows, count, inv_size);
    let mut future = remove_dependent(field, &tester, &future);
    drop(tester);
    if future.is_none() {
        best.consider(reverse_matrix(&rows));
        return;
    }
    while let Some(next) = future {
        let candidate = matrix(next.first.clone(), rows.clone());
        if maximal(&reverse_matrix(&candidate)) {
            search(
                field,
                inv_size,
                count + 1,
                candidate,
                next.rest.clone(),
                best,
            );
        }
        future = next.rest.clone();
    }
}
fn really_go(columns: usize, inv_size: usize) -> VecDeque<Answer> {
    assert!(columns > 0 && inv_size >= 2);
    let field = Field::new(inv_size);
    let rows = all_rows(columns);
    let first = rows.as_ref().unwrap();
    let mut best = Best {
        size: -1,
        count: 0,
        answers: VecDeque::new(),
    };
    search(
        &field,
        inv_size,
        1,
        matrix(first.first.clone(), None),
        first.rest.clone(),
        &mut best,
    );
    best.answers
}
fn parse_matrix(datum: &Datum) -> Matrix {
    datum.list().iter().rev().fold(None, |rest, row| {
        matrix(
            row_from(&row.list().iter().map(Datum::integer).collect::<Vec<_>>()),
            rest,
        )
    })
}
fn expected(datum: &Datum) -> VecDeque<Answer> {
    datum
        .list()
        .iter()
        .map(|d| match d {
            Datum::String(s) if s == "..." => Answer::Ellipsis,
            _ => Answer::Matrix(parse_matrix(d)),
        })
        .collect()
}

// ---- Complete result serialization ----

struct Results<'a>(&'a VecDeque<Answer>);
fn write_row(out: &mut fmt::Formatter<'_>, mut row: &Row) -> fmt::Result {
    write!(out, "(")?;
    while let Some(cell) = row {
        write!(out, "{}", cell.first)?;
        if cell.rest.is_some() {
            write!(out, " ")?;
        }
        row = &cell.rest;
    }
    write!(out, ")")
}
fn write_matrix(out: &mut fmt::Formatter<'_>, mut rows: &Matrix) -> fmt::Result {
    write!(out, "(")?;
    while let Some(row) = rows {
        write_row(out, &row.first)?;
        if row.rest.is_some() {
            write!(out, " ")?;
        }
        rows = &row.rest;
    }
    write!(out, ")")
}
impl Display for Results<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(")?;
        for (i, answer) in self.0.iter().enumerate() {
            if i > 0 {
                write!(out, " ")?;
            }
            match answer {
                Answer::Matrix(rows) => write_matrix(out, rows)?,
                Answer::Ellipsis => write!(out, "\"...\"")?,
            }
        }
        write!(out, ")")
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, columns, inv_size) = (values[0].number(), values[1].number(), values[2].number());
    let expected = expected(&values[3]);
    let (start, mut result) = (Instant::now(), VecDeque::new());
    for _ in 0..count {
        result = black_box(really_go(black_box(columns), black_box(inv_size)));
    }
    assert_eq!(result, expected);
    report("matrix", count, start, Results(&result));
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_modular_inverses_and_row_space() {
        let field = Field::new(3);
        for i in 1..field.modulus {
            assert_eq!(field.multiply(i, field.reciprocal(i)), 1);
        }
        let rows = matrix(row_from(&[1, 1, 0]), matrix(row_from(&[0, 1, 1]), None));
        let basis = row_reduce(&field, rows);
        assert!(in_row_space(&field, basis.clone(), row_from(&[1, 2, 1])));
        assert!(!in_row_space(&field, basis, row_from(&[1, 0, 0])));
    }
    #[test]
    fn partition_comparison_and_nonempty_materialized_results() {
        assert!(matches!(
            compare_row(&row_from(&[1, -1]), &[1, 1], &[vec![0, 1]]),
            Comparison::Less
        ));
        assert!(matches!(
            compare_row(&row_from(&[1, 1]), &[1, -1], &[vec![0, 1]]),
            Comparison::Greater
        ));
        assert!(!really_go(3, 3).is_empty());
    }
}
