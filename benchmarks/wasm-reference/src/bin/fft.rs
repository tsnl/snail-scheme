use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Bit reversal ----

fn reverse_bits(data: &mut [f64]) {
    let (n, mut j) = (data.len(), 0);
    for i in (0..n).step_by(2) {
        if i < j {
            data.swap(i, j);
            data.swap(i + 1, j + 1);
        }
        let mut m = n / 2;
        while m >= 2 && j >= m {
            j -= m;
            m /= 2;
        }
        j += m;
    }
}

// ---- Danielson-Lanczos butterflies ----

fn butterfly(data: &mut [f64], i: usize, j: usize, wr: f64, wi: f64) {
    let real = wr * data[j] - wi * data[j + 1];
    let imaginary = wr * data[j + 1] + wi * data[j];
    data[j] = data[i] - real;
    data[j + 1] = data[i + 1] - imaginary;
    data[i] += real;
    data[i + 1] += imaginary;
}

fn stage(data: &mut [f64], width: usize) {
    #[allow(clippy::approx_constant)] // Preserve the original rounded pi*2 constant.
    let theta = 6.28318530717959 / width as f64;
    let (wpr, wpi) = (-2.0 * (0.5 * theta).sin().powi(2), theta.sin());
    let (mut wr, mut wi) = (1.0, 0.0);
    for m in (0..width).step_by(2) {
        for i in (m..data.len()).step_by(width * 2) {
            butterfly(data, i, i + width, wr, wi);
        }
        (wr, wi) = ((wr * wpr - wi * wpi) + wr, (wi * wpr + wr * wpi) + wi);
    }
}

fn four1(data: &mut [f64]) {
    assert!(data.len() >= 2 && data.len().is_power_of_two());
    reverse_bits(data);
    let mut width = 2;
    while width < data.len() {
        stage(data, width);
        width *= 2;
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n, initial) = (values[0].number(), values[1].number(), values[2].real());
    let (start, mut result) = (Instant::now(), 0.0);
    for _ in 0..count {
        let mut data = black_box(vec![initial; black_box(n)]);
        four1(black_box(&mut data));
        result = black_box(data)[0];
    }
    assert_eq!(result, values[3].real());
    report("fft", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_nonzero_transform_matches_direct_dft() {
        let original = [1.0, 2.0, 3.0, -1.0, 4.0, 0.5, -2.0, 1.0];
        let mut actual = original;
        four1(&mut actual);
        for k in 0..4 {
            let (mut real, mut imaginary) = (0.0, 0.0);
            for j in 0..4 {
                let angle = std::f64::consts::TAU * (k * j) as f64 / 4.0;
                real += original[2 * j] * angle.cos() - original[2 * j + 1] * angle.sin();
                imaginary += original[2 * j] * angle.sin() + original[2 * j + 1] * angle.cos();
            }
            assert!((actual[2 * k] - real).abs() < 1e-12);
            assert!((actual[2 * k + 1] - imaginary).abs() < 1e-12);
        }
    }
}
