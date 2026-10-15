use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::ops::{Add, Mul};
use std::time::Instant;

// ---- Rectangular complex arithmetic ----

#[derive(Clone, Copy)]
struct Complex {
    real: f64,
    imaginary: f64,
}

impl Add for Complex {
    type Output = Self;
    fn add(self, right: Self) -> Self {
        Self {
            real: self.real + right.real,
            imaginary: self.imaginary + right.imaginary,
        }
    }
}

impl Mul for Complex {
    type Output = Self;
    fn mul(self, right: Self) -> Self {
        Self {
            real: self.real * right.real - self.imaginary * right.imaginary,
            imaginary: self.real * right.imaginary + self.imaginary * right.real,
        }
    }
}

fn escape_count(z0: Complex, step: f64, position: Complex) -> usize {
    let z0 = z0
        + Complex {
            real: position.real * step,
            imaginary: position.imaginary * step,
        };
    let (mut z, mut count) = (z0, 0);
    while count != 64 {
        if z.real * z.real + z.imaginary * z.imaginary > 16.0 {
            break;
        }
        z = z * z + z0;
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
            matrix[x][y] = escape_count(
                Complex {
                    real: -1.0,
                    imaginary: -0.5,
                },
                0.005,
                Complex {
                    real: x as f64,
                    imaginary: y as f64,
                },
            );
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
    report("mbrotZ", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complex_square_and_complete_small_matrix() {
        let z = Complex {
            real: 2.0,
            imaginary: 3.0,
        };
        let square = z * z;
        assert_eq!((square.real, square.imaginary), (-5.0, 12.0));
        assert_eq!(render(3), vec![vec![5, 5, 5], vec![5, 5, 5], vec![5, 5, 5]]);
    }
}
