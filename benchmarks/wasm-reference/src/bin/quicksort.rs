use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Original combined multiple recursive generator ----

struct Random {
    seed: [f64; 6],
}
impl Random {
    fn new() -> Self {
        Self {
            seed: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        }
    }
    fn flonum(&mut self) -> f64 {
        let (m1, m2) = (4294967087.0, 4294944443.0);
        let (p1, p2) = (
            1403580.0 * self.seed[1] - 810728.0 * self.seed[0],
            527612.0 * self.seed[5] - 1370589.0 * self.seed[3],
        );
        let (mut p1, mut p2) = (p1 - (p1 / m1).trunc() * m1, p2 - (p2 / m2).trunc() * m2);
        if p1 < 0.0 {
            p1 += m1;
        }
        if p2 < 0.0 {
            p2 += m2;
        }
        self.seed = [
            self.seed[1],
            self.seed[2],
            p1,
            self.seed[4],
            self.seed[5],
            p2,
        ];
        2.328306549295728e-10 * if p1 <= p2 { p1 - p2 + m1 } else { p1 - p2 }
    }
    fn integer(&mut self, n: usize) -> i64 {
        (n as f64 * self.flonum()).trunc() as i64
    }
}

// ---- In-place partition and smaller-first recursion ----

// Keep the crossing swap and its restoration, including equal elements;
// a library sort would substitute a different workload.
fn partition(v: &mut [i64], left: usize, right: usize) -> usize {
    let (pivot, mut i, mut j) = (v[right], left as isize - 1, right);
    loop {
        i += 1;
        while (i as usize) < right && v[i as usize] < pivot {
            i += 1;
        }
        j -= 1;
        while j > left && pivot < v[j] {
            j -= 1;
        }
        let i = i as usize;
        let temporary = v[i];
        v.swap(i, j);
        if i >= j {
            v[j] = v[i];
            v[i] = v[right];
            v[right] = temporary;
            return i;
        }
    }
}

fn helper(v: &mut [i64], left: isize, right: isize) {
    if left >= right {
        return;
    }
    let median = partition(v, left as usize, right as usize) as isize;
    if median - left < right - median {
        helper(v, left, median - 1);
        helper(v, median + 1, right);
    } else {
        helper(v, median + 1, right);
        helper(v, left, median - 1);
    }
}

fn quicksort(v: &mut [i64]) {
    helper(v, 0, v.len() as isize - 1);
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n, limit) = (values[0].number(), values[1].number(), values[2].number());
    let mut random = Random::new();
    let original: Vec<_> = (0..n).map(|_| random.integer(limit)).collect();
    let (start, mut result) = (Instant::now(), Vec::new());
    for _ in 0..count {
        result = black_box(original.clone());
        quicksort(black_box(&mut result));
    }
    assert!(result.windows(2).all(|pair| pair[0] <= pair[1]));
    report("quicksort", count, start, "sorted");
    if std::env::args().any(|a| a == "--dump") {
        println!("Audit: {result:?}");
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_value_matches_independent_library_sort() {
        let mut random = Random::new();
        for n in 0..32 {
            let mut actual: Vec<_> = (0..n).map(|_| random.integer(11)).collect();
            let mut expected = actual.clone();
            expected.sort();
            quicksort(&mut actual);
            assert_eq!(actual, expected);
        }
    }
}
