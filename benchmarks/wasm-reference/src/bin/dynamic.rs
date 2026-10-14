use r7rs_wasm_reference::{Datum, Reader, input, read_all, report};
use std::collections::{HashMap, HashSet};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Shared type arguments, union/find identity and polymorphic closures ----

type TypeId = usize;
type TypeArguments = Option<Rc<TypeArgument>>;
struct TypeArgument {
    value: TypeId,
    rest: TypeArguments,
}
fn arguments(values: &[TypeId]) -> TypeArguments {
    values.iter().rev().fold(None, |rest, &value| {
        Some(Rc::new(TypeArgument { value, rest }))
    })
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Constructor {
    Boolean,
    Character,
    Number,
    Pair,
    Procedure,
    String,
    Symbol,
    Vector,
}
#[derive(Clone)]
enum Definition {
    Concrete(Constructor, TypeArguments),
    Polymorphic(usize, Rc<Recipe>, Rc<Vec<TypeId>>),
}
struct TypeVariable {
    parent: Option<TypeId>,
    rank: usize,
    identifier: usize,
    definition: Option<Definition>,
}
struct TypeGraph {
    variables: Vec<Option<Box<TypeVariable>>>,
    vacant: Vec<TypeId>,
    counter: usize,
}
impl TypeGraph {
    fn new() -> Self {
        Self {
            variables: vec![Some(Box::new(TypeVariable {
                parent: None,
                rank: 0,
                identifier: 0,
                definition: None,
            }))],
            vacant: Vec::new(),
            counter: 0,
        }
    }
    fn variable(&mut self, definition: Option<Definition>) -> TypeId {
        self.counter += 1;
        let variable = black_box(Box::new(TypeVariable {
            parent: None,
            rank: 0,
            identifier: self.counter,
            definition,
        }));
        if let Some(id) = self.vacant.pop() {
            self.variables[id] = Some(variable);
            id
        } else {
            let id = self.variables.len();
            self.variables.push(Some(variable));
            id
        }
    }
    fn defined(&mut self, constructor: Constructor, values: &[TypeId]) -> TypeId {
        self.variable(Some(Definition::Concrete(constructor, arguments(values))))
    }
    fn null(&mut self) -> TypeId {
        // The original deliberately models null as a pair of fresh variables.
        let first = self.variable(None);
        let rest = self.variable(None);
        self.defined(Constructor::Pair, &[first, rest])
    }
    fn convert(&mut self, values: &[TypeId]) -> TypeId {
        if let Some((first, rest)) = values.split_first() {
            let rest = self.convert(rest);
            self.defined(Constructor::Pair, &[*first, rest])
        } else {
            self.null()
        }
    }
    fn find(&mut self, id: TypeId) -> TypeId {
        let parent = self.variables[id].as_ref().unwrap().parent;
        if let Some(parent) = parent {
            let representative = self.find(parent);
            self.variables[id].as_mut().unwrap().parent = Some(representative);
            representative
        } else {
            id
        }
    }
    fn link(&mut self, first: TypeId, second: TypeId) {
        let (a, b) = (
            self.variables[first].as_ref().unwrap().rank,
            self.variables[second].as_ref().unwrap().rank,
        );
        if a == b {
            self.variables[second].as_mut().unwrap().rank += 1;
            self.variables[first].as_mut().unwrap().parent = Some(second);
        } else if a > b {
            self.variables[second].as_mut().unwrap().parent = Some(first);
        } else {
            self.variables[first].as_mut().unwrap().parent = Some(second);
        }
    }
    fn dynamic(&mut self, variable: TypeId) {
        let representative = self.find(variable);
        if representative == 0 {
            return;
        }
        let definition = self.variables[representative]
            .as_ref()
            .unwrap()
            .definition
            .clone();
        self.variables[representative].as_mut().unwrap().parent = Some(0);
        if let Some(Definition::Concrete(_, arguments)) = definition {
            let mut rest = arguments;
            let mut mapped = Output::Empty;
            while let Some(argument) = rest {
                self.dynamic(argument.value);
                mapped = output_cons(Output::Empty, mapped);
                rest = argument.rest.clone();
            }
            black_box(mapped);
        }
    }
    fn equivalent(&mut self, first: TypeId, second: TypeId) {
        let (first, second) = (self.find(first), self.find(second));
        if first == second {
            return;
        }
        if second == 0 {
            self.dynamic(first);
            return;
        }
        if first == 0 {
            self.dynamic(second);
            return;
        }
        let (a, b) = (
            self.variables[first].as_ref().unwrap().definition.clone(),
            self.variables[second].as_ref().unwrap().definition.clone(),
        );
        // Link before descending into arguments, so recursive types terminate.
        match (a, b) {
            (None, None) => self.link(first, second),
            (None, Some(_)) => self.variables[first].as_mut().unwrap().parent = Some(second),
            (Some(_), None) => self.variables[second].as_mut().unwrap().parent = Some(first),
            (Some(Definition::Concrete(a, mut xs)), Some(Definition::Concrete(b, mut ys)))
                if a == b =>
            {
                self.link(first, second);
                let mut mapped = Output::Empty;
                while let Some(x) = xs {
                    let y = ys.as_ref().expect("type argument count mismatch");
                    self.equivalent(x.value, y.value);
                    mapped = output_cons(Output::Empty, mapped);
                    xs = x.rest.clone();
                    ys = y.rest.clone();
                }
                assert!(ys.is_none());
                black_box(mapped);
            }
            _ => {
                self.dynamic(first);
                self.dynamic(second);
            }
        }
    }
    fn instantiate(&mut self, variable: TypeId) -> TypeId {
        let representative = self.find(variable);
        let definition = self.variables[representative]
            .as_ref()
            .unwrap()
            .definition
            .clone();
        if let Some(Definition::Polymorphic(remaining, body, captured)) = definition {
            let variable = self.variable(None);
            let mut captured = (*captured).clone();
            captured.push(variable);
            let instance = if remaining == 1 {
                self.recipe(&body, &captured)
            } else {
                self.variable(Some(Definition::Polymorphic(
                    remaining - 1,
                    body,
                    Rc::new(captured),
                )))
            };
            self.instantiate(instance)
        } else {
            representative
        }
    }
    fn recursive_list(&mut self, element: TypeId) -> TypeId {
        let variable = self.variable(None);
        let instance = self.defined(Constructor::Pair, &[element, variable]);
        let definition = self.variables[instance]
            .as_ref()
            .unwrap()
            .definition
            .clone();
        self.variables[variable].as_mut().unwrap().definition = definition;
        variable
    }
    fn recipe(&mut self, recipe: &Recipe, environment: &[TypeId]) -> TypeId {
        match recipe {
            Recipe::Parameter(i) => environment[*i],
            Recipe::Dynamic => 0,
            Recipe::Fresh => self.variable(None),
            Recipe::Null => self.null(),
            Recipe::Concrete(constructor, children) => {
                let children: Vec<_> = children
                    .iter()
                    .map(|r| self.recipe(r, environment))
                    .collect();
                self.defined(*constructor, &children)
            }
            Recipe::Convert(children) => {
                let children: Vec<_> = children
                    .iter()
                    .map(|r| self.recipe(r, environment))
                    .collect();
                self.convert(&children)
            }
            Recipe::Forall(count, body) => self.variable(Some(Definition::Polymorphic(
                *count,
                body.clone(),
                Rc::new(environment.to_vec()),
            ))),
            Recipe::List(element) => {
                let element = self.recipe(element, environment);
                self.recursive_list(element)
            }
            Recipe::Fix(body) => {
                let variable = self.variable(None);
                let mut environment = environment.to_vec();
                environment.push(variable);
                let instance = self.recipe(body, &environment);
                let definition = self.variables[instance]
                    .as_ref()
                    .unwrap()
                    .definition
                    .clone();
                assert!(definition.is_some(), "illegal recursive type");
                self.variables[variable].as_mut().unwrap().definition = definition;
                variable
            }
        }
    }
    fn retain(&mut self, roots: &[TypeId]) {
        let mut reachable = HashSet::new();
        let mut pending = roots.to_vec();
        pending.push(0);
        while let Some(id) = pending.pop() {
            if !reachable.insert(id) {
                continue;
            }
            let variable = self.variables[id]
                .as_ref()
                .expect("reclaimed type reference");
            if let Some(parent) = variable.parent {
                pending.push(parent);
            }
            match &variable.definition {
                Some(Definition::Concrete(_, arguments)) => {
                    let mut rest = arguments.as_ref();
                    while let Some(argument) = rest {
                        pending.push(argument.value);
                        rest = argument.rest.as_ref();
                    }
                }
                Some(Definition::Polymorphic(_, _, captured)) => {
                    pending.extend(captured.iter().copied())
                }
                None => {}
            }
        }
        for (id, variable) in self.variables.iter_mut().enumerate() {
            if variable.is_some() && !reachable.contains(&id) {
                *variable = None;
                self.vacant.push(id);
            }
        }
    }
}

// ---- Original primitive type-constructor recipes ----

// Only this small constructor vocabulary is data-driven. The benchmark's
// Scheme program is parsed into the explicit AST below; it is never executed.
enum Recipe {
    Parameter(usize),
    Dynamic,
    Fresh,
    Null,
    Concrete(Constructor, Vec<Recipe>),
    Convert(Vec<Recipe>),
    Forall(usize, Rc<Recipe>),
    List(Box<Recipe>),
    Fix(Box<Recipe>),
}
fn recipe(expression: &Datum, environment: &[String]) -> Recipe {
    if let Datum::Atom(name) = expression {
        if name == "dynamic" {
            return Recipe::Dynamic;
        }
        return Recipe::Parameter(
            environment
                .iter()
                .rposition(|n| n == name)
                .expect("unbound recipe parameter"),
        );
    }
    let form = expression.list();
    let name = form[0].atom();
    match name {
        "gen-tvar" => Recipe::Fresh,
        "null" => Recipe::Null,
        "boolean" => Recipe::Concrete(Constructor::Boolean, vec![]),
        "character" => Recipe::Concrete(Constructor::Character, vec![]),
        "number" => Recipe::Concrete(Constructor::Number, vec![]),
        "charseq" => Recipe::Concrete(Constructor::String, vec![]),
        "symbol" => Recipe::Concrete(Constructor::Symbol, vec![]),
        "pair" => Recipe::Concrete(
            Constructor::Pair,
            form[1..].iter().map(|v| recipe(v, environment)).collect(),
        ),
        "array" => Recipe::Concrete(
            Constructor::Vector,
            form[1..].iter().map(|v| recipe(v, environment)).collect(),
        ),
        "procedure" => Recipe::Concrete(
            Constructor::Procedure,
            form[1..].iter().map(|v| recipe(v, environment)).collect(),
        ),
        "convert-tvars" => Recipe::Convert(
            form[1].list()[1..]
                .iter()
                .map(|v| recipe(v, environment))
                .collect(),
        ),
        "list-type" => Recipe::List(Box::new(recipe(&form[1], environment))),
        "fix" => {
            let lambda = form[1].list();
            let mut nested = environment.to_vec();
            nested.extend(lambda[1].list().iter().map(|v| v.atom().to_owned()));
            Recipe::Fix(Box::new(recipe(&lambda[2], &nested)))
        }
        "forall" | "forall2" | "forall3" | "forall4" | "forall5" => {
            let lambda = form[1].list();
            let parameters = lambda[1].list();
            let mut nested = environment.to_vec();
            nested.extend(parameters.iter().map(|v| v.atom().to_owned()));
            Recipe::Forall(parameters.len(), Rc::new(recipe(&lambda[2], &nested)))
        }
        _ => panic!("unknown original type recipe: {name}"),
    }
}

// ---- Immutable AST nodes and shared lexical bindings ----

type Ast = Rc<Node>;
type AstList = Option<Rc<AstCell>>;
struct AstCell {
    first: Ast,
    rest: AstList,
}
fn ast_list(values: &[Ast]) -> AstList {
    values.iter().rev().fold(None, |rest, first| {
        Some(Rc::new(AstCell {
            first: first.clone(),
            rest,
        }))
    })
}
fn ast_values(values: &AstList) -> Vec<Ast> {
    let (mut rest, mut result) = (values.as_ref(), Vec::new());
    while let Some(cell) = rest {
        result.push(cell.first.clone());
        rest = cell.rest.as_ref();
    }
    result
}
fn last(values: &AstList) -> Ast {
    let mut rest = values.as_ref().expect("empty AST body");
    while let Some(next) = &rest.rest {
        rest = next;
    }
    rest.first.clone()
}
struct Node {
    variable: TypeId,
    kind: Syntax,
}
enum Syntax {
    NullConstant,
    Scalar(u8, Rc<Datum>),
    SymbolConstant(usize),
    VectorConstant(AstList),
    PairConstant(Ast, Ast),
    Definition(usize),
    NullFormal,
    FormalPair(Ast, Ast),
    Variable(Ast),
    Identifier(usize),
    NullArgument,
    ArgumentPair(Ast, Ast),
    Call(Ast, Ast),
    Lambda(Ast, AstList),
    Conditional(Ast, Ast, Ast),
    Assignment(Ast, Ast),
    Cond(Vec<(Ast, AstList)>),
    Case(Ast, Vec<(AstList, AstList)>),
    And(AstList),
    Or(AstList),
    Let(u8, AstList, AstList, AstList),
    NamedLet(Ast, AstList, AstList, AstList),
    Begin(AstList),
    Empty,
    Define(Ast, Ast),
    Function(Ast, Ast, AstList),
}
type Environment = Option<Rc<EnvironmentCell>>;
struct Binding {
    name: usize,
    definition: Ast,
}
struct EnvironmentCell {
    binding: Rc<Binding>,
    rest: Environment,
}
fn extend(binding: Rc<Binding>, rest: Environment) -> Environment {
    Some(Rc::new(EnvironmentCell { binding, rest }))
}
fn lookup(environment: &Environment, name: usize) -> Option<Ast> {
    let mut rest = environment.as_ref();
    while let Some(cell) = rest {
        if cell.binding.name == name {
            return Some(cell.binding.definition.clone());
        }
        rest = cell.rest.as_ref();
    }
    None
}
fn append_environment(first: &Environment, second: Environment) -> Environment {
    match first {
        None => second,
        Some(cell) => extend(cell.binding.clone(), append_environment(&cell.rest, second)),
    }
}
type TypeEnvironment = Option<Rc<TypeBinding>>;
struct TypeBinding {
    name: usize,
    variable: TypeId,
    rest: TypeEnvironment,
}
fn append_types(first: &TypeEnvironment, second: TypeEnvironment) -> TypeEnvironment {
    match first {
        None => second,
        Some(cell) => Some(Rc::new(TypeBinding {
            name: cell.name,
            variable: cell.variable,
            rest: append_types(&cell.rest, second),
        })),
    }
}
struct Constraint {
    pair: Box<(TypeId, TypeId)>,
    rest: Option<Box<Constraint>>,
}
struct Inferencer {
    graph: TypeGraph,
    constraints: Option<Box<Constraint>>,
    groups: Vec<(String, TypeEnvironment)>,
    top: TypeEnvironment,
    symbols: Vec<String>,
    interned: HashMap<String, usize>,
    counters: [[usize; 2]; 3],
}
impl Inferencer {
    fn new() -> Self {
        let mut inferencer = Self {
            graph: TypeGraph::new(),
            constraints: None,
            groups: Vec::new(),
            top: None,
            symbols: Vec::new(),
            interned: HashMap::new(),
            counters: [[0; 2]; 3],
        };
        for definition in read_all(include_str!("../dynamic-types.scm")) {
            let definition = definition.list();
            let Datum::Atom(name) = &definition[1] else {
                continue;
            };
            if !name.ends_with("-env") {
                continue;
            }
            let mut entries = Vec::new();
            for entry in &definition[2].list()[1..] {
                let entry = entry.list();
                let key = &entry[1];
                let name = if let Datum::Atom(name) = key {
                    name.as_str()
                } else {
                    key.list()[1].atom()
                };
                let name = inferencer.intern(name);
                let recipe = recipe(&entry[2], &[]);
                let variable = inferencer.graph.recipe(&recipe, &[]);
                entries.push((name, variable));
            }
            let environment = entries
                .into_iter()
                .rev()
                .fold(None, |rest, (name, variable)| {
                    Some(Rc::new(TypeBinding {
                        name,
                        variable,
                        rest,
                    }))
                });
            inferencer.groups.push((name.clone(), environment));
        }
        assert_eq!(inferencer.groups.len(), 10);
        inferencer.reset_environment();
        inferencer
    }
    fn intern(&mut self, name: &str) -> usize {
        if let Some(id) = self.interned.get(name) {
            return *id;
        }
        let id = self.symbols.len();
        self.symbols.push(name.to_owned());
        self.interned.insert(name.to_owned(), id);
        id
    }
    fn reset_environment(&mut self) {
        let order = [
            "misc-env",
            "io-env",
            "boolean-env",
            "symbol-env",
            "number-env",
            "char-env",
            "string-env",
            "vector-env",
            "procedure-env",
            "list-env",
        ];
        self.top = self
            .groups
            .iter()
            .find(|(name, _)| name == order[9])
            .unwrap()
            .1
            .clone();
        for name in order[..9].iter().rev() {
            let group = &self.groups.iter().find(|(n, _)| n == name).unwrap().1;
            self.top = append_types(group, self.top.clone());
        }
    }
    fn identifier(&mut self, name: usize) -> TypeId {
        let mut rest = self.top.as_ref();
        while let Some(binding) = rest {
            if binding.name == name {
                return self.graph.instantiate(binding.variable);
            }
            rest = binding.rest.as_ref();
        }
        let variable = self.graph.variable(None);
        self.top = Some(Rc::new(TypeBinding {
            name,
            variable,
            rest: self.top.clone(),
        }));
        variable
    }
    fn constraint(&mut self, first: TypeId, second: TypeId) {
        self.constraints = Some(Box::new(Constraint {
            pair: Box::new((first, second)),
            rest: self.constraints.take(),
        }));
    }
    fn node(&mut self, kind: Syntax) -> Ast {
        let variable = match &kind {
            Syntax::NullConstant | Syntax::NullFormal | Syntax::NullArgument => self.graph.null(),
            Syntax::Scalar(1, _) => self.graph.defined(Constructor::Boolean, &[]),
            Syntax::Scalar(2, _) => self.graph.defined(Constructor::Character, &[]),
            Syntax::Scalar(3, _) => self.graph.defined(Constructor::Number, &[]),
            Syntax::Scalar(4, _) => self.graph.defined(Constructor::String, &[]),
            Syntax::SymbolConstant(_) => self.graph.defined(Constructor::Symbol, &[]),
            Syntax::VectorConstant(elements) => {
                let variable = self.graph.variable(None);
                for element in ast_values(elements) {
                    self.constraint(element.variable, variable);
                }
                self.graph.defined(Constructor::Vector, &[variable])
            }
            Syntax::PairConstant(first, rest)
            | Syntax::FormalPair(first, rest)
            | Syntax::ArgumentPair(first, rest) => self
                .graph
                .defined(Constructor::Pair, &[first.variable, rest.variable]),
            Syntax::Definition(_) | Syntax::Empty => self.graph.variable(None),
            Syntax::Variable(definition) => definition.variable,
            Syntax::Identifier(name) => self.identifier(*name),
            Syntax::Call(operator, arguments) => {
                let variable = self.graph.variable(None);
                let procedure = self
                    .graph
                    .defined(Constructor::Procedure, &[arguments.variable, variable]);
                self.constraint(procedure, operator.variable);
                variable
            }
            Syntax::Lambda(formals, body) => self.graph.defined(
                Constructor::Procedure,
                &[formals.variable, last(body).variable],
            ),
            Syntax::Conditional(test, yes, no) => {
                let boolean = self.graph.defined(Constructor::Boolean, &[]);
                self.constraint(boolean, test.variable);
                self.constraint(yes.variable, no.variable);
                yes.variable
            }
            Syntax::Assignment(first, second) | Syntax::Define(first, second) => {
                self.constraint(first.variable, second.variable);
                first.variable
            }
            Syntax::Cond(clauses) => {
                let variable = self.graph.variable(None);
                for (_, body) in clauses {
                    self.constraint(last(body).variable, variable);
                }
                for (guard, _) in clauses {
                    let boolean = self.graph.defined(Constructor::Boolean, &[]);
                    self.constraint(boolean, guard.variable);
                }
                variable
            }
            Syntax::Case(key, clauses) => {
                let variable = self.graph.variable(None);
                for (data, _) in clauses {
                    for datum in ast_values(data) {
                        self.constraint(datum.variable, key.variable);
                    }
                }
                for (_, body) in clauses {
                    self.constraint(last(body).variable, variable);
                }
                variable
            }
            Syntax::And(expressions) | Syntax::Or(expressions) => {
                for expression in ast_values(expressions) {
                    let boolean = self.graph.defined(Constructor::Boolean, &[]);
                    self.constraint(boolean, expression.variable);
                }
                self.graph.defined(Constructor::Boolean, &[])
            }
            Syntax::Let(_, variables, values, body) => {
                for (variable, value) in ast_values(variables).iter().zip(ast_values(values)) {
                    self.constraint(variable.variable, value.variable);
                }
                last(body).variable
            }
            Syntax::NamedLet(name, variables, values, body) => {
                let variables = ast_values(variables);
                for (variable, value) in variables.iter().zip(ast_values(values)) {
                    self.constraint(variable.variable, value.variable);
                }
                let body = last(body).variable;
                let arguments = self
                    .graph
                    .convert(&variables.iter().map(|v| v.variable).collect::<Vec<_>>());
                let procedure = self
                    .graph
                    .defined(Constructor::Procedure, &[arguments, body]);
                self.constraint(procedure, name.variable);
                body
            }
            Syntax::Begin(body) => last(body).variable,
            Syntax::Function(name, formals, body) => {
                let procedure = self.graph.defined(
                    Constructor::Procedure,
                    &[formals.variable, last(body).variable],
                );
                self.constraint(procedure, name.variable);
                name.variable
            }
            Syntax::Scalar(_, _) => unreachable!(),
        };
        Rc::new(Node { variable, kind })
    }
    fn normalize(&mut self) {
        let mut rest = self.constraints.as_ref();
        let mut mapped = Output::Empty;
        while let Some(constraint) = rest {
            self.graph.equivalent(constraint.pair.0, constraint.pair.1);
            mapped = output_cons(Output::Empty, mapped);
            rest = constraint.rest.as_ref();
        }
        black_box(mapped);
        self.constraints = None;
    }
    fn reclaim(&mut self) {
        let mut roots = Vec::new();
        for (_, environment) in &self.groups {
            let mut rest = environment.as_ref();
            while let Some(binding) = rest {
                roots.push(binding.variable);
                rest = binding.rest.as_ref();
            }
        }
        let mut rest = self.top.as_ref();
        while let Some(binding) = rest {
            roots.push(binding.variable);
            rest = binding.rest.as_ref();
        }
        self.graph.retain(&roots);
    }
}

// ---- Parsing datums, identifiers, formals and bodies ----

fn number_literal(name: &str) -> bool {
    name.parse::<f64>().is_ok()
        || name
            .split_once('/')
            .is_some_and(|(a, b)| a.parse::<i64>().is_ok() && b.parse::<i64>().is_ok())
}
fn identifier_name(value: &Datum) -> &str {
    let Datum::Atom(name) = value else {
        panic!("identifier expected");
    };
    assert!(name != "#t" && name != "#f" && !number_literal(name));
    name
}
impl Inferencer {
    fn variable_name(&mut self, datum: &Datum) -> usize {
        let name = identifier_name(datum);
        assert!(
            !matches!(
                name,
                "lambda"
                    | "if"
                    | "set!"
                    | "begin"
                    | "cond"
                    | "and"
                    | "or"
                    | "case"
                    | "let"
                    | "let*"
                    | "letrec"
                    | "do"
                    | "quasiquote"
                    | "else"
                    | "=>"
                    | "define"
                    | "unquote"
                    | "unquote-splicing"
            ),
            "illegal keyword variable"
        );
        self.intern(name)
    }
    fn datum(&mut self, value: &Datum) -> Ast {
        match value {
            Datum::Atom(name) if name == "#t" || name == "#f" => {
                self.node(Syntax::Scalar(1, Rc::new(value.clone())))
            }
            Datum::Atom(name) if number_literal(name) => {
                self.node(Syntax::Scalar(3, Rc::new(value.clone())))
            }
            Datum::Atom(name) => {
                let name = self.intern(name);
                self.node(Syntax::SymbolConstant(name))
            }
            Datum::Character(_) => self.node(Syntax::Scalar(2, Rc::new(value.clone()))),
            Datum::String(_) => self.node(Syntax::Scalar(4, Rc::new(value.clone()))),
            Datum::List(values) => self.datum_pairs(values, None),
            Datum::Dotted(values, tail) => self.datum_pairs(values, Some(tail)),
            Datum::Vector(values) => {
                let values: Vec<_> = values.iter().map(|v| self.datum(v)).collect();
                self.node(Syntax::VectorConstant(ast_list(&values)))
            }
            Datum::Bytevector(_) => panic!("original parser has no bytevector action"),
        }
    }
    fn datum_pairs(&mut self, values: &[Datum], tail: Option<&Datum>) -> Ast {
        if let Some((first, rest)) = values.split_first() {
            let first = self.datum(first);
            let rest = self.datum_pairs(rest, tail);
            self.node(Syntax::PairConstant(first, rest))
        } else if let Some(tail) = tail {
            self.datum(tail)
        } else {
            self.node(Syntax::NullConstant)
        }
    }
    fn formal(&mut self, forbidden: &Environment, value: &Datum) -> Rc<Binding> {
        let name = self.variable_name(value);
        assert!(
            lookup(forbidden, name).is_none(),
            "duplicate variable definition"
        );
        let definition = self.node(Syntax::Definition(name));
        Rc::new(Binding { name, definition })
    }
    fn formals(&mut self, formals: &Datum) -> (Environment, Ast) {
        match formals {
            Datum::List(values) => self.formal_pairs(values, None, &None),
            Datum::Dotted(values, tail) => self.formal_pairs(values, Some(tail), &None),
            _ => {
                let binding = self.formal(&None, formals);
                (extend(binding.clone(), None), binding.definition.clone())
            }
        }
    }
    fn formal_pairs(
        &mut self,
        formals: &[Datum],
        tail: Option<&Datum>,
        forbidden: &Environment,
    ) -> (Environment, Ast) {
        if let Some((first, rest)) = formals.split_first() {
            let binding = self.formal(forbidden, first);
            let forbidden = extend(binding.clone(), forbidden.clone());
            let (environment, rest) = self.formal_pairs(rest, tail, &forbidden);
            let result = self.node(Syntax::FormalPair(binding.definition.clone(), rest));
            (extend(binding, environment), result)
        } else if let Some(tail) = tail {
            let binding = self.formal(forbidden, tail);
            (extend(binding.clone(), None), binding.definition.clone())
        } else {
            let result = self.node(Syntax::NullFormal);
            (None, result)
        }
    }
    fn definitions(&mut self, formals: &[&Datum]) -> (Environment, AstList) {
        let (mut environment, mut results) = (None, Vec::new());
        for formal in formals {
            let binding = self.formal(&environment, formal);
            results.push(binding.definition.clone());
            environment = extend(binding, environment);
        }
        (environment, ast_list(&results))
    }
    fn variable(&mut self, environment: &Environment, datum: &Datum) -> Ast {
        let name = self.variable_name(datum);
        if let Some(definition) = lookup(environment, name) {
            self.node(Syntax::Variable(definition))
        } else {
            self.node(Syntax::Identifier(name))
        }
    }
    fn collect_definitions(&mut self, mut environment: Environment, body: &[Datum]) -> Environment {
        for expression in body {
            let Datum::List(form) = expression else {
                break;
            };
            let Some(Datum::Atom(name)) = form.first() else {
                break;
            };
            if name == "define" {
                if let Some(pattern) = form.get(1) {
                    let variable = match pattern {
                        Datum::Atom(name) => Some(name.as_str()),
                        Datum::List(values) | Datum::Dotted(values, _) => {
                            values.first().and_then(|v| {
                                if let Datum::Atom(name) = v {
                                    Some(name.as_str())
                                } else {
                                    None
                                }
                            })
                        }
                        _ => None,
                    };
                    if let Some(name) = variable {
                        let name = self.intern(name);
                        let definition = self.node(Syntax::Definition(name));
                        environment = extend(Rc::new(Binding { name, definition }), environment);
                    }
                }
            } else if name == "begin" {
                environment = self.collect_definitions(environment, &form[1..]);
            } else {
                break;
            }
        }
        environment
    }
    fn body(&mut self, environment: &Environment, body: &[Datum]) -> AstList {
        assert!(!body.is_empty(), "illegal empty body");
        let environment = self.collect_definitions(environment.clone(), body);
        self.commands(&environment, body)
    }
    fn expressions(&mut self, environment: &Environment, expressions: &[Datum]) -> AstList {
        let values: Vec<_> = expressions
            .iter()
            .map(|e| self.expression(environment, e))
            .collect();
        ast_list(&values)
    }
    fn argument_list(&mut self, environment: &Environment, expressions: &[Datum]) -> Ast {
        if let Some((first, rest)) = expressions.split_first() {
            let first = self.expression(environment, first);
            let rest = self.argument_list(environment, rest);
            self.node(Syntax::ArgumentPair(first, rest))
        } else {
            self.node(Syntax::NullArgument)
        }
    }
    fn commands(&mut self, environment: &Environment, commands: &[Datum]) -> AstList {
        let results: Vec<_> = commands
            .iter()
            .map(|c| self.command(environment, c))
            .collect();
        ast_list(&results)
    }
    fn command(&mut self, environment: &Environment, command: &Datum) -> Ast {
        if let Datum::List(form) = command
            && let Some(Datum::Atom(name)) = form.first()
        {
            if name == "define" {
                return self.define(environment, &form[1..]);
            }
            if name == "begin" {
                let body = self.commands(environment, &form[1..]);
                return self.node(Syntax::Begin(body));
            }
        }
        self.expression(environment, command)
    }
    fn define(&mut self, environment: &Environment, args: &[Datum]) -> Ast {
        match &args[0] {
            Datum::Atom(_) => {
                assert_eq!(args.len(), 2);
                let name = self.variable(environment, &args[0]);
                let value = self.expression(environment, &args[1]);
                self.node(Syntax::Define(name, value))
            }
            Datum::List(values) => {
                let (scope, formals) = self.formal_pairs(&values[1..], None, &None);
                let name = self.variable(environment, &values[0]);
                let scope = append_environment(&scope, environment.clone());
                let body = self.body(&scope, &args[1..]);
                self.node(Syntax::Function(name, formals, body))
            }
            Datum::Dotted(values, tail) => {
                let (scope, formals) = self.formal_pairs(&values[1..], Some(tail), &None);
                let name = self.variable(environment, &values[0]);
                let scope = append_environment(&scope, environment.clone());
                let body = self.body(&scope, &args[1..]);
                self.node(Syntax::Function(name, formals, body))
            }
            _ => panic!("invalid definition pattern"),
        }
    }
}

// ---- Parsing expression forms and binding visibility ----

impl Inferencer {
    fn expression(&mut self, environment: &Environment, expression: &Datum) -> Ast {
        if let Datum::Atom(name) = expression
            && name != "#t"
            && name != "#f"
            && !number_literal(name)
        {
            return self.variable(environment, expression);
        }
        let Datum::List(form) = expression else {
            assert!(
                !matches!(expression, Datum::Dotted(_, _)),
                "improper procedure call"
            );
            return self.datum(expression);
        };
        if form.is_empty() {
            return self.datum(expression);
        }
        let name = match &form[0] {
            Datum::Atom(name) => name.as_str(),
            _ => "",
        };
        let args = &form[1..];
        match name {
            "quote" => {
                assert_eq!(args.len(), 1);
                self.datum(&args[0])
            }
            "lambda" => {
                let (scope, formals) = self.formals(&args[0]);
                let scope = append_environment(&scope, environment.clone());
                let body = self.body(&scope, &args[1..]);
                self.node(Syntax::Lambda(formals, body))
            }
            "if" => {
                assert!(args.len() == 2 || args.len() == 3);
                let test = self.expression(environment, &args[0]);
                let yes = self.expression(environment, &args[1]);
                let no = if args.len() == 3 {
                    self.expression(environment, &args[2])
                } else {
                    self.node(Syntax::Empty)
                };
                self.node(Syntax::Conditional(test, yes, no))
            }
            "set!" => {
                assert_eq!(args.len(), 2);
                let variable = self.variable(environment, &args[0]);
                let value = self.expression(environment, &args[1]);
                self.node(Syntax::Assignment(variable, value))
            }
            "begin" => {
                let body = self.body(environment, args);
                self.node(Syntax::Begin(body))
            }
            "cond" => {
                let mut clauses = Vec::new();
                for clause in args {
                    let clause = clause.list();
                    let guard = if matches!(&clause[0], Datum::Atom(name) if name == "else") {
                        self.node(Syntax::Empty)
                    } else {
                        self.expression(environment, &clause[0])
                    };
                    let body = self.body(environment, &clause[1..]);
                    clauses.push((guard, body));
                }
                self.node(Syntax::Cond(clauses))
            }
            "case" => {
                let key = self.expression(environment, &args[0]);
                let mut clauses = Vec::new();
                for clause in &args[1..] {
                    let clause = clause.list();
                    let data = if matches!(&clause[0],Datum::Atom(s) if s=="else") {
                        vec![self.node(Syntax::Empty)]
                    } else {
                        clause[0].list().iter().map(|d| self.datum(d)).collect()
                    };
                    let body = self.body(environment, &clause[1..]);
                    clauses.push((ast_list(&data), body));
                }
                self.node(Syntax::Case(key, clauses))
            }
            "and" => {
                let expressions = self.expressions(environment, args);
                self.node(Syntax::And(expressions))
            }
            "or" => {
                let expressions = self.expressions(environment, args);
                self.node(Syntax::Or(expressions))
            }
            "let" if matches!(&args[0], Datum::Atom(_)) => self.named_let(environment, args),
            "let" => self.let_form(environment, args, 19),
            "let*" => self.let_form(environment, args, 21),
            "letrec" => self.let_form(environment, args, 22),
            "do" | "quasiquote" => panic!("not implemented by original dynamic parser: {name}"),
            _ => {
                let operator = self.expression(environment, &form[0]);
                let arguments = self.argument_list(environment, args);
                self.node(Syntax::Call(operator, arguments))
            }
        }
    }
    fn parallel_bindings(
        &mut self,
        environment: &Environment,
        bindings: &[Datum],
        recursive: bool,
    ) -> (Environment, AstList, AstList) {
        for binding in bindings {
            assert_eq!(binding.list().len(), 2);
        }
        let names: Vec<_> = bindings.iter().map(|b| &b.list()[0]).collect();
        let (scope, definitions) = self.definitions(&names);
        let environment = if recursive {
            append_environment(&scope, environment.clone())
        } else {
            environment.clone()
        };
        let values: Vec<_> = bindings
            .iter()
            .map(|b| self.expression(&environment, &b.list()[1]))
            .collect();
        (scope, definitions, ast_list(&values))
    }
    fn sequential_bindings(
        &mut self,
        environment: &Environment,
        bindings: &[Datum],
    ) -> (Environment, AstList, AstList) {
        let (mut forbidden, mut scope, mut definitions, mut values) =
            (None, environment.clone(), Vec::new(), Vec::new());
        for binding in bindings {
            let binding = binding.list();
            assert_eq!(binding.len(), 2);
            let variable = self.formal(&forbidden, &binding[0]);
            let value = self.expression(&scope, &binding[1]);
            definitions.push(variable.definition.clone());
            values.push(value);
            forbidden = extend(variable.clone(), forbidden);
            scope = extend(variable, scope);
        }
        (forbidden, ast_list(&definitions), ast_list(&values))
    }
    fn let_form(&mut self, environment: &Environment, args: &[Datum], kind: u8) -> Ast {
        let (scope, definitions, values) = if kind == 21 {
            self.sequential_bindings(environment, args[0].list())
        } else {
            self.parallel_bindings(environment, args[0].list(), kind == 22)
        };
        let scope = append_environment(&scope, environment.clone());
        let body = self.body(&scope, &args[1..]);
        self.node(Syntax::Let(kind, definitions, values, body))
    }
    fn named_let(&mut self, environment: &Environment, args: &[Datum]) -> Ast {
        let variable = self.formal(&None, &args[0]);
        let (scope, definitions, values) =
            self.parallel_bindings(environment, args[1].list(), false);
        let scope = append_environment(&scope, extend(variable.clone(), environment.clone()));
        let body = self.body(&scope, &args[2..]);
        self.node(Syntax::NamedLet(
            variable.definition.clone(),
            definitions,
            values,
            body,
        ))
    }
    fn parse_file(&mut self, filename: &str) -> AstList {
        // Read/parse each top-level form before the next. Rust buffers the file
        // text and closes the port here; the source leaves it for tracing GC.
        let source = std::fs::read_to_string(filename).expect("dynamic input file");
        let mut reader = Reader::new(&source);
        let mut program = Vec::new();
        while let Some(datum) = reader.read() {
            program.push(self.command(&None, &datum));
        }
        ast_list(&program)
    }
}

// ---- Complete tagged program materialization ----

#[derive(Clone)]
enum Output {
    Empty,
    Symbol(usize),
    Scalar(Rc<Datum>),
    Pair(Rc<OutputPair>),
    Vector(Rc<Vec<Output>>),
}
struct OutputPair {
    first: Output,
    rest: Output,
}
fn output_cons(first: Output, rest: Output) -> Output {
    Output::Pair(Rc::new(OutputPair { first, rest }))
}
fn output_list(values: &[Output]) -> Output {
    values.iter().rev().fold(Output::Empty, |rest, value| {
        output_cons(value.clone(), rest)
    })
}
impl Inferencer {
    fn symbol(&mut self, name: &str) -> Output {
        Output::Symbol(self.intern(name))
    }
    fn wrap(&mut self, mode: usize, representative: TypeId, output: Output) -> Output {
        let dynamic = representative == 0;
        self.counters[mode][usize::from(!dynamic)] += 1;
        let names = [
            ["tag", "no-tag"],
            ["untag", "no-untag"],
            ["may-untag", "no-may-untag"],
        ];
        let name = self.symbol(names[mode][usize::from(!dynamic)]);
        output_list(&[name, output])
    }
    fn tagged_list(&mut self, values: &AstList) -> Output {
        if let Some(cell) = values {
            let first = self.tagged(&cell.first);
            let rest = self.tagged_list(&cell.rest);
            output_cons(first, rest)
        } else {
            Output::Empty
        }
    }
    fn raw_datum(&mut self, datum: &Ast) -> Output {
        match &datum.kind {
            Syntax::NullConstant => Output::Empty,
            Syntax::Scalar(_, value) => Output::Scalar(value.clone()),
            Syntax::SymbolConstant(name) => Output::Symbol(*name),
            Syntax::PairConstant(first, rest) => {
                let first = self.raw_datum(first);
                let rest = self.raw_datum(rest);
                output_cons(first, rest)
            }
            Syntax::VectorConstant(elements) => {
                let elements = ast_values(elements)
                    .iter()
                    .map(|e| self.raw_datum(e))
                    .collect();
                Output::Vector(Rc::new(elements))
            }
            _ => panic!("non-datum AST in case clause"),
        }
    }
    fn binding_output(&mut self, definitions: &AstList, values: &AstList) -> Output {
        let (definitions, values) = (ast_values(definitions), ast_values(values));
        let mut bindings = Vec::new();
        for (definition, value) in definitions.iter().zip(values) {
            let definition = self.tagged(definition);
            let value = self.tagged(&value);
            bindings.push(output_list(&[definition, value]));
        }
        output_list(&bindings)
    }
    fn tagged(&mut self, ast: &Ast) -> Output {
        let representative = self.graph.find(ast.variable);
        // The exhaustive transformation deliberately constructs every output
        // node, including operations whose counts are zero in the final triple.
        match &ast.kind {
            Syntax::NullConstant => self.wrap(0, representative, Output::Empty),
            Syntax::Scalar(_, value) => self.wrap(0, representative, Output::Scalar(value.clone())),
            Syntax::SymbolConstant(name) => {
                let quote = self.symbol("quote");
                self.wrap(
                    0,
                    representative,
                    output_list(&[quote, Output::Symbol(*name)]),
                )
            }
            Syntax::VectorConstant(elements) => {
                let elements = ast_values(elements)
                    .iter()
                    .map(|e| self.tagged(e))
                    .collect();
                self.wrap(0, representative, Output::Vector(Rc::new(elements)))
            }
            Syntax::PairConstant(first, rest) => {
                let name = self.symbol("cons");
                let first = self.tagged(first);
                let rest = self.tagged(rest);
                self.wrap(0, representative, output_list(&[name, first, rest]))
            }
            Syntax::Definition(name) | Syntax::Identifier(name) => Output::Symbol(*name),
            Syntax::NullFormal | Syntax::NullArgument => Output::Empty,
            Syntax::FormalPair(first, rest) => {
                let first = self.tagged(first);
                let rest = self.tagged(rest);
                output_cons(first, rest)
            }
            Syntax::ArgumentPair(first, rest) => {
                let representative = self.graph.find(first.variable);
                let first = self.tagged(first);
                let first = self.wrap(2, representative, first);
                let rest = self.tagged(rest);
                output_cons(first, rest)
            }
            Syntax::Variable(definition) => {
                let Syntax::Definition(name) = &definition.kind else {
                    panic!("invalid variable definition");
                };
                Output::Symbol(*name)
            }
            Syntax::Call(operator, arguments) => {
                let representative = self.graph.find(operator.variable);
                let operator = self.tagged(operator);
                let operator = self.wrap(1, representative, operator);
                let arguments = self.tagged(arguments);
                output_cons(operator, arguments)
            }
            Syntax::Lambda(formals, body) => {
                let lambda = self.symbol("lambda");
                let formals = self.tagged(formals);
                let body = self.tagged_list(body);
                self.wrap(
                    0,
                    representative,
                    output_cons(lambda, output_cons(formals, body)),
                )
            }
            Syntax::Conditional(test, yes, no) => {
                let condition = self.symbol("if");
                let representative = self.graph.find(test.variable);
                let test = self.tagged(test);
                let test = self.wrap(1, representative, test);
                let yes = self.tagged(yes);
                let rest = if matches!(no.kind, Syntax::Empty) {
                    Output::Empty
                } else {
                    let no = self.tagged(no);
                    output_list(&[no])
                };
                output_cons(condition, output_cons(test, output_cons(yes, rest)))
            }
            Syntax::Assignment(first, second) => {
                let name = self.symbol("set!");
                let first = self.tagged(first);
                let second = self.tagged(second);
                output_list(&[name, first, second])
            }
            Syntax::Cond(clauses) => {
                let name = self.symbol("cond");
                let mut results = Vec::new();
                for (guard, body) in clauses {
                    let guard = if matches!(guard.kind, Syntax::Empty) {
                        self.symbol("else")
                    } else {
                        let representative = self.graph.find(guard.variable);
                        let guard = self.tagged(guard);
                        self.wrap(1, representative, guard)
                    };
                    let body = self.tagged_list(body);
                    results.push(output_cons(guard, body));
                }
                output_cons(name, output_list(&results))
            }
            Syntax::Case(key, clauses) => {
                let name = self.symbol("case");
                let key = self.tagged(key);
                let mut results = Vec::new();
                for (data, body) in clauses {
                    let data = if data
                        .as_ref()
                        .is_some_and(|d| matches!(d.first.kind, Syntax::Empty))
                    {
                        self.symbol("else")
                    } else {
                        let data: Vec<_> =
                            ast_values(data).iter().map(|d| self.raw_datum(d)).collect();
                        output_list(&data)
                    };
                    let body = self.tagged_list(body);
                    results.push(output_cons(data, body));
                }
                output_cons(name, output_cons(key, output_list(&results)))
            }
            Syntax::And(expressions) | Syntax::Or(expressions) => {
                let name = self.symbol(if matches!(ast.kind, Syntax::And(_)) {
                    "and"
                } else {
                    "or"
                });
                let mut results = Vec::new();
                for expression in ast_values(expressions) {
                    let representative = self.graph.find(expression.variable);
                    let expression = self.tagged(&expression);
                    results.push(self.wrap(1, representative, expression));
                }
                output_cons(name, output_list(&results))
            }
            Syntax::Let(kind, definitions, values, body) => {
                let name = self.symbol(match kind {
                    19 => "let",
                    21 => "let*",
                    22 => "letrec",
                    _ => unreachable!(),
                });
                let bindings = self.binding_output(definitions, values);
                let body = self.tagged_list(body);
                output_cons(name, output_cons(bindings, body))
            }
            Syntax::NamedLet(name, definitions, values, body) => {
                let binding = self.symbol("let");
                let name = self.tagged(name);
                let bindings = self.binding_output(definitions, values);
                let body = self.tagged_list(body);
                output_cons(binding, output_cons(name, output_cons(bindings, body)))
            }
            Syntax::Begin(body) => {
                let begin = self.symbol("begin");
                let body = self.tagged_list(body);
                output_cons(begin, body)
            }
            Syntax::Define(name, value) => {
                let define = self.symbol("define");
                let name = self.tagged(name);
                let value = self.tagged(value);
                output_list(&[define, name, value])
            }
            Syntax::Function(name, formals, body) => {
                let define = self.symbol("define");
                let representative = self.graph.find(name.variable);
                let name = self.tagged(name);
                let lambda = self.symbol("lambda");
                let formals = self.tagged(formals);
                let body = self.tagged_list(body);
                let lambda = self.wrap(
                    0,
                    representative,
                    output_cons(lambda, output_cons(formals, body)),
                );
                output_list(&[define, name, lambda])
            }
            Syntax::Empty => panic!("unexpected empty AST in tagged program"),
        }
    }
    fn infer(&mut self, filename: &str) -> [[usize; 2]; 3] {
        self.constraints = None;
        self.reset_environment();
        let program = self.parse_file(filename);
        self.normalize();
        self.counters = [[0; 2]; 3];
        black_box(self.tagged_list(&program));
        self.counters
    }
}

// ---- Printing and workload entry ----

struct Printed<'a>(&'a Inferencer, &'a Output);
impl Display for Printed<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.1 {
            Output::Empty => write!(f, "()"),
            Output::Symbol(name) => write!(f, "{}", self.0.symbols[*name]),
            Output::Scalar(value) => write!(f, "{value}"),
            Output::Vector(values) => {
                write!(f, "#(")?;
                for (i, value) in values.iter().enumerate() {
                    if i > 0 {
                        write!(f, " ")?;
                    }
                    write!(f, "{}", Printed(self.0, value))?;
                }
                write!(f, ")")
            }
            Output::Pair(_) => {
                write!(f, "(")?;
                let mut rest = self.1.clone();
                let mut first = true;
                while let Output::Pair(cell) = rest {
                    if !first {
                        write!(f, " ")?;
                    }
                    write!(f, "{}", Printed(self.0, &cell.first))?;
                    first = false;
                    rest = cell.rest.clone();
                }
                if !matches!(rest, Output::Empty) {
                    write!(f, " . {}", Printed(self.0, &rest))?;
                }
                write!(f, ")")
            }
        }
    }
}
struct Counters([[usize; 2]; 3]);
impl Display for Counters {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "(({} . {}) ({} . {}) ({} . {}))",
            self.0[0][0], self.0[0][1], self.0[1][0], self.0[1][1], self.0[2][0], self.0[2][1]
        )
    }
}
fn expected(value: &Datum) -> [[usize; 2]; 3] {
    let rows = value.list();
    assert_eq!(rows.len(), 3);
    std::array::from_fn(|i| {
        let Datum::Dotted(first, rest) = &rows[i] else {
            panic!("counter pair expected");
        };
        assert_eq!(first.len(), 1);
        [first[0].number(), rest.number()]
    })
}
fn main() {
    let input = input().unwrap();
    let count = input[0].number();
    let filename = input[1].atom();
    let expected = expected(&input[2]);
    let mut inferencer = Inferencer::new();
    let start = Instant::now();
    let mut result = [[0; 2]; 3];
    for _ in 0..count {
        result = black_box(inferencer.infer(black_box(filename)));
        inferencer.reclaim();
    }
    assert_eq!(result, expected);
    report("dynamic", count, start, Counters(result));
    if std::env::args().any(|a| a == "--dump") {
        inferencer.constraints = None;
        inferencer.reset_environment();
        let program = inferencer.parse_file(filename);
        inferencer.normalize();
        inferencer.counters = [[0; 2]; 3];
        let output = inferencer.tagged_list(&program);
        println!("Audit: {}", Printed(&inferencer, &output));
    }
    if std::env::args().any(|a| a == "--type-counter") {
        println!("Type counter: {}", inferencer.graph.counter);
    }
    if std::env::args().any(|a| a == "--type-identifiers") {
        let ids: Vec<_> = inferencer
            .graph
            .variables
            .iter()
            .flatten()
            .map(|v| v.identifier)
            .collect();
        println!("Type identifiers: {ids:?}");
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rank_linking_path_compression_and_dynamic_cycles() {
        let mut graph = TypeGraph::new();
        let a = graph.variable(None);
        let b = graph.variable(None);
        let c = graph.variable(None);
        graph.equivalent(a, b);
        graph.equivalent(b, c);
        assert_eq!(graph.find(a), b);
        assert_eq!(graph.find(c), b);
        assert_eq!(graph.variables[b].as_ref().unwrap().rank, 1);
        let element = graph.defined(Constructor::Number, &[]);
        let list = graph.recursive_list(element);
        graph.dynamic(list);
        assert_eq!(graph.find(list), 0);
        assert_eq!(graph.find(element), 0);
    }
    #[test]
    fn polymorphic_instances_are_fresh_and_null_is_pair() {
        let mut inferencer = Inferencer::new();
        let car = inferencer.intern("car");
        let a = inferencer.identifier(car);
        let b = inferencer.identifier(car);
        assert_ne!(a, b);
        let nil = inferencer.graph.null();
        assert!(matches!(
            inferencer.graph.variables[nil].as_ref().unwrap().definition,
            Some(Definition::Concrete(Constructor::Pair, _))
        ));
        assert!(inferencer.graph.counter > 100);
    }
    #[test]
    fn shared_variable_definition_and_recursive_binding_scope() {
        let mut inferencer = Inferencer::new();
        let ast = inferencer.expression(&None, &read_all("(lambda (x) x)")[0]);
        let Syntax::Lambda(formals, body) = &ast.kind else {
            panic!();
        };
        let Syntax::FormalPair(definition, _) = &formals.kind else {
            panic!();
        };
        let Syntax::Variable(reference) = &last(body).kind else {
            panic!();
        };
        assert!(Rc::ptr_eq(definition, reference));
        let ast = inferencer.expression(&None, &read_all("(letrec ((f (lambda (x) (f x)))) f)")[0]);
        inferencer.normalize();
        assert_ne!(inferencer.graph.find(ast.variable), 0);
    }

    #[test]
    fn retention_follows_definitions_after_union_and_reuses_only_dead_slots() {
        let mut graph = TypeGraph::new();
        let captured = graph.variable(None);
        let polymorphic = graph.variable(Some(Definition::Polymorphic(
            1,
            Rc::new(Recipe::Parameter(0)),
            Rc::new(vec![captured]),
        )));
        let dead = graph.variable(None);
        graph.dynamic(polymorphic);
        let counter = graph.counter;
        graph.retain(&[polymorphic]);
        assert_eq!(graph.find(polymorphic), 0);
        assert!(graph.variables[captured].is_some());
        assert!(graph.variables[dead].is_none());
        assert_eq!(graph.counter, counter);
        assert_eq!(graph.variable(None), dead);
        assert_eq!(
            graph.variables[dead].as_ref().unwrap().identifier,
            counter + 1
        );
        let Some(Definition::Polymorphic(_, recipe, environment)) = graph.variables[polymorphic]
            .as_ref()
            .unwrap()
            .definition
            .clone()
        else {
            panic!("union discarded the retained source definition");
        };
        assert_eq!(graph.recipe(&recipe, &environment), captured);
    }
}
