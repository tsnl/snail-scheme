// Nucleic-acid geometry and sequential search, after Marc Feeley's workload.
use r7rs_wasm_reference::{Datum, input, read_all, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Points and original transposed homogeneous transformations ----

#[derive(Clone, Debug)]
struct Point([f64; 3]);
#[derive(Debug)]
struct Transform([f64; 12]);
fn atan2(y: f64, x: f64) -> f64 {
    if x > 0.0 {
        return (y / x).atan();
    }
    if y < 0.0 {
        if x == 0.0 {
            -std::f64::consts::FRAC_PI_2
        } else {
            (y / x).atan() - std::f64::consts::PI
        }
    } else if x == 0.0 {
        std::f64::consts::FRAC_PI_2
    } else {
        (y / x).atan() + std::f64::consts::PI
    }
}
impl Point {
    fn parse(datum: &Datum) -> Rc<Self> {
        Rc::new(Self(std::array::from_fn(|i| datum.list()[i].real())))
    }
    fn subtract(&self, other: &Self) -> Box<Self> {
        black_box(Box::new(Self(std::array::from_fn(|i| {
            self.0[i] - other.0[i]
        }))))
    }
    fn distance(&self, other: &Self) -> f64 {
        let [x, y, z] = std::array::from_fn(|i| self.0[i] - other.0[i]);
        (x * x + y * y + z * z).sqrt()
    }
    fn theta(&self) -> f64 {
        atan2(self.0[0], self.0[2])
    }
    fn phi(&self) -> f64 {
        let [x, y, z] = self.0;
        let b = atan2(x, z);
        atan2(b.cos() * z + b.sin() * x, y)
    }
}
impl Transform {
    fn parse(datum: &Datum) -> Rc<Self> {
        Rc::new(Self(std::array::from_fn(|i| datum.list()[i].real())))
    }
    fn identity() -> Rc<Self> {
        Rc::new(Self([
            1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
        ]))
    }
    fn apply(&self, point: &Point) -> Box<Point> {
        let [x, y, z] = point.0;
        black_box(Box::new(Point(std::array::from_fn(|i| {
            x * self.0[i] + y * self.0[3 + i] + z * self.0[6 + i] + self.0[9 + i]
        }))))
    }
    fn combine(&self, next: &Self) -> Rc<Self> {
        let result = std::array::from_fn(|i| {
            let (row, col) = (i / 3, i % 3);
            let sum = self.0[row * 3] * next.0[col]
                + self.0[row * 3 + 1] * next.0[col + 3]
                + self.0[row * 3 + 2] * next.0[col + 6];
            if row == 3 { sum + next.0[col + 9] } else { sum }
        });
        black_box(Rc::new(Self(result)))
    }
    fn inverse(&self) -> Rc<Self> {
        let m = &self.0;
        Rc::new(Self([
            m[0],
            m[3],
            m[6],
            m[1],
            m[4],
            m[7],
            m[2],
            m[5],
            m[8],
            -(m[0] * m[9] + m[1] * m[10] + m[2] * m[11]),
            -(m[3] * m[9] + m[4] * m[10] + m[5] * m[11]),
            -(m[6] * m[9] + m[7] * m[10] + m[8] * m[11]),
        ]))
    }
}
// Keep the complete orthogonal alignment calculation together: its signs and
// arithmetic order expose the contract more clearly than partial row helpers.
fn align(p1: &Point, p2: &Point, p3: &Point) -> Rc<Transform> {
    let [x1, y1, z1] = p1.0;
    let [x31, y31, z31] = std::array::from_fn(|i| p3.0[i] - p1.0[i]);
    let rot_y = p2.subtract(p1);
    let (phi, theta) = (rot_y.phi(), rot_y.theta());
    let (sin_p, sin_t, cos_p, cos_t) = (phi.sin(), theta.sin(), phi.cos(), theta.cos());
    let (spst, spct, cpst, cpct) = (sin_p * sin_t, sin_p * cos_t, cos_p * sin_t, cos_p * cos_t);
    let rot_z = black_box(Box::new(Point([
        cos_t * x31 - sin_t * z31,
        spst * x31 + cos_p * y31 + spct * z31,
        cpst * x31 - sin_p * y31 + cpct * z31,
    ])));
    let rho = rot_z.theta();
    let (cos_r, sin_r) = (rho.cos(), rho.sin());
    let x = -x1 * cos_t + z1 * sin_t;
    let y = -x1 * spst - y1 * cos_p - z1 * spct;
    let z = -x1 * cpst + y1 * sin_p - z1 * cpct;
    black_box(Rc::new(Transform([
        cos_t * cos_r - cpst * sin_r,
        spst,
        cos_t * sin_r + cpst * cos_r,
        sin_p * sin_r,
        cos_p,
        -sin_p * cos_r,
        -sin_t * cos_r - cpct * sin_r,
        spct,
        -sin_t * sin_r + cpct * cos_r,
        x * cos_r - z * sin_r,
        y,
        x * sin_r + z * cos_r,
    ])))
}

// ---- Frozen nucleotide conformations and shared source roots ----

#[derive(Clone, Copy)]
enum Kind {
    A,
    C,
    G,
    U,
}
struct Nucleotide {
    name: Rc<str>,
    kind: Kind,
    transforms: [Rc<Transform>; 4],
    atoms: Vec<Rc<Point>>,
}
impl Nucleotide {
    fn parse(name: &str, datum: &Datum) -> Rc<Self> {
        let items = datum.list();
        let kind = match items[29].atom() {
            "rA" => Kind::A,
            "rC" => Kind::C,
            "rG" => Kind::G,
            "rU" => Kind::U,
            _ => panic!("invalid nucleotide"),
        };
        let atoms = items[4..29]
            .iter()
            .chain(&items[30..])
            .map(Point::parse)
            .collect();
        Rc::new(Self {
            name: Rc::from(name),
            kind,
            transforms: std::array::from_fn(|i| Transform::parse(&items[i])),
            atoms,
        })
    }
}
struct Variable {
    id: usize,
    transform: Rc<Transform>,
    nucleotide: Rc<Nucleotide>,
}
type Assignments = Option<Rc<Assignment>>;
struct Assignment {
    variable: Rc<Variable>,
    rest: Assignments,
}
fn assignment(variable: Rc<Variable>, rest: Assignments) -> Assignments {
    Some(Rc::new(Assignment { variable, rest }))
}
fn variable(id: usize, transform: Rc<Transform>, nucleotide: Rc<Nucleotide>) -> Rc<Variable> {
    Rc::new(Variable {
        id,
        transform,
        nucleotide,
    })
}
fn get_var(mut partial: &Assignments, id: usize) -> &Variable {
    loop {
        let cell = partial.as_ref().expect("missing reference nucleotide");
        if cell.variable.id == id {
            return &cell.variable;
        }
        partial = &cell.rest;
    }
}
impl Variable {
    fn atom(&self, index: usize) -> Box<Point> {
        self.transform.apply(&self.nucleotide.atoms[index])
    }
}
fn base_transform(relation: &Transform, reference: &Variable, nuc: &Nucleotide) -> Rc<Transform> {
    let (n, c) = match reference.nucleotide.kind {
        Kind::A | Kind::G => (27, 22),
        Kind::C | Kind::U => (19, 21),
    };
    let alignment = align(&reference.atom(10), &reference.atom(n), &reference.atom(c)).inverse();
    nuc.transforms[0].combine(&relation.combine(&alignment))
}
enum Placement {
    Reference(Rc<Transform>),
    Relative(Rc<Transform>),
    Stacked(Rc<Transform>, Rc<Transform>),
    Phosphate,
}
struct Domain {
    id: usize,
    reference: usize,
    nucleotides: Vec<Rc<Nucleotide>>,
    placement: Placement,
}
struct Database {
    identity: Rc<Transform>,
    nucleotides: Vec<Rc<Nucleotide>>,
    relations: Vec<(String, Rc<Transform>)>,
    pseudoknot: Vec<Domain>,
    anticodon: Vec<Domain>,
}
impl Database {
    fn new() -> Self {
        let source = read_all(include_str!("../nucleic-data.scm"));
        let source = source[0].list();
        let mut data = Self {
            identity: Transform::identity(),
            nucleotides: source[0]
                .list()
                .iter()
                .map(|entry| Nucleotide::parse(entry.list()[0].atom(), &entry.list()[1]))
                .collect(),
            relations: source[1]
                .list()
                .iter()
                .map(|entry| {
                    (
                        entry.list()[0].atom().to_owned(),
                        Transform::parse(&entry.list()[1]),
                    )
                })
                .collect(),
            pseudoknot: Vec::new(),
            anticodon: Vec::new(),
        };
        data.pseudoknot = source[2]
            .list()
            .iter()
            .map(|call| data.domain(call))
            .collect();
        data.anticodon = source[3]
            .list()
            .iter()
            .map(|call| data.domain(call))
            .collect();
        data
    }
    fn nuc(&self, name: &str) -> Rc<Nucleotide> {
        self.nucleotides
            .iter()
            .find(|n| n.name.as_ref() == name)
            .unwrap()
            .clone()
    }
    fn relation(&self, name: &str) -> Rc<Transform> {
        self.relations
            .iter()
            .find(|(n, _)| n == name)
            .unwrap()
            .1
            .clone()
    }
    fn domain(&self, datum: &Datum) -> Domain {
        let args = datum.list();
        let (operation, name, id) = (args[0].atom(), args[1].atom(), args[2].number());
        let reference = if args.len() == 4 { args[3].number() } else { 0 };
        let nucleotides = if operation == "P-O3*" {
            (1..=10)
                .map(|i| self.nuc(&format!("{}{:02}", &name[..2], i)))
                .collect()
        } else {
            vec![self.nuc(name)]
        };
        let placement = match operation {
            "reference" => Placement::Reference(self.identity.clone()),
            "stacked5*" => {
                Placement::Stacked(self.relation("G37-A38-tfo"), self.relation("helix5*-tfo"))
            }
            "stacked3*" => {
                Placement::Stacked(self.relation("A38-G37-tfo"), self.relation("helix3*-tfo"))
            }
            "P-O3*" => Placement::Phosphate,
            _ => Placement::Relative(self.relation(&format!("{operation}-tfo"))),
        };
        Domain {
            id,
            reference,
            nucleotides,
            placement,
        }
    }
}
impl Domain {
    fn positioned(&self, relation: &Transform, reference: &Variable) -> Rc<Variable> {
        let nuc = self.nucleotides[0].clone();
        variable(self.id, base_transform(relation, reference, &nuc), nuc)
    }
    fn candidates(&self, partial: &Assignments) -> Assignments {
        match &self.placement {
            Placement::Reference(transform) => assignment(
                variable(self.id, transform.clone(), self.nucleotides[0].clone()),
                None,
            ),
            Placement::Relative(relation) => assignment(
                self.positioned(relation, get_var(partial, self.reference)),
                None,
            ),
            Placement::Stacked(first, second) => {
                let reference = get_var(partial, self.reference);
                assignment(
                    self.positioned(first, reference),
                    assignment(self.positioned(second, reference), None),
                )
            }
            Placement::Phosphate => self.connected(get_var(partial, self.reference)),
        }
    }
    fn connected(&self, reference: &Variable) -> Assignments {
        let alignment =
            align(&reference.atom(18), &reference.atom(16), &reference.atom(7)).inverse();
        let mut candidates = None;
        for nuc in &self.nucleotides {
            let (t60, t180, t275) = (
                nuc.transforms[3].combine(&alignment),
                nuc.transforms[2].combine(&alignment),
                nuc.transforms[1].combine(&alignment),
            );
            candidates = assignment(
                variable(self.id, t60, nuc.clone()),
                assignment(
                    variable(self.id, t180, nuc.clone()),
                    assignment(variable(self.id, t275, nuc.clone()), candidates),
                ),
            );
        }
        candidates
    }
}

// ---- Sequential backtracking with actual persistent partial/solution lists ----

type Solutions = Option<Rc<Solution>>;
struct Solution {
    variables: Assignments,
    rest: Solutions,
}
fn solution(variables: Assignments, rest: Solutions) -> Solutions {
    Some(Rc::new(Solution { variables, rest }))
}
fn append_solutions(first: &Solutions, second: Solutions) -> Solutions {
    match first {
        None => second,
        Some(s) => solution(s.variables.clone(), append_solutions(&s.rest, second)),
    }
}
#[derive(Clone, Copy)]
enum Problem {
    Pseudoknot,
    Anticodon,
}
fn constraint(var: &Variable, partial: &Assignments, problem: Problem) -> bool {
    let bound = match (problem, var.id) {
        (Problem::Pseudoknot, 18) => Some((19, 4.0)),
        (Problem::Pseudoknot, 6) => Some((7, 4.5)),
        (Problem::Anticodon, 33) => Some((34, 3.0)),
        _ => None,
    };
    bound.is_none_or(|(reference, limit)| {
        get_var(partial, reference).atom(0).distance(&var.atom(18)) <= limit
    })
}
fn search(partial: Assignments, domains: &[Domain], problem: Problem) -> Solutions {
    if domains.is_empty() {
        return solution(partial, None);
    }
    try_assignments(domains[0].candidates(&partial), &partial, domains, problem)
}
fn try_assignments(
    candidates: Assignments,
    partial: &Assignments,
    domains: &[Domain],
    problem: Problem,
) -> Solutions {
    let candidate = candidates?;
    if !constraint(&candidate.variable, partial, problem) {
        return try_assignments(candidate.rest.clone(), partial, domains, problem);
    }
    let first = search(
        assignment(candidate.variable.clone(), partial.clone()),
        &domains[1..],
        problem,
    );
    let second = try_assignments(candidate.rest.clone(), partial, domains, problem);
    append_solutions(&first, second)
}

// ---- Original atom-list append, distance maps and maximum traversals ----

type Atoms = Option<Rc<AtomCell>>;
struct AtomCell {
    point: Rc<Point>,
    rest: Atoms,
}
fn atoms(points: &[Rc<Point>]) -> Atoms {
    points.iter().rev().fold(None, |rest, point| {
        Some(Rc::new(AtomCell {
            point: point.clone(),
            rest,
        }))
    })
}
fn append_atoms(first: &Atoms, second: Atoms) -> Atoms {
    match first {
        None => second,
        Some(p) => Some(Rc::new(AtomCell {
            point: p.point.clone(),
            rest: append_atoms(&p.rest, second),
        })),
    }
}
fn all_atoms(nuc: &Nucleotide) -> Atoms {
    append_atoms(&atoms(&nuc.atoms[..25]), atoms(&nuc.atoms[25..]))
}
type Distances = Option<Box<Distance>>;
struct Distance {
    value: f64,
    rest: Distances,
}
impl Drop for Distance {
    fn drop(&mut self) {
        let mut rest = self.rest.take();
        while let Some(mut cell) = rest {
            rest = cell.rest.take();
        }
    }
}
fn distances(points: &Atoms, transform: &Transform) -> Distances {
    let point = points.as_ref()?;
    let position = transform.apply(&point.point);
    let [x, y, z] = position.0;
    Some(Box::new(Distance {
        value: (x * x + y * y + z * z).sqrt(),
        rest: distances(&point.rest, transform),
    }))
}
fn maximum(values: &Distances) -> f64 {
    let first = values.as_ref().expect("empty maximum");
    let (mut value, mut rest) = (first.value, &first.rest);
    while let Some(next) = rest {
        if next.value > value {
            value = next.value;
        }
        rest = &next.rest;
    }
    value
}
fn variable_maximum(variable: &Variable) -> f64 {
    maximum(&black_box(distances(
        &all_atoms(&variable.nucleotide),
        &variable.transform,
    )))
}
fn solution_distances(variables: &Assignments) -> Distances {
    let variable = variables.as_ref()?;
    Some(Box::new(Distance {
        value: variable_maximum(&variable.variable),
        rest: solution_distances(&variable.rest),
    }))
}
fn solution_maximum(variables: &Assignments) -> f64 {
    maximum(&black_box(solution_distances(variables)))
}
fn all_distances(solutions: &Solutions) -> Distances {
    let solution = solutions.as_ref()?;
    Some(Box::new(Distance {
        value: solution_maximum(&solution.variables),
        rest: all_distances(&solution.rest),
    }))
}
fn run(partial: &Assignments, database: &Database) -> f64 {
    let solutions = black_box(search(
        partial.clone(),
        &database.pseudoknot,
        Problem::Pseudoknot,
    ));
    maximum(&black_box(all_distances(&solutions)))
}
fn parse_partial(datum: &Datum) -> Assignments {
    datum.list().iter().rev().fold(None, |rest, value| {
        let value = value.list();
        assignment(
            variable(
                value[0].number(),
                Transform::parse(&value[1]),
                Nucleotide::parse("input", &value[2]),
            ),
            rest,
        )
    })
}

// ---- Untimed complete solution audit and benchmark predicate ----

struct Audit<'a>(&'a Solutions);
impl Display for Audit<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(")?;
        let (mut rest, mut first) = (self.0, true);
        while let Some(solution) = rest {
            if !first {
                write!(out, " ")?;
            }
            write_assignments(&solution.variables, out)?;
            rest = &solution.rest;
            first = false;
        }
        write!(out, ")")
    }
}
fn write_assignments(mut variables: &Assignments, out: &mut fmt::Formatter<'_>) -> fmt::Result {
    write!(out, "(")?;
    let mut first = true;
    while let Some(cell) = variables {
        if !first {
            write!(out, " ")?;
        }
        let v = &cell.variable;
        write!(out, "({} {} (", v.id, v.nucleotide.name)?;
        for (i, number) in v.transform.0.iter().enumerate() {
            if i > 0 {
                write!(out, " ")?;
            }
            write!(out, "{number:?}")?;
        }
        write!(out, "))")?;
        variables = &cell.rest;
        first = false;
    }
    write!(out, ")")
}
fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, expected) = (values[0].number(), values[2].real());
    let database = Database::new();
    let partial = parse_partial(&values[1]);
    let (start, mut result) = (Instant::now(), 0.0);
    for _ in 0..count {
        result = black_box(run(black_box(&partial), &database));
    }
    let ratio = result / expected;
    assert!(ratio > 0.999999 && ratio < 1.000001);
    report("nucleic", count, start, result);
    if std::env::args().any(|s| s == "--dump") {
        println!(
            "Audit: {}",
            Audit(&search(partial, &database.pseudoknot, Problem::Pseudoknot))
        );
    }
    if std::env::args().any(|s| s == "--audit-anticodon") {
        println!(
            "Anticodon audit: {}",
            Audit(&search(None, &database.anticodon, Problem::Anticodon))
        );
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    fn close(first: &Point, second: &Point) {
        for i in 0..3 {
            assert!((first.0[i] - second.0[i]).abs() < 1e-10);
        }
    }
    #[test]
    fn complete_transform_composition_inverse_and_alignment() {
        let p = Point([1.0, 2.0, 3.0]);
        let t = Transform([0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 4.0, 5.0, 6.0]);
        close(&t.apply(&p), &Point([2.0, 6.0, 9.0]));
        close(&t.inverse().apply(&t.apply(&p)), &p);
        close(&t.combine(&t.inverse()).apply(&p), &p);
        let a = align(
            &Point([1.0, 2.0, 3.0]),
            &Point([1.0, 4.0, 3.0]),
            &Point([1.0, 2.0, 5.0]),
        );
        close(&a.apply(&Point([1.0, 2.0, 3.0])), &Point([0.0, 0.0, 0.0]));
        close(&a.apply(&Point([1.0, 4.0, 3.0])), &Point([0.0, 2.0, 0.0]));
        assert_eq!(atan2(0.0, 0.0), std::f64::consts::FRAC_PI_2);
    }
    #[test]
    fn fixed_data_and_persistent_partial_identity() {
        let db = Database::new();
        assert_eq!(db.nucleotides.len(), 46);
        assert_eq!(db.pseudoknot.len(), 23);
        let first = db.pseudoknot[0].candidates(&None);
        let second = db.pseudoknot[1].candidates(&first);
        let partial = assignment(second.as_ref().unwrap().variable.clone(), first.clone());
        assert!(Rc::ptr_eq(
            partial.as_ref().unwrap().rest.as_ref().unwrap(),
            first.as_ref().unwrap()
        ));
        assert_eq!(get_var(&partial, 23).nucleotide.name.as_ref(), "rA");
        let (Placement::Reference(first), Placement::Reference(second)) =
            (&db.pseudoknot[0].placement, &db.anticodon[0].placement)
        else {
            unreachable!()
        };
        assert!(Rc::ptr_eq(first, second));
    }
    #[test]
    fn source_order_candidate_groups_and_materialized_prefix() {
        let db = Database::new();
        let prefix = search(None, &db.pseudoknot[..16], Problem::Pseudoknot);
        let variables = &prefix.as_ref().unwrap().variables;
        let candidates = db.pseudoknot[16].candidates(variables);
        let first = candidates.as_ref().unwrap();
        assert_eq!(first.variable.nucleotide.name.as_ref(), "rU10");
        assert!(Rc::ptr_eq(
            &first.variable.nucleotide,
            &first.rest.as_ref().unwrap().variable.nucleotide
        ));
        assert_eq!(
            first
                .rest
                .as_ref()
                .unwrap()
                .rest
                .as_ref()
                .unwrap()
                .variable
                .nucleotide
                .name
                .as_ref(),
            "rU10"
        );
        assert!(search(None, &db.anticodon[..2], Problem::Anticodon).is_some());
    }
    #[test]
    fn atom_append_copies_common_prefix_and_keeps_specific_tail_identity() {
        let db = Database::new();
        let nuc = db.nuc("rA");
        let prefix = atoms(&nuc.atoms[..25]);
        let suffix = atoms(&nuc.atoms[25..]);
        let joined = append_atoms(&prefix, suffix.clone());
        assert!(!Rc::ptr_eq(
            joined.as_ref().unwrap(),
            prefix.as_ref().unwrap()
        ));
        let mut tail = &joined;
        for _ in 0..25 {
            tail = &tail.as_ref().unwrap().rest;
        }
        assert!(Rc::ptr_eq(tail.as_ref().unwrap(), suffix.as_ref().unwrap()));
    }
}
