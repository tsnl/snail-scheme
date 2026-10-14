use num_bigint::BigInt;
use r7rs_wasm_reference::{Datum, input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::time::Instant;

// ---- Fixed-point exact arithmetic ----

fn square(x: &BigInt) -> BigInt {
    x * x
}
fn fourth_root(x: &BigInt) -> BigInt {
    x.sqrt().sqrt()
}

fn brent_salamin(digits: u32) -> BigInt {
    let one = BigInt::from(10).pow(digits);
    let (mut a, mut b, mut t, mut x) = (
        one.clone(),
        (square(&one) / 2_u32).sqrt(),
        &one / 4_u32,
        BigInt::from(1),
    );
    while a != b {
        let new_a = (&a + &b) / 2_u32;
        b = (&a * &b).sqrt();
        t -= &x * square(&(&new_a - &a)) / &one;
        (a, x) = (new_a, x * 2_u32);
    }
    square(&(a + b)) / (t * 4_u32)
}

fn borwein2(digits: u32) -> BigInt {
    let one = BigInt::from(10).pow(digits);
    let one2 = square(&one);
    let sqrt2 = (&one2 * 2_u32).sqrt();
    let qurt2 = fourth_root(&(square(&one2) * 2_u32));
    let (mut x, mut y, mut p) = (
        &one * (&sqrt2 + &one) / (&qurt2 * 2_u32),
        qurt2,
        &one * 2_u32 + sqrt2,
    );
    loop {
        let new_p = &p * (&x + &one) / (&y + &one);
        if x == one {
            return new_p;
        }
        let sqrt_x = (&one * &x).sqrt();
        y = &one * (&x * &y + &one2) / ((&y + &one) * &sqrt_x);
        x = &one * (&x + &one) / (&sqrt_x * 2_u32);
        p = new_p;
    }
}

fn borwein4(digits: u32) -> BigInt {
    let one = BigInt::from(10).pow(digits);
    let one2 = square(&one);
    let one4 = square(&one2);
    let sqrt2 = (&one2 * 2_u32).sqrt();
    let (mut y, mut a, mut x) = (&sqrt2 - &one, &one * 6_u32 - sqrt2 * 4_u32, BigInt::from(8));
    while y != BigInt::from(0) {
        let t1 = fourth_root(&(&one4 - square(&square(&y))));
        let t2 = &one * (&one - &t1) / (&one + t1);
        let t3 = square(&(square(&(&one + &t2)) / &one)) / &one;
        let t4 = &one + &t2 + square(&t2) / &one;
        a = (t3 * a - &x * &t2 * t4) / &one;
        (y, x) = (t2, x * 4_u32);
    }
    one2 / a
}

fn pies(n: u32, m: u32, step: u32) -> Vec<[BigInt; 3]> {
    (n..=m)
        .step_by(step as usize)
        .map(|digits| {
            let (bs, b2, b4) = (brent_salamin(digits), borwein2(digits), borwein4(digits));
            [b2.clone(), bs - &b2, b4 - b2]
        })
        .collect()
}

fn expected(datum: &Datum) -> Vec<[BigInt; 3]> {
    datum
        .list()
        .iter()
        .map(|row| std::array::from_fn(|i| row.list()[i].atom().parse().unwrap()))
        .collect()
}

// ---- Exact result serialization ----

struct Pies<'a>(&'a [[BigInt; 3]]);
impl Display for Pies<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(")?;
        for (i, row) in self.0.iter().enumerate() {
            if i > 0 {
                write!(out, " ")?;
            }
            write!(out, "({} {} {})", row[0], row[1], row[2])?;
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
    let expected = expected(&values[4]);
    let (start, mut result) = (Instant::now(), Vec::new());
    for _ in 0..count {
        result = black_box(pies(black_box(n), black_box(m), black_box(step)));
    }
    assert_eq!(result, expected);
    report("pi", count, start, Pies(&result));
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_roots_and_fixed_point_rounding() {
        assert_eq!(BigInt::from(-7) / 3, BigInt::from(-2));
        for (input, expected) in [(15, 3), (16, 4), (17, 4)] {
            assert_eq!(BigInt::from(input).sqrt(), BigInt::from(expected));
        }
        assert_eq!(fourth_root(&BigInt::from(80)), BigInt::from(2));
        assert_eq!(fourth_root(&BigInt::from(81)), BigInt::from(3));
        assert_eq!(BigInt::from(99).sqrt(), BigInt::from(9));
        assert_eq!(fourth_root(&BigInt::from(255)), BigInt::from(3));
        // Independently evaluated by the original Chez implementations.
        assert_eq!(borwein2(10), BigInt::from(31415926532_i64));
        assert_eq!(brent_salamin(10), BigInt::from(31415926510_i64));
        assert_eq!(borwein4(10), BigInt::from(31415926405_i64));
    }

    #[test]
    fn empty_precision_range() {
        assert!(pies(3, 1, 1).is_empty());
    }
}
