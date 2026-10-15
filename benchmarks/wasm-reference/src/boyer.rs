use crate::{Datum, input, read_all, report};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Quoted constants and interned source symbols ----

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Atom {
    Symbol(usize),
    Number(i64),
    Empty,
}
#[derive(Clone)]
enum Quoted {
    Atom(Atom),
    Pair(Rc<QuotedPair>),
    Empty,
}
struct QuotedPair {
    first: Quoted,
    rest: Quoted,
}
fn quote_pair(first: Quoted, rest: Quoted) -> Quoted {
    Quoted::Pair(Rc::new(QuotedPair { first, rest }))
}
impl Quoted {
    fn parse(datum: &Datum, symbols: &mut Vec<String>) -> Self {
        match datum {
            Datum::Atom(s) => Self::Atom(parse_atom(s, symbols)),
            Datum::List(items) => items.iter().rev().fold(Self::Empty, |rest, item| {
                quote_pair(Self::parse(item, symbols), rest)
            }),
            _ => panic!("invalid quoted Boyer term"),
        }
    }
    fn pair(&self) -> &QuotedPair {
        match self {
            Self::Pair(pair) => pair,
            _ => panic!("expected a quoted pair"),
        }
    }
    fn atom(&self) -> Atom {
        match self {
            Self::Atom(atom) => *atom,
            _ => panic!("expected a quoted atom"),
        }
    }
}
fn parse_atom(text: &str, symbols: &mut Vec<String>) -> Atom {
    if let Ok(n) = text.parse() {
        return Atom::Number(n);
    }
    let id = symbols.iter().position(|s| s == text).unwrap_or_else(|| {
        symbols.push(text.to_owned());
        symbols.len() - 1
    });
    Atom::Symbol(id)
}
struct Constants {
    alist: Quoted,
    term: Quoted,
    rules: Quoted,
    if_symbol: Atom,
    or_symbol: Atom,
    false_term: Quoted,
    true_term: Quoted,
}
impl Constants {
    fn new() -> Self {
        let data = read_all(include_str!("boyer-data.scm"));
        let data = data[0].list();
        let mut symbols = Vec::new();
        Self {
            alist: Quoted::parse(&data[0], &mut symbols),
            term: Quoted::parse(&data[1], &mut symbols),
            rules: Quoted::parse(&data[2], &mut symbols),
            if_symbol: parse_atom("if", &mut symbols),
            or_symbol: parse_atom("or", &mut symbols),
            false_term: quote_pair(Quoted::Atom(parse_atom("f", &mut symbols)), Quoted::Empty),
            true_term: quote_pair(Quoted::Atom(parse_atom("t", &mut symbols)), Quoted::Empty),
        }
    }
    fn problem(&self, n: usize) -> Quoted {
        let mut term = self.term.clone();
        for _ in 0..n {
            term = quote_pair(
                Quoted::Atom(self.or_symbol),
                quote_pair(term, quote_pair(self.false_term.clone(), Quoted::Empty)),
            );
        }
        term
    }
}

// ---- Translated terms, actual argument cells and constructor identity ----

#[derive(Clone)]
enum Term {
    Atom(Atom),
    Call(Rc<Call>),
}
struct Call {
    constructor: usize,
    arguments: Arguments,
}
type Arguments = Option<Rc<Argument>>;
struct Argument {
    first: Term,
    rest: Arguments,
}
fn call(constructor: usize, arguments: Arguments) -> Term {
    Term::Call(Rc::new(Call {
        constructor,
        arguments,
    }))
}
fn argument(first: Term, rest: Arguments) -> Arguments {
    Some(Rc::new(Argument { first, rest }))
}
fn same_arguments(first: &Arguments, second: &Arguments) -> bool {
    match (first, second) {
        (None, None) => true,
        (Some(a), Some(b)) => Rc::ptr_eq(a, b),
        _ => false,
    }
}
fn same_term(first: &Term, second: &Term) -> bool {
    match (first, second) {
        (Term::Call(a), Term::Call(b)) => Rc::ptr_eq(a, b),
        (Term::Atom(a), Term::Atom(b)) => a == b,
        _ => false,
    }
}
fn term_equal(first: &Term, second: &Term) -> bool {
    match (first, second) {
        (Term::Call(a), Term::Call(b)) => {
            a.constructor == b.constructor && arguments_equal(&a.arguments, &b.arguments)
        }
        (Term::Atom(a), Term::Atom(b)) => a == b,
        _ => false,
    }
}
fn arguments_equal(mut first: &Arguments, mut second: &Arguments) -> bool {
    while let Some(a) = first {
        let Some(b) = second else { return false };
        if !term_equal(&a.first, &b.first) {
            return false;
        }
        (first, second) = (&a.rest, &b.rest);
    }
    second.is_none()
}
fn term_member(term: &Term, mut list: &Arguments) -> bool {
    while let Some(first) = list {
        if term_equal(term, &first.first) {
            return true;
        }
        list = &first.rest;
    }
    false
}
impl Term {
    fn value(&self, index: usize) -> &Term {
        let Self::Call(call) = self else {
            panic!("expected a call")
        };
        let mut list = &call.arguments;
        for _ in 0..index {
            list = &list.as_ref().unwrap().rest;
        }
        &list.as_ref().unwrap().first
    }
}

// ---- Linear symbol records and separately allocated substitution entries ----

type Lemmas = Option<Rc<Lemma>>;
struct Lemma {
    term: Term,
    rest: Lemmas,
}
struct SymbolRecord {
    symbol: Atom,
    lemmas: Lemmas,
}
type Substitution = Option<Rc<Binding>>;
struct Binding {
    entry: Rc<Entry>,
    rest: Substitution,
}
struct Entry {
    variable: Atom,
    value: Term,
}
fn bind(variable: Atom, value: Term, rest: Substitution) -> Substitution {
    Some(Rc::new(Binding {
        entry: Rc::new(Entry { variable, value }),
        rest,
    }))
}
fn lookup(variable: Atom, mut bindings: &Substitution) -> Option<&Term> {
    while let Some(binding) = bindings {
        if binding.entry.variable == variable {
            return Some(&binding.entry.value);
        }
        bindings = &binding.rest;
    }
    None
}
fn substitute(term: &Term, bindings: &Substitution) -> Term {
    match term {
        Term::Atom(a) => lookup(*a, bindings).unwrap_or(term).clone(),
        Term::Call(c) => call(c.constructor, substitute_arguments(&c.arguments, bindings)),
    }
}
fn substitute_arguments(list: &Arguments, bindings: &Substitution) -> Arguments {
    list.as_ref().map(|a| {
        Rc::new(Argument {
            first: substitute(&a.first, bindings),
            rest: substitute_arguments(&a.rest, bindings),
        })
    })
}
struct Prover {
    // Constructor IDs refer back into this owned table, so lemma terms can
    // form the source's logical cycles without leaking an Rc ownership cycle.
    records: Vec<SymbolRecord>,
    bindings: Substitution,
    if_constructor: usize,
    false_term: Term,
    true_term: Term,
    rewrites: usize,
    sharing: bool,
}
impl Prover {
    fn symbol_record(&mut self, symbol: Atom) -> usize {
        if let Some(id) = self.records.iter().rposition(|r| r.symbol == symbol) {
            return id;
        }
        self.records.push(SymbolRecord {
            symbol,
            lemmas: None,
        });
        self.records.len() - 1
    }
    fn translate(&mut self, term: &Quoted) -> Term {
        match term {
            Quoted::Atom(atom) => Term::Atom(*atom),
            Quoted::Empty => Term::Atom(Atom::Empty),
            Quoted::Pair(pair) => {
                let constructor = self.symbol_record(pair.first.atom());
                call(constructor, self.translate_arguments(&pair.rest))
            }
        }
    }
    fn translate_arguments(&mut self, list: &Quoted) -> Arguments {
        match list {
            Quoted::Empty => None,
            Quoted::Pair(a) => {
                let first = self.translate(&a.first);
                argument(first, self.translate_arguments(&a.rest))
            }
            _ => panic!("expected a proper argument list"),
        }
    }
    fn translate_bindings(&mut self, list: &Quoted) -> Substitution {
        match list {
            Quoted::Empty => None,
            Quoted::Pair(cell) => {
                let entry = cell.first.pair();
                let value = self.translate(&entry.rest);
                bind(
                    entry.first.atom(),
                    value,
                    self.translate_bindings(&cell.rest),
                )
            }
            _ => panic!("expected a proper binding list"),
        }
    }
    fn setup(constants: &Constants, sharing: bool) -> Self {
        let mut prover = Self {
            records: Vec::new(),
            bindings: None,
            if_constructor: 0,
            false_term: Term::Atom(Atom::Empty),
            true_term: Term::Atom(Atom::Empty),
            rewrites: 0,
            sharing,
        };
        prover.if_constructor = prover.symbol_record(constants.if_symbol);
        prover.false_term = prover.translate(&constants.false_term);
        prover.true_term = prover.translate(&constants.true_term);
        prover.add_lemmas(&constants.rules);
        prover
    }
    fn add_lemmas(&mut self, mut rules: &Quoted) {
        while let Quoted::Pair(rule) = rules {
            let symbol = rule.first.pair().rest.pair().first.pair().first.atom();
            let term = self.translate(&rule.first);
            let get = self.symbol_record(symbol);
            let lemmas = Some(Rc::new(Lemma {
                term,
                rest: self.records[get].lemmas.clone(),
            }));
            let put = self.symbol_record(symbol);
            self.records[put].lemmas = lemmas;
            rules = &rule.rest;
        }
    }

    // ---- Directional unification and source-order lemma selection ----

    fn unify(&mut self, value: &Term, pattern: &Term) -> bool {
        match pattern {
            Term::Atom(atom) => self.unify_atom(value, *atom),
            Term::Call(pattern) => match value {
                Term::Call(value) if value.constructor == pattern.constructor => {
                    self.unify_arguments(&value.arguments, &pattern.arguments)
                }
                _ => false,
            },
        }
    }
    fn unify_atom(&mut self, value: &Term, atom: Atom) -> bool {
        if let Some(bound) = lookup(atom, &self.bindings) {
            return term_equal(value, bound);
        }
        if matches!(atom, Atom::Number(_)) {
            return matches!(value, Term::Atom(a) if *a == atom);
        }
        self.bindings = bind(atom, value.clone(), self.bindings.take());
        true
    }
    fn unify_arguments(&mut self, mut values: &Arguments, mut patterns: &Arguments) -> bool {
        while let Some(value) = values {
            let Some(pattern) = patterns else {
                return false;
            };
            if !self.unify(&value.first, &pattern.first) {
                return false;
            }
            (values, patterns) = (&value.rest, &pattern.rest);
        }
        patterns.is_none()
    }
    fn replacement(&mut self, term: &Term) -> Option<Term> {
        let Term::Call(call) = term else { return None };
        let mut lemmas = self.records[call.constructor].lemmas.clone();
        while let Some(lemma) = lemmas {
            self.bindings = None;
            if self.unify(term, lemma.term.value(0)) {
                return Some(substitute(lemma.term.value(1), &self.bindings));
            }
            lemmas = lemma.rest.clone();
        }
        None
    }

    // ---- Full rewrite recurrence and sharing-cons reuse ----

    fn rewrite(&mut self, mut term: Term) -> Term {
        loop {
            self.rewrites += 1;
            let Term::Call(original) = term else {
                return term;
            };
            let arguments = self.rewrite_arguments(&original.arguments);
            let result = if self.sharing && same_arguments(&arguments, &original.arguments) {
                Term::Call(original)
            } else {
                call(original.constructor, arguments)
            };
            match self.replacement(&result) {
                Some(next) => term = next,
                None => return result,
            }
        }
    }
    fn rewrite_arguments(&mut self, list: &Arguments) -> Arguments {
        let Some(original) = list else { return None };
        let first = self.rewrite(original.first.clone());
        let rest = self.rewrite_arguments(&original.rest);
        if self.sharing
            && same_term(&first, &original.first)
            && same_arguments(&rest, &original.rest)
        {
            return list.clone();
        }
        argument(first, rest)
    }

    // ---- Tautology testing with persistent true/false assumption lists ----

    fn truep(&self, term: &Term, list: &Arguments) -> bool {
        term_equal(term, &self.true_term) || term_member(term, list)
    }
    fn falsep(&self, term: &Term, list: &Arguments) -> bool {
        term_equal(term, &self.false_term) || term_member(term, list)
    }
    fn tautology(&self, mut term: Term, true_list: Arguments, mut false_list: Arguments) -> bool {
        loop {
            if self.truep(&term, &true_list) {
                return true;
            }
            if self.falsep(&term, &false_list) {
                return false;
            }
            let Term::Call(c) = &term else { return false };
            if c.constructor != self.if_constructor {
                return false;
            }
            let condition = term.value(0).clone();
            let yes = term.value(1).clone();
            let no = term.value(2).clone();
            if self.truep(&condition, &true_list) {
                term = yes;
            } else if self.falsep(&condition, &false_list) {
                term = no;
            } else {
                if !self.tautology(
                    yes,
                    argument(condition.clone(), true_list.clone()),
                    false_list.clone(),
                ) {
                    return false;
                }
                term = no;
                false_list = argument(condition, false_list);
            }
        }
    }
    fn test(&mut self, constants: &Constants, n: usize) -> Option<usize> {
        let bindings = self.translate_bindings(&constants.alist);
        let term = self.translate(&constants.problem(n));
        let term = substitute(&term, &bindings);
        let result = self.rewrite(term);
        self.tautology(result, None, None).then_some(self.rewrites)
    }
}

// ---- Separate workload executables with common prover machinery ----

pub fn run(name: &str, sharing: bool) -> std::io::Result<()> {
    let values = input()?;
    let (count, n, expected) = (values[0].number(), values[1].number(), values[2].number());
    let constants = Constants::new();
    let (start, mut result) = (Instant::now(), None);
    for _ in 0..count {
        let mut prover = Prover::setup(&constants, sharing);
        result = black_box(prover.test(&constants, black_box(n)));
    }
    assert_eq!(result, Some(expected));
    report(name, count, start, result.unwrap());
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_original_small_rewrite_counts_in_both_modes() {
        let constants = Constants::new();
        for sharing in [false, true] {
            let mut prover = Prover::setup(&constants, sharing);
            assert_eq!(prover.test(&constants, 0), Some(95024));
        }
    }
    #[test]
    fn sharing_cons_reuses_only_unchanged_identity() {
        let constants = Constants::new();
        for sharing in [false, true] {
            let mut prover = Prover::setup(&constants, sharing);
            let term = call(usize::MAX, argument(Term::Atom(Atom::Symbol(999)), None));
            // This constructor deliberately has no rewrite rules.
            prover.records.push(SymbolRecord {
                symbol: Atom::Symbol(999),
                lemmas: None,
            });
            let Term::Call(original) = term else {
                unreachable!()
            };
            let term = Term::Call(Rc::new(Call {
                constructor: prover.records.len() - 1,
                arguments: original.arguments.clone(),
            }));
            let result = prover.rewrite(term.clone());
            assert_eq!(same_term(&term, &result), sharing);
            assert!(term_equal(&term, &result));
            let substituted = substitute(&term, &None);
            assert!(!same_term(&term, &substituted));
            assert!(term_equal(&term, &substituted));
        }
    }
    #[test]
    fn repeated_variable_and_numeric_pattern_constraints() {
        let constants = Constants::new();
        let mut prover = Prover::setup(&constants, false);
        let variable = Atom::Symbol(999);
        assert!(prover.unify_atom(&Term::Atom(Atom::Number(7)), variable));
        assert!(!prover.unify_atom(&Term::Atom(Atom::Number(8)), variable));
        assert!(prover.unify_atom(&Term::Atom(Atom::Number(7)), Atom::Number(7)));
        assert!(!prover.unify_atom(&Term::Atom(Atom::Symbol(7)), Atom::Number(7)));
    }
}
