use r7rs_wasm_reference::{Datum, input, list::List, report};
use std::hint::black_box;
use std::time::Instant;

// ---- List counters ----

fn shorter(x: &List, y: &List) -> bool {
    !y.is_empty() && (x.is_empty() || shorter(x.tail(), y.tail()))
}

fn mas<'a>(x: &'a List, y: &'a List, z: &'a List) -> &'a List {
    if !shorter(y, x) {
        z
    } else {
        mas(
            mas(x.tail(), y, z),
            mas(y.tail(), z, x),
            mas(z.tail(), x, y),
        )
    }
}

fn parse_list(datum: &Datum) -> List {
    List::from_values(&datum.list().iter().map(Datum::integer).collect::<Vec<_>>())
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, x, y, z) = (
        values[0].number(),
        parse_list(&values[1]),
        parse_list(&values[2]),
        parse_list(&values[3]),
    );
    let (start, mut result) = (Instant::now(), &z);
    for _ in 0..count {
        result = black_box(mas(black_box(&x), black_box(&y), black_box(&z)));
    }
    let length = result.len();
    assert_eq!(length, values[4].number());
    report("takl", count, start, length);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_result_suffix() {
        let (x, y, z) = (
            List::from_values(&[6, 5, 4, 3, 2, 1]),
            List::from_values(&[4, 3, 2, 1]),
            List::from_values(&[2, 1]),
        );
        assert_eq!(mas(&x, &y, &z).values(), vec![3, 2, 1]);
        assert!(!shorter(&List::Nil, &List::Nil));
    }
}
