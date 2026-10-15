use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Scalar Mandelbrot iteration ----

fn escape_count(r: f64, i: f64, step: f64, x: usize, y: usize) -> usize {
    let (cr, ci) = (r + x as f64 * step, i + y as f64 * step);
    let (mut zr, mut zi, mut count) = (cr, ci, 0);
    while count != 64 {
        let (zr2, zi2) = (zr * zr, zi * zi);
        if zr2 + zi2 > 16.0 {
            break;
        }
        (zr, zi) = (zr2 - zi2 + cr, 2.0 * (zr * zi) + ci);
        count += 1;
    }
    count
}

fn render(n: usize) -> Vec<Vec<usize>> {
    let mut matrix = vec![Vec::new(); n];
    for i in (0..n).rev() {
        matrix[i] = vec![0; n];
    }
    for y in (0..n).rev() {
        for x in (0..n).rev() {
            matrix[x][y] = escape_count(-1.0, -0.5, 0.005, x, y);
        }
    }
    matrix
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].number());
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(render(black_box(n)))[0][0];
    }
    assert_eq!(result, values[2].number());
    report("mbrot", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_small_matrix_values() {
        assert_eq!(render(3), vec![vec![5, 5, 5], vec![5, 5, 5], vec![5, 5, 5]]);
        assert_eq!(escape_count(0.0, 0.0, 0.0, 0, 0), 64);
        assert_eq!(escape_count(5.0, 0.0, 0.0, 0, 0), 0);
    }
}
