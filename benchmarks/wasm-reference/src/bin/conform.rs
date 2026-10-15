use r7rs_wasm_reference::{Datum, input, report};
use std::collections::VecDeque;
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Mutable type graph with stable node identities ----

type Id = usize;
const NONE: Id = 0;
const ANY: Id = 1;
#[derive(Clone, Copy, PartialEq, Eq)]
enum Operation {
    Phi,
    Theta,
}
#[derive(Clone, Copy)]
struct Edge {
    operation: Operation,
    argument: Id,
    result: Id,
}
struct Node {
    name: Rc<str>,
    green: Vec<Id>,
    red: Vec<Id>,
    blue: Option<Vec<Edge>>,
}
type Table = Vec<(Id, Vec<(Id, Id)>)>;
struct Graph {
    nodes: Vec<Node>,
    roots: Vec<Id>,
    met: Table,
    joined: Table,
}

enum NameInput {
    Symbol(Rc<str>),
    Text(Rc<str>),
}
impl NameInput {
    fn parse(datum: &Datum) -> Self {
        match datum {
            Datum::Atom(s) => Self::Symbol(Rc::from(s.as_str())),
            Datum::String(s) => Self::Text(Rc::from(s.as_str())),
            _ => panic!("invalid node name"),
        }
    }
    fn name(&self) -> Rc<str> {
        match self {
            Self::Symbol(s) => Rc::from(s.to_string()),
            Self::Text(s) => s.clone(),
        }
    }
}
fn adjoin<T: PartialEq>(value: T, values: &mut Vec<T>) {
    if !values.contains(&value) {
        values.insert(0, value);
    }
}
fn table_lookup(table: &Table, first: Id, second: Id) -> Option<Id> {
    table
        .iter()
        .find(|(key, _)| *key == first)?
        .1
        .iter()
        .find(|(key, _)| *key == second)
        .map(|(_, value)| *value)
}
fn table_insert(table: &mut Table, first: Id, second: Id, value: Id) {
    if let Some((_, line)) = table.iter_mut().find(|(key, _)| *key == first) {
        line.insert(0, (second, value));
    } else {
        table.insert(0, (first, vec![(second, value)]));
    }
}

impl Graph {
    fn node(&mut self, name: Rc<str>) -> Id {
        let id = self.nodes.len();
        self.nodes.push(Node {
            name,
            green: Vec::new(),
            red: Vec::new(),
            blue: None,
        });
        id
    }
    fn new(names: &[NameInput]) -> Self {
        let mut graph = Self {
            nodes: Vec::new(),
            roots: Vec::new(),
            met: Vec::new(),
            joined: Vec::new(),
        };
        graph.node(Rc::from("none"));
        graph.node(Rc::from("any"));
        let ids: Vec<_> = names.iter().map(|name| graph.node(name.name())).collect();
        let (a, b, c, d) = (ids[0], ids[1], ids[2], ids[3]);
        graph.nodes[a].blue = Some(vec![Edge {
            operation: Operation::Phi,
            argument: ANY,
            result: b,
        }]);
        graph.nodes[b].blue = Some(vec![
            Edge {
                operation: Operation::Phi,
                argument: ANY,
                result: a,
            },
            Edge {
                operation: Operation::Theta,
                argument: ANY,
                result: b,
            },
        ]);
        graph.nodes[c].blue = Some(vec![Edge {
            operation: Operation::Theta,
            argument: ANY,
            result: b,
        }]);
        graph.nodes[d].blue = Some(vec![
            Edge {
                operation: Operation::Phi,
                argument: ANY,
                result: c,
            },
            Edge {
                operation: Operation::Theta,
                argument: ANY,
                result: d,
            },
        ]);
        graph.roots = vec![a, b, c, d, ANY, NONE];
        graph
    }
    fn blue(&self, node: Id) -> &[Edge] {
        assert!(
            node != NONE && node != ANY,
            "special node has no accessible edges"
        );
        self.nodes[node]
            .blue
            .as_ref()
            .expect("node is still under construction")
    }
    fn edge(&self, node: Id, operation: Operation) -> Option<Edge> {
        self.blue(node)
            .iter()
            .find(|e| e.operation == operation)
            .copied()
    }
    fn signature(&self, node: Id, operation: Operation) -> (Id, Id) {
        self.edge(node, operation)
            .map_or((NONE, ANY), |e| (e.argument, e.result))
    }

    // Red edges are temporary coinductive assumptions. Successful conformity
    // moves them to green; failure removes every assumption made by this call.
    fn does_conform(&mut self, first: Id, second: Id, touched: &mut Vec<Id>) -> bool {
        if first == NONE || second == ANY {
            return true;
        }
        if first == ANY || second == NONE {
            return false;
        }
        if self.nodes[first].green.contains(&second) || self.nodes[first].red.contains(&second) {
            return true;
        }
        adjoin(second, &mut self.nodes[first].red);
        adjoin(first, touched);
        for i in 0..self.blue(second).len() {
            let edge = self.blue(second)[i];
            let Some(other) = self.edge(first, edge.operation) else {
                return false;
            };
            if !self.does_conform(other.result, edge.result, touched)
                || !self.does_conform(edge.argument, other.argument, touched)
            {
                return false;
            }
        }
        true
    }
    fn conforms(&mut self, first: Id, second: Id) -> bool {
        let mut touched = Vec::new();
        let result = self.does_conform(first, second, &mut touched);
        for node in touched {
            if result {
                let mut green = std::mem::take(&mut self.nodes[node].red);
                green.append(&mut self.nodes[node].green);
                self.nodes[node].green = green;
            } else {
                self.nodes[node].red.clear();
            }
        }
        result
    }
    fn equivalent(&mut self, first: Id, second: Id) -> bool {
        self.conforms(first, second) && self.conforms(second, first)
    }

    // Cache the placeholder before descending into signatures. Recursive
    // types can then refer to the same node without duplicating their cycles.
    fn meet(&mut self, first: Id, second: Id) -> Id {
        if first == second {
            return first;
        }
        if first == ANY || second == ANY {
            return ANY;
        }
        if first == NONE {
            return second;
        }
        if second == NONE {
            return first;
        }
        if let Some(node) = table_lookup(&self.met, first, second) {
            return node;
        }
        if self.conforms(first, second) {
            return second;
        }
        if self.conforms(second, first) {
            return first;
        }
        let node = self.node(Rc::from(format!(
            "({} ^ {})",
            self.nodes[first].name, self.nodes[second].name
        )));
        self.roots.insert(0, node);
        table_insert(&mut self.met, first, second, node);
        let operations: Vec<_> = self
            .blue(first)
            .iter()
            .map(|e| e.operation)
            .filter(|&op| self.edge(second, op).is_some())
            .collect();
        let mut blue = Vec::new();
        for operation in operations {
            let (a1, r1) = self.signature(first, operation);
            let (a2, r2) = self.signature(second, operation);
            blue.push(Edge {
                operation,
                argument: self.join(a1, a2),
                result: self.meet(r1, r2),
            });
        }
        self.nodes[node].blue = Some(blue);
        node
    }
    fn join(&mut self, first: Id, second: Id) -> Id {
        if first == second {
            return first;
        }
        if first == ANY {
            return second;
        }
        if second == ANY {
            return first;
        }
        if first == NONE || second == NONE {
            return NONE;
        }
        if let Some(node) = table_lookup(&self.joined, first, second) {
            return node;
        }
        if self.conforms(first, second) {
            return first;
        }
        if self.conforms(second, first) {
            return second;
        }
        let node = self.node(Rc::from(format!(
            "({} v {})",
            self.nodes[first].name, self.nodes[second].name
        )));
        self.roots.insert(0, node);
        table_insert(&mut self.joined, first, second, node);
        let mut operations: Vec<_> = self.blue(second).iter().map(|e| e.operation).collect();
        for edge in self.blue(first) {
            adjoin(edge.operation, &mut operations);
        }
        let mut blue = Vec::new();
        for operation in operations {
            let (a1, r1) = self.signature(first, operation);
            let (a2, r2) = self.signature(second, operation);
            blue.push(Edge {
                operation,
                argument: self.meet(a1, a2),
                result: self.join(r1, r2),
            });
        }
        self.nodes[node].blue = Some(blue);
        node
    }

    // Preserve the source's alternating split and role-swapping merge. A
    // different stable sort can choose a different equal-length representative.
    fn sort_names(&self, values: VecDeque<Id>) -> VecDeque<Id> {
        if values.len() < 2 {
            return values;
        }
        let (mut one, mut two) = (VecDeque::new(), VecDeque::new());
        for node in values {
            std::mem::swap(&mut one, &mut two);
            two.push_front(node);
        }
        let (mut one, mut two) = (self.sort_names(one), self.sort_names(two));
        let mut result = VecDeque::new();
        while let Some(&first) = one.front() {
            let second = *two.front().unwrap();
            if self.nodes[second].name.len() < self.nodes[first].name.len() {
                result.push_back(two.pop_front().unwrap());
                std::mem::swap(&mut one, &mut two);
            } else {
                result.push_back(one.pop_front().unwrap());
            }
        }
        result.append(&mut two);
        result
    }
    fn classify(&mut self) -> Vec<VecDeque<Id>> {
        let mut classes: Vec<VecDeque<Id>> = Vec::new();
        for node in self.roots.clone() {
            if let Some(index) = classes
                .iter()
                .position(|class| self.equivalent(node, *class.front().unwrap()))
            {
                classes[index].push_front(node);
            } else {
                classes.push(VecDeque::from([node]));
            }
        }
        classes
            .into_iter()
            .map(|class| self.sort_names(class))
            .collect()
    }
    fn canonical(classes: &[VecDeque<Id>], node: Id) -> Id {
        *classes
            .iter()
            .find(|class| class.contains(&node))
            .expect("unclassified node")
            .front()
            .unwrap()
    }
    fn fix_table(table: &Table, classes: &[VecDeque<Id>]) -> Table {
        table
            .iter()
            .filter(|(node, _)| *node == Self::canonical(classes, *node))
            .map(|(node, line)| {
                let line = line
                    .iter()
                    .filter(|(column, _)| *column == Self::canonical(classes, *column))
                    .map(|&(column, value)| (column, Self::canonical(classes, value)))
                    .collect();
                (*node, line)
            })
            .collect()
    }
    fn reduce(&mut self) {
        let classes = self.classify();
        let roots: Vec<_> = classes
            .iter()
            .map(|class| *class.front().unwrap())
            .collect();
        for &id in &roots {
            if id == NONE || id == ANY {
                continue;
            }
            let node = &mut self.nodes[id];
            for color in [&mut node.green, &mut node.red] {
                for id in color {
                    *id = Self::canonical(&classes, *id);
                }
            }
            for edge in node.blue.as_mut().unwrap() {
                edge.argument = Self::canonical(&classes, edge.argument);
                edge.result = Self::canonical(&classes, edge.result);
            }
        }
        self.met = Self::fix_table(&self.met, &classes);
        self.joined = Self::fix_table(&self.joined, &classes);
        self.roots = roots;
    }
    fn lattice(&mut self) {
        loop {
            let roots = self.roots.clone();
            for &first in &roots {
                for &second in &roots {
                    self.meet(first, second);
                    self.join(first, second);
                }
            }
            self.reduce();
            if self.roots.len() == roots.len() {
                return;
            }
        }
    }
}

// The owned arena exposes cyclic identities and releases all nodes after a
// run. It retains removed noncanonical nodes until that release; Scheme's
// tracing collector may reclaim those nodes during later lattice passes.
fn test(names: &[NameInput]) -> Vec<Rc<str>> {
    let mut graph = Graph::new(names);
    graph.lattice();
    graph
        .roots
        .iter()
        .map(|&id| graph.nodes[id].name.clone())
        .collect()
}
struct Names<'a>(&'a [Rc<str>]);
impl Display for Names<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(")?;
        for (i, name) in self.0.iter().enumerate() {
            if i > 0 {
                write!(out, " ")?;
            }
            write!(out, "{name:?}")?;
        }
        write!(out, ")")
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let names: Vec<_> = values[1].list().iter().map(NameInput::parse).collect();
    let expected: Vec<Rc<str>> = values[2]
        .list()
        .iter()
        .map(|d| Rc::from(d.atom()))
        .collect();
    let (start, mut result) = (Instant::now(), Vec::new());
    for _ in 0..count {
        result = black_box(test(black_box(&names)));
    }
    assert_eq!(result, expected);
    report("conform", count, start, Names(&result));
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    fn names() -> Vec<NameInput> {
        ["a", "b", "c", "d"]
            .into_iter()
            .map(|s| NameInput::Symbol(Rc::from(s)))
            .collect()
    }
    #[test]
    fn recursive_blue_edges_and_temporary_assumptions() {
        let mut graph = Graph::new(&names());
        assert!(graph.conforms(2, 2));
        assert!(!graph.conforms(4, 2));
        assert!(graph.nodes.iter().all(|n| n.red.is_empty()));
        assert_eq!(graph.nodes[2].blue.as_ref().unwrap()[0].result, 3);
    }
    #[test]
    fn lattice_nodes_are_canonical_and_edges_keep_valid_identities() {
        let mut graph = Graph::new(&names());
        graph.lattice();
        for &id in &graph.roots {
            if id == NONE || id == ANY {
                continue;
            }
            for edge in graph.blue(id) {
                assert!(graph.roots.contains(&edge.argument));
                assert!(graph.roots.contains(&edge.result));
            }
        }
    }
}
