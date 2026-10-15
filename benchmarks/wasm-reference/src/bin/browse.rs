use r7rs_wasm_reference::{Datum, input, read_all, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Shared pattern trees and persistent bindings ----

#[derive(Clone)]
enum Value {
    Symbol(Rc<str>),
    List(List),
}
type List = Option<Rc<Cell>>;
struct Cell {
    first: Value,
    rest: List,
}
enum Binding {
    One(Value),
    Many(List),
}
type Environment = Option<Rc<Entry>>;
struct Entry {
    name: Rc<str>,
    value: Binding,
    rest: Environment,
}

fn cons(first: Value, rest: List) -> List {
    Some(Rc::new(Cell { first, rest }))
}
fn parse(datum: &Datum) -> Value {
    match datum {
        Datum::Atom(name) => Value::Symbol(Rc::from(name.as_str())),
        Datum::List(values) => Value::List(
            values
                .iter()
                .rev()
                .fold(None, |rest, first| cons(parse(first), rest)),
        ),
        _ => panic!("expected pattern symbol or list"),
    }
}
fn list(value: &Value) -> &List {
    match value {
        Value::List(list) => list,
        _ => panic!("expected list"),
    }
}
fn same_atom(first: &Value, second: &Value) -> bool {
    match (first, second) {
        (Value::Symbol(a), Value::Symbol(b)) => a == b,
        (Value::List(None), Value::List(None)) => true,
        (Value::List(Some(a)), Value::List(Some(b))) => Rc::ptr_eq(a, b),
        _ => false,
    }
}
fn lookup<'a>(mut environment: &'a Environment, name: &str) -> Option<&'a Binding> {
    while let Some(entry) = environment {
        if entry.name.as_ref() == name {
            return Some(&entry.value);
        }
        environment = &entry.rest;
    }
    None
}
fn bind(environment: &Environment, name: Rc<str>, value: Binding) -> Environment {
    Some(Rc::new(Entry {
        name,
        value,
        rest: environment.clone(),
    }))
}
fn append(first: &List, second: &List) -> List {
    match first {
        None => second.clone(),
        Some(cell) => cons(cell.first.clone(), append(&cell.rest, second)),
    }
}

// ---- Original backtracking matcher ----

// The source deliberately returns the empty list when nonempty patterns meet
// empty data. Scheme treats that result as true; preserve that control flow.
fn match_pattern(pattern: &List, data: &List, environment: &Environment) -> bool {
    let Some(pattern) = pattern else {
        return data.is_none();
    };
    let Some(data) = data else {
        return true;
    };
    if matches!(&pattern.first, Value::Symbol(s) if s.as_ref() == "?")
        || same_atom(&pattern.first, &data.first)
    {
        return match_pattern(&pattern.rest, &data.rest, environment);
    }
    match &pattern.first {
        Value::Symbol(s) if s.as_ref() == "*" => {
            match_pattern(&pattern.rest, &Some(data.clone()), environment)
                || match_pattern(&pattern.rest, &data.rest, environment)
                || match_pattern(&Some(pattern.clone()), &data.rest, environment)
        }
        Value::Symbol(s) if s.starts_with('?') => match lookup(environment, s) {
            Some(Binding::One(value)) => match_pattern(
                &cons(value.clone(), pattern.rest.clone()),
                &Some(data.clone()),
                environment,
            ),
            None => match_pattern(
                &pattern.rest,
                &data.rest,
                &bind(environment, s.clone(), Binding::One(data.first.clone())),
            ),
            _ => panic!("single variable has sequence binding"),
        },
        Value::Symbol(s) if s.starts_with('*') => {
            match_sequence(s, &pattern.rest, &Some(data.clone()), environment)
        }
        Value::Symbol(_) => false,
        Value::List(Some(inner)) => match &data.first {
            Value::List(Some(other)) => {
                match_pattern(&Some(inner.clone()), &Some(other.clone()), environment)
                    && match_pattern(&pattern.rest, &data.rest, environment)
            }
            _ => false,
        },
        Value::List(None) => panic!("source symbol->string received a nonsymbol"),
    }
}

fn match_sequence(name: &Rc<str>, pattern: &List, data: &List, environment: &Environment) -> bool {
    if let Some(Binding::Many(values)) = lookup(environment, name) {
        return match_pattern(&append(values, pattern), data, environment);
    }
    let (mut prefix, mut rest) = (None, data);
    loop {
        if match_pattern(
            pattern,
            rest,
            &bind(environment, name.clone(), Binding::Many(prefix.clone())),
        ) {
            return true;
        }
        let Some(cell) = rest else {
            return false;
        };
        // Source append-to-tail! scans and mutates its fresh prefix. No prefix
        // escapes a failed match; copying it preserves bindings and linear
        // append work while disclosing additional Rust cell allocations.
        prefix = append(&prefix, &cons(cell.first.clone(), None));
        rest = &cell.rest;
    }
}

// ---- Linear property tables and original initialization ----

#[derive(PartialEq, Eq)]
enum Key {
    Number(Rc<str>),
    Pattern,
}
enum Property {
    False,
    Patterns(Vec<Value>),
}
struct Unit {
    name: Rc<str>,
    properties: Vec<(Key, Property)>,
}
struct Database {
    units: Vec<Unit>,
    names: Vec<Rc<str>>,
}

fn generate_symbol(next: &mut usize) -> Rc<str> {
    *next += 1;
    Rc::from(next.to_string())
}
fn put(units: &mut Vec<Unit>, name: &Rc<str>, key: Key, value: Property) {
    if !units.iter().any(|unit| Rc::ptr_eq(&unit.name, name)) {
        units.insert(
            0,
            Unit {
                name: name.clone(),
                properties: Vec::new(),
            },
        );
    }
    let unit = units
        .iter_mut()
        .find(|unit| Rc::ptr_eq(&unit.name, name))
        .unwrap();
    match unit.properties.iter_mut().find(|(old, _)| *old == key) {
        Some((_, slot)) => *slot = value,
        None => unit.properties.insert(0, (key, value)),
    }
}
fn randomize(mut names: Vec<Rc<str>>) -> Vec<Rc<str>> {
    let (mut random, mut result) = (21, Vec::new());
    while !names.is_empty() {
        random = random * 17 % 251;
        result.push(names.remove(random % names.len()));
    }
    result.reverse();
    result
}
fn initialize() -> Database {
    let source = read_all(
        "((a a a b b b b a a a a a b b a a a) (a a b b b b a a (a a) (b b)) (a a a b (b a) b a b a))",
    );
    let base: Vec<_> = source[0].list().iter().map(parse).collect();
    let patterns: Vec<_> = (0..4).rev().map(|i| base[i % base.len()].clone()).collect();
    let (mut units, mut names, mut next) = (Vec::new(), Vec::new(), 0);
    for step in 0..100 {
        let (name, i) = (generate_symbol(&mut next), 10 - step % 11);
        names.push(name.clone());
        for _ in 0..i {
            put(
                &mut units,
                &name,
                Key::Number(generate_symbol(&mut next)),
                Property::False,
            );
        }
        put(
            &mut units,
            &name,
            Key::Pattern,
            Property::Patterns(patterns.clone()),
        );
        for _ in 0..10 - i {
            put(
                &mut units,
                &name,
                Key::Number(generate_symbol(&mut next)),
                Property::False,
            );
        }
    }
    black_box(generate_symbol(&mut next)); // Original final do-loop step generates this unused symbol.
    names.reverse();
    Database {
        units,
        names: randomize(names),
    }
}
fn patterns<'a>(database: &'a Database, name: &Rc<str>) -> &'a [Value] {
    let unit = database
        .units
        .iter()
        .find(|unit| Rc::ptr_eq(&unit.name, name))
        .unwrap();
    match &unit
        .properties
        .iter()
        .find(|(key, _)| *key == Key::Pattern)
        .unwrap()
        .1
    {
        Property::Patterns(values) => values,
        Property::False => panic!("missing patterns"),
    }
}

// ---- Database investigation and two result maps ----

fn browse(database: &Database, pats: &[Value]) -> Vec<usize> {
    for name in &database.names {
        for pat in pats {
            for data in patterns(database, name) {
                black_box(match_pattern(list(pat), list(data), &None));
            }
        }
    }
    let strings: Vec<_> = database
        .names
        .iter()
        .map(|symbol| symbol.to_string())
        .collect();
    strings.iter().map(|text| text.parse().unwrap()).collect()
}
struct Numbers<'a>(&'a [usize]);
impl Display for Numbers<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(")?;
        for (i, n) in self.0.iter().enumerate() {
            if i > 0 {
                write!(out, " ")?;
            }
            write!(out, "{n}")?;
        }
        write!(out, ")")
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let pats: Vec<_> = values[1].list().iter().map(parse).collect();
    let expected: Vec<_> = values[2].list().iter().map(Datum::number).collect();
    let database = initialize();
    let (start, mut result) = (Instant::now(), Vec::new());
    for _ in 0..count {
        result = black_box(browse(&database, black_box(&pats)));
    }
    assert_eq!(result, expected);
    report("browse", count, start, Numbers(&result));
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    fn value(source: &str) -> Value {
        parse(&read_all(source)[0])
    }
    #[test]
    fn named_single_and_sequence_variables_keep_shared_values() {
        assert!(match_pattern(
            list(&value("(?a ?a)")),
            list(&value("(x x)")),
            &None
        ));
        assert!(!match_pattern(
            list(&value("(?a ?a)")),
            list(&value("(x y)")),
            &None
        ));
        assert!(match_pattern(
            list(&value("(*a b *a)")),
            list(&value("(x y b x y)")),
            &None
        ));
        assert!(match_pattern(list(&value("(x)")), &None, &None)); // Empty-list truthiness in source.
    }
    #[test]
    fn database_names_and_pattern_identity() {
        let database = initialize();
        assert_eq!(database.names.len(), 100);
        assert_eq!(database.names[0].as_ref(), "837");
        let p = patterns(&database, &database.names[0]);
        let (Value::List(Some(first)), Value::List(Some(last))) = (&p[0], &p[3]) else {
            panic!("missing shared pattern")
        };
        assert!(Rc::ptr_eq(first, last));
    }
}
