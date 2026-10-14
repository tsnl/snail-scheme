use r7rs_wasm_reference::{Datum, input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::time::Instant;

// ---- Two-phase simplex tableau ----

const EPSILON: f64 = 0.000001;

#[derive(Debug, PartialEq, Eq)]
enum Outcome {
    Infeasible,
    Unbounded,
    Basis(Vec<usize>, Vec<usize>),
}
struct Simplex {
    a: Vec<Vec<f64>>,
    m: usize,
    n: usize,
    m1: usize,
    m12: usize,
    l1: Vec<usize>,
    l2: Vec<usize>,
    l3: Vec<bool>,
    iposv: Vec<usize>,
    izrov: Vec<usize>,
    ip: usize,
    kp: usize,
    bmax: f64,
}

impl Simplex {
    fn new(a: Vec<Vec<f64>>, m1: usize, m2: usize, m3: usize) -> Self {
        let (m, n) = (a.len() - 2, a[0].len() - 1);
        assert_eq!(m, m1 + m2 + m3);
        assert!(a[1..=m].iter().all(|row| row[0] >= 0.0));
        Self {
            a,
            m,
            n,
            m1,
            m12: m1 + m2 + 1,
            l1: (1..=n).collect(),
            l2: (1..=m).collect(),
            l3: vec![true; m2],
            iposv: (n..n + m).collect(),
            izrov: (0..n).collect(),
            ip: 0,
            kp: 0,
            bmax: 0.0,
        }
    }

    fn choose_column(&mut self, row: usize, absolute: bool) {
        self.kp = self.l1[0];
        self.bmax = self.a[row][self.kp];
        for &column in &self.l1[1..] {
            let value = self.a[row][column];
            let delta = if absolute {
                value.abs() - self.bmax.abs()
            } else {
                value - self.bmax
            };
            if delta > 0.0 {
                self.kp = column;
                self.bmax = value;
            }
        }
    }

    fn tie_breaks_before(&self, row: usize) -> bool {
        for k in 1..=self.n {
            let (qp, q0) = (
                -self.a[self.ip][k] / self.a[self.ip][self.kp],
                -self.a[row][k] / self.a[row][self.kp],
            );
            if q0 != qp {
                return q0 < qp;
            }
        }
        false
    }

    fn choose_row(&mut self) {
        self.ip = 0;
        let mut minimum = 0.0;
        for &row in &self.l2 {
            if self.a[row][self.kp] < -EPSILON {
                let quotient = -self.a[row][0] / self.a[row][self.kp];
                if self.ip == 0
                    || quotient < minimum
                    || (quotient == minimum && self.tie_breaks_before(row))
                {
                    self.ip = row;
                    minimum = quotient;
                }
            }
        }
    }

    fn pivot(&mut self, first_phase: bool) {
        let reciprocal = 1.0 / self.a[self.ip][self.kp];
        for row in 0..self.m + if first_phase { 2 } else { 1 } {
            if row != self.ip {
                self.a[row][self.kp] *= reciprocal;
                for column in 0..=self.n {
                    if column != self.kp {
                        self.a[row][column] -= self.a[self.ip][column] * self.a[row][self.kp];
                    }
                }
            }
        }
        for column in 0..=self.n {
            if column != self.kp {
                self.a[self.ip][column] *= -reciprocal;
            }
        }
        self.a[self.ip][self.kp] = reciprocal;
    }

    fn exchange_basis(&mut self) {
        std::mem::swap(&mut self.izrov[self.kp - 1], &mut self.iposv[self.ip - 1]);
    }
    fn negate_column(&mut self) {
        self.a[self.m + 1][self.kp] += 1.0;
        for row in 0..self.m + 2 {
            self.a[row][self.kp] = -self.a[row][self.kp];
        }
    }

    fn remove_artificial_variable(&mut self) {
        let basic = self.iposv[self.ip - 1];
        if basic >= self.n + self.m12 - 1 {
            let index = self.l1.iter().position(|&k| k == self.kp).unwrap();
            self.l1.remove(index);
            self.negate_column();
        } else if basic >= self.n + self.m1 && self.l3[basic - self.m1 - self.n] {
            self.l3[basic - self.m1 - self.n] = false;
            self.negate_column();
        }
        self.exchange_basis();
    }

    fn finish_constraints(&mut self) -> bool {
        // Preserve the source's ip-dependent artificial-row check.
        for row in self.m12..=self.m {
            if self.iposv[row - 1] == self.ip + self.n - 1 {
                self.choose_column(row, true);
                if self.bmax > 0.0 {
                    self.ip = row;
                    return true;
                }
            }
        }
        for row in self.m1 + 1..self.m12 {
            if self.l3[row - self.m1 - 1] {
                for value in &mut self.a[row] {
                    *value = -*value;
                }
            }
        }
        false
    }

    fn phase_one(&mut self) -> bool {
        for column in 0..=self.n {
            let mut sum = 0.0;
            for row in self.m1 + 1..=self.m {
                sum += self.a[row][column];
            }
            self.a[self.m + 1][column] = -sum;
        }
        loop {
            self.choose_column(self.m + 1, false);
            let pivot = if self.bmax <= EPSILON {
                if self.a[self.m + 1][0] < -EPSILON {
                    return false;
                }
                if self.a[self.m + 1][0] <= EPSILON {
                    self.finish_constraints()
                } else {
                    self.choose_row();
                    if self.ip == 0 {
                        return false;
                    }
                    true
                }
            } else {
                self.choose_row();
                if self.ip == 0 {
                    return false;
                }
                true
            };
            if !pivot {
                return true;
            }
            self.pivot(true);
            self.remove_artificial_variable();
        }
    }

    fn solve(mut self) -> Outcome {
        if (!self.l3.is_empty() || self.m12 - 1 < self.m) && !self.phase_one() {
            return Outcome::Infeasible;
        }
        loop {
            self.choose_column(0, false);
            if self.bmax <= 0.0 {
                break;
            }
            self.choose_row();
            if self.ip == 0 {
                return Outcome::Unbounded;
            }
            self.pivot(false);
            self.exchange_basis();
        }
        Outcome::Basis(self.iposv, self.izrov)
    }
}

fn test() -> Outcome {
    Simplex::new(
        black_box(vec![
            vec![0.0, 1.0, 1.0, 3.0, -0.5],
            vec![740.0, -1.0, 0.0, -2.0, 0.0],
            vec![0.0, 0.0, -2.0, 0.0, 7.0],
            vec![0.5, 0.0, -1.0, 1.0, -2.0],
            vec![9.0, -1.0, -1.0, -1.0, -1.0],
            vec![0.0; 5],
        ]),
        2,
        1,
        1,
    )
    .solve()
}

fn expected(datum: &Datum) -> Outcome {
    let values = datum.list();
    Outcome::Basis(
        values[0].list().iter().map(Datum::number).collect(),
        values[1].list().iter().map(Datum::number).collect(),
    )
}

impl Display for Outcome {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Infeasible => write!(out, "#f"),
            Self::Unbounded => write!(out, "#t"),
            Self::Basis(positions, columns) => {
                write!(out, "(")?;
                for (i, vector) in [positions, columns].iter().enumerate() {
                    if i > 0 {
                        write!(out, " ")?;
                    }
                    write!(out, "#(")?;
                    for (j, n) in vector.iter().enumerate() {
                        if j > 0 {
                            write!(out, " ")?;
                        }
                        write!(out, "{n}")?;
                    }
                    write!(out, ")")?;
                }
                write!(out, ")")
            }
        }
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let expected = expected(&values[2]);
    let (start, mut result) = (Instant::now(), Outcome::Infeasible);
    for _ in 0..count {
        black_box(values[1].real());
        result = black_box(test());
    }
    assert_eq!(result, expected);
    report("simplex", count, start, &result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_basis_vectors() {
        assert_eq!(test(), Outcome::Basis(vec![4, 1, 3, 2], vec![0, 5, 7, 6]));
    }
}
