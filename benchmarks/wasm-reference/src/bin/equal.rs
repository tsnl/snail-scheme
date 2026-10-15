// Derived from William D. Clinger's 2007 equality benchmark.
// Copyright 2007 William D Clinger.
// Permission to copy this software, in whole or in part, to use this software
// for any lawful purpose, and to redistribute this software is granted subject
// to the restriction that all copies include this copyright notice in full.
use r7rs_wasm_reference::{input, report};
use std::collections::HashSet;
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Shared pairs and vectors ----

#[derive(Clone)]
enum Value {
    Nil,
    Atom(char),
    Pair(Rc<Pair>),
    Vector(Rc<Vec<Value>>),
}
struct Pair {
    first: Value,
    rest: Value,
}
fn cons(first: Value, rest: Value) -> Value {
    Value::Pair(Rc::new(Pair { first, rest }))
}

// Unshared deep car chains must not overflow the native Wasm stack merely
// while Rust reclaims them. Shared suffixes keep their own references.
impl Drop for Pair {
    fn drop(&mut self) {
        if matches!(self.first, Value::Nil) && matches!(self.rest, Value::Nil) {
            return;
        }
        let mut pending = vec![
            std::mem::replace(&mut self.first, Value::Nil),
            std::mem::replace(&mut self.rest, Value::Nil),
        ];
        while let Some(value) = pending.pop() {
            if let Value::Pair(pair) = value
                && let Ok(mut pair) = Rc::try_unwrap(pair)
            {
                pending.push(std::mem::replace(&mut pair.first, Value::Nil));
                pending.push(std::mem::replace(&mut pair.rest, Value::Nil));
            }
        }
    }
}

fn list(n: usize, value: &Value) -> Value {
    (0..n).fold(Value::Nil, |rest, _| cons(value.clone(), rest))
}
fn shared_tree(n: usize) -> Value {
    if n == 0 {
        Value::Nil
    } else {
        list(n, &shared_tree(n - 1))
    }
}
fn unshared_tree(n: usize) -> Value {
    (0..n).fold(Value::Nil, |rest, _| cons(unshared_tree(n - 1), rest))
}
fn deep_tree(n: usize) -> Value {
    (0..n).fold(Value::Nil, |first, _| cons(first, Value::Atom('a')))
}

// ---- Structural equality over shared graphs ----

// Scheme equal? is a runtime primitive. This Rust counterpart visits each
// corresponding pair once, retaining DAG sharing and avoiding factorial
// revisits or native recursion. Its explicit work/visited sets are a disclosed
// equality-primitive policy, rather than a change to the benchmark structures.
fn equal(left: &Value, right: &Value) -> bool {
    let (mut pending, mut visited) = (vec![(left, right)], HashSet::new());
    while let Some((left, right)) = pending.pop() {
        match (left, right) {
            (Value::Nil, Value::Nil) => {}
            (Value::Atom(a), Value::Atom(b)) if a == b => {}
            (Value::Pair(a), Value::Pair(b)) => {
                if !Rc::ptr_eq(a, b)
                    && visited.insert((Rc::as_ptr(a) as usize, Rc::as_ptr(b) as usize))
                {
                    pending.push((&a.rest, &b.rest));
                    pending.push((&a.first, &b.first));
                }
            }
            (Value::Vector(a), Value::Vector(b)) if a.len() == b.len() => {
                if !Rc::ptr_eq(a, b)
                    && visited.insert((Rc::as_ptr(a) as usize, Rc::as_ptr(b) as usize))
                {
                    pending.extend(a.iter().zip(b.iter()).rev());
                }
            }
            _ => return false,
        }
    }
    true
}

fn iterate(n: usize, left: &Value, right: &Value) -> bool {
    let mut result = false;
    for _ in 0..n {
        result = black_box(equal(black_box(left), black_box(right)));
    }
    result
}

// ---- Original five enabled equality cases ----

fn run(parameters: &[usize]) -> bool {
    // The circular-list case (parameter zero) is disabled in the original.
    let n = parameters[1];
    if !iterate(n, &shared_tree(n), &shared_tree(n)) {
        return false;
    }
    let n = parameters[2];
    if !iterate(n, &unshared_tree(n), &unshared_tree(n)) {
        return false;
    }
    let n = parameters[3];
    if !iterate(
        n,
        &Value::Vector(Rc::new(vec![Value::Atom('a'); n])),
        &Value::Vector(Rc::new(vec![Value::Atom('a'); n])),
    ) {
        return false;
    }
    let n = parameters[4];
    if !iterate(n, &list(n, &unshared_tree(3)), &list(n, &unshared_tree(3))) {
        return false;
    }
    let n = parameters[5];
    iterate(n, &deep_tree(n), &deep_tree(n))
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let parameters: Vec<_> = values[..6].iter().map(|d| d.number()).collect();
    let start = Instant::now();
    let result = run(black_box(&parameters));
    assert!(result);
    report("equal", 1, start, "#t");
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sharing_and_every_structural_difference() {
        let shared = shared_tree(4);
        assert!(equal(&shared, &unshared_tree(4)));
        assert!(!equal(&shared, &unshared_tree(3)));
        assert!(!equal(
            &cons(Value::Atom('a'), Value::Nil),
            &cons(Value::Atom('b'), Value::Nil)
        ));
        assert!(!equal(
            &Value::Vector(Rc::new(vec![Value::Nil])),
            &Value::Vector(Rc::new(vec![]))
        ));
        assert!(equal(&deep_tree(5000), &deep_tree(5000)));
    }
}
