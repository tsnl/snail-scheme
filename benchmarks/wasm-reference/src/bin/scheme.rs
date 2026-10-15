use r7rs_wasm_reference::{Datum, input, report};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Scheme values and shared mutable pairs ----

#[derive(Clone)]
enum Value {
    Empty,
    Boolean(bool),
    Integer(i64),
    Real(f64),
    Symbol(usize),
    Character(char),
    String(Rc<RefCell<Vec<char>>>),
    Pair(Rc<RefCell<Pair>>),
    Vector(Rc<RefCell<Vec<Value>>>),
    Primitive(usize),
    Closure(Rc<Closure>),
}
struct Pair {
    first: Value,
    rest: Value,
}
fn cons(first: Value, rest: Value) -> Value {
    Value::Pair(Rc::new(RefCell::new(Pair { first, rest })))
}
fn list(values: &[Value]) -> Value {
    values
        .iter()
        .rev()
        .fold(Value::Empty, |rest, first| cons(first.clone(), rest))
}
fn append(first: &Value, second: Value) -> Value {
    if matches!(first, Value::Empty) {
        return second;
    }
    cons(first.first(), append(&first.rest(), second))
}
impl Value {
    fn first(&self) -> Self {
        let Self::Pair(cell) = self else {
            panic!("car of non-pair");
        };
        cell.borrow().first.clone()
    }
    fn rest(&self) -> Self {
        let Self::Pair(cell) = self else {
            panic!("cdr of non-pair");
        };
        cell.borrow().rest.clone()
    }
    fn tail(&self, n: usize) -> Self {
        let mut value = self.clone();
        for _ in 0..n {
            value = value.rest();
        }
        value
    }
    fn nth(&self, n: usize) -> Self {
        self.tail(n).first()
    }
    fn values(&self) -> Vec<Self> {
        let (mut rest, mut result) = (self.clone(), Vec::new());
        while let Self::Pair(cell) = rest {
            result.push(cell.borrow().first.clone());
            rest = cell.borrow().rest.clone();
        }
        assert!(matches!(rest, Self::Empty), "improper list");
        result
    }
    fn truth(&self) -> bool {
        !matches!(self, Self::Boolean(false))
    }
    fn symbol(&self) -> usize {
        let Self::Symbol(id) = self else {
            panic!("identifier expected");
        };
        *id
    }
    fn integer(&self) -> i64 {
        let Self::Integer(n) = self else {
            panic!("integer expected");
        };
        *n
    }
    fn real(&self) -> f64 {
        match self {
            Self::Integer(n) => *n as f64,
            Self::Real(n) => *n,
            _ => panic!("number expected"),
        }
    }
    fn character(&self) -> char {
        let Self::Character(c) = self else {
            panic!("character expected");
        };
        *c
    }
    fn string(&self) -> Rc<RefCell<Vec<char>>> {
        let Self::String(s) = self else {
            panic!("string expected");
        };
        s.clone()
    }
    fn vector(&self) -> Rc<RefCell<Vec<Value>>> {
        let Self::Vector(v) = self else {
            panic!("vector expected");
        };
        v.clone()
    }
}
fn eq(first: &Value, second: &Value) -> bool {
    match (first, second) {
        (Value::Empty, Value::Empty) => true,
        (Value::Boolean(a), Value::Boolean(b)) => a == b,
        (Value::Integer(a), Value::Integer(b)) => a == b,
        (Value::Real(a), Value::Real(b)) => a == b,
        (Value::Symbol(a), Value::Symbol(b)) => a == b,
        (Value::Character(a), Value::Character(b)) => a == b,
        (Value::Pair(a), Value::Pair(b)) => Rc::ptr_eq(a, b),
        (Value::String(a), Value::String(b)) => Rc::ptr_eq(a, b),
        (Value::Vector(a), Value::Vector(b)) => Rc::ptr_eq(a, b),
        (Value::Closure(a), Value::Closure(b)) => Rc::ptr_eq(a, b),
        (Value::Primitive(a), Value::Primitive(b)) => a == b,
        _ => false,
    }
}
fn equal(first: &Value, second: &Value) -> bool {
    match (first, second) {
        (Value::Pair(a), Value::Pair(b)) => {
            equal(&a.borrow().first, &b.borrow().first) && equal(&a.borrow().rest, &b.borrow().rest)
        }
        (Value::String(a), Value::String(b)) => *a.borrow() == *b.borrow(),
        (Value::Vector(a), Value::Vector(b)) => {
            let (a, b) = (a.borrow(), b.borrow());
            a.len() == b.len() && a.iter().zip(b.iter()).all(|(a, b)| equal(a, b))
        }
        _ => eq(first, second),
    }
}

// ---- Compiled operations and lexical environments ----

// Each node replaces one captured generator closure from scheme.scm. Compiling
// the graph remains timed. Calls of arity <= 3 keep arguments on the Rust stack;
// higher arities materialize the original argument list before application.
type Code = Rc<Operation>;
enum Operation {
    Constant(Value),
    Reference(Location),
    Assignment(Location, Code),
    Lambda(usize, bool, Code),
    Recursive(Vec<Code>, Code),
    Sequence(Code, Code),
    Conditional(Code, Code, Code),
    And(Code, Code),
    Or(Code, Code),
    Send(Code, Code, Code),
    Case(Code, Vec<(Value, Code)>, Code),
    Cons(Code, Code),
    Append(Code, Code),
    Vector(Code),
    Macro(usize, Value),
    Call0(Code),
    Call1(Code, Code),
    Call2(Code, Code, Code),
    Call3(Code, Code, Code, Code),
    CallMany(Code, Vec<Code>),
}
#[derive(Clone, Copy)]
enum Location {
    Local(usize, usize),
    Global(usize),
}
struct Closure {
    parameters: usize,
    rest: bool,
    body: Code,
    environment: Option<usize>,
}
struct Frame {
    parent: Option<usize>,
    slots: Box<[Value]>,
}
#[derive(Clone, Default)]
struct CompileEnvironment {
    chain: Option<Rc<CompileFrame>>,
    macros: Option<Rc<Macro>>,
}
struct CompileFrame {
    variables: Value,
    parent: Option<Rc<CompileFrame>>,
}
struct Macro {
    name: usize,
    procedure: Value,
    rest: Option<Rc<Macro>>,
}
impl CompileEnvironment {
    fn push(&self, variables: Value) -> Self {
        if matches!(variables, Value::Empty) {
            return self.clone();
        }
        Self {
            chain: Some(Rc::new(CompileFrame {
                variables,
                parent: self.chain.clone(),
            })),
            macros: self.macros.clone(),
        }
    }
    fn macro_binding(&self, name: &Value) -> Option<Value> {
        let Value::Symbol(name) = name else {
            return None;
        };
        let mut macros = self.macros.as_ref();
        while let Some(m) = macros {
            if m.name == *name {
                return Some(m.procedure.clone());
            }
            macros = m.rest.as_ref();
        }
        None
    }
}
fn code(operation: Operation) -> Code {
    Rc::new(operation)
}
fn constant(value: Value) -> Code {
    code(Operation::Constant(value))
}
fn combination(operator: Code, mut args: Vec<Code>) -> Code {
    match args.len() {
        0 => code(Operation::Call0(operator)),
        1 => code(Operation::Call1(operator, args.remove(0))),
        2 => code(Operation::Call2(operator, args.remove(0), args.remove(0))),
        3 => code(Operation::Call3(
            operator,
            args.remove(0),
            args.remove(0),
            args.remove(0),
        )),
        _ => code(Operation::CallMany(operator, args)),
    }
}

// ---- Global binding cells and frame lifetime ----

struct GlobalBinding {
    value: Value,
    id: usize,
    rest: Option<Rc<GlobalBinding>>,
}
struct Interpreter {
    symbols: Vec<String>,
    interned: HashMap<String, usize>,
    globals: Option<Rc<GlobalBinding>>,
    bindings: Vec<Value>,
    macros: Option<Rc<Macro>>,
    frames: Vec<Option<Frame>>,
    vacant: Vec<usize>,
    primitives: Vec<&'static str>,
}
impl Interpreter {
    fn new() -> Self {
        let mut interpreter = Self {
            symbols: Vec::new(),
            interned: HashMap::new(),
            globals: None,
            bindings: Vec::new(),
            macros: None,
            frames: Vec::new(),
            vacant: Vec::new(),
            primitives: Vec::new(),
        };
        for name in include_str!("../scheme-primitives.txt").lines() {
            let symbol = interpreter.intern(name);
            let binding = interpreter.global(symbol);
            let primitive = interpreter.primitives.len();
            interpreter.primitives.push(name);
            interpreter.assign(Location::Global(binding), None, Value::Primitive(primitive));
        }
        interpreter
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
    fn symbol(&mut self, name: &str) -> Value {
        Value::Symbol(self.intern(name))
    }
    fn parse(&mut self, datum: &Datum) -> Value {
        match datum {
            Datum::Atom(name) if name == "#t" => Value::Boolean(true),
            Datum::Atom(name) if name == "#f" => Value::Boolean(false),
            Datum::Atom(name) => {
                if let Ok(n) = name.parse() {
                    Value::Integer(n)
                } else if let Ok(n) = name.parse() {
                    Value::Real(n)
                } else {
                    self.symbol(name)
                }
            }
            Datum::Character(c) => Value::Character(*c),
            Datum::String(s) => Value::String(Rc::new(RefCell::new(s.chars().collect()))),
            Datum::List(values) => {
                let values: Vec<_> = values.iter().map(|v| self.parse(v)).collect();
                list(&values)
            }
            Datum::Dotted(values, rest) => {
                let mut result = self.parse(rest);
                for v in values.iter().rev() {
                    let first = self.parse(v);
                    result = cons(first, result);
                }
                result
            }
            Datum::Vector(values) => Value::Vector(Rc::new(RefCell::new(
                values.iter().map(|v| self.parse(v)).collect(),
            ))),
            Datum::Bytevector(_) => panic!("source interpreter does not register bytevectors"),
        }
    }
    fn named(&self, value: &Value, name: &str) -> bool {
        matches!(value, Value::Symbol(id) if self.symbols[*id] == name)
    }
    fn global(&mut self, name: usize) -> usize {
        let mut globals = self.globals.as_ref();
        while let Some(cell) = globals {
            if cell.value.first().symbol() == name {
                return cell.id;
            }
            globals = cell.rest.as_ref();
        }
        let id = self.bindings.len();
        // The same mutable (name . value) pair is shared by the association
        // cell and compiled references, whose stable id avoids an Rc cycle.
        let value = cons(Value::Symbol(name), Value::Empty);
        self.bindings.push(value.clone());
        self.globals = Some(Rc::new(GlobalBinding {
            value,
            id,
            rest: self.globals.clone(),
        }));
        id
    }
    fn location(&mut self, name: usize, environment: &CompileEnvironment) -> Location {
        let (mut chain, mut up) = (environment.chain.as_ref(), 0);
        while let Some(frame) = chain {
            let (mut variables, mut over) = (frame.variables.clone(), 0);
            while let Value::Pair(cell) = variables {
                if cell.borrow().first.symbol() == name {
                    return Location::Local(up, over);
                }
                variables = cell.borrow().rest.clone();
                over += 1;
            }
            chain = frame.parent.as_ref();
            up += 1;
        }
        Location::Global(self.global(name))
    }
    fn frame(&mut self, parent: Option<usize>, values: Vec<Value>) -> usize {
        let frame = Frame {
            parent,
            slots: black_box(values.into_boxed_slice()),
        };
        if let Some(id) = self.vacant.pop() {
            self.frames[id] = Some(frame);
            id
        } else {
            let id = self.frames.len();
            self.frames.push(Some(frame));
            id
        }
    }
    fn ancestor(&self, mut environment: Option<usize>, up: usize) -> usize {
        for _ in 0..up {
            environment = self.frames[environment.unwrap()].as_ref().unwrap().parent;
        }
        environment.expect("missing lexical environment")
    }
    fn reference(&self, location: Location, environment: Option<usize>) -> Value {
        match location {
            Location::Global(id) => self.bindings[id].rest(),
            Location::Local(up, over) => self.frames[self.ancestor(environment, up)]
                .as_ref()
                .unwrap()
                .slots[over]
                .clone(),
        }
    }
    fn assign(&mut self, location: Location, environment: Option<usize>, value: Value) -> Value {
        match location {
            Location::Global(id) => {
                let Value::Pair(cell) = &self.bindings[id] else {
                    unreachable!()
                };
                cell.borrow_mut().rest = value;
            }
            Location::Local(up, over) => {
                let id = self.ancestor(environment, up);
                self.frames[id].as_mut().unwrap().slots[over] = value;
            }
        }
        Value::Empty
    }
}

// ---- Compilation of expressions, bodies and binding forms ----

impl Interpreter {
    fn variable(&self, value: &Value) -> usize {
        let id = value.symbol();
        assert!(
            !matches!(
                self.symbols[id].as_str(),
                "quote"
                    | "quasiquote"
                    | "unquote"
                    | "unquote-splicing"
                    | "lambda"
                    | "if"
                    | "set!"
                    | "cond"
                    | "=>"
                    | "else"
                    | "and"
                    | "or"
                    | "case"
                    | "let"
                    | "let*"
                    | "letrec"
                    | "begin"
                    | "do"
                    | "define"
                    | "define-macro"
            ),
            "syntactic keyword used as variable"
        );
        id
    }
    fn compile(&mut self, expression: &Value, environment: &CompileEnvironment) -> Code {
        if let Value::Symbol(id) = expression {
            self.variable(expression);
            return code(Operation::Reference(self.location(*id, environment)));
        }
        if !matches!(expression, Value::Pair(_)) {
            return constant(expression.clone());
        }
        let operator = expression.first();
        if let Some(procedure) = environment.macro_binding(&operator) {
            let expanded = self.apply_list(procedure, expression.rest());
            return self.compile(&expanded, environment);
        }
        let name = match &operator {
            Value::Symbol(id) => self.symbols[*id].as_str(),
            _ => "",
        };
        // This exhaustive source-form dispatch keeps each syntax decision visible.
        match name {
            "quote" => constant(expression.nth(1)),
            "quasiquote" => self.quasiquote(&expression.nth(1), 1, environment),
            "unquote" | "unquote-splicing" => panic!("ill-placed unquote"),
            "lambda" => self.lambda(expression, environment),
            "if" => {
                let predicate = self.compile(&expression.nth(1), environment);
                let yes = self.compile(&expression.nth(2), environment);
                let rest = expression.tail(3);
                let no = if matches!(rest, Value::Pair(_)) {
                    self.compile(&rest.first(), environment)
                } else {
                    constant(Value::Empty)
                };
                code(Operation::Conditional(predicate, yes, no))
            }
            "set!" => {
                let id = self.variable(&expression.nth(1));
                let location = self.location(id, environment);
                let value = self.compile(&expression.nth(2), environment);
                code(Operation::Assignment(location, value))
            }
            "cond" => self.condition(&expression.rest(), environment),
            "and" => self.boolean_sequence(&expression.rest(), environment, true),
            "or" => self.boolean_sequence(&expression.rest(), environment, false),
            "case" => self.case(expression, environment),
            "let" => self.let_form(expression, environment),
            "let*" => self.let_star(expression, environment),
            "letrec" => {
                let (variables, values) = self.bindings(&expression.nth(1));
                self.recursive(variables, values, expression.tail(2), environment)
            }
            "begin" => self.sequence(&expression.rest(), environment),
            "do" => self.do_form(expression, environment),
            "define" => {
                let (name, value) = self.definition(expression);
                let location = self.location(name.symbol(), environment);
                let value = self.compile(&value, environment);
                code(Operation::Sequence(
                    code(Operation::Assignment(location, value)),
                    constant(name),
                ))
            }
            "define-macro" => {
                let (name, value) = self.definition(expression);
                let procedure = self.evaluate(&value);
                code(Operation::Macro(name.symbol(), procedure))
            }
            _ => {
                let operator = self.compile(&operator, environment);
                let args = self.compile_values(&expression.rest(), environment);
                combination(operator, args)
            }
        }
    }
    fn compile_values(
        &mut self,
        expressions: &Value,
        environment: &CompileEnvironment,
    ) -> Vec<Code> {
        let (mut rest, mut result) = (expressions.clone(), Vec::new());
        while matches!(rest, Value::Pair(_)) {
            result.push(self.compile(&rest.first(), environment));
            rest = rest.rest();
        }
        result
    }
    fn parameters(&self, mut parameters: Value) -> (Value, usize, bool) {
        let mut variables = Vec::new();
        while matches!(parameters, Value::Pair(_)) {
            let variable = parameters.first();
            self.variable(&variable);
            variables.push(variable);
            parameters = parameters.rest();
        }
        let rest = !matches!(parameters, Value::Empty);
        if rest {
            self.variable(&parameters);
            variables.push(parameters);
        }
        (list(&variables), variables.len(), rest)
    }
    fn lambda(&mut self, expression: &Value, environment: &CompileEnvironment) -> Code {
        let (variables, count, rest) = self.parameters(expression.nth(1));
        let body = self.body(expression.tail(2), environment.push(variables));
        code(Operation::Lambda(count, rest, body))
    }
    fn definition(&mut self, expression: &Value) -> (Value, Value) {
        let pattern = expression.nth(1);
        if matches!(pattern, Value::Pair(_)) {
            let name = pattern.first();
            self.variable(&name);
            let lambda = self.symbol("lambda");
            (name, cons(lambda, cons(pattern.rest(), expression.tail(2))))
        } else {
            self.variable(&pattern);
            (pattern, expression.nth(2))
        }
    }
    fn body(&mut self, mut body: Value, mut environment: CompileEnvironment) -> Code {
        let (mut variables, mut values) = (Value::Empty, Value::Empty);
        loop {
            assert!(
                matches!(body, Value::Pair(_)),
                "body must contain an evaluable expression"
            );
            let expression = body.first();
            if !matches!(expression, Value::Pair(_)) {
                break;
            }
            let operator = expression.first();
            if let Some(procedure) = environment.macro_binding(&operator) {
                let expanded = self.apply_list(procedure, expression.rest());
                body = cons(expanded, body.rest());
            } else if self.named(&operator, "begin") {
                body = append(&expression.rest(), body.rest());
            } else if self.named(&operator, "define") {
                let (variable, value) = self.definition(&expression);
                variables = cons(variable, variables);
                values = cons(value, values);
                body = body.rest();
            } else if self.named(&operator, "define-macro") {
                let (name, expression) = self.definition(&expression);
                let procedure = self.evaluate(&expression);
                environment.macros = Some(Rc::new(Macro {
                    name: name.symbol(),
                    procedure,
                    rest: environment.macros.clone(),
                }));
                body = body.rest();
            } else {
                break;
            }
        }
        if matches!(variables, Value::Empty) {
            self.sequence(&body, &environment)
        } else {
            self.recursive(variables, values, body, &environment)
        }
    }
    fn recursive(
        &mut self,
        variables: Value,
        values: Value,
        body: Value,
        environment: &CompileEnvironment,
    ) -> Code {
        if matches!(variables, Value::Empty) {
            return self.body(body, environment.clone());
        }
        let environment = environment.push(variables);
        let values = self.compile_values(&values, &environment);
        let body = self.body(body, environment);
        code(Operation::Recursive(values, body))
    }
    fn sequence(&mut self, expressions: &Value, environment: &CompileEnvironment) -> Code {
        if !matches!(expressions, Value::Pair(_)) {
            return constant(Value::Empty);
        }
        let first = self.compile(&expressions.first(), environment);
        let rest = expressions.rest();
        if !matches!(rest, Value::Pair(_)) {
            first
        } else {
            code(Operation::Sequence(
                first,
                self.sequence(&rest, environment),
            ))
        }
    }
    fn bindings(&self, bindings: &Value) -> (Value, Value) {
        let (mut rest, mut variables, mut values) = (bindings.clone(), Vec::new(), Vec::new());
        while matches!(rest, Value::Pair(_)) {
            let binding = rest.first();
            let variable = binding.first();
            self.variable(&variable);
            variables.push(variable);
            values.push(binding.nth(1));
            rest = rest.rest();
        }
        (list(&variables), list(&values))
    }
    fn let_form(&mut self, expression: &Value, environment: &CompileEnvironment) -> Code {
        let bindings = expression.nth(1);
        if matches!(bindings, Value::Symbol(_)) {
            let name = bindings;
            let (variables, values) = self.bindings(&expression.nth(2));
            let lambda = self.symbol("lambda");
            let recursive = self.symbol("letrec");
            let procedure = cons(lambda, cons(variables, expression.tail(3)));
            let operator = list(&[recursive, list(&[list(&[name.clone(), procedure])]), name]);
            self.compile(&cons(operator, values), environment)
        } else if matches!(bindings, Value::Pair(_)) {
            let (variables, values) = self.bindings(&bindings);
            let lambda = self.symbol("lambda");
            self.compile(
                &cons(cons(lambda, cons(variables, expression.tail(2))), values),
                environment,
            )
        } else {
            self.body(expression.tail(2), environment.clone())
        }
    }
    fn let_star(&mut self, expression: &Value, environment: &CompileEnvironment) -> Code {
        let bindings = expression.nth(1);
        if !matches!(bindings, Value::Pair(_)) {
            return self.body(expression.tail(2), environment.clone());
        }
        let binding = self.symbol("let");
        let sequential = self.symbol("let*");
        let nested = cons(sequential, cons(bindings.rest(), expression.tail(2)));
        self.compile(
            &list(&[binding, list(&[bindings.first()]), nested]),
            environment,
        )
    }
}

// ---- Conditional and quotation compilation ----

impl Interpreter {
    fn boolean_sequence(
        &mut self,
        expressions: &Value,
        environment: &CompileEnvironment,
        and: bool,
    ) -> Code {
        if !matches!(expressions, Value::Pair(_)) {
            return constant(Value::Boolean(and));
        }
        let first = self.compile(&expressions.first(), environment);
        let rest = expressions.rest();
        if !matches!(rest, Value::Pair(_)) {
            return first;
        }
        let rest = self.boolean_sequence(&rest, environment, and);
        code(if and {
            Operation::And(first, rest)
        } else {
            Operation::Or(first, rest)
        })
    }
    fn condition(&mut self, clauses: &Value, environment: &CompileEnvironment) -> Code {
        if !matches!(clauses, Value::Pair(_)) {
            return constant(Value::Empty);
        }
        let clause = clauses.first();
        let predicate = clause.first();
        if self.named(&predicate, "else") {
            return self.sequence(&clause.rest(), environment);
        }
        let predicate = self.compile(&predicate, environment);
        let next = self.condition(&clauses.rest(), environment);
        if !matches!(clause.rest(), Value::Pair(_)) {
            return code(Operation::Or(predicate, next));
        }
        if self.named(&clause.nth(1), "=>") {
            let handler = self.compile(&clause.nth(2), environment);
            code(Operation::Send(predicate, handler, next))
        } else {
            let body = self.sequence(&clause.rest(), environment);
            code(Operation::Conditional(predicate, body, next))
        }
    }
    fn case(&mut self, expression: &Value, environment: &CompileEnvironment) -> Code {
        let key = self.compile(&expression.nth(1), environment);
        let (mut rest, mut clauses, mut fallback) =
            (expression.tail(2), Vec::new(), constant(Value::Empty));
        while matches!(rest, Value::Pair(_)) {
            let clause = rest.first();
            let body = self.sequence(&clause.rest(), environment);
            if self.named(&clause.first(), "else") {
                fallback = body;
                break;
            }
            clauses.push((clause.first(), body));
            rest = rest.rest();
        }
        code(Operation::Case(key, clauses, fallback))
    }
    fn quasiquote(
        &mut self,
        expression: &Value,
        level: usize,
        environment: &CompileEnvironment,
    ) -> Code {
        if level == 0 {
            return self.compile(expression, environment);
        }
        match expression {
            Value::Pair(_) => {
                let first = expression.first();
                if self.named(&first, "quasiquote") {
                    self.quasiquote_list(expression, level + 1, environment)
                } else if self.named(&first, "unquote") {
                    if level == 1 {
                        self.compile(&expression.nth(1), environment)
                    } else {
                        self.quasiquote_list(expression, level - 1, environment)
                    }
                } else if self.named(&first, "unquote-splicing") {
                    assert_ne!(level, 1, "ill-placed unquote-splicing");
                    self.quasiquote_list(expression, level - 1, environment)
                } else {
                    self.quasiquote_list(expression, level, environment)
                }
            }
            Value::Vector(values) => {
                let elements = list(&values.borrow());
                let body = self.quasiquote_list(&elements, level, environment);
                code(Operation::Vector(body))
            }
            _ => constant(expression.clone()),
        }
    }
    fn quasiquote_list(
        &mut self,
        expressions: &Value,
        level: usize,
        environment: &CompileEnvironment,
    ) -> Code {
        if !matches!(expressions, Value::Pair(_)) {
            return self.quasiquote(expressions, level, environment);
        }
        let first = expressions.first();
        let rest = expressions.rest();
        if level == 1
            && matches!(first, Value::Pair(_))
            && self.named(&first.first(), "unquote-splicing")
        {
            let first = self.compile(&first.nth(1), environment);
            let rest = self.quasiquote(&rest, 1, environment);
            code(Operation::Append(first, rest))
        } else {
            let first = self.quasiquote(&first, level, environment);
            let rest = self.quasiquote(&rest, level, environment);
            code(Operation::Cons(first, rest))
        }
    }
    fn do_form(&mut self, expression: &Value, environment: &CompileEnvironment) -> Code {
        let bindings = expression.nth(1);
        let exit = expression.nth(2);
        let (variables, values) = self.bindings(&bindings);
        let outer = environment.push(list(&[Value::Boolean(false)]));
        let inner = outer.push(variables.clone());
        let predicate = self.compile(&exit.first(), &inner);
        let yes = self.sequence(&exit.rest(), &inner);
        let body = self.sequence(&expression.tail(3), &inner);
        let steps: Vec<_> = bindings
            .values()
            .iter()
            .map(|b| {
                if matches!(b.tail(2), Value::Pair(_)) {
                    b.nth(2)
                } else {
                    b.first()
                }
            })
            .collect();
        let steps = self.compile_values(&list(&steps), &inner);
        let recursive = combination(
            code(Operation::Reference(Location::Local(
                if matches!(variables, Value::Empty) {
                    0
                } else {
                    1
                },
                0,
            ))),
            steps,
        );
        let body = code(Operation::Conditional(
            predicate,
            yes,
            code(Operation::Sequence(body, recursive)),
        ));
        let procedure = code(Operation::Lambda(variables.values().len(), false, body));
        let values = self.compile_values(&values, &outer);
        code(Operation::Recursive(
            vec![procedure],
            combination(code(Operation::Reference(Location::Local(0, 0))), values),
        ))
    }
}

// ---- Execution of the compiled graph ----

impl Interpreter {
    fn evaluate(&mut self, expression: &Value) -> Value {
        let environment = CompileEnvironment {
            chain: None,
            macros: self.macros.clone(),
        };
        let compiled = black_box(self.compile(black_box(expression), &environment));
        self.execute(&compiled, None)
    }
    fn execute(&mut self, compiled: &Code, environment: Option<usize>) -> Value {
        // Atomic operations stay in one exhaustive dispatch. The sequence and
        // operand order are the source's left-to-right choices in this reference.
        match compiled.as_ref() {
            Operation::Constant(value) => value.clone(),
            Operation::Reference(location) => self.reference(*location, environment),
            Operation::Assignment(location, value) => {
                let value = self.execute(value, environment);
                self.assign(*location, environment, value)
            }
            Operation::Lambda(parameters, rest, body) => Value::Closure(Rc::new(Closure {
                parameters: *parameters,
                rest: *rest,
                body: body.clone(),
                environment,
            })),
            Operation::Recursive(values, body) => {
                let frame = self.frame(environment, vec![Value::Boolean(false); values.len()]);
                for (slot, value) in values.iter().enumerate() {
                    let value = self.execute(value, Some(frame));
                    self.frames[frame].as_mut().unwrap().slots[slot] = value;
                }
                self.execute(body, Some(frame))
            }
            Operation::Sequence(first, second) => {
                self.execute(first, environment);
                self.execute(second, environment)
            }
            Operation::Conditional(predicate, yes, no) => {
                let predicate = self.execute(predicate, environment);
                self.execute(if predicate.truth() { yes } else { no }, environment)
            }
            Operation::And(first, second) => {
                let value = self.execute(first, environment);
                if value.truth() {
                    self.execute(second, environment)
                } else {
                    value
                }
            }
            Operation::Or(first, second) => {
                let value = self.execute(first, environment);
                if value.truth() {
                    value
                } else {
                    self.execute(second, environment)
                }
            }
            Operation::Send(predicate, handler, no) => {
                let value = self.execute(predicate, environment);
                if value.truth() {
                    let handler = self.execute(handler, environment);
                    self.apply(handler, &[value])
                } else {
                    self.execute(no, environment)
                }
            }
            Operation::Case(key, clauses, no) => {
                let key = self.execute(key, environment);
                for (datums, body) in clauses {
                    if datums.values().iter().any(|datum| eq(datum, &key)) {
                        return self.execute(body, environment);
                    }
                }
                self.execute(no, environment)
            }
            Operation::Cons(first, second) => {
                let first = self.execute(first, environment);
                let second = self.execute(second, environment);
                cons(first, second)
            }
            Operation::Append(first, second) => {
                let first = self.execute(first, environment);
                let second = self.execute(second, environment);
                append(&first, second)
            }
            Operation::Vector(values) => {
                let values = self.execute(values, environment);
                Value::Vector(Rc::new(RefCell::new(values.values())))
            }
            Operation::Macro(name, procedure) => {
                self.macros = Some(Rc::new(Macro {
                    name: *name,
                    procedure: procedure.clone(),
                    rest: self.macros.clone(),
                }));
                Value::Symbol(*name)
            }
            Operation::Call0(operator) => {
                let operator = self.execute(operator, environment);
                self.apply(operator, &[])
            }
            Operation::Call1(operator, a) => {
                let operator = self.execute(operator, environment);
                let a = self.execute(a, environment);
                self.apply(operator, &[a])
            }
            Operation::Call2(operator, a, b) => {
                let operator = self.execute(operator, environment);
                let a = self.execute(a, environment);
                let b = self.execute(b, environment);
                self.apply(operator, &[a, b])
            }
            Operation::Call3(operator, a, b, c) => {
                let operator = self.execute(operator, environment);
                let a = self.execute(a, environment);
                let b = self.execute(b, environment);
                let c = self.execute(c, environment);
                self.apply(operator, &[a, b, c])
            }
            Operation::CallMany(operator, arguments) => {
                let operator = self.execute(operator, environment);
                let arguments = self.evaluate_arguments(arguments, environment);
                self.apply_list(operator, arguments)
            }
        }
    }
    fn evaluate_arguments(&mut self, arguments: &[Code], environment: Option<usize>) -> Value {
        let Some((first, rest)) = arguments.split_first() else {
            return Value::Empty;
        };
        let first = self.execute(first, environment);
        let rest = self.evaluate_arguments(rest, environment);
        cons(first, rest)
    }
    fn apply(&mut self, procedure: Value, arguments: &[Value]) -> Value {
        match procedure {
            Value::Primitive(id) => self.primitive(id, arguments),
            Value::Closure(closure) => {
                if closure.parameters == 0 {
                    assert!(arguments.is_empty());
                    return self.execute(&closure.body, closure.environment);
                }
                let fixed = closure.parameters - usize::from(closure.rest);
                if !closure.rest && closure.parameters <= 3 {
                    assert_eq!(arguments.len(), fixed);
                }
                assert!(arguments.len() >= fixed, "too few arguments");
                let mut values = arguments[..fixed].to_vec();
                if closure.rest {
                    values.push(list(&arguments[fixed..]));
                }
                let environment = Some(self.frame(closure.environment, values));
                self.execute(&closure.body, environment)
            }
            _ => panic!("attempt to call a non-procedure"),
        }
    }
    fn apply_list(&mut self, procedure: Value, arguments: Value) -> Value {
        if let Value::Closure(closure) = &procedure
            && closure.rest
        {
            let (mut rest, mut values) = (arguments, Vec::new());
            for _ in 0..closure.parameters - 1 {
                values.push(rest.first());
                rest = rest.rest();
            }
            values.push(rest);
            let environment = Some(self.frame(closure.environment, values));
            return self.execute(&closure.body, environment);
        }
        self.apply(procedure, &arguments.values())
    }
}

// ---- Primitive procedures from the original registration table ----

impl Interpreter {
    fn primitive(&mut self, id: usize, arguments: &[Value]) -> Value {
        let name = self.primitives[id];
        let a = || arguments.first().expect("missing argument");
        let b = || arguments.get(1).expect("missing argument");
        let boolean = Value::Boolean;
        match name {
            "not" => boolean(!a().truth()),
            "boolean?" => boolean(matches!(a(), Value::Boolean(_))),
            "pair?" => boolean(matches!(a(), Value::Pair(_))),
            "cons" => cons(a().clone(), b().clone()),
            "car" => a().first(),
            "cdr" => a().rest(),
            "set-car!" | "set-cdr!" => {
                let Value::Pair(pair) = a() else {
                    panic!("pair expected");
                };
                if name == "set-car!" {
                    pair.borrow_mut().first = b().clone();
                } else {
                    pair.borrow_mut().rest = b().clone();
                }
                Value::Empty
            }
            "null?" => boolean(matches!(a(), Value::Empty)),
            "list?" => {
                let mut rest = a().clone();
                while matches!(rest, Value::Pair(_)) {
                    rest = rest.rest();
                }
                boolean(matches!(rest, Value::Empty))
            }
            "list" => list(arguments),
            "length" => Value::Integer(a().values().len() as i64),
            "append" => {
                let mut result = arguments.last().cloned().unwrap_or(Value::Empty);
                for first in arguments.iter().rev().skip(1) {
                    result = append(first, result);
                }
                result
            }
            "reverse" => {
                let mut result = Value::Empty;
                let mut rest = a().clone();
                while matches!(rest, Value::Pair(_)) {
                    result = cons(rest.first(), result);
                    rest = rest.rest();
                }
                result
            }
            "list-ref" => a().nth(b().integer() as usize),
            "eq?" | "eqv?" => boolean(eq(a(), b())),
            "equal?" => boolean(equal(a(), b())),
            "memq" | "memv" | "member" => self.member(a(), b(), name == "member", false),
            "assq" | "assv" | "assoc" => self.member(a(), b(), name == "assoc", true),
            "symbol?" => boolean(matches!(a(), Value::Symbol(_))),
            "symbol->string" => Value::String(Rc::new(RefCell::new(
                self.symbols[a().symbol()].chars().collect(),
            ))),
            "string->symbol" => self.symbol(&a().string().borrow().iter().collect::<String>()),
            "number?" | "complex?" | "real?" | "rational?" => {
                boolean(matches!(a(), Value::Integer(_) | Value::Real(_)))
            }
            "integer?" => boolean(
                matches!(a(), Value::Integer(_))
                    || matches!(a(), Value::Real(n) if n.fract() == 0.0),
            ),
            "exact?" => boolean(matches!(a(), Value::Integer(_))),
            "inexact?" => boolean(matches!(a(), Value::Real(_))),
            "max" | "min" => arguments
                .iter()
                .cloned()
                .reduce(|a, b| {
                    if (a.real() > b.real()) == (name == "max") {
                        a
                    } else {
                        b
                    }
                })
                .unwrap(),
            "abs" => match a() {
                Value::Integer(n) => Value::Integer(n.abs()),
                value => Value::Real(value.real().abs()),
            },
            "floor" => Value::Real(a().real().floor()),
            "ceiling" => Value::Real(a().real().ceil()),
            "truncate" => Value::Real(a().real().trunc()),
            "round" => Value::Real(a().real().round_ties_even()),
            "exp" => Value::Real(a().real().exp()),
            "log" => Value::Real(a().real().ln()),
            "sin" => Value::Real(a().real().sin()),
            "cos" => Value::Real(a().real().cos()),
            "tan" => Value::Real(a().real().tan()),
            "asin" => Value::Real(a().real().asin()),
            "acos" => Value::Real(a().real().acos()),
            "atan" => Value::Real(if arguments.len() == 1 {
                a().real().atan()
            } else {
                a().real().atan2(b().real())
            }),
            "sqrt" => Value::Real(a().real().sqrt()),
            "expt" => Value::Real(a().real().powf(b().real())),
            "exact->inexact" => Value::Real(a().real()),
            "inexact->exact" => {
                assert_eq!(a().real().fract(), 0.0);
                Value::Integer(a().real() as i64)
            }
            "number->string" => {
                let s = match a() {
                    Value::Integer(n) => n.to_string(),
                    value => value.real().to_string(),
                };
                Value::String(Rc::new(RefCell::new(s.chars().collect())))
            }
            "string->number" => {
                let s: String = a().string().borrow().iter().collect();
                if let Ok(n) = s.parse() {
                    Value::Integer(n)
                } else if let Ok(n) = s.parse() {
                    Value::Real(n)
                } else {
                    boolean(false)
                }
            }
            "char?" => boolean(matches!(a(), Value::Character(_))),
            "char->integer" => Value::Integer(a().character() as i64),
            "integer->char" => Value::Character(char::from_u32(a().integer() as u32).unwrap()),
            "char-upcase" => Value::Character(a().character().to_uppercase().next().unwrap()),
            "char-downcase" => Value::Character(a().character().to_lowercase().next().unwrap()),
            "char-alphabetic?" => boolean(a().character().is_alphabetic()),
            "char-numeric?" => boolean(a().character().is_numeric()),
            "char-whitespace?" => boolean(a().character().is_whitespace()),
            "char-lower-case?" => boolean(a().character().is_lowercase()),
            "string?" => boolean(matches!(a(), Value::String(_))),
            "make-string" => Value::String(Rc::new(RefCell::new(vec![
                arguments
                    .get(1)
                    .map(Value::character)
                    .unwrap_or('\0');
                a().integer() as usize
            ]))),
            "string" => Value::String(Rc::new(RefCell::new(
                arguments.iter().map(Value::character).collect(),
            ))),
            "string-length" => Value::Integer(a().string().borrow().len() as i64),
            "string-ref" => Value::Character(a().string().borrow()[b().integer() as usize]),
            "string-set!" => {
                a().string().borrow_mut()[b().integer() as usize] = arguments[2].character();
                Value::Empty
            }
            "substring" => Value::String(Rc::new(RefCell::new(
                a().string().borrow()[b().integer() as usize..arguments[2].integer() as usize]
                    .to_vec(),
            ))),
            "string-append" => Value::String(Rc::new(RefCell::new(
                arguments
                    .iter()
                    .flat_map(|v| v.string().borrow().clone())
                    .collect(),
            ))),
            "vector?" => boolean(matches!(a(), Value::Vector(_))),
            "make-vector" => Value::Vector(Rc::new(RefCell::new(vec![
                arguments
                    .get(1)
                    .cloned()
                    .unwrap_or(
                        Value::Boolean(false)
                    );
                a().integer() as usize
            ]))),
            "vector" => Value::Vector(Rc::new(RefCell::new(arguments.to_vec()))),
            "vector-length" => Value::Integer(a().vector().borrow().len() as i64),
            "vector-ref" => a().vector().borrow()[b().integer() as usize].clone(),
            "vector-set!" => {
                a().vector().borrow_mut()[b().integer() as usize] = arguments[2].clone();
                Value::Empty
            }
            "procedure?" => boolean(matches!(a(), Value::Primitive(_) | Value::Closure(_))),
            "apply" => {
                let rest = arguments.last().unwrap().clone();
                let args = arguments[1..arguments.len() - 1]
                    .iter()
                    .rev()
                    .fold(rest, |rest, v| cons(v.clone(), rest));
                self.apply_list(a().clone(), args)
            }
            "map" | "for-each" => self.map(a().clone(), &arguments[1..], name == "map"),
            name if name.starts_with('c') && name.ends_with('r') && name.len() <= 6 => {
                let mut result = a().clone();
                for selector in name[1..name.len() - 1].chars().rev() {
                    result = if selector == 'a' {
                        result.first()
                    } else {
                        result.rest()
                    };
                }
                result
            }
            name if name.starts_with("string") && name.ends_with('?') => {
                let (a, b) = (a().string(), b().string());
                let (a, b) = (a.borrow(), b.borrow());
                if name.contains("-ci") {
                    let (a, b): (String, String) = (
                        a.iter().flat_map(|c| c.to_lowercase()).collect(),
                        b.iter().flat_map(|c| c.to_lowercase()).collect(),
                    );
                    boolean(compare(&a, &b, name))
                } else {
                    boolean(compare(&*a, &*b, name))
                }
            }
            name if name.starts_with("char") && name.ends_with('?') => {
                let (a, b) = (a().character(), b().character());
                if name.contains("-ci") {
                    boolean(compare(
                        &a.to_lowercase().to_string(),
                        &b.to_lowercase().to_string(),
                        name,
                    ))
                } else {
                    boolean(compare(&a, &b, name))
                }
            }
            _ => panic!("registered source primitive outside benchmark domain: {name}"),
        }
    }
    fn member(&self, item: &Value, sequence: &Value, structural: bool, association: bool) -> Value {
        let mut rest = sequence.clone();
        while matches!(rest, Value::Pair(_)) {
            let candidate = if association {
                rest.first().first()
            } else {
                rest.first()
            };
            if if structural {
                equal(item, &candidate)
            } else {
                eq(item, &candidate)
            } {
                return if association { rest.first() } else { rest };
            }
            rest = rest.rest();
        }
        Value::Boolean(false)
    }
    fn map(&mut self, procedure: Value, sequences: &[Value], collect: bool) -> Value {
        if sequences.iter().any(|v| matches!(v, Value::Empty)) {
            return Value::Empty;
        }
        let arguments: Vec<_> = sequences.iter().map(Value::first).collect();
        let value = self.apply(procedure.clone(), &arguments);
        let sequences: Vec<_> = sequences.iter().map(Value::rest).collect();
        let rest = self.map(procedure, &sequences, collect);
        if collect {
            cons(value, rest)
        } else {
            Value::Empty
        }
    }
}
fn compare<T: Ord + ?Sized>(first: &T, second: &T, name: &str) -> bool {
    if name.ends_with("<=?") {
        first <= second
    } else if name.ends_with(">=?") {
        first >= second
    } else if name.ends_with("<?") {
        first < second
    } else if name.ends_with(">?") {
        first > second
    } else {
        first == second
    }
}

// ---- Reclamation at iteration boundaries ----

// Frames can refer to closures that capture those same frames. Owned indices
// preserve those cycles without leaking an Rc cycle. Sweep only after complete
// evaluation; globals, macros and both current/previous harness values are roots.
// This policy retains dead frames until the iteration ends, unlike tracing GC
// which may collect during execution. Pair/string/vector lifetimes still use Rc.
impl Interpreter {
    fn reclaim(&mut self, roots: &[Value]) {
        let mut marked = HashSet::new();
        let mut seen = HashSet::new();
        for value in self.bindings.iter().chain(roots) {
            self.mark_value(value, &mut marked, &mut seen);
        }
        let mut macros = self.macros.as_ref();
        while let Some(m) = macros {
            self.mark_value(&m.procedure, &mut marked, &mut seen);
            macros = m.rest.as_ref();
        }
        for (id, frame) in self.frames.iter_mut().enumerate() {
            if frame.is_some() && !marked.contains(&id) {
                *frame = None;
                self.vacant.push(id);
            }
        }
    }
    fn mark_value(&self, value: &Value, frames: &mut HashSet<usize>, seen: &mut HashSet<usize>) {
        match value {
            Value::Closure(closure) => {
                self.mark_frame(closure.environment, frames, seen);
                self.mark_code(&closure.body, frames, seen);
            }
            Value::Pair(pair) if seen.insert(Rc::as_ptr(pair) as usize) => {
                self.mark_value(&pair.borrow().first, frames, seen);
                self.mark_value(&pair.borrow().rest, frames, seen);
            }
            Value::Vector(vector) if seen.insert(Rc::as_ptr(vector) as usize) => {
                for value in vector.borrow().iter() {
                    self.mark_value(value, frames, seen);
                }
            }
            _ => {}
        }
    }
    fn mark_frame(
        &self,
        frame: Option<usize>,
        frames: &mut HashSet<usize>,
        seen: &mut HashSet<usize>,
    ) {
        let Some(id) = frame else {
            return;
        };
        if !frames.insert(id) {
            return;
        }
        let frame = self.frames[id]
            .as_ref()
            .expect("closure captured a reclaimed frame");
        self.mark_frame(frame.parent, frames, seen);
        for value in &frame.slots {
            self.mark_value(value, frames, seen);
        }
    }
    fn mark_code(&self, compiled: &Code, frames: &mut HashSet<usize>, seen: &mut HashSet<usize>) {
        if !seen.insert(Rc::as_ptr(compiled) as usize) {
            return;
        }
        match compiled.as_ref() {
            Operation::Constant(value) | Operation::Macro(_, value) => {
                self.mark_value(value, frames, seen)
            }
            Operation::Reference(_) => {}
            Operation::Assignment(_, a)
            | Operation::Lambda(_, _, a)
            | Operation::Vector(a)
            | Operation::Call0(a) => self.mark_code(a, frames, seen),
            Operation::Sequence(a, b)
            | Operation::And(a, b)
            | Operation::Or(a, b)
            | Operation::Cons(a, b)
            | Operation::Append(a, b)
            | Operation::Call1(a, b) => {
                self.mark_code(a, frames, seen);
                self.mark_code(b, frames, seen);
            }
            Operation::Conditional(a, b, c)
            | Operation::Send(a, b, c)
            | Operation::Call2(a, b, c) => {
                self.mark_code(a, frames, seen);
                self.mark_code(b, frames, seen);
                self.mark_code(c, frames, seen);
            }
            Operation::Call3(a, b, c, d) => {
                self.mark_code(a, frames, seen);
                self.mark_code(b, frames, seen);
                self.mark_code(c, frames, seen);
                self.mark_code(d, frames, seen);
            }
            Operation::Recursive(values, body) | Operation::CallMany(body, values) => {
                self.mark_code(body, frames, seen);
                for value in values {
                    self.mark_code(value, frames, seen);
                }
            }
            Operation::Case(key, clauses, fallback) => {
                self.mark_code(key, frames, seen);
                self.mark_code(fallback, frames, seen);
                for (datums, body) in clauses {
                    self.mark_value(datums, frames, seen);
                    self.mark_code(body, frames, seen);
                }
            }
        }
    }
}

// ---- Result formatting and benchmark entry ----

struct Printed<'a>(&'a Interpreter, &'a Value);
impl Display for Printed<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.1 {
            Value::Empty => write!(f, "()"),
            Value::Boolean(b) => write!(f, "#{}", if *b { 't' } else { 'f' }),
            Value::Integer(n) => write!(f, "{n}"),
            Value::Real(n) => write!(f, "{n}"),
            Value::Symbol(id) => write!(f, "{}", self.0.symbols[*id]),
            Value::Character(c) => write!(f, "#\\{c}"),
            Value::String(s) => write!(f, "{:?}", s.borrow().iter().collect::<String>()),
            Value::Pair(_) => {
                write!(f, "(")?;
                let mut rest = self.1.clone();
                let mut first = true;
                while matches!(rest, Value::Pair(_)) {
                    if !first {
                        write!(f, " ")?;
                    }
                    write!(f, "{}", Printed(self.0, &rest.first()))?;
                    first = false;
                    rest = rest.rest();
                }
                if !matches!(rest, Value::Empty) {
                    write!(f, " . {}", Printed(self.0, &rest))?;
                }
                write!(f, ")")
            }
            Value::Vector(values) => {
                write!(f, "#(")?;
                for (i, value) in values.borrow().iter().enumerate() {
                    if i > 0 {
                        write!(f, " ")?;
                    }
                    write!(f, "{}", Printed(self.0, value))?;
                }
                write!(f, ")")
            }
            Value::Primitive(_) | Value::Closure(_) => write!(f, "#<procedure>"),
        }
    }
}
fn main() {
    let values = input().unwrap();
    let count = values[0].number();
    let mut interpreter = Interpreter::new();
    let expression = interpreter.parse(&values[1]);
    let expected = interpreter.parse(&values[2]);
    let start = Instant::now();
    let mut result = Value::Empty;
    for _ in 0..count {
        let next = black_box(interpreter.evaluate(black_box(&expression)));
        interpreter.reclaim(&[expression.clone(), expected.clone(), result, next.clone()]);
        result = next;
    }
    assert!(
        equal(&result, &expected),
        "wrong Scheme result: {}",
        Printed(&interpreter, &result)
    );
    report("scheme", count, start, Printed(&interpreter, &result));
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use r7rs_wasm_reference::read_all;
    fn evaluate(source: &str) -> (Interpreter, Value) {
        let mut interpreter = Interpreter::new();
        let expression = interpreter.parse(&read_all(source)[0]);
        let value = interpreter.evaluate(&expression);
        (interpreter, value)
    }
    fn result(source: &str, expected: &str) {
        let (mut interpreter, value) = evaluate(source);
        let expected = interpreter.parse(&read_all(expected)[0]);
        assert!(
            equal(&value, &expected),
            "{}",
            Printed(&interpreter, &value)
        );
    }
    #[test]
    fn local_recursion_and_shared_tail() {
        result(
            "(let () (define (copy x) (if (null? x) x (cons (car x) (copy (cdr x))))) (copy '(a b c)))",
            "(a b c)",
        );
        let (interpreter, value) =
            evaluate("(let ((x '(a b))) (cons (eq? (cdr (cons 'z x)) x) x))");
        assert_eq!(Printed(&interpreter, &value).to_string(), "(#t a b)");
    }
    #[test]
    fn lexical_mutation_rest_arguments_and_quasiquote() {
        result(
            "(let ((x 'outer)) (let ((f (lambda () x))) (set! x 'changed) (list (f) ((lambda (a . rest) rest) 'a 'b 'c))))",
            "(changed (b c))",
        );
        result("(let ((x '(b c))) `(a ,@x ,(car x)))", "(a b c b)");
        result(
            "(cond ((memq 'b '(a b c)) => (lambda (x) (cdr x))) (else #f))",
            "(c)",
        );
    }
    #[test]
    fn global_cells_and_escaped_closures_survive_reclamation() {
        let mut interpreter = Interpreter::new();
        let expression = interpreter.parse(
            &read_all(
                "(begin (define saved (let ((x 'first)) (lambda () (set! x 'next) x))) 'done)",
            )[0],
        );
        let result = interpreter.evaluate(&expression);
        interpreter.reclaim(&[result]);
        let expression = interpreter.parse(&read_all("(saved)")[0]);
        let result = interpreter.evaluate(&expression);
        assert_eq!(Printed(&interpreter, &result).to_string(), "next");
        interpreter.reclaim(&[result]);
        assert!(interpreter.frames.iter().any(Option::is_some));
        let expression = interpreter.parse(&read_all("(begin (set! saved #f) 'done)")[0]);
        let result = interpreter.evaluate(&expression);
        interpreter.reclaim(&[result]);
        assert!(interpreter.frames.iter().all(Option::is_none));
    }
    #[test]
    fn canonical_compilation_and_complete_sort() {
        let data = read_all(include_str!("../../../r7rs-benchmarks/inputs/scheme.input"));
        let mut interpreter = Interpreter::new();
        let expression = interpreter.parse(&data[1]);
        let expected = interpreter.parse(&data[2]);
        let result = interpreter.evaluate(&expression);
        assert!(equal(&result, &expected));
        interpreter.reclaim(&[result]);
        assert!(interpreter.frames.iter().all(Option::is_none));
    }

    #[test]
    fn quoted_closure_keeps_its_frame_through_compiled_code() {
        let (mut interpreter, captured) =
            evaluate("(let ((x 'first)) (lambda () (set! x 'next) x))");
        let expression = list(&[
            interpreter.symbol("lambda"),
            Value::Empty,
            list(&[interpreter.symbol("quote"), captured]),
        ]);
        let outer = interpreter.evaluate(&expression);
        drop(expression);
        for _ in 0..3 {
            interpreter.reclaim(std::slice::from_ref(&outer));
            let temporary = interpreter.parse(&read_all("((lambda (x) x) 'unrelated)")[0]);
            interpreter.evaluate(&temporary);
        }
        let inner = interpreter.apply(outer, &[]);
        let result = interpreter.apply(inner, &[]);
        assert_eq!(Printed(&interpreter, &result).to_string(), "next");
        interpreter.reclaim(&[result]);
        assert!(interpreter.frames.iter().all(Option::is_none));
    }
}
