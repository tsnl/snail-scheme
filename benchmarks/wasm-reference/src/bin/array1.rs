use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Forward initialization and reverse copy ----

fn create_x(n: usize) -> Vec<usize> {
    let mut result = vec![0; n];
    for (i, value) in result.iter_mut().enumerate() {
        *value = i;
    }
    result
}

fn create_y(x: &[usize]) -> Vec<usize> {
    let mut result = vec![0; x.len()];
    for i in (0..x.len()).rev() {
        result[i] = x[i];
    }
    result
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].number());
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        let x = black_box(create_x(black_box(n)));
        result = black_box(create_y(black_box(&x))).len();
    }
    assert_eq!(result, values[2].number());
    report("array1", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn checks_every_copied_element() {
        assert_eq!(create_x(7), vec![0, 1, 2, 3, 4, 5, 6]);
        assert_eq!(create_y(&[9, 4, 7, 2]), vec![9, 4, 7, 2]);
        assert_eq!(create_y(&[]), vec![]);
    }
}
