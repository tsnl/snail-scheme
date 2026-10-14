use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Polygon ray crossings ----

fn contains(xp: &[f64], yp: &[f64], x: f64, y: f64) -> bool {
    let (mut inside, mut j) = (false, 0);
    for i in (0..xp.len()).rev() {
        let disjoint = (yp[i] > y || y >= yp[j]) && (yp[j] > y || y >= yp[i]);
        if !disjoint && x < xp[i] + (xp[j] - xp[i]) * (y - yp[i]) / (yp[j] - yp[i]) {
            inside = !inside;
        }
        j = i;
    }
    inside
}

fn run(xp: &[f64], yp: &[f64]) -> usize {
    // Preserve the fresh per-iteration polygon copies.
    let (xp, yp) = (black_box(xp.to_vec()), black_box(yp.to_vec()));
    let points = [
        (0.5, 0.5),
        (0.5, 1.5),
        (-0.5, 1.5),
        (0.75, 2.25),
        (0.0, 2.01),
        (-0.5, 2.5),
        (-1.0, -0.5),
        (-1.5, 0.5),
        (-2.25, -1.0),
        (0.5, -0.25),
        (0.5, -1.25),
        (-0.5, -2.5),
    ];
    points
        .iter()
        .filter(|&&(x, y)| contains(&xp, &yp, x, y))
        .count()
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let xp: Vec<_> = values[1].list().iter().map(|v| v.real()).collect();
    let yp: Vec<_> = values[2].list().iter().map(|v| v.real()).collect();
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run(black_box(&xp), black_box(&yp)));
    }
    assert_eq!(result, values[3].number());
    report("pnpoly", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn inside_outside_and_boundary() {
        let (x, y) = ([0.0, 1.0, 1.0, 0.0], [0.0, 0.0, 1.0, 1.0]);
        assert!(contains(&x, &y, 0.5, 0.5));
        assert!(!contains(&x, &y, 1.5, 0.5));
        assert!(!contains(&x, &y, 0.5, 1.0));
    }
}
