// The benchmark and intermediate-diagnostic executables share these source
// records and passes; each build uses a different subset. Retained source/debug
// fields and explicit unsupported future tags are part of the source model.
#![allow(dead_code)]
// Nested decisions preserve the source pass's visible control-flow order.
#![allow(clippy::collapsible_if)]

use r7rs_wasm_reference::{Datum, input, report};
use std::cell::RefCell;
use std::rc::Rc;

#[path = "compiler_gvm.rs"]
mod gvm;

// ---- Persistent ordered identity sets ----

// Every cell is separately allocated. Union copies the first prefix and shares
// its second suffix, matching the source's list-based sets and their order.
#[derive(Clone, Default)]
struct Ids(Option<Rc<IdCell>>);
struct IdCell {
    id: usize,
    next: Ids,
}
impl Ids {
    fn cons(id: usize, next: Ids) -> Self {
        Self(Some(Rc::new(IdCell { id, next })))
    }
    fn from_slice(ids: &[usize]) -> Self {
        ids.iter()
            .rev()
            .fold(Self::default(), |next, &id| Self::cons(id, next))
    }
    fn values(&self) -> Vec<usize> {
        let mut result = Vec::new();
        let mut cursor = self;
        while let Some(cell) = &cursor.0 {
            result.push(cell.id);
            cursor = &cell.next;
        }
        result
    }
    fn empty(&self) -> bool {
        self.0.is_none()
    }
    fn has(&self, id: usize) -> bool {
        match &self.0 {
            None => false,
            Some(cell) => cell.id == id || cell.next.has(id),
        }
    }
    fn adjoin(&self, id: usize) -> Self {
        if self.has(id) {
            self.clone()
        } else {
            Self::cons(id, self.clone())
        }
    }
    fn remove(&self, id: usize) -> Self {
        match &self.0 {
            None => Self::default(),
            Some(cell) if cell.id == id => cell.next.clone(),
            Some(cell) => Self::cons(cell.id, cell.next.remove(id)),
        }
    }
    fn union(&self, second: &Self) -> Self {
        match &self.0 {
            None => second.clone(),
            Some(cell) if second.has(cell.id) => cell.next.union(second),
            Some(cell) => Self::cons(cell.id, cell.next.union(second)),
        }
    }
    fn difference(&self, second: &Self) -> Self {
        match &self.0 {
            None => Self::default(),
            Some(cell) if second.has(cell.id) => cell.next.difference(second),
            Some(cell) => Self::cons(cell.id, cell.next.difference(second)),
        }
    }
    fn intersection(&self, second: &Self) -> Self {
        match &self.0 {
            None => Self::default(),
            Some(cell) if second.has(cell.id) => {
                Self::cons(cell.id, cell.next.intersection(second))
            }
            Some(cell) => cell.next.intersection(second),
        }
    }
    fn equal_set(&self, second: &Self) -> bool {
        match &self.0 {
            None => second.empty(),
            Some(cell) => second.has(cell.id) && cell.next.equal_set(&second.remove(cell.id)),
        }
    }
    fn append(&self, second: &Self) -> Self {
        match &self.0 {
            None => second.clone(),
            Some(cell) => Self::cons(cell.id, cell.next.append(second)),
        }
    }
}

// ---- Located syntax and lexical environments ----

#[derive(Clone)]
enum SourceCode {
    Value(Datum),
    List(Ids, Option<usize>),
    Vector(Vec<usize>),
}
struct Location<'a> {
    original: Option<&'a Datum>,
    parent: Option<usize>,
}
struct Source<'a> {
    code: SourceCode,
    location: Rc<Location<'a>>,
}
#[derive(Clone)]
struct Declaration {
    kind: String,
    value: Datum,
    names: Vec<String>,
    next: Option<Rc<Declaration>>,
}
struct Environment {
    // Declaring a new environment shares this mutable variable-list root.
    vars: Rc<RefCell<Ids>>,
    declarations: Option<Rc<Declaration>>,
    parent: Option<usize>,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Binding {
    Global,
    Temporary,
    Procedure(usize),
}
struct Variable {
    name: String,
    binding: Binding,
    references: Ids,
    assignments: Ids,
    source: usize,
}

// ---- Parse nodes and their identity invariants ----

#[derive(Clone)]
struct Procedure {
    name: Option<String>,
    minimum: usize,
    rest: bool,
    parameters: Ids,
}
#[derive(Clone)]
enum NodeKind {
    Constant(Rc<Datum>),
    Reference(usize),
    Set(usize),
    Define(usize),
    Test,
    Conjunction,
    Disjunction,
    Procedure(Procedure),
    Call,
    Future,
}
struct Node {
    kind: NodeKind,
    parent: Option<usize>,
    children: Ids,
    free: Option<Ids>,
    environment: usize,
    source: usize,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Use {
    Value,
    Predicate,
    Discard,
}

// Separate boxes retain the source's record allocations and stable identities.
// The arena owns logical parent/reference cycles until a whole compilation ends.
#[allow(clippy::vec_box)]
struct Compiler<'a> {
    sources: Vec<Box<Source<'a>>>,
    environments: Vec<Box<Environment>>,
    variables: Vec<Box<Variable>>,
    nodes: Vec<Box<Node>>,
    global: usize,
}
fn atom(text: &str) -> Datum {
    Datum::Atom(text.to_owned())
}
fn undefined() -> Datum {
    atom("#[undefined]")
}
fn symbol(value: &Datum) -> Option<&str> {
    match value {
        Datum::Atom(text) if text != "#t" && text != "#f" && text.parse::<f64>().is_err() => {
            Some(text)
        }
        _ => None,
    }
}
impl<'a> Compiler<'a> {
    fn new() -> Self {
        Self {
            sources: vec![],
            environments: vec![],
            variables: vec![],
            nodes: vec![],
            global: 0,
        }
    }
    fn source(&mut self, value: &'a Datum) -> usize {
        let code = match value {
            Datum::List(list) => SourceCode::List(self.source_list(list), None),
            Datum::Dotted(list, tail) => {
                let list = self.source_list(list);
                let tail = self.source(tail);
                SourceCode::List(list, Some(tail))
            }
            Datum::Vector(values) => {
                let mut children = vec![0; values.len()];
                for i in (0..values.len()).rev() {
                    children[i] = self.source(&values[i]);
                }
                SourceCode::Vector(children)
            }
            Datum::Atom(text) if symbol(value).is_some() => {
                SourceCode::Value(atom(&text.to_lowercase()))
            }
            _ => SourceCode::Value(value.clone()),
        };
        let id = self.sources.len();
        self.sources.push(Box::new(Source {
            code,
            location: Rc::new(Location {
                original: Some(value),
                parent: None,
            }),
        }));
        id
    }
    fn source_list(&mut self, values: &'a [Datum]) -> Ids {
        if values.is_empty() {
            return Ids::default();
        }
        let first = self.source(&values[0]);
        let rest = self.source_list(&values[1..]);
        Ids::cons(first, rest)
    }
    fn generated_source(&mut self, origin: usize, code: SourceCode) -> usize {
        let id = self.sources.len();
        self.sources.push(Box::new(Source {
            code,
            location: self.sources[origin].location.clone(),
        }));
        id
    }
    fn source_expression(&self, source: usize) -> Datum {
        match &self.sources[source].code {
            SourceCode::Value(value) => value.clone(),
            SourceCode::List(ids, tail) => {
                let values = ids
                    .values()
                    .iter()
                    .map(|&id| self.source_expression(id))
                    .collect();
                match tail {
                    None => Datum::List(values),
                    Some(id) => Datum::Dotted(values, Box::new(self.source_expression(*id))),
                }
            }
            SourceCode::Vector(ids) => {
                Datum::Vector(ids.iter().map(|&id| self.source_expression(id)).collect())
            }
        }
    }
    fn source_items(&self, id: usize) -> Vec<usize> {
        match &self.sources[id].code {
            SourceCode::List(ids, None) => ids.values(),
            _ => panic!("proper list expected"),
        }
    }
    fn source_symbol(&self, id: usize) -> Option<&str> {
        match &self.sources[id].code {
            SourceCode::Value(value) => symbol(value),
            _ => None,
        }
    }
    fn form(&self, id: usize, name: &str) -> bool {
        match &self.sources[id].code {
            SourceCode::List(ids, _) => ids
                .0
                .as_ref()
                .is_some_and(|cell| self.source_symbol(cell.id) == Some(name)),
            _ => false,
        }
    }
    fn frame(&mut self, parent: Option<usize>, vars: Ids) -> usize {
        let id = self.environments.len();
        self.environments.push(Box::new(Environment {
            vars: Rc::new(RefCell::new(vars)),
            declarations: None,
            parent,
        }));
        id
    }
    fn declare(&mut self, env: usize, mut declaration: Declaration) -> usize {
        declaration.next = self.environments[env].declarations.clone();
        let id = self.environments.len();
        self.environments.push(Box::new(Environment {
            vars: self.environments[env].vars.clone(),
            declarations: Some(Rc::new(declaration)),
            parent: self.environments[env].parent,
        }));
        id
    }
    fn declaration(&self, mut env: usize, kind: &str, name: Option<&str>, default: Datum) -> Datum {
        loop {
            let mut declarations = self.environments[env].declarations.as_ref();
            while let Some(declaration) = declarations {
                if declaration.kind == kind
                    && (declaration.names.is_empty()
                        || name.is_some_and(|n| declaration.names.iter().any(|x| x == n)))
                {
                    return declaration.value.clone();
                }
                declarations = declaration.next.as_ref();
            }
            match self.environments[env].parent {
                Some(parent) => env = parent,
                None => return default,
            }
        }
    }
    fn variable(&mut self, source: usize, name: &str, binding: Binding) -> usize {
        let id = self.variables.len();
        self.variables.push(Box::new(Variable {
            name: name.to_owned(),
            binding,
            references: Ids::default(),
            assignments: Ids::default(),
            source,
        }));
        id
    }
    fn new_names(&mut self, sources: &[usize]) -> Ids {
        let ids: Vec<_> = sources
            .iter()
            .map(|&source| {
                let name = self
                    .source_symbol(source)
                    .expect("identifier expected")
                    .to_owned();
                self.variable(source, &name, Binding::Temporary)
            })
            .collect();
        Ids::from_slice(&ids)
    }
    fn lookup(&mut self, mut env: usize, name: &str, source: usize, define: bool) -> usize {
        loop {
            for var in self.environments[env].vars.borrow().values() {
                if self.variables[var].name == name {
                    assert!(!define, "duplicate definition");
                    return var;
                }
            }
            if !define {
                if let Some(parent) = self.environments[env].parent {
                    env = parent;
                    continue;
                }
            }
            let binding = if self.environments[env].parent.is_none() {
                Binding::Global
            } else {
                Binding::Temporary
            };
            let var = self.variable(source, name, binding);
            let root = self.environments[env].vars.borrow().clone();
            *self.environments[env].vars.borrow_mut() = Ids::cons(var, root);
            return var;
        }
    }
    fn add_declarations(&mut self, source: usize, mut env: usize) -> usize {
        for item in self.source_items(source).into_iter().skip(1) {
            let mut values = self.source_items(item);
            let positive = self.source_symbol(values[0]) != Some("not");
            if !positive {
                values.remove(0);
            }
            let name = self
                .source_symbol(values[0])
                .expect("declaration name")
                .to_owned();
            let (kind, value) = match name.as_str() {
                "ieee-scheme" | "r4rs-scheme" | "multilisp" => {
                    assert!(positive);
                    ("dialect".to_owned(), atom(&name))
                }
                "block" | "separate" => {
                    assert!(positive);
                    ("compilation-strategy".to_owned(), atom(&name))
                }
                "generic" | "fixnum" | "flonum" => {
                    assert!(positive);
                    ("arith".to_owned(), atom(&name))
                }
                "namespace" => {
                    assert!(positive);
                    let value = self.source_expression(values[1]);
                    values.remove(1);
                    (name, value)
                }
                "lambda-lift" | "safe" | "interrupts-enabled" | "standard-bindings"
                | "extended-bindings" => (name, atom(if positive { "#t" } else { "#f" })),
                _ => panic!("unknown declaration {name}"),
            };
            let names = values[1..]
                .iter()
                .map(|&id| self.source_expression(id).atom().to_owned())
                .collect();
            env = self.declare(
                env,
                Declaration {
                    kind,
                    value,
                    names,
                    next: None,
                },
            );
        }
        env
    }
    fn new_node(&mut self, source: usize, env: usize, kind: NodeKind, children: Ids) -> usize {
        let id = self.nodes.len();
        for child in children.values() {
            self.nodes[child].parent = Some(id);
        }
        self.nodes.push(Box::new(Node {
            kind: kind.clone(),
            parent: None,
            children,
            free: None,
            environment: env,
            source,
        }));
        match kind {
            NodeKind::Reference(var) => {
                self.variables[var].references = self.variables[var].references.adjoin(id)
            }
            NodeKind::Set(var) | NodeKind::Define(var) => {
                self.variables[var].assignments = self.variables[var].assignments.adjoin(id)
            }
            NodeKind::Procedure(proc) => {
                for var in proc.parameters.values() {
                    self.variables[var].binding = Binding::Procedure(id);
                }
            }
            _ => (),
        }
        id
    }
    fn constant(&mut self, source: usize, env: usize, value: Datum) -> usize {
        self.new_node(
            source,
            env,
            NodeKind::Constant(Rc::new(value)),
            Ids::default(),
        )
    }
    fn reference(&mut self, source: usize, env: usize, var: usize) -> usize {
        self.new_node(source, env, NodeKind::Reference(var), Ids::default())
    }
    fn procedure(
        &mut self,
        source: usize,
        env: usize,
        parameters: Ids,
        minimum: usize,
        rest: bool,
        body: usize,
    ) -> usize {
        self.new_node(
            source,
            env,
            NodeKind::Procedure(Procedure {
                name: None,
                parameters,
                minimum,
                rest,
            }),
            Ids::from_slice(&[body]),
        )
    }
    fn call(&mut self, source: usize, env: usize, operator: usize, args: Ids) -> usize {
        self.new_node(source, env, NodeKind::Call, Ids::cons(operator, args))
    }
    fn sequence(&mut self, source: usize, env: usize, before: usize, after: usize) -> usize {
        let var = self.variable(source, "temp", Binding::Temporary);
        let proc = self.procedure(source, env, Ids::from_slice(&[var]), 1, false, after);
        self.call(source, env, proc, Ids::from_slice(&[before]))
    }
    fn name_procedures(&mut self, vars: &Ids, vals: &Ids) {
        for (var, value) in vars.values().into_iter().zip(vals.values()) {
            if let NodeKind::Procedure(proc) = &mut self.nodes[value].kind {
                proc.name = Some(self.variables[var].name.clone());
            }
        }
    }
    fn definition(&mut self, source: usize) -> (usize, usize) {
        let code = self.source_items(source);
        if let SourceCode::List(parameters, tail) = self.sources[code[1]].code.clone() {
            let cell = parameters.0.expect("definition name");
            let parms = self.generated_source(source, SourceCode::List(cell.next.clone(), tail));
            let lambda = self.generated_source(source, SourceCode::Value(atom("lambda")));
            let value = self.generated_source(
                source,
                SourceCode::List(
                    Ids::cons(lambda, Ids::cons(parms, Ids::from_slice(&code[2..]))),
                    None,
                ),
            );
            (cell.id, value)
        } else if code.len() == 2 {
            let quote = self.generated_source(source, SourceCode::Value(atom("quote")));
            let value = self.generated_source(source, SourceCode::Value(undefined()));
            let value = self.generated_source(
                source,
                SourceCode::List(Ids::from_slice(&[quote, value]), None),
            );
            (code[1], value)
        } else {
            assert_eq!(code.len(), 3);
            (code[1], code[2])
        }
    }
    fn parse_program(&mut self, source: usize) -> Vec<(usize, usize)> {
        self.global = self.frame(None, Ids::default());
        let mut env = self.global;
        let mut pending = Ids::from_slice(&[source]);
        let mut result = Vec::new();
        while let Some(cell) = pending.0.clone() {
            let source = cell.id;
            pending = cell.next.clone();
            if self.form(source, "begin") {
                let SourceCode::List(body, None) = &self.sources[source].code else {
                    unreachable!()
                };
                pending = body.0.as_ref().unwrap().next.append(&pending);
            } else if self.form(source, "declare") {
                env = self.add_declarations(source, env);
            } else if self.form(source, "define") {
                let (name, value) = self.definition(source);
                let spelling = self.source_symbol(name).unwrap().to_owned();
                let var = self.lookup(env, &spelling, name, false);
                let value = self.parse(value, env, Use::Value);
                self.name_procedures(&Ids::from_slice(&[var]), &Ids::from_slice(&[value]));
                let node = self.new_node(
                    source,
                    env,
                    NodeKind::Define(var),
                    Ids::from_slice(&[value]),
                );
                result.push((node, env));
            } else {
                result.push((self.parse(source, env, Use::Value), env));
            }
        }
        result
    }
    fn parse(&mut self, source: usize, env: usize, use_: Use) -> usize {
        if let SourceCode::Value(value) = self.sources[source].code.clone() {
            if use_ == Use::Discard {
                return self.constant(source, env, undefined());
            }
            return match symbol(&value) {
                Some(name) => {
                    let var = self.lookup(env, name, source, false);
                    self.reference(source, env, var)
                }
                None => self.constant(source, env, value),
            };
        }
        if let SourceCode::Vector(_) = self.sources[source].code {
            return self.constant(source, env, self.source_expression(source));
        }
        let code = self.source_items(source);
        if code.is_empty() {
            return self.constant(source, env, Datum::List(vec![]));
        }
        match self.source_symbol(code[0]).unwrap_or("") {
            "quote" => {
                assert_eq!(code.len(), 2);
                let val = if use_ == Use::Discard {
                    undefined()
                } else {
                    self.source_expression(code[1])
                };
                self.constant(source, env, val)
            }
            "lambda" => self.parse_lambda(source, env, use_, &code),
            "set!" => {
                assert_eq!(code.len(), 3);
                let name = self.source_symbol(code[1]).unwrap().to_owned();
                let var = self.lookup(env, &name, code[1], false);
                let value = self.parse(code[2], env, Use::Value);
                self.new_node(source, env, NodeKind::Set(var), Ids::from_slice(&[value]))
            }
            "if" => {
                assert!(code.len() == 3 || code.len() == 4);
                let pred = self.parse(code[1], env, Use::Predicate);
                let yes = self.parse(code[2], env, use_);
                let no = if code.len() == 4 {
                    self.parse(code[3], env, use_)
                } else {
                    self.constant(source, env, undefined())
                };
                self.new_node(
                    source,
                    env,
                    NodeKind::Test,
                    Ids::from_slice(&[pred, yes, no]),
                )
            }
            "begin" => self.parse_sequence(source, &code[1..], env, use_),
            "cond" => self.parse_cond(source, &code[1..], env, use_),
            "and" | "or" => {
                let and = self.source_symbol(code[0]) == Some("and");
                self.parse_boolean(source, &code[1..], env, use_, and)
            }
            "let" => self.parse_let(source, &code, env, use_),
            "let*" => {
                self.parse_let_star(source, &self.source_items(code[1]), &code[2..], env, use_)
            }
            "letrec" => self.parse_letrec(source, &code, env, use_),
            "do" => self.parse_do(source, &code, env, use_),
            "define" | "declare" | "include" | "define-macro" => {
                panic!("ill-placed or unsupported syntax")
            }
            "quasiquote" | "case" | "delay" | "future" => {
                panic!("remaining frontend syntax port pending")
            }
            _ => {
                let operator = self.parse(code[0], env, Use::Value);
                let args: Vec<_> = code[1..]
                    .iter()
                    .map(|&id| self.parse(id, env, Use::Value))
                    .collect();
                self.call(source, env, operator, Ids::from_slice(&args))
            }
        }
    }
    fn parse_lambda(&mut self, source: usize, env: usize, use_: Use, code: &[usize]) -> usize {
        if use_ == Use::Discard {
            return self.constant(source, env, undefined());
        }
        let (params, tail) = match self.sources[code[1]].code.clone() {
            SourceCode::List(params, tail) => (params.values(), tail),
            SourceCode::Value(_) => (vec![], Some(code[1])),
            _ => panic!("invalid lambda parameters"),
        };
        let minimum = params.len();
        let mut vars = self.new_names(&params).values();
        if let Some(tail) = tail {
            vars.extend(self.new_names(&[tail]).values());
        }
        let vars = Ids::from_slice(&vars);
        let body_env = self.frame(Some(env), vars.clone());
        let body = self.parse_body(source, &code[2..], body_env, Use::Value);
        self.procedure(source, env, vars, minimum, tail.is_some(), body)
    }
    fn parse_body(&mut self, source: usize, body: &[usize], env: usize, use_: Use) -> usize {
        let mut env = self.frame(Some(env), Ids::default());
        let mut pending = Ids::from_slice(body);
        let mut vars = Vec::new();
        let mut values = Vec::new();
        while let Some(cell) = pending.0.clone() {
            let next = cell.id;
            if self.form(next, "begin") {
                let SourceCode::List(body, None) = &self.sources[next].code else {
                    unreachable!()
                };
                pending = body.0.as_ref().unwrap().next.append(&cell.next);
            } else if self.form(next, "declare") {
                pending = cell.next.clone();
                env = self.add_declarations(next, env);
            } else if self.form(next, "define") {
                pending = cell.next.clone();
                let (name, value) = self.definition(next);
                let spelling = self.source_symbol(name).unwrap().to_owned();
                vars.push(self.lookup(env, &spelling, name, true));
                values.push((value, env));
            } else {
                break;
            }
        }
        assert!(!pending.empty(), "body needs an expression");
        let pending = pending.values();
        if vars.is_empty() {
            return self.parse_sequence(source, &pending, env, use_);
        }
        let mut parsed = vec![0; values.len()];
        for i in (0..values.len()).rev() {
            parsed[i] = self.parse(values[i].0, values[i].1, Use::Value);
        }
        self.recursive_let(
            source,
            Ids::from_slice(&vars),
            Ids::from_slice(&parsed),
            &pending,
            env,
            use_,
        )
    }
    fn parse_sequence(&mut self, source: usize, values: &[usize], env: usize, use_: Use) -> usize {
        assert!(!values.is_empty(), "empty sequence");
        if values.len() == 1 {
            return self.parse(values[0], env, use_);
        }
        let before = self.parse(values[0], env, Use::Discard);
        let after = self.parse_sequence(source, &values[1..], env, use_);
        self.sequence(source, env, before, after)
    }
    fn parse_cond(&mut self, source: usize, clauses: &[usize], env: usize, use_: Use) -> usize {
        if clauses.is_empty() {
            return self.constant(source, env, undefined());
        }
        let clause = self.source_items(clauses[0]);
        if self.source_symbol(clause[0]) == Some("else") {
            return self.parse_sequence(clauses[0], &clause[1..], env, use_);
        }
        let pred = self.parse(
            clause[0],
            env,
            if use_ == Use::Value {
                Use::Value
            } else {
                Use::Predicate
            },
        );
        if clause.len() == 1 {
            let alt = self.parse_cond(source, &clauses[1..], env, use_);
            return self.new_node(
                clauses[0],
                env,
                NodeKind::Disjunction,
                Ids::from_slice(&[pred, alt]),
            );
        }
        if self.source_symbol(clause[1]) == Some("=>") {
            panic!("cond arrow port pending");
        }
        let yes = self.parse_sequence(clauses[0], &clause[1..], env, use_);
        let no = self.parse_cond(source, &clauses[1..], env, use_);
        self.new_node(
            clauses[0],
            env,
            NodeKind::Test,
            Ids::from_slice(&[pred, yes, no]),
        )
    }
    fn parse_boolean(
        &mut self,
        source: usize,
        values: &[usize],
        env: usize,
        use_: Use,
        and: bool,
    ) -> usize {
        if values.is_empty() {
            return self.constant(source, env, atom(if and { "#t" } else { "#f" }));
        }
        if values.len() == 1 {
            return self.parse(values[0], env, use_);
        }
        let first = self.parse(
            values[0],
            env,
            if use_ == Use::Value {
                Use::Value
            } else {
                Use::Predicate
            },
        );
        let rest = self.parse_boolean(source, &values[1..], env, use_, and);
        self.new_node(
            values[0],
            env,
            if and {
                NodeKind::Conjunction
            } else {
                NodeKind::Disjunction
            },
            Ids::from_slice(&[first, rest]),
        )
    }
    fn bindings(&mut self, bindings: &[usize], env: usize) -> (Ids, Ids) {
        let pairs: Vec<_> = bindings.iter().map(|&id| self.source_items(id)).collect();
        let vars = self.new_names(&pairs.iter().map(|pair| pair[0]).collect::<Vec<_>>());
        let values: Vec<_> = pairs
            .iter()
            .map(|pair| self.parse(pair[1], env, Use::Value))
            .collect();
        (vars, Ids::from_slice(&values))
    }
    fn parse_let(&mut self, source: usize, code: &[usize], env: usize, use_: Use) -> usize {
        if self.source_symbol(code[1]).is_some() {
            let self_var = self.new_names(&[code[1]]);
            let (vars, vals) = self.bindings(&self.source_items(code[2]), env);
            let vars_env = self.frame(Some(env), vars.clone());
            let body_env = self.frame(Some(vars_env), self_var.clone());
            let body = self.parse_body(source, &code[3..], body_env, use_);
            let function = self.procedure(
                source,
                body_env,
                vars.clone(),
                vars.values().len(),
                false,
                body,
            );
            self.name_procedures(&self_var, &Ids::from_slice(&[function]));
            self.name_procedures(&vars, &vals);
            let reference = self.reference(source, body_env, self_var.values()[0]);
            let call = self.call(source, body_env, reference, vals);
            let wrapper = self.procedure(source, body_env, self_var, 1, false, call);
            self.call(source, body_env, wrapper, Ids::from_slice(&[function]))
        } else {
            let bindings = self.source_items(code[1]);
            if bindings.is_empty() {
                return self.parse_body(source, &code[2..], env, use_);
            }
            let (vars, vals) = self.bindings(&bindings, env);
            let body_env = self.frame(Some(env), vars.clone());
            self.name_procedures(&vars, &vals);
            let body = self.parse_body(source, &code[2..], body_env, use_);
            let proc = self.procedure(
                source,
                body_env,
                vars.clone(),
                vars.values().len(),
                false,
                body,
            );
            self.call(source, body_env, proc, vals)
        }
    }
    fn parse_let_star(
        &mut self,
        source: usize,
        bindings: &[usize],
        body: &[usize],
        env: usize,
        use_: Use,
    ) -> usize {
        if bindings.is_empty() {
            return self.parse_body(source, body, env, use_);
        }
        let (vars, vals) = self.bindings(&bindings[..1], env);
        let body_env = self.frame(Some(env), vars.clone());
        self.name_procedures(&vars, &vals);
        let next = self.parse_let_star(source, &bindings[1..], body, body_env, use_);
        let proc = self.procedure(bindings[0], body_env, vars, 1, false, next);
        self.call(bindings[0], body_env, proc, vals)
    }
    fn parse_letrec(&mut self, source: usize, code: &[usize], env: usize, use_: Use) -> usize {
        let pairs: Vec<_> = self
            .source_items(code[1])
            .into_iter()
            .map(|id| self.source_items(id))
            .collect();
        let vars = self.new_names(&pairs.iter().map(|pair| pair[0]).collect::<Vec<_>>());
        let body_env = self.frame(Some(env), vars.clone());
        let vals: Vec<_> = pairs
            .iter()
            .map(|pair| self.parse(pair[1], body_env, Use::Value))
            .collect();
        self.recursive_let(
            source,
            vars,
            Ids::from_slice(&vals),
            &code[2..],
            body_env,
            use_,
        )
    }
    fn parse_do(&mut self, source: usize, code: &[usize], env: usize, use_: Use) -> usize {
        let loop_var = self.variable(source, "loop", Binding::Temporary);
        let pairs: Vec<_> = self
            .source_items(code[1])
            .into_iter()
            .map(|id| self.source_items(id))
            .collect();
        let vars = self.new_names(&pairs.iter().map(|pair| pair[0]).collect::<Vec<_>>());
        let init: Vec<_> = pairs
            .iter()
            .map(|pair| self.parse(pair[1], env, Use::Value))
            .collect();
        let body_env = self.frame(Some(env), vars.clone());
        let step: Vec<_> = pairs
            .iter()
            .map(|pair| {
                self.parse(
                    if pair.len() == 2 { pair[0] } else { pair[2] },
                    body_env,
                    Use::Value,
                )
            })
            .collect();
        let exit = self.source_items(code[2]);
        self.name_procedures(&vars, &Ids::from_slice(&init));
        let pred = self.parse(exit[0], body_env, Use::Predicate);
        let yes = if exit.len() == 1 {
            self.constant(code[2], body_env, undefined())
        } else {
            self.parse_sequence(code[2], &exit[1..], body_env, use_)
        };
        let recur = self.reference(source, body_env, loop_var);
        let mut no = self.call(source, body_env, recur, Ids::from_slice(&step));
        if code.len() > 3 {
            let before = self.parse_sequence(source, &code[3..], body_env, Use::Discard);
            no = self.sequence(source, body_env, before, no);
        }
        let body = self.new_node(
            source,
            body_env,
            NodeKind::Test,
            Ids::from_slice(&[pred, yes, no]),
        );
        let function = self.procedure(
            source,
            body_env,
            vars.clone(),
            vars.values().len(),
            false,
            body,
        );
        let recur = self.reference(source, body_env, loop_var);
        let first_call = self.call(source, body_env, recur, Ids::from_slice(&init));
        let wrapper = self.procedure(
            source,
            body_env,
            Ids::from_slice(&[loop_var]),
            1,
            false,
            first_call,
        );
        self.call(source, body_env, wrapper, Ids::from_slice(&[function]))
    }
    fn free_variables(&mut self, node: usize) -> Ids {
        if let Some(cached) = &self.nodes[node].free {
            return cached.clone();
        }
        let children = self.nodes[node].children.values();
        let mut result = Ids::default();
        for child in &children {
            result = result.union(&self.free_variables(*child));
        }
        match self.nodes[node].kind.clone() {
            NodeKind::Reference(var) | NodeKind::Set(var)
                if self.variables[var].binding != Binding::Global =>
            {
                result = result.adjoin(var)
            }
            NodeKind::Procedure(proc) => result = result.difference(&proc.parameters),
            NodeKind::Call if matches!(self.nodes[children[0]].kind, NodeKind::Procedure(_)) => {
                let NodeKind::Procedure(proc) = &self.nodes[children[0]].kind else {
                    unreachable!()
                };
                result = result.difference(&proc.parameters);
            }
            _ => (),
        }
        self.nodes[node].free = Some(result.clone());
        result
    }
    fn recursive_order(&mut self, vars: &Ids, vals: &Ids) -> Vec<Ids> {
        let mut graph: Vec<_> = vars
            .values()
            .into_iter()
            .zip(vals.values())
            .map(|(var, val)| (var, vars.intersection(&self.free_variables(val))))
            .collect();
        loop {
            let next: Vec<_> = graph
                .iter()
                .map(|(var, edges)| {
                    let mut more = Ids::default();
                    for edge in edges.values() {
                        more = more.union(&graph.iter().find(|(id, _)| *id == edge).unwrap().1);
                    }
                    (*var, edges.union(&more))
                })
                .collect();
            let changed = graph
                .iter()
                .zip(&next)
                .any(|(old, new)| !old.1.equal_set(&new.1));
            graph = next;
            if !changed {
                break;
            }
        }
        let mut groups = Vec::new();
        while !graph.is_empty() {
            let mut selected: Vec<_> = graph
                .iter()
                .filter(|(_, edges)| edges.empty())
                .map(|(id, _)| *id)
                .collect();
            if selected.is_empty() {
                for (var, edges) in &graph {
                    if !edges.has(*var) {
                        continue;
                    }
                    let cycle: Vec<_> = graph.iter().filter(|(var, _)| edges.has(*var)).collect();
                    if cycle.iter().all(|(_, other)| edges.equal_set(other)) {
                        selected = cycle.iter().map(|(var, _)| *var).collect();
                        break;
                    }
                }
            }
            assert!(!selected.is_empty(), "no terminal dependency component");
            let ids = Ids::from_slice(&selected);
            groups.push(ids.clone());
            graph = graph
                .into_iter()
                .filter(|(id, _)| !ids.has(*id))
                .map(|(id, edges)| (id, edges.difference(&ids)))
                .collect();
        }
        groups
    }
    fn recursive_let(
        &mut self,
        source: usize,
        vars: Ids,
        vals: Ids,
        body: &[usize],
        env: usize,
        use_: Use,
    ) -> usize {
        self.name_procedures(&vars, &vals);
        let order = self.recursive_order(&vars, &vals);
        self.bind_recursive_groups(
            source,
            &order,
            &vars
                .values()
                .into_iter()
                .zip(vals.values())
                .collect::<Vec<_>>(),
            body,
            env,
            use_,
        )
    }
    fn bind_recursive_groups(
        &mut self,
        source: usize,
        order: &[Ids],
        values: &[(usize, usize)],
        body: &[usize],
        env: usize,
        use_: Use,
    ) -> usize {
        if order.is_empty() {
            return self.parse_body(source, body, env, use_);
        }
        let mut before = Vec::new();
        let mut after = Vec::new();
        for var in order[0].values() {
            let val = values.iter().find(|(id, _)| *id == var).unwrap().1;
            if matches!(self.nodes[val].kind, NodeKind::Procedure(_))
                || self.free_variables(val).intersection(&order[0]).empty()
            {
                before.push((var, val));
            } else {
                after.push((var, val));
            }
        }
        let mut result = self.bind_recursive_groups(source, &order[1..], values, body, env, use_);
        for &(var, val) in after.iter().rev() {
            let set = self.new_node(source, env, NodeKind::Set(var), Ids::from_slice(&[val]));
            result = self.sequence(source, env, set, result);
        }
        if !before.is_empty() {
            let vars: Vec<_> = before.iter().map(|(var, _)| *var).collect();
            let vals: Vec<_> = before.iter().map(|(_, val)| *val).collect();
            let proc = self.procedure(
                source,
                env,
                Ids::from_slice(&vars),
                vars.len(),
                false,
                result,
            );
            result = self.call(source, env, proc, Ids::from_slice(&vals));
        }
        if !after.is_empty() {
            let vars: Vec<_> = after.iter().map(|(var, _)| *var).collect();
            let vals: Vec<_> = vars
                .iter()
                .map(|_| self.constant(source, env, undefined()))
                .collect();
            let proc = self.procedure(
                source,
                env,
                Ids::from_slice(&vars),
                vars.len(),
                false,
                result,
            );
            result = self.call(source, env, proc, Ids::from_slice(&vals));
        }
        result
    }
    fn invalidate(&mut self, mut node: usize) {
        loop {
            self.nodes[node].free = None;
            match self.nodes[node].parent {
                Some(parent) => node = parent,
                None => break,
            }
        }
    }
    fn replace_children(&mut self, node: usize, children: Ids) {
        for child in children.values() {
            self.nodes[child].parent = Some(node);
        }
        self.nodes[node].children = children;
        self.invalidate(node);
    }
}

// ---- Partial evaluation without arithmetic folding ----

impl Compiler<'_> {
    fn global_value(&self, var: usize) -> Option<usize> {
        if self.variables[var].binding != Binding::Global {
            return None;
        }
        let assignments = self.variables[var].assignments.values();
        if assignments.len() != 1 || !matches!(self.nodes[assignments[0]].kind, NodeKind::Define(_))
        {
            return None;
        }
        let definition = &self.nodes[assignments[0]];
        if self
            .declaration(
                definition.environment,
                "compilation-strategy",
                None,
                atom("separate"),
            )
            .atom()
            != "block"
        {
            return None;
        }
        Some(definition.children.values()[0])
    }
    fn partial_evaluate(&mut self, node: usize, constants: &[(usize, Rc<Datum>)]) -> usize {
        let source = self.nodes[node].source;
        let env = self.nodes[node].environment;
        let children = self.nodes[node].children.values();
        match self.nodes[node].kind.clone() {
            NodeKind::Constant(value) => {
                self.new_node(source, env, NodeKind::Constant(value), Ids::default())
            }
            NodeKind::Reference(var) => {
                self.variables[var].references = self.variables[var].references.remove(node);
                let value = constants
                    .iter()
                    .find(|(id, _)| *id == var)
                    .map(|(_, value)| value.clone())
                    .or_else(|| {
                        self.global_value(var)
                            .and_then(|id| match &self.nodes[id].kind {
                                NodeKind::Constant(value) => Some(value.clone()),
                                _ => None,
                            })
                    });
                match value {
                    Some(value) => {
                        self.new_node(source, env, NodeKind::Constant(value), Ids::default())
                    }
                    None => self.reference(source, env, var),
                }
            }
            NodeKind::Set(var) => {
                let value = self.partial_evaluate(children[0], constants);
                self.variables[var].assignments = self.variables[var].assignments.remove(node);
                self.new_node(source, env, NodeKind::Set(var), Ids::from_slice(&[value]))
            }
            NodeKind::Test | NodeKind::Conjunction | NodeKind::Disjunction => {
                let kind = self.nodes[node].kind.clone();
                let pred = self.partial_evaluate(children[0], constants);
                if let NodeKind::Constant(value) = &self.nodes[pred].kind {
                    let false_ = matches!(&**value, Datum::Atom(text) if text == "#f");
                    match kind {
                        NodeKind::Test => {
                            self.partial_evaluate(children[if false_ { 2 } else { 1 }], constants)
                        }
                        NodeKind::Conjunction if false_ => pred,
                        NodeKind::Disjunction if !false_ => pred,
                        _ => self.partial_evaluate(children[1], constants),
                    }
                } else {
                    let mut values = vec![pred];
                    for child in &children[1..] {
                        values.push(self.partial_evaluate(*child, constants));
                    }
                    self.new_node(source, env, kind, Ids::from_slice(&values))
                }
            }
            NodeKind::Procedure(proc) => {
                let body = self.partial_evaluate(children[0], constants);
                self.new_node(
                    source,
                    env,
                    NodeKind::Procedure(proc),
                    Ids::from_slice(&[body]),
                )
            }
            NodeKind::Call if self.let_call(node) => self.partial_evaluate_let(node, constants),
            NodeKind::Call | NodeKind::Future => {
                let kind = self.nodes[node].kind.clone();
                let values: Vec<_> = children
                    .iter()
                    .map(|&id| self.partial_evaluate(id, constants))
                    .collect();
                self.new_node(source, env, kind, Ids::from_slice(&values))
            }
            _ => panic!("partial evaluation expects an expression"),
        }
    }
    fn let_call(&self, node: usize) -> bool {
        if !matches!(self.nodes[node].kind, NodeKind::Call) {
            return false;
        }
        let children = self.nodes[node].children.values();
        match &self.nodes[children[0]].kind {
            NodeKind::Procedure(proc) => {
                !proc.rest && proc.parameters.values().len() == children.len() - 1
            }
            _ => false,
        }
    }
    fn partial_evaluate_let(&mut self, node: usize, constants: &[(usize, Rc<Datum>)]) -> usize {
        let source = self.nodes[node].source;
        let env = self.nodes[node].environment;
        let children = self.nodes[node].children.values();
        let proc_id = children[0];
        let NodeKind::Procedure(proc) = self.nodes[proc_id].kind.clone() else {
            unreachable!()
        };
        let immutable = Ids::from_slice(
            &proc
                .parameters
                .values()
                .into_iter()
                .filter(|&var| self.variables[var].assignments.empty())
                .collect::<Vec<_>>(),
        );
        for var in proc.parameters.values() {
            self.variables[var].references = Ids::default();
            self.variables[var].assignments = Ids::default();
        }
        let mut vars = Vec::new();
        let mut vals = Vec::new();
        let mut known = constants.to_vec();
        for (var, value) in proc
            .parameters
            .values()
            .into_iter()
            .zip(children[1..].iter().copied())
        {
            let value = self.partial_evaluate(value, constants);
            if immutable.has(var) {
                if let NodeKind::Constant(value) = &self.nodes[value].kind {
                    known.insert(0, (var, value.clone()));
                    continue;
                }
            }
            vars.push(var);
            vals.push(value);
        }
        let body_id = self.nodes[proc_id].children.values()[0];
        let body = self.partial_evaluate(body_id, &known);
        if vars.is_empty() {
            return body;
        }
        let new_proc = self.procedure(
            self.nodes[proc_id].source,
            self.nodes[proc_id].environment,
            Ids::from_slice(&vars),
            vars.len(),
            false,
            body,
        );
        self.call(source, env, new_proc, Ids::from_slice(&vals))
    }
}

// ---- Assignment conversion into shared mutable cells ----

impl Compiler<'_> {
    fn extended_reference(&mut self, source: usize, env: usize, name: &str) -> usize {
        let declaration = Declaration {
            kind: "extended-bindings".into(),
            value: atom("#t"),
            names: vec![],
            next: None,
        };
        let declared = self.declare(env, declaration);
        let var = self.lookup(self.global, name, source, false);
        self.reference(source, declared, var)
    }
    fn cell_call(
        &mut self,
        source: usize,
        env: usize,
        conversion_env: usize,
        name: &str,
        args: &[usize],
    ) -> usize {
        let oper = self.extended_reference(source, conversion_env, name);
        self.call(source, env, oper, Ids::from_slice(args))
    }
    fn copy_variable(&mut self, var: usize) -> usize {
        let name = self.variables[var].name.clone();
        self.variable(self.variables[var].source, &name, Binding::Temporary)
    }
    fn mutable_copies(&mut self, vars: &Ids) -> Vec<(usize, usize)> {
        vars.values()
            .into_iter()
            .filter(|&var| !self.variables[var].assignments.empty())
            .collect::<Vec<_>>()
            .into_iter()
            .map(|var| (var, self.copy_variable(var)))
            .collect()
    }
    fn assignment_convert(
        &mut self,
        node: usize,
        conversion_env: usize,
        mutations: &[(usize, usize)],
    ) -> usize {
        let source = self.nodes[node].source;
        let env = self.nodes[node].environment;
        let children = self.nodes[node].children.values();
        match self.nodes[node].kind.clone() {
            NodeKind::Constant(_) => node,
            NodeKind::Reference(var) => {
                if self.variables[var].binding == Binding::Global {
                    return node;
                }
                let Some((_, copy)) = mutations.iter().find(|(id, _)| *id == var) else {
                    return node;
                };
                self.variables[var].references = self.variables[var].references.remove(node);
                let reference = self.reference(source, env, *copy);
                self.cell_call(source, env, conversion_env, "##cell-ref", &[reference])
            }
            NodeKind::Set(var) => {
                let value = self.assignment_convert(children[0], conversion_env, mutations);
                self.variables[var].assignments = self.variables[var].assignments.remove(node);
                if self.variables[var].binding == Binding::Global {
                    return self.new_node(
                        source,
                        env,
                        NodeKind::Set(var),
                        Ids::from_slice(&[value]),
                    );
                }
                let copy = mutations
                    .iter()
                    .find(|(id, _)| *id == var)
                    .expect("mutable lexical variable needs a cell")
                    .1;
                let reference = self.reference(source, env, copy);
                self.cell_call(
                    source,
                    env,
                    conversion_env,
                    "##cell-set!",
                    &[reference, value],
                )
            }
            NodeKind::Procedure(proc) => {
                self.assignment_convert_procedure(node, proc, conversion_env, mutations)
            }
            NodeKind::Call if self.let_call(node) => {
                self.assignment_convert_let(node, conversion_env, mutations)
            }
            NodeKind::Test
            | NodeKind::Conjunction
            | NodeKind::Disjunction
            | NodeKind::Call
            | NodeKind::Future => {
                let kind = self.nodes[node].kind.clone();
                let values: Vec<_> = children
                    .iter()
                    .map(|&id| self.assignment_convert(id, conversion_env, mutations))
                    .collect();
                self.new_node(source, env, kind, Ids::from_slice(&values))
            }
            _ => panic!("assignment conversion expects an expression"),
        }
    }
    fn assignment_convert_procedure(
        &mut self,
        node: usize,
        proc: Procedure,
        conversion_env: usize,
        mutations: &[(usize, usize)],
    ) -> usize {
        let source = self.nodes[node].source;
        let env = self.nodes[node].environment;
        let copies = self.mutable_copies(&proc.parameters);
        let mut scoped = copies.clone();
        scoped.extend_from_slice(mutations);
        let child = self.nodes[node].children.values()[0];
        let mut body = self.assignment_convert(child, conversion_env, &scoped);
        if !copies.is_empty() {
            let vars: Vec<_> = copies.iter().map(|(_, copy)| *copy).collect();
            let mut vals = Vec::new();
            for &(var, _) in &copies {
                let source = self.variables[var].source;
                let reference = self.reference(source, env, var);
                vals.push(self.cell_call(source, env, conversion_env, "##make-cell", &[reference]));
            }
            let function =
                self.procedure(source, env, Ids::from_slice(&vars), vars.len(), false, body);
            body = self.call(source, env, function, Ids::from_slice(&vals));
        }
        self.new_node(
            source,
            env,
            NodeKind::Procedure(proc),
            Ids::from_slice(&[body]),
        )
    }
    fn assignment_convert_let(
        &mut self,
        node: usize,
        conversion_env: usize,
        mutations: &[(usize, usize)],
    ) -> usize {
        let source = self.nodes[node].source;
        let env = self.nodes[node].environment;
        let children = self.nodes[node].children.values();
        let function = children[0];
        let NodeKind::Procedure(proc) = self.nodes[function].kind.clone() else {
            unreachable!()
        };
        let mut free = Ids::default();
        for &val in &children[1..] {
            free = free.union(&self.free_variables(val));
        }
        let copies = self.mutable_copies(&proc.parameters);
        let mut scoped = copies.clone();
        scoped.extend_from_slice(mutations);
        let body_id = self.nodes[function].children.values()[0];
        let mut body = self.assignment_convert(body_id, conversion_env, &scoped);
        let mut vars = Vec::new();
        let mut vals = Vec::new();
        for (var, value) in proc
            .parameters
            .values()
            .into_iter()
            .zip(children[1..].iter().copied())
        {
            if let Some((_, copy)) = copies.iter().find(|(id, _)| *id == var) {
                let src = self.nodes[value].source;
                let decl = self.nodes[value].environment;
                vars.push(*copy);
                if free.has(var) {
                    let undefined = self.constant(src, decl, undefined());
                    vals.push(self.cell_call(
                        src,
                        decl,
                        conversion_env,
                        "##make-cell",
                        &[undefined],
                    ));
                    let value = self.assignment_convert(value, conversion_env, &scoped);
                    let reference = self.reference(src, decl, *copy);
                    let set = self.cell_call(
                        src,
                        decl,
                        conversion_env,
                        "##cell-set!",
                        &[reference, value],
                    );
                    body = self.sequence(src, decl, set, body);
                } else {
                    let value = self.assignment_convert(value, conversion_env, &scoped);
                    vals.push(self.cell_call(src, decl, conversion_env, "##make-cell", &[value]));
                }
            } else {
                vars.push(var);
                vals.push(self.assignment_convert(value, conversion_env, &scoped));
            }
        }
        if vars.is_empty() {
            return body;
        }
        let function = self.new_node(
            self.nodes[function].source,
            self.nodes[function].environment,
            NodeKind::Procedure(Procedure {
                name: proc.name,
                parameters: Ids::from_slice(&vars),
                minimum: vars.len(),
                rest: false,
            }),
            Ids::from_slice(&[body]),
        );
        self.call(source, env, function, Ids::from_slice(&vals))
    }
}

// ---- Lambda lifting and destructive reference rewrites ----

#[derive(Clone)]
struct LiftBinding {
    variable: usize,
    references: usize,
    index: usize,
}
fn merge_lift_order(first: &[LiftBinding], second: &[LiftBinding]) -> Vec<LiftBinding> {
    let mut result = Vec::new();
    let mut i = 0;
    let mut j = 0;
    while i < first.len() && j < second.len() {
        if (first[i].references, first[i].index) < (second[j].references, second[j].index) {
            result.push(first[i].clone());
            i += 1;
        } else {
            result.push(second[j].clone());
            j += 1;
        }
    }
    result.extend_from_slice(&first[i..]);
    result.extend_from_slice(&second[j..]);
    result
}
fn sort_lift_order(values: &[LiftBinding]) -> Vec<LiftBinding> {
    if values.len() < 2 {
        return values.to_vec();
    }
    let first: Vec<_> = values.iter().step_by(2).cloned().collect();
    let second: Vec<_> = values.iter().skip(1).step_by(2).cloned().collect();
    merge_lift_order(&sort_lift_order(&first), &sort_lift_order(&second))
}
impl Compiler<'_> {
    fn lift_environment(&self, vars: &Ids, env: &[LiftBinding]) -> Vec<LiftBinding> {
        let mut result: Vec<_> = vars
            .values()
            .into_iter()
            .enumerate()
            .map(|(i, variable)| LiftBinding {
                variable,
                references: self.variables[variable].references.values().len(),
                index: env.len() + i,
            })
            .collect();
        result.extend_from_slice(env);
        result
    }
    fn operator_position(&self, node: usize) -> bool {
        self.nodes[node].parent.is_some_and(|parent| {
            matches!(self.nodes[parent].kind, NodeKind::Call)
                && self.nodes[parent].children.values()[0] == node
        })
    }
    fn lambda_lift(&mut self, node: usize, constant_procedures: &Ids, env: &[LiftBinding]) {
        let children = self.nodes[node].children.values();
        match self.nodes[node].kind.clone() {
            NodeKind::Procedure(proc) => {
                let scoped = self.lift_environment(&proc.parameters, env);
                self.lambda_lift(children[0], constant_procedures, &scoped);
            }
            NodeKind::Call if self.let_call(node) => {
                let NodeKind::Procedure(proc) = &self.nodes[children[0]].kind else {
                    unreachable!()
                };
                let scoped = self.lift_environment(&proc.parameters, env);
                self.lambda_lift_let(node, constant_procedures, &scoped);
            }
            _ => {
                for child in children {
                    self.lambda_lift(child, constant_procedures, env);
                }
            }
        }
    }
    fn liftable_variables(&mut self, vars: &Ids, values: &[(usize, usize)]) -> Ids {
        let mut candidates = Ids::from_slice(
            &vars
                .values()
                .into_iter()
                .filter(|&var| {
                    let val = values.iter().find(|(id, _)| *id == var).unwrap().1;
                    matches!(self.nodes[val].kind, NodeKind::Procedure(_))
                        && self
                            .declaration(
                                self.nodes[val].environment,
                                "lambda-lift",
                                None,
                                atom("#t"),
                            )
                            .atom()
                            != "#f"
                        && self.variables[var]
                            .references
                            .values()
                            .into_iter()
                            .all(|node| self.operator_position(node))
                })
                .collect::<Vec<_>>(),
        );
        loop {
            let others = Ids::from_slice(
                &vars
                    .values()
                    .into_iter()
                    .filter(|var| {
                        let val = values.iter().find(|(id, _)| id == var).unwrap().1;
                        matches!(self.nodes[val].kind, NodeKind::Procedure(_))
                            && !candidates.has(*var)
                    })
                    .collect::<Vec<_>>(),
            );
            let mut next = Vec::new();
            for var in candidates.values() {
                let val = values.iter().find(|(id, _)| *id == var).unwrap().1;
                if self.free_variables(val).intersection(&others).empty() {
                    next.push(var);
                }
            }
            let next = Ids::from_slice(&next);
            if candidates.equal_set(&next) {
                return candidates;
            }
            candidates = next;
        }
    }
    fn closed_free_variables(
        &mut self,
        vars: &Ids,
        values: &[(usize, usize)],
    ) -> Vec<(usize, Ids)> {
        let mut map: Vec<_> = vars
            .values()
            .into_iter()
            .map(|var| {
                let value = values.iter().find(|(id, _)| *id == var).unwrap().1;
                (var, self.free_variables(value))
            })
            .collect();
        loop {
            let mut changed = false;
            for i in 0..map.len() {
                let mut free = map[i].1.clone();
                for var in map[i].1.values() {
                    if let Some((_, other)) = map.iter().find(|(id, _)| *id == var) {
                        free = free.union(other);
                    }
                }
                if !free.equal_set(&map[i].1) {
                    map[i].1 = free;
                    changed = true;
                }
            }
            if !changed {
                return map;
            }
        }
    }
    fn ordered_lifted_variables(
        &self,
        free: &Ids,
        constants: &Ids,
        env: &[LiftBinding],
    ) -> Vec<usize> {
        let values: Vec<_> = free
            .difference(constants)
            .values()
            .into_iter()
            .map(|var| {
                env.iter()
                    .find(|entry| entry.variable == var)
                    .expect("lifted variable must have an enclosing lexical binding")
                    .clone()
            })
            .collect();
        sort_lift_order(&values)
            .into_iter()
            .map(|entry| entry.variable)
            .collect()
    }
    fn lambda_lift_let(&mut self, node: usize, constants: &Ids, env: &[LiftBinding]) {
        let children = self.nodes[node].children.values();
        let function = children[0];
        let NodeKind::Procedure(proc) = self.nodes[function].kind.clone() else {
            unreachable!()
        };
        let values: Vec<_> = proc
            .parameters
            .values()
            .into_iter()
            .zip(children[1..].iter().copied())
            .collect();
        let liftable = self.liftable_variables(&proc.parameters, &values);
        let map = self.closed_free_variables(&liftable, &values);
        let lifted = Ids::from_slice(&map.iter().map(|(var, _)| *var).collect::<Vec<_>>());
        let constants = lifted.union(constants);
        for (var, free) in &map {
            let value = values.iter().find(|(id, _)| id == var).unwrap().1;
            let vars = self.ordered_lifted_variables(free, &constants, env);
            if vars.is_empty() {
                continue;
            }
            for reference in self.variables[*var].references.values() {
                let call = self.nodes[reference]
                    .parent
                    .expect("operator must be in a call");
                let old = self.nodes[call].children.0.as_ref().unwrap();
                let operator = old.id;
                let old_args = old.next.clone();
                let refs: Vec<_> = vars
                    .iter()
                    .map(|&var| {
                        self.reference(
                            self.variables[var].source,
                            self.nodes[value].environment,
                            var,
                        )
                    })
                    .collect();
                let args = Ids::from_slice(&refs).append(&old_args);
                self.replace_children(call, Ids::cons(operator, args));
            }
        }
        for (var, free) in &map {
            let value = values.iter().find(|(id, _)| id == var).unwrap().1;
            let vars = self.ordered_lifted_variables(free, &constants, env);
            if vars.is_empty() {
                continue;
            }
            let copies: Vec<_> = vars.iter().map(|&var| self.copy_variable(var)).collect();
            let NodeKind::Procedure(proc) = &mut self.nodes[value].kind else {
                unreachable!()
            };
            proc.parameters = Ids::from_slice(&copies).append(&proc.parameters);
            proc.minimum += vars.len();
            for &copy in &copies {
                self.variables[copy].binding = Binding::Procedure(value);
            }
            self.invalidate(value);
            let renaming: Vec<_> = vars.into_iter().zip(copies).collect();
            self.rename_lifted(value, &renaming);
        }
        for &value in &children[1..] {
            self.lambda_lift(value, &constants, env);
        }
        let body = self.nodes[function].children.values()[0];
        self.lambda_lift(body, &constants, env);
    }
    fn rename_lifted(&mut self, node: usize, renaming: &[(usize, usize)]) {
        match self.nodes[node].kind {
            NodeKind::Reference(var) => {
                if let Some((_, copy)) = renaming.iter().find(|(id, _)| *id == var) {
                    self.variables[var].references = self.variables[var].references.remove(node);
                    self.variables[*copy].references =
                        self.variables[*copy].references.adjoin(node);
                    self.nodes[node].kind = NodeKind::Reference(*copy);
                }
            }
            NodeKind::Set(var) => {
                if let Some((_, copy)) = renaming.iter().find(|(id, _)| *id == var) {
                    self.variables[var].assignments = self.variables[var].assignments.remove(node);
                    self.variables[*copy].assignments =
                        self.variables[*copy].assignments.adjoin(node);
                    self.nodes[node].kind = NodeKind::Set(*copy);
                }
            }
            _ => (),
        }
        self.nodes[node].free = None;
        for child in self.nodes[node].children.values() {
            self.rename_lifted(child, renaming);
        }
    }
    fn normalize(&mut self, node: usize, env: usize) -> usize {
        let conversion_env = self.declare(
            env,
            Declaration {
                kind: "safe".into(),
                value: atom("#f"),
                names: vec![],
                next: None,
            },
        );
        let definition = matches!(self.nodes[node].kind, NodeKind::Define(_));
        let value = if definition {
            self.nodes[node].children.values()[0]
        } else {
            node
        };
        let partial = self.partial_evaluate(value, &[]);
        let converted = self.assignment_convert(partial, conversion_env, &[]);
        self.lambda_lift(converted, &Ids::default(), &[]);
        if definition {
            self.replace_children(node, Ids::from_slice(&[converted]));
            node
        } else {
            converted
        }
    }
}

// ---- Complete expression diagnostics, outside workload timing ----

impl Compiler<'_> {
    fn renamed(&self, var: usize, env: &[(usize, String)]) -> Datum {
        atom(
            env.iter()
                .find(|(id, _)| *id == var)
                .map(|(_, name)| name.as_str())
                .unwrap_or(&self.variables[var].name),
        )
    }
    fn rename(
        &self,
        vars: &Ids,
        env: &[(usize, String)],
        counter: &mut usize,
    ) -> Vec<(usize, String)> {
        *counter += 1;
        let mut result: Vec<_> = vars
            .values()
            .into_iter()
            .map(|var| (var, format!("{}#{}", self.variables[var].name, *counter)))
            .collect();
        result.extend_from_slice(env);
        result
    }
    fn expression(&mut self, node: usize, env: &[(usize, String)], counter: &mut usize) -> Datum {
        let children = self.nodes[node].children.values();
        match self.nodes[node].kind.clone() {
            NodeKind::Constant(value) => Datum::List(vec![atom("quote"), (*value).clone()]),
            NodeKind::Reference(var) => self.renamed(var, env),
            NodeKind::Set(var) | NodeKind::Define(var) => {
                let name = if matches!(self.nodes[node].kind, NodeKind::Set(_)) {
                    "set!"
                } else {
                    "define"
                };
                Datum::List(vec![
                    atom(name),
                    self.renamed(var, env),
                    self.expression(children[0], env, counter),
                ])
            }
            NodeKind::Test | NodeKind::Conjunction | NodeKind::Disjunction | NodeKind::Future => {
                let name = match self.nodes[node].kind {
                    NodeKind::Test => "if",
                    NodeKind::Conjunction => "and",
                    NodeKind::Disjunction => "or",
                    _ => "future",
                };
                let mut result = vec![atom(name)];
                for child in children {
                    result.push(self.expression(child, env, counter));
                }
                Datum::List(result)
            }
            NodeKind::Procedure(proc) => {
                let renamed = self.rename(&proc.parameters, env, counter);
                let vars = proc.parameters.values();
                let mut params: Vec<_> = vars
                    .iter()
                    .map(|&var| self.renamed(var, &renamed))
                    .collect();
                for item in params
                    .iter_mut()
                    .take(vars.len() - usize::from(proc.rest))
                    .skip(proc.minimum)
                {
                    *item = Datum::List(vec![item.clone()]);
                }
                let formals = if proc.rest {
                    let rest = params.pop().unwrap();
                    if params.is_empty() {
                        rest
                    } else {
                        Datum::Dotted(params, Box::new(rest))
                    }
                } else {
                    Datum::List(params)
                };
                Datum::List(vec![
                    atom("lambda"),
                    formals,
                    self.expression(children[0], &renamed, counter),
                ])
            }
            NodeKind::Call if self.let_call(node) => {
                let NodeKind::Procedure(proc) = self.nodes[children[0]].kind.clone() else {
                    unreachable!()
                };
                let renamed = self.rename(&proc.parameters, env, counter);
                let mut free = Ids::default();
                for &child in &children[1..] {
                    free = free.union(&self.free_variables(child));
                }
                let form = if proc.parameters.intersection(&free).empty() {
                    "let"
                } else {
                    "letrec"
                };
                let bindings = proc
                    .parameters
                    .values()
                    .into_iter()
                    .zip(children[1..].iter().copied())
                    .map(|(var, val)| {
                        Datum::List(vec![
                            self.renamed(var, &renamed),
                            self.expression(val, &renamed, counter),
                        ])
                    })
                    .collect();
                let body = self.nodes[children[0]].children.values()[0];
                Datum::List(vec![
                    atom(form),
                    Datum::List(bindings),
                    self.expression(body, &renamed, counter),
                ])
            }
            NodeKind::Call => Datum::List(
                children
                    .into_iter()
                    .map(|child| self.expression(child, env, counter))
                    .collect(),
            ),
        }
    }
}

pub fn frontend_main() {
    let values = input().unwrap();
    if std::env::args().any(|arg| arg == "--asm-probe") {
        println!("{}", gvm::asm_probe(&values[0]));
        eprintln!("Draft assembler diagnostics only: original full compiler remains pending");
        return;
    }
    let mut compiler = Compiler::new();
    let source = compiler.source(&values[1]);
    let parsed = compiler.parse_program(source);
    let partial = std::env::args().any(|arg| arg == "--partial");
    let normalize = std::env::args().any(|arg| arg == "--normalize");
    let gvm = std::env::args().any(|arg| arg == "--gvm-raw");
    let gvm_purified = std::env::args().any(|arg| arg == "--gvm");
    let word_audit = std::env::args().any(|arg| arg == "--assembly-audit");
    let assembly = word_audit || std::env::args().any(|arg| arg == "--assembly");
    let nodes: Vec<_> = parsed
        .into_iter()
        .map(|(node, env)| {
            if normalize || gvm || gvm_purified || assembly {
                return compiler.normalize(node, env);
            }
            if !partial {
                return node;
            }
            if matches!(compiler.nodes[node].kind, NodeKind::Define(_)) {
                let child = compiler.nodes[node].children.values()[0];
                let value = compiler.partial_evaluate(child, &[]);
                compiler.replace_children(node, Ids::from_slice(&[value]));
                node
            } else {
                compiler.partial_evaluate(node, &[])
            }
        })
        .collect();
    if assembly {
        let (lines, words) = gvm::assembly(
            &mut compiler,
            &nodes,
            &gvm::Catalog::new(),
            gvm::OperandTable::new(),
            word_audit,
        );
        let lines = Datum::List(lines.into_iter().map(Datum::String).collect());
        if let Some(words) = words {
            println!(
                "{}",
                Datum::List(vec![
                    lines,
                    Datum::List(
                        words
                            .into_iter()
                            .map(|word| Datum::Atom(word.to_string()))
                            .collect()
                    )
                ])
            );
        } else {
            println!("{lines}");
        }
        eprintln!("One-pass assembly diagnostics; full canonical count remains pending");
        return;
    }
    if gvm || gvm_purified {
        println!("{}", gvm::intermediate(&mut compiler, &nodes, gvm_purified));
        eprintln!("Draft GVM diagnostics only: original full compiler validation remains pending");
        return;
    }
    let mut result = Vec::new();
    for node in nodes {
        result.push(compiler.expression(node, &[], &mut 0));
    }
    println!("{}", Datum::List(result));
    eprintln!(
        "Draft frontend only: original {}-iteration full compiler validation remains pending",
        values[0].number()
    );
}

// ---- Original full compilation loop and complete assembly predicate ----

struct AssemblyLines(Vec<String>);
impl std::fmt::Display for AssemblyLines {
    fn fmt(&self, output: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(output, "(")?;
        for (index, line) in self.0.iter().enumerate() {
            if index != 0 {
                write!(output, " ")?;
            }
            write!(output, "{line:?}")?;
        }
        write!(output, ")")
    }
}

fn compile_once(
    expression: &Datum,
    target: &Datum,
    option: &Datum,
    catalog: &gvm::Catalog,
) -> Vec<String> {
    // Primitive registrations persist across ce calls. Syntax/global environments
    // and the complete 10,000-slot virtual table belong to each compilation;
    // create the table before parsing so their live intervals overlap as in ce.
    let mut compiler = Compiler::new();
    let operands = gvm::OperandTable::new();
    assert_eq!(target.atom(), "m68000", "unsupported Compiler target");
    assert_eq!(option.atom(), "asm", "unsupported Compiler output option");
    let source = compiler.source(expression);
    let parsed = compiler.parse_program(source);
    let nodes: Vec<_> = parsed
        .into_iter()
        .map(|(node, env)| compiler.normalize(node, env))
        .collect();
    gvm::assembly(&mut compiler, &nodes, catalog, operands, false).0
}

pub fn benchmark_main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let expected: Vec<_> = values[4]
        .list()
        .iter()
        .map(|line| match line {
            Datum::String(text) => text.clone(),
            _ => panic!("expected complete assembly-line list"),
        })
        .collect();
    let catalog = gvm::Catalog::new();
    let (start, mut result) = (std::time::Instant::now(), Vec::new());
    for _ in 0..count {
        result = std::hint::black_box(compile_once(
            std::hint::black_box(&values[1]),
            std::hint::black_box(&values[2]),
            std::hint::black_box(&values[3]),
            &catalog,
        ));
    }
    assert_eq!(result, expected);
    report("compiler", count, start, AssemblyLines(result));
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ordered_union_shares_the_second_suffix_and_preserves_identity() {
        let first = Ids::from_slice(&[1, 2]);
        let second = Ids::from_slice(&[2, 3]);
        let union = first.union(&second);
        assert_eq!(union.values(), vec![1, 2, 3]);
        assert!(Rc::ptr_eq(
            union.0.as_ref().unwrap().next.0.as_ref().unwrap(),
            second.0.as_ref().unwrap()
        ));
        assert_eq!(first.values(), vec![1, 2]);
    }
    #[test]
    fn declaration_frames_share_mutable_variable_roots() {
        let input = atom("x");
        let mut compiler = Compiler::new();
        let source = compiler.source(&input);
        let env = compiler.frame(None, Ids::default());
        let declared = compiler.declare(
            env,
            Declaration {
                kind: "safe".into(),
                value: atom("#f"),
                names: vec![],
                next: None,
            },
        );
        let var = compiler.lookup(declared, "x", source, false);
        assert_eq!(compiler.lookup(env, "x", source, false), var);
        assert!(Rc::ptr_eq(
            &compiler.environments[env].vars,
            &compiler.environments[declared].vars
        ));
    }
}
