use r7rs_wasm_reference::{input, report};
use std::cmp::Ordering;
use std::collections::LinkedList;
use std::hint::black_box;
use std::io::{self, Write};
use std::rc::Rc;
use std::time::Instant;

// ---- Persistent edges and materialized graphs ----

type Edges = Option<Rc<Edge>>;
type Graph = Vec<Edges>;

struct Edge {
    vertex: usize,
    rest: Edges,
}

struct Search {
    root: usize,
    max_out: usize,
    connected: Vec<Vec<bool>>,
    edges: Graph,
    out_degrees: Vec<usize>,
    iotas: Vec<Rc<[usize]>>,
    permutation: Vec<usize>,
    graphs: LinkedList<Graph>,
}

impl Search {
    fn new(size: usize) -> Self {
        assert!(size > 0);
        Self {
            root: size - 1,
            max_out: 2,
            connected: vec![vec![false; size]; size],
            edges: vec![None; size],
            out_degrees: vec![0; size],
            iotas: (0..size)
                .map(|limit| Rc::from((0..limit).collect::<Vec<_>>()))
                .collect(),
            permutation: vec![0; size - 1],
            graphs: LinkedList::new(),
        }
    }

    // Every graph snapshot shares immutable outgoing-edge lists. Backtracking
    // replaces search roots without changing lists retained by emitted graphs.
    fn add_edge(&mut self, from: usize, to: usize) {
        self.connected[from][to] = true;
        self.edges[from] = Some(Rc::new(Edge {
            vertex: to,
            rest: self.edges[from].clone(),
        }));
    }

    fn remove_edge(&mut self, from: usize, to: usize) {
        self.connected[from][to] = false;
        let edge = self.edges[from].as_ref().expect("edge to remove");
        assert_eq!(edge.vertex, to);
        self.edges[from] = edge.rest.clone();
    }

    // ---- Minimal labelling through a depth-first permutation tree ----

    fn compare_next_vertex(&self, depth: usize, next: usize) -> Ordering {
        for previous in 0..depth {
            let image = self.permutation[previous];
            let forward = self.connected[next][image].cmp(&self.connected[depth][previous]);
            if forward != Ordering::Equal {
                return forward;
            }
            let backward = self.connected[image][next].cmp(&self.connected[previous][depth]);
            if backward != Ordering::Equal {
                return backward;
            }
        }
        Ordering::Equal
    }

    fn minimal(&mut self, size: usize, include_root: bool) -> bool {
        let universe = self.iotas[size].clone();
        self.visit_permutation(&universe, 0, include_root)
    }

    fn visit_permutation(&mut self, universe: &[usize], depth: usize, include_root: bool) -> bool {
        if universe.is_empty() {
            return !include_root
                || self.compare_next_vertex(self.root, self.root) != Ordering::Less;
        }
        for (position, &next) in universe.iter().enumerate() {
            match self.compare_next_vertex(depth, next) {
                Ordering::Less => return false,
                Ordering::Greater => {}
                Ordering::Equal => {
                    self.permutation[depth] = next;
                    let rest: Vec<_> = universe
                        .iter()
                        .enumerate()
                        .filter_map(|(i, &vertex)| (i != position).then_some(vertex))
                        .collect();
                    if !self.visit_permutation(&rest, depth + 1, include_root) {
                        return false;
                    }
                }
            }
        }
        true
    }

    // ---- Non-root edge enumeration ----

    fn visit_vertex(&mut self, vertex: usize) {
        if !self.minimal(vertex, false) {
            return;
        }
        if vertex == self.root {
            let reach = self.reachability();
            self.visit_root(0, 0, &None, &reach);
        } else {
            self.visit_edge_pair(vertex, 0, 0);
        }
    }

    // Keep the four atomic edge cases together: neither edge, incoming only,
    // both edges, outgoing only. This is the original traversal order.
    fn visit_edge_pair(&mut self, vertex: usize, previous: usize, outs: usize) {
        if previous == vertex {
            self.out_degrees[vertex] = outs;
            self.visit_vertex(vertex + 1);
            return;
        }
        self.visit_edge_pair(vertex, previous + 1, outs);
        if self.out_degrees[previous] < self.max_out {
            self.add_edge(previous, vertex);
            self.out_degrees[previous] += 1;
            self.visit_edge_pair(vertex, previous + 1, outs);
            self.visit_outgoing(vertex, previous, outs);
            self.out_degrees[previous] -= 1;
            self.remove_edge(previous, vertex);
        }
        self.visit_outgoing(vertex, previous, outs);
    }

    fn visit_outgoing(&mut self, vertex: usize, previous: usize, outs: usize) {
        if outs < self.max_out {
            self.add_edge(vertex, previous);
            self.visit_edge_pair(vertex, previous + 1, outs + 1);
            self.remove_edge(vertex, previous);
        }
    }

    // ---- Root reachability and root edges ----

    fn reachability(&self) -> Vec<Vec<bool>> {
        let mut reachable = vec![vec![false; self.root]; self.root];
        for (vertex, row) in reachable.iter_mut().enumerate() {
            row[vertex] = true;
            let mut edges = self.edges[vertex].as_deref();
            while let Some(edge) = edges {
                row[edge.vertex] = true;
                edges = edge.rest.as_deref();
            }
        }
        close_reachability(&mut reachable);
        reachable
    }

    fn visit_root(&mut self, vertex: usize, outs: usize, selected: &Edges, reach: &[Vec<bool>]) {
        if vertex < self.root && outs < self.max_out {
            self.connected[self.root][vertex] = true;
            let included = Some(Rc::new(Edge {
                vertex,
                rest: selected.clone(),
            }));
            self.visit_root(vertex + 1, outs + 1, &included, reach);
            self.connected[self.root][vertex] = false;
            self.visit_root(vertex + 1, outs, selected, reach);
        } else if root_reaches_all(self.root, selected, reach) && self.minimal(self.root, true) {
            self.edges[self.root] = selected.clone();
            self.graphs.push_front(self.edges.clone());
        }
    }
}

// Preserve the original Warshall loops and in-place row updates. Iterating a
// borrowed row would prevent the same row from being read as the middle row.
#[allow(clippy::needless_range_loop)]
fn close_reachability(reachable: &mut [Vec<bool>]) {
    for middle in 0..reachable.len() {
        for from in 0..reachable.len() {
            if reachable[from][middle] {
                for to in 0..reachable.len() {
                    if reachable[middle][to] {
                        reachable[from][to] = true;
                    }
                }
            }
        }
    }
}

fn root_reaches_all(size: usize, selected: &Edges, reach: &[Vec<bool>]) -> bool {
    (0..size).all(|vertex| {
        let mut edges = selected.as_deref();
        while let Some(edge) = edges {
            if reach[edge.vertex][vertex] {
                return true;
            }
            edges = edge.rest.as_deref();
        }
        false
    })
}

// ---- Materialization and exact functional audit ----

fn generate(size: usize) -> LinkedList<Graph> {
    let mut search = Search::new(size);
    search.visit_vertex(0);
    search.graphs
}

fn count_graphs(graphs: &LinkedList<Graph>) -> usize {
    // Scheme traverses the materialized outer list with length. Keep that
    // traversal even though LinkedList also stores its length as metadata.
    graphs.iter().fold(0, |count, graph| {
        black_box(graph);
        count + 1
    })
}

fn write_edges(output: &mut impl Write, edges: &Edges) -> io::Result<()> {
    write!(output, "(")?;
    let mut rest = edges.as_deref();
    let mut separator = "";
    while let Some(edge) = rest {
        write!(output, "{separator}{}", edge.vertex)?;
        separator = " ";
        rest = edge.rest.as_deref();
    }
    write!(output, ")")
}

fn write_graphs(graphs: &LinkedList<Graph>) -> io::Result<()> {
    let mut output = io::BufWriter::new(io::stdout().lock());
    write!(output, "(")?;
    for graph in graphs {
        write!(output, "#(")?;
        for edges in graph {
            write_edges(&mut output, edges)?;
            write!(output, " ")?;
        }
        write!(output, ")")?;
    }
    writeln!(output, ")")
}

// ---- Benchmark driver ----

fn main() -> io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    if std::env::args().any(|argument| argument == "--dump") {
        let graphs = generate(values[1].number());
        assert_eq!(count_graphs(&graphs), values[2].number());
        return write_graphs(&graphs);
    }
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(count_graphs(&generate(black_box(values[1].number()))));
    }
    assert_eq!(result, values[2].number());
    report("graphs", count, start, result);
    Ok(())
}
