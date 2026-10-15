use num_bigint::BigInt;
use r7rs_wasm_reference::{Datum, input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::time::Instant;

// ---- Binary splitting of the Chudnovsky series ----

// Scheme computes this fixed value at top level, before the benchmark clock.
// Keep the full u64 scalar on wasm32; only the variable cube belongs in a leaf.
const C_CUBED: u64 = 640320_u64.pow(3);

struct Split {
    g: BigInt,
    p: BigInt,
    q: BigInt,
}

fn split(a: u32, b: u32) -> Split {
    if b - a == 1 {
        let g = BigInt::from(6 * b - 5) * (2 * b - 1) * (6 * b - 1);
        let p = BigInt::from(b).pow(3) * C_CUBED / 24_u32;
        let sign = if b.is_multiple_of(2) { 1 } else { -1 };
        let q = &g * (BigInt::from(b) * 545140134_u32 + 13591409_u32) * sign;
        Split { g, p, q }
    } else {
        let middle = (a + b) / 2;
        let (left, right) = (split(a, middle), split(middle, b));
        Split {
            g: &left.g * &right.g,
            p: &left.p * &right.p,
            q: left.q * right.p + right.q * left.g,
        }
    }
}

fn pi(digits: u32) -> BigInt {
    let terms = (2.0 + digits as f64 / 14.181647462).floor() as u32;
    let sqrt_c = (BigInt::from(640320) * BigInt::from(100).pow(digits)).sqrt();
    let Split { p, q, .. } = split(0, terms);
    &p * 640320_u32 * sqrt_c / ((q + &p * 13591409_u32) * 12_u32)
}

fn pies(n: u32, m: u32, step: u32) -> Vec<BigInt> {
    (n..=m).step_by(step as usize).map(pi).collect()
}

// ---- Exact result serialization ----

struct Pies<'a>(&'a [BigInt]);
impl Display for Pies<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(")?;
        for (i, value) in self.0.iter().enumerate() {
            if i > 0 {
                write!(out, " ")?;
            }
            write!(out, "{value}")?;
        }
        write!(out, ")")
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n, m, step) = (
        values[0].number(),
        values[1].number() as u32,
        values[2].number() as u32,
        values[3].number() as u32,
    );
    let expected: Vec<BigInt> = values[4]
        .list()
        .iter()
        .map(|d: &Datum| d.atom().parse().unwrap())
        .collect();
    let (start, mut result) = (Instant::now(), Vec::new());
    for _ in 0..count {
        result = black_box(pies(black_box(n), black_box(m), black_box(step)));
    }
    assert_eq!(result, expected);
    report("chudnovsky", count, start, Pies(&result));
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn truncated_pi_digits() {
        assert_eq!(pi(10), BigInt::from(31415926535_i64));
        assert_eq!(
            pies(1, 3, 1),
            vec![BigInt::from(31), BigInt::from(314), BigInt::from(3141)]
        );
    }

    #[test]
    fn exact_split_boundaries() {
        // Complete triples independently evaluated by the original Chez code.
        for (a, b, expected) in [
            (0, 1, ["5", "10939058860032000", "-2793657715"]),
            (1, 2, ["231", "87512470880256000", "254994357387"]),
            (
                0,
                2,
                [
                    "1155",
                    "957304069945956794936328192000000",
                    "-244479889433338740603253065",
                ],
            ),
        ] {
            let Split { g, p, q } = split(a, b);
            assert_eq!([g, p, q], expected.map(|value| value.parse().unwrap()));
        }
    }

    #[test]
    fn empty_precision_range() {
        assert!(pies(3, 1, 1).is_empty());
    }
}
