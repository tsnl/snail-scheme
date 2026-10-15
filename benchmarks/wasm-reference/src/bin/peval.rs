use r7rs_wasm_reference::{Datum, input, read_all, report};
use std::cell::RefCell;
use std::collections::HashMap;
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Mutable expression cells and exact bounded numeric constants ----

#[derive(Clone, Copy, PartialEq, Eq)]
struct Number {
    numerator: i64,
    denominator: i64,
}
impl Number {
    fn new(numerator: i64, denominator: i64) -> Self {
        assert_ne!(denominator, 0);
        let (mut a, mut b) = (numerator.abs(), denominator.abs());
        while b != 0 {
            (a, b) = (b, a % b);
        }
        let divisor = a * denominator.signum();
        Self {
            numerator: numerator / divisor,
            denominator: denominator / divisor,
        }
    }
    fn integer(numerator: i64) -> Self {
        Self {
            numerator,
            denominator: 1,
        }
    }
    fn add(self, other: Self) -> Self {
        Self::new(
            self.numerator * other.denominator + other.numerator * self.denominator,
            self.denominator * other.denominator,
        )
    }
    fn multiply(self, other: Self) -> Self {
        Self::new(
            self.numerator * other.numerator,
            self.denominator * other.denominator,
        )
    }
    fn negate(self) -> Self {
        Self::new(-self.numerator, self.denominator)
    }
    fn divide(self, other: Self) -> Self {
        Self::new(
            self.numerator * other.denominator,
            self.denominator * other.numerator,
        )
    }
}
#[derive(Clone)]
enum Expr {
    Empty,
    Symbol(usize),
    Number(Number),
    Boolean(bool),
    Pair(Cell),
    Other(Rc<Datum>),
    Unknown,
}
type Cell = Rc<RefCell<Pair>>;
struct Pair {
    first: Expr,
    rest: Expr,
}
fn cons(first: Expr, rest: Expr) -> Expr {
    Expr::Pair(Rc::new(RefCell::new(Pair { first, rest })))
}
fn list(values: &[Expr]) -> Expr {
    values
        .iter()
        .rev()
        .fold(Expr::Empty, |rest, first| cons(first.clone(), rest))
}
fn append(first: &Expr, second: Expr) -> Expr {
    match first {
        Expr::Empty => second,
        Expr::Pair(cell) => cons(
            cell.borrow().first.clone(),
            append(&cell.borrow().rest, second),
        ),
        _ => panic!("improper append input"),
    }
}
impl Expr {
    fn cell(&self) -> Cell {
        match self {
            Self::Pair(cell) => cell.clone(),
            _ => panic!("expected an expression pair"),
        }
    }
    fn first(&self) -> Self {
        self.cell().borrow().first.clone()
    }
    fn rest(&self) -> Self {
        self.cell().borrow().rest.clone()
    }
    fn tail(&self, n: usize) -> Self {
        let mut result = self.clone();
        for _ in 0..n {
            result = result.rest();
        }
        result
    }
    fn nth(&self, n: usize) -> Self {
        self.tail(n).first()
    }
    fn symbol(&self) -> usize {
        match self {
            Self::Symbol(id) => *id,
            _ => panic!("expected a symbol"),
        }
    }
    fn values(&self) -> Vec<Self> {
        let (mut rest, mut values) = (self.clone(), Vec::new());
        while let Self::Pair(cell) = rest {
            values.push(cell.borrow().first.clone());
            rest = cell.borrow().rest.clone();
        }
        assert!(matches!(rest, Self::Empty));
        values
    }
    fn empty(&self) -> bool {
        matches!(self, Self::Empty)
    }
}
fn eq(first: &Expr, second: &Expr) -> bool {
    match (first, second) {
        (Expr::Pair(a), Expr::Pair(b)) => Rc::ptr_eq(a, b),
        (Expr::Other(a), Expr::Other(b)) => Rc::ptr_eq(a, b),
        (Expr::Symbol(a), Expr::Symbol(b)) => a == b,
        (Expr::Number(a), Expr::Number(b)) => a == b,
        (Expr::Boolean(a), Expr::Boolean(b)) => a == b,
        (Expr::Empty, Expr::Empty) | (Expr::Unknown, Expr::Unknown) => true,
        _ => false,
    }
}
fn equal(first: &Expr, second: &Expr) -> bool {
    match (first, second) {
        (Expr::Pair(a), Expr::Pair(b)) => {
            equal(&a.borrow().first, &b.borrow().first) && equal(&a.borrow().rest, &b.borrow().rest)
        }
        (Expr::Other(a), Expr::Other(b)) => a == b,
        _ => eq(first, second),
    }
}

// ---- Symbol identity, immutable environments and specialization knowledge ----

#[derive(Clone, Copy)]
struct Keywords {
    quote: usize,
    condition: usize,
    begin: usize,
    binding: usize,
    recursive: usize,
    lambda: usize,
    cons: usize,
    list: usize,
    add: usize,
    multiply: usize,
}
type Environment = Option<Rc<Frame>>;
struct Frame {
    expression: Expr,
    rest: Environment,
}
fn frame(expression: Expr, rest: Environment) -> Environment {
    Some(Rc::new(Frame { expression, rest }))
}
type Substitution = Option<Rc<SubstitutionCell>>;
struct SubstitutionCell {
    entry: Option<Rc<Entry>>,
    rest: Substitution,
}
struct Entry {
    variable: usize,
    value: Expr,
}
fn binding(variable: usize, value: Expr, rest: Substitution) -> Substitution {
    Some(Rc::new(SubstitutionCell {
        entry: Some(Rc::new(Entry { variable, value })),
        rest,
    }))
}
fn lookup(variable: usize, mut bindings: &Substitution) -> Option<Expr> {
    while let Some(cell) = bindings {
        if let Some(entry) = &cell.entry
            && entry.variable == variable
        {
            return Some(entry.value.clone());
        }
        bindings = &cell.rest;
    }
    None
}
fn assoc(variable: usize, mut bindings: Expr) -> Option<Expr> {
    while let Expr::Pair(cell) = bindings {
        let entry = cell.borrow().first.clone();
        if matches!(entry.first(), Expr::Symbol(id) if id == variable) {
            return Some(entry);
        }
        bindings = cell.borrow().rest.clone();
    }
    None
}
struct Evaluator {
    symbols: Vec<String>,
    interned: HashMap<String, usize>,
    keys: Keywords,
    current_number: usize,
    changed: bool,
}
impl Evaluator {
    fn new() -> Self {
        let names = [
            "quote", "if", "begin", "let", "letrec", "lambda", "cons", "list", "+", "*",
        ];
        let interned = names
            .iter()
            .enumerate()
            .map(|(i, s)| (s.to_string(), i))
            .collect();
        let id = |name: &str| names.iter().position(|s| *s == name).unwrap();
        Self {
            symbols: names.iter().map(|s| s.to_string()).collect(),
            interned,
            keys: Keywords {
                quote: id("quote"),
                condition: id("if"),
                begin: id("begin"),
                binding: id("let"),
                recursive: id("letrec"),
                lambda: id("lambda"),
                cons: id("cons"),
                list: id("list"),
                add: id("+"),
                multiply: id("*"),
            },
            current_number: 0,
            changed: false,
        }
    }
    fn intern(&mut self, name: &str) -> usize {
        if let Some(&id) = self.interned.get(name) {
            return id;
        }
        let id = self.symbols.len();
        self.symbols.push(name.to_owned());
        self.interned.insert(name.to_owned(), id);
        id
    }
    fn parse(&mut self, datum: &Datum) -> Expr {
        match datum {
            Datum::Atom(s) if s == "#t" || s == "#f" => Expr::Boolean(s == "#t"),
            Datum::Atom(s) => match s.parse::<i64>() {
                Ok(n) => Expr::Number(Number::integer(n)),
                Err(_) => Expr::Symbol(self.intern(s)),
            },
            Datum::List(items) => list(&items.iter().map(|d| self.parse(d)).collect::<Vec<_>>()),
            Datum::Dotted(items, tail) => {
                let mut result = self.parse(tail);
                for item in items.iter().rev() {
                    result = cons(self.parse(item), result);
                }
                result
            }
            _ => Expr::Other(Rc::new(datum.clone())),
        }
    }
    fn headed(&self, expression: &Expr, keyword: usize) -> bool {
        matches!(expression, Expr::Pair(cell) if matches!(cell.borrow().first, Expr::Symbol(id) if id == keyword))
    }
    fn constant(&self, expression: &Expr) -> bool {
        !matches!(expression, Expr::Symbol(_))
            && (!matches!(expression, Expr::Pair(_)) || self.headed(expression, self.keys.quote))
    }
    fn constant_value(&self, expression: &Expr) -> Expr {
        if matches!(expression, Expr::Pair(_)) {
            expression.nth(1)
        } else {
            expression.clone()
        }
    }
    fn quote(&self, value: Expr) -> Expr {
        list(&[Expr::Symbol(self.keys.quote), value])
    }
    fn new_variable(&mut self, original: usize) -> Expr {
        self.current_number += 1;
        let name = format!("{}_{}", self.symbols[original], self.current_number);
        Expr::Symbol(self.intern(&name))
    }
    fn new_variables(&mut self, parameters: &Expr, env: &Substitution) -> Substitution {
        let entries: Vec<_> = parameters
            .values()
            .iter()
            .map(|p| {
                let original = p.symbol();
                (original, self.new_variable(original))
            })
            .collect();
        entries
            .into_iter()
            .rev()
            .fold(env.clone(), |rest, (name, value)| {
                binding(name, value, rest)
            })
    }

    // ---- Alpha renaming and substitution over the original expression forms ----

    fn alpha(&mut self, expression: &Expr, env: &Substitution) -> Expr {
        if self.constant(expression) {
            return self.quote(self.constant_value(expression));
        }
        if let Expr::Symbol(id) = expression {
            return lookup(*id, env).unwrap_or_else(|| expression.clone());
        }
        let head = expression.first();
        match head {
            Expr::Symbol(id) if id == self.keys.condition || id == self.keys.begin => {
                cons(head, self.alpha_list(&expression.rest(), env))
            }
            Expr::Symbol(id) if id == self.keys.binding || id == self.keys.recursive => {
                self.alpha_binding(expression, env, id == self.keys.recursive)
            }
            Expr::Symbol(id) if id == self.keys.lambda => {
                let renamed = self.new_variables(&expression.nth(1), env);
                let parameters = list(
                    &expression
                        .nth(1)
                        .values()
                        .iter()
                        .map(|p| lookup(p.symbol(), &renamed).unwrap())
                        .collect::<Vec<_>>(),
                );
                list(&[head, parameters, self.alpha(&expression.nth(2), &renamed)])
            }
            _ => self.alpha_list(expression, env),
        }
    }
    fn alpha_list(&mut self, expressions: &Expr, env: &Substitution) -> Expr {
        if expressions.empty() {
            return Expr::Empty;
        }
        let first = self.alpha(&expressions.first(), env);
        cons(first, self.alpha_list(&expressions.rest(), env))
    }
    fn alpha_binding(&mut self, expression: &Expr, env: &Substitution, recursive: bool) -> Expr {
        let entries = expression.nth(1).values();
        let variables = list(&entries.iter().map(Expr::first).collect::<Vec<_>>());
        let renamed = self.new_variables(&variables, env);
        let entries: Vec<_> = entries
            .iter()
            .map(|entry| {
                list(&[
                    lookup(entry.first().symbol(), &renamed).unwrap(),
                    self.alpha(&entry.nth(1), if recursive { &renamed } else { env }),
                ])
            })
            .collect();
        list(&[
            expression.first(),
            list(&entries),
            self.alpha(&expression.nth(2), &renamed),
        ])
    }
    fn beta(&self, expression: &Expr, env: &Substitution) -> Expr {
        if self.constant(expression) {
            return self.quote(self.constant_value(expression));
        }
        if let Expr::Symbol(id) = expression {
            return lookup(*id, env).unwrap_or_else(|| expression.clone());
        }
        let head = expression.first();
        match head {
            Expr::Symbol(id) if id == self.keys.condition || id == self.keys.begin => {
                cons(head, self.beta_list(&expression.rest(), env))
            }
            Expr::Symbol(id) if id == self.keys.binding || id == self.keys.recursive => {
                let entries: Vec<_> = expression
                    .nth(1)
                    .values()
                    .iter()
                    .map(|entry| list(&[entry.first(), self.beta(&entry.nth(1), env)]))
                    .collect();
                list(&[head, list(&entries), self.beta(&expression.nth(2), env)])
            }
            Expr::Symbol(id) if id == self.keys.lambda => {
                list(&[head, expression.nth(1), self.beta(&expression.nth(2), env)])
            }
            _ => self.beta_list(expression, env),
        }
    }
    fn beta_list(&self, expressions: &Expr, env: &Substitution) -> Expr {
        if expressions.empty() {
            return Expr::Empty;
        }
        cons(
            self.beta(&expressions.first(), env),
            self.beta_list(&expressions.rest(), env),
        )
    }
    fn remove_constant(&self, expressions: &Expr, knowledge: &Expr) -> Expr {
        if expressions.empty() {
            return Expr::Empty;
        }
        let rest = self.remove_constant(&expressions.rest(), &knowledge.rest());
        if matches!(knowledge.first(), Expr::Unknown) {
            cons(expressions.first(), rest)
        } else {
            rest
        }
    }
    fn extract_constant(&self, expressions: &Expr, knowledge: &Expr) -> Expr {
        if expressions.empty() {
            return Expr::Empty;
        }
        let rest = self.extract_constant(&expressions.rest(), &knowledge.rest());
        if matches!(knowledge.first(), Expr::Unknown) {
            rest
        } else {
            cons(expressions.first(), rest)
        }
    }
    fn parameter_bindings(&self, parameters: &Expr, arguments: &Expr) -> Substitution {
        if parameters.empty() {
            return None;
        }
        let entry = if matches!(arguments.first(), Expr::Unknown) {
            None
        } else {
            Some(Rc::new(Entry {
                variable: parameters.first().symbol(),
                value: self.quote(arguments.first()),
            }))
        };
        Some(Rc::new(SubstitutionCell {
            entry,
            rest: self.parameter_bindings(&parameters.rest(), &arguments.rest()),
        }))
    }
    fn specialize(&mut self, procedure: &Expr, arguments: &Expr) -> Expr {
        let parameters = procedure.nth(1);
        let specialized = list(&[
            Expr::Symbol(self.keys.lambda),
            self.remove_constant(&parameters, arguments),
            self.beta(
                &procedure.nth(2),
                &self.parameter_bindings(&parameters, arguments),
            ),
        ]);
        self.simplify(specialized)
    }
    fn partial_evaluate(&mut self, procedure: &Expr, arguments: &Expr) -> Expr {
        let renamed = self.alpha(procedure, &None);
        self.specialize(&renamed, arguments)
    }

    // ---- Primitive folding, associative flattening and residual calls ----

    fn arg_pattern(&self, expressions: &Expr) -> Expr {
        if expressions.empty() {
            return Expr::Empty;
        }
        let first = expressions.first();
        let value = if self.constant(&first) {
            self.constant_value(&first)
        } else {
            Expr::Unknown
        };
        cons(value, self.arg_pattern(&expressions.rest()))
    }
    fn flatten(&self, expressions: &Expr, operator: usize) -> Expr {
        if expressions.empty() {
            return Expr::Empty;
        }
        let first = expressions.first();
        if self.headed(&first, operator) {
            append(
                &self.flatten(&first.rest(), operator),
                self.flatten(&expressions.rest(), operator),
            )
        } else {
            cons(first, self.flatten(&expressions.rest(), operator))
        }
    }
    fn fold_global(&self, operator: usize, expressions: &Expr) -> Expr {
        let args = if operator == self.keys.add || operator == self.keys.multiply {
            self.flatten(expressions, operator)
        } else {
            expressions.clone()
        };
        let values = args.values();
        if values.iter().all(|e| self.constant(e)) {
            let constants = list(
                &values
                    .iter()
                    .map(|e| self.constant_value(e))
                    .collect::<Vec<_>>(),
            );
            if let Some(folded) = self.reduce_global(operator, &constants) {
                return folded;
            }
        }
        let pattern = self.arg_pattern(&args);
        let nonconstant = self.remove_constant(&args, &pattern);
        let constants = self.extract_constant(&args, &pattern);
        let constants = list(
            &constants
                .values()
                .iter()
                .map(|e| self.constant_value(e))
                .collect::<Vec<_>>(),
        );
        if operator == self.keys.add || operator == self.keys.multiply {
            return self.fold_associative(operator, &args, nonconstant, &constants);
        }
        if operator == self.keys.cons {
            return self.fold_cons(&args);
        }
        cons(Expr::Symbol(operator), args)
    }
    fn fold_associative(
        &self,
        operator: usize,
        args: &Expr,
        remaining: Expr,
        constants: &Expr,
    ) -> Expr {
        let Some(folded) = self.reduce_global(operator, constants) else {
            return cons(Expr::Symbol(operator), args.clone());
        };
        let identity = if operator == self.keys.add { 0 } else { 1 };
        let rest = if eq(
            &self.constant_value(&folded),
            &Expr::Number(Number::integer(identity)),
        ) {
            remaining
        } else {
            cons(folded, remaining)
        };
        cons(Expr::Symbol(operator), rest)
    }
    fn fold_cons(&self, args: &Expr) -> Expr {
        let tail = args.nth(1);
        if self.constant(&tail) && self.constant_value(&tail).empty() {
            return list(&[Expr::Symbol(self.keys.list), args.first()]);
        }
        if self.headed(&tail, self.keys.list) {
            return cons(
                Expr::Symbol(self.keys.list),
                cons(args.first(), tail.rest()),
            );
        }
        cons(Expr::Symbol(self.keys.cons), args.clone())
    }
    fn reduce_global(&self, operator: usize, arguments: &Expr) -> Option<Expr> {
        let args = arguments.values();
        let numbers: Option<Vec<_>> = args
            .iter()
            .map(|e| match e {
                Expr::Number(n) => Some(*n),
                _ => None,
            })
            .collect();
        let result = match self.symbols[operator].as_str() {
            "car" if args.len() == 1 && matches!(args[0], Expr::Pair(_)) => args[0].first(),
            "cdr" if args.len() == 1 && matches!(args[0], Expr::Pair(_)) => args[0].rest(),
            "+" => Expr::Number(numbers?.into_iter().fold(Number::integer(0), Number::add)),
            "*" => Expr::Number(
                numbers?
                    .into_iter()
                    .fold(Number::integer(1), Number::multiply),
            ),
            "-" if !args.is_empty() => {
                let values = numbers?;
                Expr::Number(if values.len() == 1 {
                    values[0].negate()
                } else {
                    values[0].add(
                        values[1..]
                            .iter()
                            .copied()
                            .fold(Number::integer(0), Number::add)
                            .negate(),
                    )
                })
            }
            "/" if args.len() > 1 => {
                let values = numbers?;
                Expr::Number(
                    values[0].divide(
                        values[1..]
                            .iter()
                            .copied()
                            .fold(Number::integer(1), Number::multiply),
                    ),
                )
            }
            "<" | "=" | ">" if args.len() == 2 => {
                let values = numbers?;
                let (a, b) = (
                    values[0].numerator * values[1].denominator,
                    values[1].numerator * values[0].denominator,
                );
                Expr::Boolean(match self.symbols[operator].as_str() {
                    "<" => a < b,
                    "=" => a == b,
                    _ => a > b,
                })
            }
            "eq?" if args.len() == 2 => Expr::Boolean(eq(&args[0], &args[1])),
            "not" if args.len() == 1 => Expr::Boolean(matches!(args[0], Expr::Boolean(false))),
            "null?" if args.len() == 1 => Expr::Boolean(args[0].empty()),
            "pair?" if args.len() == 1 => Expr::Boolean(matches!(args[0], Expr::Pair(_))),
            "symbol?" if args.len() == 1 => Expr::Boolean(matches!(args[0], Expr::Symbol(_))),
            _ => return None,
        };
        Some(self.quote(result))
    }

    // ---- Reference counts and visible lexical binding frames ----

    fn ref_count(&self, expression: &Expr, variable: usize) -> References {
        let mut result = References {
            total: 0,
            operator: 0,
            always: true,
        };
        self.count_refs(expression, variable, true, &mut result);
        result
    }
    fn count_refs(
        &self,
        expression: &Expr,
        variable: usize,
        always: bool,
        result: &mut References,
    ) {
        if self.constant(expression) {
            return;
        }
        if let Expr::Symbol(id) = expression {
            if *id == variable {
                result.total += 1;
                result.always &= always;
            }
            return;
        }
        let head = expression.first();
        match head {
            Expr::Symbol(id) if id == self.keys.condition => {
                self.count_refs(&expression.nth(1), variable, always, result);
                for value in expression.tail(2).values() {
                    self.count_refs(&value, variable, false, result);
                }
            }
            Expr::Symbol(id) if id == self.keys.begin => {
                for value in expression.rest().values() {
                    self.count_refs(&value, variable, always, result);
                }
            }
            Expr::Symbol(id) if id == self.keys.binding || id == self.keys.recursive => {
                for entry in expression.nth(1).values() {
                    self.count_refs(&entry.nth(1), variable, always, result);
                }
                self.count_refs(&expression.nth(2), variable, always, result);
            }
            Expr::Symbol(id) if id == self.keys.lambda => {
                self.count_refs(&expression.nth(2), variable, false, result)
            }
            _ => {
                for value in expression.values() {
                    self.count_refs(&value, variable, always, result);
                }
                if matches!(head, Expr::Symbol(id) if id == variable) {
                    result.operator += 1;
                }
            }
        }
    }
    fn binding_frame(&self, variable: usize, mut env: &Environment) -> Option<Expr> {
        while let Some(frame) = env {
            let expr = &frame.expression;
            if self.headed(expr, self.keys.lambda) {
                if expr
                    .nth(1)
                    .values()
                    .iter()
                    .any(|e| matches!(e, Expr::Symbol(id) if *id == variable))
                {
                    return Some(expr.clone());
                }
            } else if assoc(variable, expr.nth(1)).is_some() {
                return Some(expr.clone());
            }
            env = &frame.rest;
        }
        None
    }
    fn bound_expression(&self, variable: usize, frame: &Expr) -> Expr {
        if self.headed(frame, self.keys.lambda) {
            Expr::Unknown
        } else {
            assoc(variable, frame.nth(1)).unwrap().nth(1)
        }
    }
    fn add_binding(&mut self, value: Expr, frame: &Expr, original: usize) -> Expr {
        let bindings = frame.nth(1);
        for entry in bindings.values() {
            if equal(&entry.nth(1), &value) {
                return entry.first();
            }
        }
        let variable = self.new_variable(original);
        let mut last = bindings.cell();
        while !last.borrow().rest.empty() {
            let next = last.borrow().rest.cell();
            last = next;
        }
        last.borrow_mut().rest = list(&[list(&[variable.clone(), value])]);
        variable
    }

    // ---- Destructive simplification at real car locations ----

    fn simplify_cells(&mut self, mut expressions: Expr, env: &Environment) {
        while let Expr::Pair(cell) = expressions {
            self.simplify_cell(&cell, env);
            expressions = cell.borrow().rest.clone();
        }
    }
    fn simplify_cell(&mut self, location: &Cell, env: &Environment) {
        let expression = location.borrow().first.clone();
        if self.constant(&expression) || matches!(expression, Expr::Symbol(_)) {
            return;
        }
        let head = expression.first();
        match head {
            Expr::Symbol(id) if id == self.keys.condition => {
                self.simplify_if(location, &expression, env)
            }
            Expr::Symbol(id) if id == self.keys.begin => {
                self.simplify_begin(location, &expression, env)
            }
            Expr::Symbol(id) if id == self.keys.binding || id == self.keys.recursive => {
                self.simplify_binding(location, &expression, env)
            }
            Expr::Symbol(id) if id == self.keys.lambda => self.simplify_cell(
                &expression.tail(2).cell(),
                &frame(expression.clone(), env.clone()),
            ),
            _ => self.simplify_call(location, &expression, env),
        }
    }
    fn simplify_if(&mut self, location: &Cell, expression: &Expr, env: &Environment) {
        self.simplify_cell(&expression.tail(1).cell(), env);
        let condition = expression.nth(1);
        if !self.constant(&condition) {
            self.simplify_cells(expression.tail(2), env);
            return;
        }
        let false_value = matches!(
            self.constant_value(&condition),
            Expr::Empty | Expr::Boolean(false)
        );
        location.borrow_mut().first = if !false_value {
            expression.nth(2)
        } else if expression.values().len() == 3 {
            self.quote(Expr::Empty)
        } else {
            expression.nth(3)
        };
        self.simplify_cell(location, env);
    }
    fn simplify_begin(&mut self, location: &Cell, expression: &Expr, env: &Environment) {
        self.simplify_cells(expression.rest(), env);
        let mut cursor = expression.cell();
        while !cursor.borrow().rest.rest().empty() {
            let next = cursor.borrow().rest.cell();
            let value = next.borrow().first.clone();
            if self.constant(&value)
                || matches!(value, Expr::Symbol(_))
                || self.headed(&value, self.keys.lambda)
            {
                cursor.borrow_mut().rest = next.borrow().rest.clone();
            } else {
                cursor = next;
            }
        }
        if expression.tail(2).empty() {
            location.borrow_mut().first = expression.nth(1);
        }
    }
    fn keep_bindings(&self, location: &Cell, index: usize) -> Expr {
        let expression = location.borrow().first.clone();
        let bindings = expression.nth(1);
        if index >= bindings.values().len() {
            return Expr::Empty;
        }
        let variable = bindings.nth(index).first().symbol();
        let value = assoc(variable, bindings).unwrap().nth(1);
        let refs = self.ref_count(&expression, variable);
        let own = self.ref_count(&value, variable);
        let (total, operators) = (refs.total - own.total, refs.operator - own.operator);
        if total == 0 {
            return self.keep_bindings(location, index + 1);
        }
        let removable = self.constant(&value)
            || matches!(value, Expr::Symbol(_))
            || (self.headed(&value, self.keys.lambda)
                && total == 1
                && operators == 1
                && own.total == 0)
            || (refs.always && total == 1);
        if removable {
            location.borrow_mut().first = self.beta(&expression, &binding(variable, value, None));
            self.keep_bindings(location, index + 1)
        } else {
            cons(
                Expr::Symbol(variable),
                self.keep_bindings(location, index + 1),
            )
        }
    }
    fn simplify_binding(&mut self, location: &Cell, expression: &Expr, env: &Environment) {
        let inner = frame(expression.clone(), env.clone());
        self.simplify_cell(&expression.tail(2).cell(), &inner);
        self.simplify_binding_values(expression.nth(1), &inner);
        let keep = self.keep_bindings(location, 0);
        let current = location.borrow().first.clone();
        if keep.values().len() < current.nth(1).values().len() {
            if keep.empty() {
                location.borrow_mut().first = current.nth(2);
            } else {
                let remaining: Vec<_> = keep
                    .values()
                    .iter()
                    .map(|v| assoc(v.symbol(), current.nth(1)).unwrap())
                    .collect();
                current.tail(1).cell().borrow_mut().first = list(&remaining);
            }
            self.simplify_cell(location, env);
        } else if keep.empty() {
            location.borrow_mut().first = current.nth(2);
        }
    }
    fn simplify_binding_values(&mut self, mut bindings: Expr, env: &Environment) {
        while let Expr::Pair(cell) = bindings {
            let entry = cell.borrow().first.clone();
            self.simplify_cell(&entry.tail(1).cell(), env);
            // Specialization can append bindings while this traversal runs.
            bindings = cell.borrow().rest.clone();
        }
    }
    fn simplify_call(&mut self, location: &Cell, expression: &Expr, env: &Environment) {
        self.simplify_cells(expression.clone(), env);
        let operator = expression.first();
        if let Expr::Symbol(id) = operator {
            if let Some(frame) = self.binding_frame(id, env) {
                let procedure = self.bound_expression(id, &frame);
                if self.headed(&procedure, self.keys.lambda)
                    && expression.rest().values().iter().any(|e| self.constant(e))
                {
                    let pattern = self.arg_pattern(&expression.rest());
                    let specialized = self.specialize(&procedure, &pattern);
                    let arguments = self.remove_constant(&expression.rest(), &pattern);
                    location.borrow_mut().first =
                        cons(self.add_binding(specialized, &frame, id), arguments);
                }
            } else {
                location.borrow_mut().first = self.fold_global(id, &expression.rest());
            }
        } else if self.headed(&operator, self.keys.lambda) {
            let entries: Vec<_> = operator
                .nth(1)
                .values()
                .iter()
                .zip(expression.rest().values())
                .map(|(v, a)| list(&[v.clone(), a]))
                .collect();
            location.borrow_mut().first = list(&[
                Expr::Symbol(self.keys.binding),
                list(&entries),
                operator.nth(2),
            ]);
            self.simplify_cell(location, env);
        }
    }

    // ---- Empty-call removal and the original two-pass fixed point ----

    fn remove_empty_cells(&mut self, mut expressions: Expr, env: &Environment) {
        while let Expr::Pair(cell) = expressions {
            self.remove_empty_cell(&cell, env);
            expressions = cell.borrow().rest.clone();
        }
    }
    fn remove_empty_cell(&mut self, location: &Cell, env: &Environment) {
        let expression = location.borrow().first.clone();
        if self.constant(&expression) || matches!(expression, Expr::Symbol(_)) {
            return;
        }
        let head = expression.first();
        match head {
            Expr::Symbol(id) if id == self.keys.condition || id == self.keys.begin => {
                self.remove_empty_cells(expression.rest(), env)
            }
            Expr::Symbol(id) if id == self.keys.binding || id == self.keys.recursive => {
                let inner = frame(expression.clone(), env.clone());
                self.remove_empty_cell(&expression.tail(2).cell(), &inner);
                for entry in expression.nth(1).values() {
                    self.remove_empty_cell(&entry.tail(1).cell(), &inner);
                }
            }
            Expr::Symbol(id) if id == self.keys.lambda => {
                self.remove_empty_cell(&expression.tail(2).cell(), env)
            }
            _ => {
                self.remove_empty_cells(expression.rest(), env);
                if expression.rest().empty()
                    && let Expr::Symbol(id) = head
                    && let Some(frame) = self.binding_frame(id, env)
                {
                    let procedure = self.bound_expression(id, &frame);
                    if self.headed(&procedure, self.keys.lambda) {
                        self.changed = true;
                        location.borrow_mut().first = procedure.nth(2);
                    }
                }
            }
        }
    }
    fn simplify(&mut self, expression: Expr) -> Expr {
        let location = cons(expression, Expr::Empty).cell();
        // A recursive specialization owns its fixed-point flag separately.
        let outer_changed = self.changed;
        loop {
            self.changed = false;
            self.simplify_cell(&location, &None);
            self.remove_empty_cell(&location, &None);
            if !self.changed {
                self.changed = outer_changed;
                return location.borrow().first.clone();
            }
        }
    }

    // ---- All ten original partial-evaluation examples ----

    fn test(
        &mut self,
        examples: &[Expr],
        constants: &[Expr],
        input: &Expr,
        arguments: &Expr,
    ) -> Expr {
        self.current_number = 0;
        let number = |n| Expr::Number(Number::integer(n));
        let cases = [
            (
                &examples[0],
                list(&[constants[0].clone(), Expr::Unknown, number(1)]),
            ),
            (&examples[1], list(&[Expr::Unknown, number(1)])),
            (&examples[2], list(&[Expr::Unknown, number(1)])),
            (&examples[2], list(&[constants[1].clone(), Expr::Unknown])),
            (&examples[3], list(&[constants[2].clone(), Expr::Unknown])),
            (&examples[3], list(&[constants[3].clone(), Expr::Unknown])),
            (&examples[4], list(&[number(5), Expr::Unknown])),
            (&examples[5], Expr::Empty),
            (&examples[6], list(&[constants[4].clone()])),
            (input, arguments.clone()),
        ];
        let result: Vec<_> = cases
            .iter()
            .map(|(procedure, args)| self.partial_evaluate(procedure, args))
            .collect();
        list(&result)
    }
}
struct References {
    total: usize,
    operator: usize,
    always: bool,
}

// ---- Complete result serialization and benchmark driver ----

struct Expression<'a> {
    expression: &'a Expr,
    symbols: &'a [String],
}
impl Expression<'_> {
    fn write(&self, expression: &Expr, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        match expression {
            Expr::Empty => write!(out, "()"),
            Expr::Symbol(id) => write!(out, "{}", self.symbols[*id]),
            Expr::Number(n) if n.denominator == 1 => write!(out, "{}", n.numerator),
            Expr::Number(n) => write!(out, "{}/{}", n.numerator, n.denominator),
            Expr::Boolean(b) => write!(out, "#{}", if *b { "t" } else { "f" }),
            Expr::Other(datum) => write!(out, "{datum}"),
            Expr::Unknown => write!(out, "#<not-constant>"),
            Expr::Pair(_) => self.write_list(expression, out),
        }
    }
    fn write_list(&self, expression: &Expr, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(out, "(")?;
        let (mut rest, mut first) = (expression.clone(), true);
        while let Expr::Pair(cell) = rest {
            if !first {
                write!(out, " ")?;
            }
            self.write(&cell.borrow().first, out)?;
            rest = cell.borrow().rest.clone();
            first = false;
        }
        if !rest.empty() {
            write!(out, " . ")?;
            self.write(&rest, out)?;
        }
        write!(out, ")")
    }
}
impl Display for Expression<'_> {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.write(self.expression, out)
    }
}
fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let mut evaluator = Evaluator::new();
    let data = read_all(include_str!("../peval-data.scm"));
    let examples: Vec<_> = data[0].list()[0]
        .list()
        .iter()
        .map(|d| evaluator.parse(d))
        .collect();
    let constants: Vec<_> = data[0].list()[1]
        .list()
        .iter()
        .map(|d| evaluator.parse(d))
        .collect();
    let (input, arguments, expected) = (
        evaluator.parse(&values[1]),
        evaluator.parse(&values[2]),
        evaluator.parse(&values[3]),
    );
    let (start, mut result) = (Instant::now(), Expr::Empty);
    for _ in 0..count {
        result = black_box(evaluator.test(
            &examples,
            &constants,
            black_box(&input),
            black_box(&arguments),
        ));
    }
    assert_eq!(result.values().len(), 10);
    assert!(equal(&result.nth(9), &expected));
    report(
        "peval",
        count,
        start,
        Expression {
            expression: &result.nth(9),
            symbols: &evaluator.symbols,
        },
    );
    if std::env::args().any(|s| s == "--dump") {
        println!(
            "Audit: {}",
            Expression {
                expression: &result,
                symbols: &evaluator.symbols
            }
        );
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    fn parse(evaluator: &mut Evaluator, text: &str) -> Expr {
        evaluator.parse(&read_all(text)[0])
    }
    #[test]
    fn alpha_renaming_avoids_shadowing_and_preserves_complete_form() {
        let mut evaluator = Evaluator::new();
        let input = parse(&mut evaluator, "(lambda (x) (let ((x x)) x))");
        let result = evaluator.alpha(&input, &None);
        let expected = parse(&mut evaluator, "(lambda (x_1) (let ((x_2 x_1)) x_2))");
        assert!(equal(&result, &expected));
    }
    #[test]
    fn destructive_replacement_retains_the_selected_branch_identity() {
        let mut evaluator = Evaluator::new();
        let input = parse(
            &mut evaluator,
            "(if (quote #t) (quote (a b)) (quote (c d)))",
        );
        let selected = input.nth(2);
        let result = evaluator.simplify(input);
        assert!(eq(&selected, &result));
        let zero = parse(&mut evaluator, "(if (quote ()) (quote a) (quote b))");
        let result = evaluator.simplify(zero);
        let expected = parse(&mut evaluator, "(quote b)");
        assert!(equal(&result, &expected));
    }
    #[test]
    fn exact_constant_folding_and_primitive_false_semantics() {
        let mut evaluator = Evaluator::new();
        let divide = evaluator.intern("/");
        let result = evaluator
            .reduce_global(
                divide,
                &list(&[
                    Expr::Number(Number::integer(3)),
                    Expr::Number(Number::integer(2)),
                ]),
            )
            .unwrap();
        assert!(matches!(result.nth(1), Expr::Number(n) if n == Number::new(3, 2)));
        let not = evaluator.intern("not");
        let result = evaluator.reduce_global(not, &list(&[Expr::Empty])).unwrap();
        assert!(matches!(result.nth(1), Expr::Boolean(false)));
    }
}
