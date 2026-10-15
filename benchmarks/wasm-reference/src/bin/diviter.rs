use r7rs_wasm_reference::{input, list::List, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Iterative list division ----

fn divide(mut list: &List) -> List {
    let mut result = List::Nil;
    while let List::Cons(value, _) = list {
        result = List::cons(*value, result);
        list = list.tail().tail();
    }
    result
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let list = List::from_values(&vec![0; values[1].number()]);
    let (start, mut result) = (Instant::now(), List::Nil);
    for _ in 0..count {
        result = black_box(divide(black_box(&list)));
    }
    let length = result.len();
    assert_eq!(length, values[2].number());
    report("diviter", count, start, length);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn checks_order_and_contents() {
        assert_eq!(
            divide(&List::from_values(&[1, 2, 3, 4, 5, 6])).values(),
            vec![5, 3, 1]
        );
        assert_eq!(divide(&List::Nil), List::Nil);
    }
}
