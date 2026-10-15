use r7rs_wasm_reference::{Datum, input, report};
use std::fmt::{self, Display};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Shared expression trees ----

#[derive(Clone, Debug, PartialEq, Eq)]
enum Expression {
    Number(i64),
    Symbol(Rc<str>),
    Operation(Rc<Operation>),
}

#[derive(Debug, PartialEq, Eq)]
struct Operation {
    operator: Operator,
    arguments: Vec<Expression>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Operator {
    Add,
    Subtract,
    Multiply,
    Divide,
}

impl Operator {
    fn parse(symbol: &str) -> Self {
        match symbol {
            "+" => Self::Add,
            "-" => Self::Subtract,
            "*" => Self::Multiply,
            "/" => Self::Divide,
            _ => panic!("no derivation method available"),
        }
    }

    fn symbol(self) -> &'static str {
        match self {
            Self::Add => "+",
            Self::Subtract => "-",
            Self::Multiply => "*",
            Self::Divide => "/",
        }
    }
}

impl Expression {
    fn call(operator: Operator, arguments: Vec<Self>) -> Self {
        Self::Operation(Rc::new(Operation {
            operator,
            arguments,
        }))
    }

    fn parse(datum: &Datum) -> Self {
        match datum {
            Datum::Atom(value) => match value.parse() {
                Ok(number) => Self::Number(number),
                Err(_) => Self::Symbol(Rc::from(value.as_str())),
            },
            Datum::List(values) => Self::call(
                Operator::parse(values[0].atom()),
                values[1..].iter().map(Self::parse).collect(),
            ),
            _ => panic!("expected an arithmetic expression"),
        }
    }
}

// ---- Symbolic differentiation ----

// Compound input subexpressions remain shared, as they are in the Scheme
// product rule. Each iteration allocates a fresh derivative expression tree.
fn derivative(expression: &Expression) -> Expression {
    match expression {
        Expression::Number(_) => Expression::Number(0),
        Expression::Symbol(name) => Expression::Number(i64::from(name.as_ref() == "x")),
        Expression::Operation(call) => match call.operator {
            Operator::Add | Operator::Subtract => Expression::call(
                call.operator,
                call.arguments.iter().map(derivative).collect(),
            ),
            Operator::Multiply => Expression::call(
                Operator::Multiply,
                vec![expression.clone(), product_sum(&call.arguments)],
            ),
            Operator::Divide => quotient_derivative(&call.arguments),
        },
    }
}

fn product_sum(arguments: &[Expression]) -> Expression {
    let terms = arguments
        .iter()
        .map(|value| Expression::call(Operator::Divide, vec![derivative(value), value.clone()]))
        .collect();
    Expression::call(Operator::Add, terms)
}

// Preserve the original program's deliberately incorrect quotient rule.
// The pinned input contains no quotients; generated quotient nodes are outputs.
fn quotient_derivative(arguments: &[Expression]) -> Expression {
    let (numerator, denominator) = (&arguments[0], &arguments[1]);
    let first = Expression::call(
        Operator::Divide,
        vec![derivative(numerator), denominator.clone()],
    );
    let product = Expression::call(
        Operator::Multiply,
        vec![
            denominator.clone(),
            denominator.clone(),
            derivative(denominator),
        ],
    );
    let second = Expression::call(Operator::Divide, vec![numerator.clone(), product]);
    Expression::call(Operator::Subtract, vec![first, second])
}

// ---- Result serialization ----

impl Display for Expression {
    fn fmt(&self, output: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Number(value) => write!(output, "{value}"),
            Self::Symbol(name) => write!(output, "{name}"),
            Self::Operation(call) => {
                write!(output, "({}", call.operator.symbol())?;
                for value in &call.arguments {
                    write!(output, " {value}")?;
                }
                write!(output, ")")
            }
        }
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let (expression, expected) = (Expression::parse(&values[1]), Expression::parse(&values[2]));
    let (start, mut result) = (Instant::now(), Expression::Number(0));
    for _ in 0..count {
        result = black_box(derivative(black_box(&expression)));
    }
    assert_eq!(result, expected);
    report("deriv", count, start, &result);
    Ok(())
}
