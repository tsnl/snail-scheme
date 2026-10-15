use r7rs_wasm_reference::{input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Grammar configurations and their rule names ----

struct RuleName {
    symbol: Rc<str>,
    number: usize,
}
struct Tables {
    symbols: Vec<Rc<str>>,
    starters: Vec<Vec<usize>>,
    enders: Vec<Vec<usize>>,
    predictors: Vec<Vec<usize>>,
    steps: Vec<i64>,
    names: Vec<Option<Rc<RuleName>>>,
}

impl Tables {
    fn compile(grammar: &[(&str, Vec<Vec<&str>>)]) -> Self {
        let mut symbols: Vec<Rc<str>> = Vec::new();
        for (head, rules) in grammar {
            for symbol in std::iter::once(head).chain(rules.iter().flatten()) {
                if !symbols.iter().any(|s| s.as_ref() == *symbol) {
                    symbols.push(Rc::from(*symbol));
                }
            }
        }
        let configurations = symbols.len()
            + grammar
                .iter()
                .flat_map(|(_, r)| r)
                .map(|r| r.len() + 1)
                .sum::<usize>();
        let mut table = Self {
            starters: vec![Vec::new(); symbols.len()],
            enders: vec![Vec::new(); symbols.len()],
            predictors: vec![Vec::new(); symbols.len()],
            steps: vec![0; configurations],
            names: vec![None; configurations],
            symbols,
        };
        table.setup(grammar);
        table
    }
    fn index(&self, symbol: &str) -> usize {
        self.symbols
            .iter()
            .rposition(|s| s.as_ref() == symbol)
            .unwrap()
    }
    fn setup(&mut self, grammar: &[(&str, Vec<Vec<&str>>)]) {
        let terminals = self.symbols.len();
        for i in (0..terminals).rev() {
            self.steps[i] = i as i64 - terminals as i64;
            self.names[i] = Some(Rc::new(RuleName {
                symbol: self.symbols[i].clone(),
                number: 0,
            }));
            self.enders[i].push(i);
        }
        let mut conf = terminals;
        for (head, rules) in grammar {
            let head = self.index(head);
            for (rule_number, rule) in rules.iter().enumerate() {
                self.names[conf] = Some(Rc::new(RuleName {
                    symbol: self.symbols[head].clone(),
                    number: rule_number + 1,
                }));
                self.starters[head].insert(0, conf);
                for symbol in rule {
                    let nt = self.index(symbol);
                    self.steps[conf] = nt as i64;
                    self.predictors[nt].insert(0, conf);
                    conf += 1;
                }
                self.steps[conf] = head as i64 - terminals as i64;
                self.enders[head].insert(0, conf);
                conf += 1;
            }
        }
    }
}

// ---- Configuration sets with separate old and new origin chains ----

// Negative links encode the two list heads exactly as in the source:
// -3 selects old_head, -1 selects new_head. Some(-1) marks a present final
// origin; None denotes absence. Integer zero must therefore remain present.
struct Set {
    queued_next: i64,
    old_tail: i64,
    old_head: i64,
    new_tail: i64,
    new_head: i64,
    links: Vec<Option<i64>>,
}
struct State {
    position: usize,
    queued: i64,
    sets: Vec<Option<Set>>,
}
struct States {
    states: Vec<State>,
}

impl Set {
    fn new(position: usize) -> Self {
        Self {
            queued_next: -1,
            old_tail: -3,
            old_head: -1,
            new_tail: -1,
            new_head: -1,
            links: vec![None; position + 1],
        }
    }
    fn link(&mut self, from: i64, to: i64) {
        match from {
            -3 => self.old_head = to,
            -1 => self.new_head = to,
            i if i >= 0 => self.links[i as usize] = Some(to),
            _ => panic!("invalid set link"),
        }
    }
    fn next(&self, origin: usize) -> i64 {
        self.links[origin].expect("origin absent")
    }
    fn merge_new(&mut self) -> i64 {
        let head = self.new_head;
        self.link(self.old_tail, head);
        self.old_tail = self.new_tail;
        self.new_tail = -1;
        self.new_head = -1;
        head
    }
}
impl State {
    fn new(position: usize, configurations: usize) -> Self {
        Self {
            position,
            queued: -1,
            sets: (0..configurations).map(|_| None).collect(),
        }
    }
    fn adjoin(&mut self, conf: usize, origin: usize) {
        let set = self.sets[conf].get_or_insert_with(|| Set::new(self.position));
        if set.links[origin].is_some() {
            return;
        }
        let tail = set.new_tail;
        set.links[origin] = Some(-1);
        set.link(tail, origin as i64);
        set.new_tail = origin as i64;
        if tail < 0 {
            set.queued_next = self.queued;
            self.queued = conf as i64;
        }
    }
    fn pop(&mut self) -> Option<(usize, i64)> {
        if self.queued < 0 {
            return None;
        }
        let conf = self.queued as usize;
        let set = self.sets[conf].as_mut().unwrap();
        self.queued = set.queued_next;
        Some((conf, set.merge_new()))
    }
    fn contains(&self, conf: usize, origin: usize) -> bool {
        self.sets[conf]
            .as_ref()
            .is_some_and(|set| set.links[origin].is_some())
    }
}
impl States {
    fn new(tokens: usize, configurations: usize) -> Self {
        Self {
            states: (0..=tokens)
                .map(|i| State::new(i, configurations))
                .collect(),
        }
    }
    fn union(&mut self, target: usize, next: usize, source: usize, conf: usize) {
        let mut origin = self.states[source].sets[conf].as_ref().unwrap().old_head;
        while origin >= 0 {
            self.states[target].adjoin(next, origin as usize);
            origin = self.states[source].sets[conf]
                .as_ref()
                .unwrap()
                .next(origin as usize);
        }
    }
    fn predict(&mut self, tables: &Tables, position: usize, conf: usize, nt: usize) {
        for &starter in &tables.starters[nt] {
            self.states[position].adjoin(starter, position);
        }
        for &ender in &tables.enders[nt] {
            if self.states[position].contains(ender, position) {
                self.union(position, conf + 1, position, conf);
            }
        }
    }
    fn reduce(&mut self, tables: &Tables, position: usize, conf: usize, head: i64, nt: usize) {
        for &predictor in &tables.predictors[nt] {
            let mut origin = head;
            while origin >= 0 {
                let i = origin as usize;
                if self.states[i].sets[predictor].is_some() {
                    self.union(position, predictor + 1, i, predictor);
                }
                origin = self.states[position].sets[conf].as_ref().unwrap().next(i);
            }
        }
    }
    fn forward_at(&mut self, tables: &Tables, position: usize) {
        while let Some((conf, head)) = self.states[position].pop() {
            let step = tables.steps[conf];
            if step >= 0 {
                self.predict(tables, position, conf, step as usize);
            } else {
                self.reduce(
                    tables,
                    position,
                    conf,
                    head,
                    (step + tables.symbols.len() as i64) as usize,
                );
            }
        }
    }
    fn forward(tables: &Tables, tokens: &[Token]) -> Self {
        let mut states = Self::new(tokens.len(), tables.steps.len());
        for &starter in &tables.starters[0] {
            states.states[0].adjoin(starter, 0);
        }
        states.forward_at(tables, 0);
        for (i, token) in tokens.iter().enumerate() {
            for &nt in &token.classes {
                states.states[i + 1].adjoin(nt, i);
            }
            states.forward_at(tables, i + 1);
        }
        states
    }
    fn retain(&mut self, forward: &Self, position: usize, conf: usize, origin: usize) -> bool {
        if !forward.states[position].contains(conf, origin) {
            return false;
        }
        self.states[position].adjoin(conf, origin);
        true
    }
    fn produce(&mut self, forward: &Self, tables: &Tables, conf: usize, i: usize, j: usize) {
        if conf < tables.symbols.len() || tables.steps[conf - 1] < 0 {
            return;
        }
        let previous = conf - 1;
        for &ender in &tables.enders[tables.steps[previous] as usize] {
            if let Some(set) = &forward.states[j].sets[ender] {
                let mut origin = set.old_head;
                while origin >= 0 {
                    let k = origin as usize;
                    if k >= i && self.retain(forward, k, previous, i) {
                        self.retain(forward, j, ender, k);
                    }
                    origin = set.next(k);
                }
            }
        }
    }
    fn backward(tables: &Tables, tokens: &[Token], forward: &Self) -> Self {
        let mut states = Self::new(tokens.len(), tables.steps.len());
        for &ender in &tables.enders[0] {
            states.retain(forward, tokens.len(), ender, 0);
        }
        for j in (0..=tokens.len()).rev() {
            while let Some((conf, head)) = states.states[j].pop() {
                let mut origin = head;
                while origin >= 0 {
                    states.produce(forward, tables, conf, origin as usize, j);
                    origin = states.states[j].sets[conf]
                        .as_ref()
                        .unwrap()
                        .next(origin as usize);
                }
            }
        }
        states
    }
}

// ---- Materialized derivation trees and shared subtrees ----

struct Token {
    information: Rc<str>,
    classes: Vec<usize>,
}
#[derive(Clone)]
enum Item {
    Token(Rc<str>),
    Tree(Rc<Tree>),
}
struct Tree {
    name: Rc<RuleName>,
    items: Vec<Item>,
}
struct TreeCell {
    tree: Rc<Tree>,
    rest: Option<Box<TreeCell>>,
}
#[derive(Default)]
struct Trees {
    first: Option<Box<TreeCell>>,
}

impl Trees {
    fn prepend(&mut self, tree: Rc<Tree>) {
        self.first = Some(Box::new(TreeCell {
            tree,
            rest: self.first.take(),
        }));
    }
    fn length(&self) -> usize {
        let (mut rest, mut n) = (self.first.as_deref(), 0);
        while let Some(cell) = rest {
            n += 1;
            rest = cell.rest.as_deref();
        }
        n
    }
    // Source append copies the first outer list. Explicit reverse cursors
    // avoid millions of native return frames without reusing its cells.
    fn prepend_copy(&mut self, other: &Self) {
        let (mut cells, mut rest) = (Vec::new(), other.first.as_deref());
        while let Some(cell) = rest {
            cells.push(&cell.tree);
            rest = cell.rest.as_deref();
        }
        for tree in cells.into_iter().rev() {
            self.prepend(tree.clone());
        }
    }
}
impl Drop for Trees {
    fn drop(&mut self) {
        let mut rest = self.first.take();
        while let Some(mut cell) = rest {
            rest = cell.rest.take();
        }
    }
}

struct Parse {
    tables: Tables,
    tokens: Vec<Token>,
    states: States,
}
impl Parse {
    fn new(n: usize) -> Self {
        let input = vec![Rc::<str>::from("a"); n];
        let tables = Tables::compile(&[("s", vec![vec!["a"], vec!["s", "s"]])]);
        let tokens = input
            .into_iter()
            .map(|information| Token {
                classes: vec![tables.index(&information)],
                information,
            })
            .collect::<Vec<_>>();
        let forward = States::forward(&tables, &tokens);
        let states = States::backward(&tables, &tokens, &forward);
        Self {
            tables,
            tokens,
            states,
        }
    }
    // This recursion intentionally has no memoization: it retains the source's
    // repeated derivation construction, temporary lists and sharing.
    fn derivations(&self, conf: usize, i: usize, j: usize) -> Trees {
        let mut trees = Trees::default();
        if let Some(name) = &self.tables.names[conf] {
            let items = if conf < self.tables.symbols.len() {
                vec![Item::Token(self.tokens[i].information.clone())]
            } else {
                Vec::new()
            };
            trees.prepend(Rc::new(Tree {
                name: name.clone(),
                items,
            }));
            return trees;
        }
        let previous = conf - 1;
        for &ender in &self.tables.enders[self.tables.steps[previous] as usize] {
            if let Some(set) = &self.states.states[j].sets[ender] {
                let mut origin = set.old_head;
                while origin >= 0 {
                    let k = origin as usize;
                    if k >= i && self.states.states[k].contains(previous, i) {
                        let previous_trees = self.derivations(previous, i, k);
                        let ender_trees = self.derivations(ender, k, j);
                        Self::combine(&mut trees, &previous_trees, &ender_trees);
                    }
                    origin = set.next(k);
                }
            }
        }
        trees
    }
    fn combine(trees: &mut Trees, previous: &Trees, enders: &Trees) {
        let mut enders = enders.first.as_deref();
        while let Some(ender) = enders {
            let mut previous = previous.first.as_deref();
            while let Some(prior) = previous {
                let mut items = prior.tree.items.clone();
                items.push(Item::Tree(ender.tree.clone()));
                trees.prepend(Rc::new(Tree {
                    name: prior.tree.name.clone(),
                    items,
                }));
                previous = prior.rest.as_deref();
            }
            enders = ender.rest.as_deref();
        }
    }
    fn goal_trees(&self) -> Trees {
        let mut trees = Trees::default();
        for &ender in &self.tables.enders[0] {
            if self.states.states[self.tokens.len()].contains(ender, 0) {
                trees.prepend_copy(&self.derivations(ender, 0, self.tokens.len()));
            }
        }
        trees
    }
}

// ---- Untimed complete tree serialization ----

impl Display for Tree {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(({} {})", self.name.symbol, self.name.number)?;
        for item in &self.items {
            match item {
                Item::Token(s) => write!(out, " {s}")?,
                Item::Tree(tree) => write!(out, " {tree}")?,
            }
        }
        write!(out, ")")
    }
}
impl Display for Trees {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut rest = self.first.as_deref();
        write!(out, "(")?;
        while let Some(cell) = rest {
            write!(out, "{}", cell.tree)?;
            if cell.rest.is_some() {
                write!(out, " ")?;
            }
            rest = cell.rest.as_deref();
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
        let parse = Parse::new(black_box(n));
        let trees = black_box(parse.goal_trees());
        result = black_box(trees.length());
    }
    assert_eq!(result, values[2].number());
    report("earley", count, start, result);
    if std::env::args().any(|a| a == "--dump") {
        println!("Audit: {}", Parse::new(n).goal_trees());
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn configuration_tables_preserve_original_order() {
        let p = Parse::new(1);
        assert_eq!(p.tables.steps, vec![-2, -1, 1, -2, 0, 0, -2]);
        assert_eq!(p.tables.starters[0], vec![4, 2]);
        assert_eq!(p.tables.enders[0], vec![6, 3, 0]);
        assert_eq!(p.tables.predictors[0], vec![5, 4]);
    }
    #[test]
    fn materialized_small_forest_counts() {
        assert_eq!(
            (0..=6)
                .map(|n| Parse::new(n).goal_trees().length())
                .collect::<Vec<_>>(),
            vec![0, 1, 1, 2, 5, 14, 42]
        );
        assert_eq!(
            Parse::new(1).goal_trees().to_string(),
            "(((s 1) ((a 0) a)))"
        );
    }
    #[test]
    fn zero_origin_is_present_and_new_sets_queue_once() {
        let mut state = State::new(2, 7);
        state.adjoin(3, 0);
        state.adjoin(3, 1);
        assert!(state.contains(3, 0));
        assert_eq!(state.pop(), Some((3, 0)));
        assert_eq!(state.pop(), None);
        state.adjoin(3, 2);
        assert_eq!(state.pop(), Some((3, 2)));
    }
}
