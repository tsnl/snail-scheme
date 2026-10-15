use r7rs_wasm_reference::{input, list::List, report};
use std::hint::black_box;
use std::time::Instant;

// ---- List filtering sieve ----

fn interval(m: i64, n: i64) -> List {
    if m > n {
        List::Nil
    } else {
        List::cons(m, interval(m + 1, n))
    }
}

fn remove_multiples(n: i64, list: &List) -> List {
    match list {
        List::Nil => List::Nil,
        List::Cons(value, rest) if value % n == 0 => remove_multiples(n, rest),
        List::Cons(value, rest) => List::cons(*value, remove_multiples(n, rest)),
    }
}

fn sieve(list: &List) -> List {
    match list {
        List::Nil => List::Nil,
        List::Cons(prime, rest) => List::cons(*prime, sieve(&remove_multiples(*prime, rest))),
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].integer());
    let expected = List::from_values(
        &values[2]
            .list()
            .iter()
            .map(|d| d.integer())
            .collect::<Vec<_>>(),
    );
    let (start, mut result) = (Instant::now(), List::Nil);
    for _ in 0..count {
        result = black_box(sieve(&black_box(interval(2, black_box(n)))));
    }
    assert_eq!(result, expected);
    report("primes", count, start, &result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_small_prime_lists() {
        assert_eq!(
            sieve(&interval(2, 20)).values(),
            vec![2, 3, 5, 7, 11, 13, 17, 19]
        );
        assert_eq!(sieve(&interval(2, 1)), List::Nil);
    }
}
