use r7rs_wasm_reference::{input, report};
use std::collections::LinkedList;
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Shared carbon radicals and materialized molecules ----

type Radical = Option<Rc<Carbon>>; // None is the source's shared hydrogen atom.
struct Carbon {
    branches: [Radical; 3],
}
enum Center {
    Bond([Radical; 2]),
    Carbon([Radical; 4]),
}
struct Generated {
    bonds: LinkedList<Box<Center>>,
    carbons: LinkedList<Box<Center>>,
}

// The radical table retains shared immutable branches. Each final molecule
// has an owned center allocation and a separately allocated outer list cell;
// all complete molecules remain live until the original length traversal.

// ---- Original ordered size partitions ----

fn three_partitions(m: usize) -> Vec<[usize; 3]> {
    let mut partitions = Vec::new();
    for first in 0..=m / 3 {
        for second in first..=(m - first) / 2 {
            partitions.push([first, second, m - first - second]);
        }
    }
    partitions
}

fn four_partitions(m: usize) -> Vec<[usize; 4]> {
    let mut partitions = Vec::new();
    for first in 0..=m / 4 {
        for second in first..=(m - first) / 3 {
            let start = second.max(m.div_ceil(2).saturating_sub(first + second));
            for third in start..=(m - first - second) / 2 {
                partitions.push([first, second, third, m - first - second - third]);
            }
        }
    }
    partitions
}

// ---- Three-branch radical generation ----

fn radicals_of_size(n: usize, table: &[Vec<Radical>]) -> Vec<Radical> {
    let mut radicals = Vec::new();
    for [s1, s2, s3] in three_partitions(n - 1) {
        for (i, first) in table[s1].iter().enumerate() {
            let start2 = if s1 == s2 { i } else { 0 };
            for (j, second) in table[s2].iter().enumerate().skip(start2) {
                let start3 = if s2 == s3 { j } else { 0 };
                for third in &table[s3][start3..] {
                    radicals.push(Some(Rc::new(Carbon {
                        branches: [first.clone(), second.clone(), third.clone()],
                    })));
                }
            }
        }
    }
    radicals
}

// ---- Bond-centered and carbon-centered molecules ----

fn bond_centers(n: usize, table: &[Vec<Radical>]) -> LinkedList<Box<Center>> {
    let mut molecules = LinkedList::new();
    if n.is_multiple_of(2) {
        let radicals = &table[n / 2];
        for (i, first) in radicals.iter().enumerate() {
            for second in &radicals[i..] {
                molecules.push_back(Box::new(Center::Bond([first.clone(), second.clone()])));
            }
        }
    }
    molecules
}

// The exhaustive four-branch dispatch is the combinatorial operation itself.
// Equal-sized branches start at the preceding branch's suffix to avoid
// generating identical arrangements under permutations of those branches.
fn carbon_centers(n: usize, table: &[Vec<Radical>]) -> LinkedList<Box<Center>> {
    let mut molecules = LinkedList::new();
    for [s1, s2, s3, s4] in four_partitions(n - 1) {
        for (i, first) in table[s1].iter().enumerate() {
            for (j, second) in table[s2]
                .iter()
                .enumerate()
                .skip(if s1 == s2 { i } else { 0 })
            {
                for (k, third) in table[s3]
                    .iter()
                    .enumerate()
                    .skip(if s2 == s3 { j } else { 0 })
                {
                    for fourth in &table[s4][if s3 == s4 { k } else { 0 }..] {
                        molecules.push_back(Box::new(Center::Carbon([
                            first.clone(),
                            second.clone(),
                            third.clone(),
                            fourth.clone(),
                        ])));
                    }
                }
            }
        }
    }
    molecules
}

fn generate(n: usize) -> Generated {
    let mut radicals = vec![Vec::new(); n / 2 + 1];
    radicals[0].push(None);
    for i in 1..=n / 2 {
        radicals[i] = radicals_of_size(i, &radicals);
    }
    Generated {
        bonds: bond_centers(n, &radicals),
        carbons: carbon_centers(n, &radicals),
    }
}

fn number(n: usize) -> usize {
    let generated = black_box(generate(n));
    molecule_count(&generated.bonds) + molecule_count(&generated.carbons)
}

fn molecule_count(molecules: &LinkedList<Box<Center>>) -> usize {
    let mut count = 0;
    for molecule in molecules {
        black_box(molecule);
        count += 1;
    }
    count
}

// ---- Untimed full topology serialization ----

struct DisplayRadical<'a>(&'a Radical);
impl Display for DisplayRadical<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.0 {
            None => write!(out, "H"),
            Some(carbon) => write!(
                out,
                "#(C {} {} {})",
                DisplayRadical(&carbon.branches[0]),
                DisplayRadical(&carbon.branches[1]),
                DisplayRadical(&carbon.branches[2])
            ),
        }
    }
}
impl Display for Center {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Bond(branches) => write!(
                out,
                "#(BCP {} {})",
                DisplayRadical(&branches[0]),
                DisplayRadical(&branches[1])
            ),
            Self::Carbon(branches) => write!(
                out,
                "#(CCP {} {} {} {})",
                DisplayRadical(&branches[0]),
                DisplayRadical(&branches[1]),
                DisplayRadical(&branches[2]),
                DisplayRadical(&branches[3])
            ),
        }
    }
}
impl Display for Generated {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "#(")?;
        for (i, molecules) in [&self.bonds, &self.carbons].iter().enumerate() {
            if i > 0 {
                write!(out, " ")?;
            }
            write!(out, "(")?;
            for (j, molecule) in molecules.iter().enumerate() {
                if j > 0 {
                    write!(out, " ")?;
                }
                write!(out, "{molecule}")?;
            }
            write!(out, ")")?;
        }
        write!(out, ")")
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].number());
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(number(black_box(n)));
    }
    assert_eq!(result, values[2].number());
    report("paraffins", count, start, result);
    if std::env::args().any(|a| a == "--dump") {
        println!("Audit: {}", generate(n));
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn independently_known_small_alkane_counts() {
        assert_eq!(
            (1..=8).map(number).collect::<Vec<_>>(),
            vec![1, 1, 1, 2, 3, 5, 9, 18]
        );
    }
    #[test]
    fn complete_methane_topology_and_shared_ethane_branches() {
        assert_eq!(generate(1).to_string(), "#(() (#(CCP H H H H)))");
        let ethane = generate(2);
        let Center::Bond(branches) = ethane.bonds.front().unwrap().as_ref() else {
            panic!("missing bond center")
        };
        assert!(Rc::ptr_eq(
            branches[0].as_ref().unwrap(),
            branches[1].as_ref().unwrap()
        ));
    }
}
