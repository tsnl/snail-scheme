use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Owned trees with mutation and unused payload ----

struct Node {
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
    i: i64,
    j: i64,
}
impl Node {
    fn empty() -> Box<Self> {
        Box::new(Self {
            left: None,
            right: None,
            i: 0,
            j: 0,
        })
    }
}

fn tree_size(depth: usize) -> usize {
    (1_usize << (depth + 1)) - 1
}

fn populate(depth: usize, node: &mut Node) {
    if depth == 0 {
        return;
    }
    node.left = Some(Node::empty());
    node.right = Some(Node::empty());
    populate(depth - 1, node.left.as_mut().unwrap());
    populate(depth - 1, node.right.as_mut().unwrap());
}

fn make_tree(depth: usize) -> Box<Node> {
    if depth == 0 {
        Node::empty()
    } else {
        Box::new(Node {
            left: Some(make_tree(depth - 1)),
            right: Some(make_tree(depth - 1)),
            i: 0,
            j: 0,
        })
    }
}

fn construction(stretch: usize, depth: usize) {
    let iterations = 2 * tree_size(stretch) / tree_size(depth);
    println!("Creating {iterations} trees of depth {depth}");
    println!("GCBench: Top down construction");
    for _ in 0..iterations {
        let mut tree = Node::empty();
        populate(depth, &mut tree);
        black_box(tree);
    }
    println!("GCBench: Bottom up construction");
    for _ in 0..iterations {
        black_box(make_tree(depth));
    }
}

fn run(stretch: usize) {
    println!("Garbage Collector Test");
    black_box(make_tree(stretch));
    let mut long_lived = Node::empty();
    populate(stretch - 2, &mut long_lived);
    let mut array = vec![0.0; 4 * tree_size(stretch - 2)];
    for i in 0..array.len() / 2 {
        array[i] = 1.0 / (i + 1) as f64;
    }
    for depth in (4..=stretch - 2).step_by(2) {
        construction(stretch, depth);
    }
    let n = 1000.min(array.len() / 2 - 1);
    assert_eq!(array[n], 1.0 / (n + 1) as f64);
    black_box((&long_lived, &array, long_lived.i, long_lived.j));
}

// ---- Benchmark driver ----

// Rust releases dead trees immediately; Scheme waits for tracing GC. The
// allocation count and surviving tree/array lifetimes are preserved, while
// this case deliberately exposes that language allocation-policy difference.
fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, depth) = (values[0].number(), values[1].number());
    let start = Instant::now();
    for _ in 0..count {
        run(black_box(depth));
    }
    report("gcbench", count, start, "ignored");
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    fn nodes(tree: &Node) -> usize {
        1 + tree.left.as_ref().map_or(0, |n| nodes(n)) + tree.right.as_ref().map_or(0, |n| nodes(n))
    }
    #[test]
    fn both_construction_orders_have_every_node() {
        let mut top_down = Node::empty();
        populate(5, &mut top_down);
        assert_eq!(nodes(&top_down), tree_size(5));
        assert_eq!(nodes(&make_tree(5)), tree_size(5));
    }
}
