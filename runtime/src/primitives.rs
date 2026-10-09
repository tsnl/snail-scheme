//! Checked Scheme operations. Allocation here never triggers collection; the
//! calling VM handler publishes its results before the next safepoint.

use crate::{heap::Object, host, value::Value, vm::Vm};
use std::{cmp::Ordering, collections::HashSet};

pub(crate) enum PrimitiveResult {
    Values(Vec<Value>),
    Invoke(Value, Vec<Value>),
    CallWithValues(Value, Value),
    Exit(i32),
}

pub(crate) fn arity(name: &str, args: &[Value], min: usize, max: usize) -> Result<(), String> {
    if (min..=max).contains(&args.len()) {
        Ok(())
    } else {
        Err(format!(
            "{name}: wrong number of arguments (got {})",
            args.len()
        ))
    }
}

fn one(value: Value) -> Result<PrimitiveResult, String> {
    Ok(PrimitiveResult::Values(vec![value]))
}

pub(crate) fn primitive(
    vm: &mut Vm,
    name: &str,
    args: &[Value],
) -> Result<PrimitiveResult, String> {
    if let Some(result) = host::primitive(vm, name, args) {
        return result;
    }
    let value = match name {
        "+" | "-" | "*" | "/" | "quotient" | "remainder" | "modulo" => arithmetic(name, args)?,
        "=" | "<" | "<=" | ">" | ">=" => numeric_compare(name, args)?,
        "eq?" | "eqv?" => {
            arity(name, args, 2, 2)?;
            Value::Bool(args[0] == args[1])
        }
        "boolean?" | "number?" | "real?" | "inexact?" | "integer?" | "exact-integer?" | "pair?"
        | "null?" | "symbol?" | "string?" | "char?" | "vector?" | "bytevector?" | "procedure?" => {
            arity(name, args, 1, 1)?;
            predicate(vm, name, args[0])
        }
        "cons" | "car" | "cdr" | "set-car!" | "set-cdr!" => pair(vm, name, args)?,
        "vector" | "make-vector" | "vector-ref" | "vector-set!" | "vector-length" => {
            vector(vm, name, args)?
        }
        "bytevector" | "bytevector-length" | "bytevector-u8-ref" | "bytevector-u8-set!" => {
            bytevector(vm, name, args)?
        }
        "string" | "string-ref" | "string-length" | "string-append" | "substring" | "string=?"
        | "string->symbol" | "symbol->string" | "string->number" | "number->string" => {
            string(vm, name, args)?
        }
        "char->integer" | "integer->char" | "char=?" | "char<?" | "char<=?" | "char>?"
        | "char>=?" | "char-ci=?" | "char-alphabetic?" | "char-numeric?" | "char-whitespace?" => {
            character(name, args)?
        }
        "%make-record-type" | "%make-record" | "%record?" | "%record-ref" | "%record-set!" => {
            record(vm, name, args)?
        }
        "values" => return Ok(PrimitiveResult::Values(args.to_vec())),
        "call-with-values" => {
            arity(name, args, 2, 2)?;
            return Ok(PrimitiveResult::CallWithValues(args[0], args[1]));
        }
        "apply" => {
            arity(name, args, 2, usize::MAX)?;
            let mut arguments = args[1..args.len() - 1].to_vec();
            arguments.extend(vm.list_values(args[args.len() - 1])?);
            return Ok(PrimitiveResult::Invoke(args[0], arguments));
        }
        "error" => {
            arity(name, args, 1, usize::MAX)?;
            let messages = args
                .iter()
                .map(|v| format_value(vm, *v, true))
                .collect::<Result<Vec<_>, _>>()?;
            return Err(messages.join(" "));
        }
        _ => return Err(format!("unknown primitive: {name}")),
    };
    one(value)
}

fn number(value: Value) -> Result<f64, String> {
    match value {
        Value::Integer(n) => Ok(n as f64),
        Value::Float(n) => Ok(n),
        _ => Err("expected a number".into()),
    }
}

fn arithmetic(name: &str, args: &[Value]) -> Result<Value, String> {
    let minimum = if matches!(name, "+" | "*") { 0 } else { 1 };
    if matches!(name, "quotient" | "remainder" | "modulo") {
        arity(name, args, 2, 2)?;
        let a = args[0].integer()?;
        let b = args[1].integer()?;
        let value = if name == "quotient" {
            a.checked_div(b)
        } else {
            a.checked_rem(b)
        }
        .ok_or_else(|| format!("{name}: division by zero or integer overflow"))?;
        return Ok(Value::Integer(
            if name == "modulo" && value != 0 && (value < 0) != (b < 0) {
                value + b
            } else {
                value
            },
        ));
    }
    arity(name, args, minimum, usize::MAX)?;
    // Preserve exact integers until an inexact operand or a nonintegral division
    // requires a floating-point result. Bignums and exact rationals are future work.
    let (initial, rest) = if matches!(name, "+" | "*") {
        (Value::Integer(if name == "+" { 0 } else { 1 }), args)
    } else if args.len() == 1 {
        (Value::Integer(if name == "-" { 0 } else { 1 }), args)
    } else {
        number(args[0])?;
        (args[0], &args[1..])
    };
    rest.iter()
        .try_fold(initial, |acc, &value| numeric_step(name, acc, value))
}

fn numeric_step(name: &str, left: Value, right: Value) -> Result<Value, String> {
    if let (Value::Integer(a), Value::Integer(b)) = (left, right) {
        let exact = match name {
            "+" => a.checked_add(b),
            "-" => a.checked_sub(b),
            "*" => a.checked_mul(b),
            "/" => {
                if b == 0 {
                    return Err("/: division by zero".into());
                }
                if a.checked_rem(b) == Some(0) {
                    a.checked_div(b)
                } else if a == i64::MIN && b == -1 {
                    None
                } else {
                    return Ok(Value::Float(a as f64 / b as f64));
                }
            }
            _ => unreachable!(),
        };
        return exact
            .map(Value::Integer)
            .ok_or_else(|| format!("{name}: integer overflow"));
    }
    let a = number(left)?;
    let b = number(right)?;
    Ok(Value::Float(match name {
        "+" => a + b,
        "-" => a - b,
        "*" => a * b,
        "/" => {
            if b == 0.0 {
                return Err("/: division by zero".into());
            }
            a / b
        }
        _ => unreachable!(),
    }))
}

/// Compare mixed numbers without rounding a large integer to f64 first.
fn compare_integer_float(integer: i64, float: f64) -> Option<Ordering> {
    if float.is_nan() {
        return None;
    }
    if float >= 9223372036854775808.0 {
        return Some(Ordering::Less);
    }
    if float < -9223372036854775808.0 {
        return Some(Ordering::Greater);
    }
    let whole = float as i64;
    match integer.cmp(&whole) {
        Ordering::Equal => (whole as f64).partial_cmp(&float),
        other => Some(other),
    }
}

fn numeric_compare(name: &str, args: &[Value]) -> Result<Value, String> {
    arity(name, args, 2, usize::MAX)?;
    for &value in args {
        number(value)?;
    }
    let matches = args.windows(2).all(|pair| {
        let comparison = match (pair[0], pair[1]) {
            (Value::Integer(a), Value::Integer(b)) => Some(a.cmp(&b)),
            (Value::Integer(a), Value::Float(b)) => compare_integer_float(a, b),
            (Value::Float(a), Value::Integer(b)) => {
                compare_integer_float(b, a).map(Ordering::reverse)
            }
            (Value::Float(a), Value::Float(b)) => a.partial_cmp(&b),
            _ => unreachable!(),
        };
        match name {
            "=" => comparison == Some(Ordering::Equal),
            "<" => comparison == Some(Ordering::Less),
            ">" => comparison == Some(Ordering::Greater),
            "<=" => matches!(comparison, Some(Ordering::Less | Ordering::Equal)),
            ">=" => matches!(comparison, Some(Ordering::Greater | Ordering::Equal)),
            _ => unreachable!(),
        }
    });
    Ok(Value::Bool(matches))
}

fn predicate(vm: &Vm, name: &str, value: Value) -> Value {
    let object = vm.heap.get(value).ok();
    Value::Bool(match name {
        "boolean?" => matches!(value, Value::Bool(_)),
        "number?" | "real?" => matches!(value, Value::Integer(_) | Value::Float(_)),
        "inexact?" => matches!(value, Value::Float(_)),
        "integer?" => {
            matches!(value, Value::Integer(_))
                || matches!(value, Value::Float(n) if n.is_finite() && n.fract() == 0.0)
        }
        "exact-integer?" => matches!(value, Value::Integer(_)),
        "null?" => value == Value::Nil,
        "char?" => matches!(value, Value::Char(_)),
        "pair?" => matches!(object, Some(Object::Pair(..))),
        "symbol?" => matches!(object, Some(Object::Symbol(_))),
        "string?" => matches!(object, Some(Object::String(_))),
        "vector?" => matches!(object, Some(Object::Vector(_))),
        "bytevector?" => matches!(object, Some(Object::Bytevector(_))),
        "procedure?" => matches!(object, Some(Object::Closure(_) | Object::Primitive(_))),
        _ => unreachable!(),
    })
}

fn pair(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    let count = if matches!(name, "car" | "cdr") { 1 } else { 2 };
    arity(name, args, count, count)?;
    if name == "cons" {
        return Ok(vm.alloc(Object::Pair(args[0], args[1])));
    }
    let Object::Pair(car, cdr) = vm.heap.get_mut(args[0])? else {
        return Err(format!("{name}: expected a pair"));
    };
    match name {
        "car" => Ok(*car),
        "cdr" => Ok(*cdr),
        "set-car!" => {
            *car = args[1];
            Ok(Value::Unspecified)
        }
        "set-cdr!" => {
            *cdr = args[1];
            Ok(Value::Unspecified)
        }
        _ => unreachable!(),
    }
}

fn vector(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    if name == "vector" {
        return Ok(vm.alloc(Object::Vector(args.to_vec())));
    }
    if name == "make-vector" {
        arity(name, args, 1, 2)?;
        let length = args[0].index()?;
        let fill = args.get(1).copied().unwrap_or(Value::Unspecified);
        let mut elements = Vec::new();
        elements
            .try_reserve_exact(length)
            .map_err(|_| "make-vector: allocation too large")?;
        elements.resize(length, fill);
        return Ok(vm.alloc(Object::Vector(elements)));
    }
    let count = match name {
        "vector-length" => 1,
        "vector-ref" => 2,
        _ => 3,
    };
    arity(name, args, count, count)?;
    let Object::Vector(elements) = vm.heap.get_mut(args[0])? else {
        return Err(format!("{name}: expected a vector"));
    };
    if name == "vector-length" {
        return length_value(elements.len());
    }
    let element = elements
        .get_mut(args[1].index()?)
        .ok_or("vector index out of range")?;
    if name == "vector-ref" {
        Ok(*element)
    } else {
        *element = args[2];
        Ok(Value::Unspecified)
    }
}

fn byte(value: Value) -> Result<u8, String> {
    u8::try_from(value.integer()?).map_err(|_| "expected a byte between 0 and 255".into())
}

fn bytevector(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    if name == "bytevector" {
        let bytes = args
            .iter()
            .map(|&v| byte(v))
            .collect::<Result<Vec<_>, _>>()?;
        return Ok(vm.alloc(Object::Bytevector(bytes)));
    }
    let count = match name {
        "bytevector-length" => 1,
        "bytevector-u8-ref" => 2,
        _ => 3,
    };
    arity(name, args, count, count)?;
    let Object::Bytevector(bytes) = vm.heap.get_mut(args[0])? else {
        return Err(format!("{name}: expected a bytevector"));
    };
    if name == "bytevector-length" {
        return length_value(bytes.len());
    }
    let element = bytes
        .get_mut(args[1].index()?)
        .ok_or("bytevector index out of range")?;
    if name == "bytevector-u8-ref" {
        Ok(Value::Integer(i64::from(*element)))
    } else {
        *element = byte(args[2])?;
        Ok(Value::Unspecified)
    }
}

fn length_value(length: usize) -> Result<Value, String> {
    i64::try_from(length)
        .map(Value::Integer)
        .map_err(|_| "length exceeds integer range".into())
}

fn char_value(value: Value) -> Result<char, String> {
    match value {
        Value::Char(c) => Ok(c),
        _ => Err("expected a character".into()),
    }
}

fn string(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    match name {
        "string" => {
            let text = args
                .iter()
                .map(|&v| char_value(v))
                .collect::<Result<String, _>>()?;
            Ok(vm.alloc(Object::String(text)))
        }
        "string-append" => {
            let parts = args
                .iter()
                .map(|&v| vm.string(v))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(vm.alloc(Object::String(parts.concat())))
        }
        "string=?" => {
            arity(name, args, 2, usize::MAX)?;
            let texts = args
                .iter()
                .map(|&v| vm.string(v))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(Value::Bool(texts.windows(2).all(|pair| pair[0] == pair[1])))
        }
        "string->number" | "number->string" => convert_number(vm, name, args),
        "string->symbol" => {
            arity(name, args, 1, 1)?;
            Ok(vm.intern(&vm.string(args[0])?))
        }
        "symbol->string" => {
            arity(name, args, 1, 1)?;
            let Object::Symbol(symbol) = vm.heap.get(args[0])? else {
                return Err("symbol->string: expected a symbol".into());
            };
            let text = symbol.clone();
            Ok(vm.alloc(Object::String(text)))
        }
        "string-length" => {
            arity(name, args, 1, 1)?;
            length_value(vm.string(args[0])?.chars().count())
        }
        "string-ref" => {
            arity(name, args, 2, 2)?;
            vm.string(args[0])?
                .chars()
                .nth(args[1].index()?)
                .map(Value::Char)
                .ok_or_else(|| "string index out of range".into())
        }
        "substring" => {
            arity(name, args, 3, 3)?;
            let text: Vec<char> = vm.string(args[0])?.chars().collect();
            let start = args[1].index()?;
            let end = args[2].index()?;
            let part = text
                .get(start..end)
                .ok_or("substring indices out of range")?;
            Ok(vm.alloc(Object::String(part.iter().collect())))
        }
        _ => unreachable!(),
    }
}

fn convert_number(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    arity(name, args, 1, 2)?;
    let radix = match args.get(1) {
        Some(v) => v.integer()?,
        None => 10,
    };
    if !matches!(radix, 2 | 8 | 10 | 16) {
        return Err("unsupported numeric radix".into());
    }
    if name == "string->number" {
        let text = vm.string(args[0])?;
        match i64::from_str_radix(&text, radix as u32) {
            Ok(n) => return Ok(Value::Integer(n)),
            Err(error)
                if matches!(
                    error.kind(),
                    std::num::IntErrorKind::PosOverflow | std::num::IntErrorKind::NegOverflow
                ) =>
            {
                return Err("string->number: integer overflow".into());
            }
            Err(_) => {}
        }
        if radix == 10 {
            let float = parse_float(&text);
            if let Some(n) = float {
                return Ok(Value::Float(n));
            }
        }
        return Ok(Value::Bool(false));
    }
    let text = match args[0] {
        Value::Integer(n) => {
            let magnitude = n.unsigned_abs();
            let digits = match radix {
                2 => format!("{magnitude:b}"),
                8 => format!("{magnitude:o}"),
                16 => format!("{magnitude:x}"),
                _ => magnitude.to_string(),
            };
            if n < 0 { format!("-{digits}") } else { digits }
        }
        Value::Float(n) if radix == 10 => float_text(n),
        Value::Float(_) => return Err("inexact number requires decimal radix".into()),
        _ => return Err("number->string: expected a number".into()),
    };
    Ok(vm.alloc(Object::String(text)))
}

pub(crate) fn parse_float(text: &str) -> Option<f64> {
    match text {
        "+inf.0" => Some(f64::INFINITY),
        "-inf.0" => Some(f64::NEG_INFINITY),
        "+nan.0" | "-nan.0" => Some(f64::NAN),
        _ if text.contains(['.', 'e', 'E']) => text.parse::<f64>().ok(),
        _ => None,
    }
}

fn float_text(number: f64) -> String {
    if number.is_nan() {
        "+nan.0".into()
    } else if number == f64::INFINITY {
        "+inf.0".into()
    } else if number == f64::NEG_INFINITY {
        "-inf.0".into()
    } else {
        format!("{number:?}")
    }
}

fn character(name: &str, args: &[Value]) -> Result<Value, String> {
    let comparison = matches!(
        name,
        "char=?" | "char<?" | "char<=?" | "char>?" | "char>=?" | "char-ci=?"
    );
    arity(
        name,
        args,
        if comparison { 2 } else { 1 },
        if comparison { usize::MAX } else { 1 },
    )?;
    if name == "integer->char" {
        return u32::try_from(args[0].integer()?)
            .ok()
            .and_then(char::from_u32)
            .map(Value::Char)
            .ok_or_else(|| "integer->char: invalid Unicode scalar value".into());
    }
    let chars = args
        .iter()
        .map(|&v| char_value(v))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(match name {
        "char->integer" => Value::Integer(i64::from(chars[0] as u32)),
        "char-alphabetic?" => Value::Bool(chars[0].is_alphabetic()),
        "char-numeric?" => Value::Bool(chars[0].is_numeric()),
        "char-whitespace?" => Value::Bool(chars[0].is_whitespace()),
        _ => Value::Bool(chars.windows(2).all(|p| match name {
            "char=?" => p[0] == p[1],
            "char<?" => p[0] < p[1],
            "char<=?" => p[0] <= p[1],
            "char>?" => p[0] > p[1],
            "char>=?" => p[0] >= p[1],
            // Baseline case-insensitive comparison uses Unicode lowercase.
            "char-ci=?" => p[0].to_lowercase().eq(p[1].to_lowercase()),
            _ => unreachable!(),
        })),
    })
}

fn symbol_name(vm: &Vm, value: Value) -> Result<String, String> {
    match vm.heap.get(value)? {
        Object::Symbol(name) => Ok(name.clone()),
        _ => Err("expected a symbol".into()),
    }
}

fn symbol_list(vm: &Vm, value: Value) -> Result<Vec<String>, String> {
    vm.list_values(value)?
        .iter()
        .map(|&v| symbol_name(vm, v))
        .collect()
}

fn record(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    let count = match name {
        "%make-record-type" | "%record?" => 2,
        "%record-set!" => 4,
        _ => 3,
    };
    arity(name, args, count, count)?;
    if name == "%make-record-type" {
        let name = symbol_name(vm, args[0])?;
        let fields = symbol_list(vm, args[1])?;
        if fields.iter().collect::<HashSet<_>>().len() != fields.len() {
            return Err("duplicate record field".into());
        }
        return Ok(vm.alloc(Object::RecordType { name, fields }));
    }
    let Object::RecordType {
        fields: field_names,
        ..
    } = vm.heap.get(args[0])?
    else {
        return Err("expected a record type descriptor".into());
    };
    if name == "%record?" {
        return Ok(Value::Bool(matches!(vm.heap.get(args[1]),
            Ok(Object::Record { descriptor, .. }) if *descriptor == args[0])));
    }
    if name == "%make-record" {
        let names = symbol_list(vm, args[1])?;
        let values = vm.list_values(args[2])?;
        let fields = constructor_fields(field_names, &names, values)?;
        return Ok(vm.alloc(Object::Record {
            descriptor: args[0],
            fields,
        }));
    }
    let field = symbol_name(vm, args[1])?;
    let index = field_names
        .iter()
        .position(|name| name == &field)
        .ok_or("unknown record field")?;
    let Object::Record { descriptor, fields } = vm.heap.get_mut(args[2])? else {
        return Err("expected a record instance".into());
    };
    if *descriptor != args[0] {
        return Err("record belongs to a different record type".into());
    }
    if name == "%record-ref" {
        Ok(fields[index])
    } else {
        fields[index] = args[3];
        Ok(Value::Unspecified)
    }
}

/// Establish the complete slot order before allocating a record. Constructors
/// may reorder or omit fields, but cannot name an unknown or repeated field.
fn constructor_fields(
    field_names: &[String],
    names: &[String],
    values: Vec<Value>,
) -> Result<Vec<Value>, String> {
    if names.len() != values.len() {
        return Err("record constructor arity mismatch".into());
    }
    let mut fields = vec![Value::Unspecified; field_names.len()];
    let mut seen = HashSet::new();
    for (name, value) in names.iter().zip(values) {
        let index = field_names
            .iter()
            .position(|field| field == name)
            .ok_or("unknown record field")?;
        if !seen.insert(index) {
            return Err("duplicate constructor field".into());
        }
        fields[index] = value;
    }
    Ok(fields)
}

enum PrintTask {
    Value(Value),
    Tail(Value),
    Text(String),
    Leave(usize),
}

/// Printing uses its own work stack, so deeply nested datums and cycles cannot
/// recurse through the host stack. Repeated acyclic references print normally.
pub(crate) fn format_value(vm: &Vm, value: Value, display: bool) -> Result<String, String> {
    let mut output = String::new();
    let mut pending = vec![PrintTask::Value(value)];
    let mut active = HashSet::new();
    while let Some(task) = pending.pop() {
        match task {
            PrintTask::Text(text) => output.push_str(&text),
            PrintTask::Leave(index) => {
                active.remove(&index);
            }
            PrintTask::Tail(Value::Nil) => {}
            PrintTask::Tail(value) => {
                if let Ok(Object::Pair(car, cdr)) = vm.heap.get(value) {
                    let Value::Heap(index) = value else {
                        unreachable!()
                    };
                    if active.insert(index) {
                        output.push(' ');
                        pending.push(PrintTask::Leave(index));
                        pending.push(PrintTask::Tail(*cdr));
                        pending.push(PrintTask::Value(*car));
                    } else {
                        output.push_str(" . #<cycle>");
                    }
                } else {
                    output.push_str(" . ");
                    pending.push(PrintTask::Value(value));
                }
            }
            PrintTask::Value(value) => {
                print_atom_or_container(vm, value, display, &mut output, &mut pending, &mut active)?
            }
        }
    }
    Ok(output)
}

fn print_atom_or_container(
    vm: &Vm,
    value: Value,
    display: bool,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut HashSet<usize>,
) -> Result<(), String> {
    match value {
        Value::Nil => output.push_str("()"),
        Value::Bool(b) => output.push_str(if b { "#t" } else { "#f" }),
        Value::Integer(n) => output.push_str(&n.to_string()),
        Value::Float(n) => output.push_str(&float_text(n)),
        Value::Char(c) => {
            if display {
                output.push(c);
            } else {
                output.push_str("#\\");
                match c {
                    ' ' => output.push_str("space"),
                    '\n' => output.push_str("newline"),
                    '\t' => output.push_str("tab"),
                    '\r' => output.push_str("return"),
                    _ => output.push(c),
                }
            }
        }
        Value::Eof => output.push_str("#<eof>"),
        Value::Unspecified => output.push_str("#<unspecified>"),
        Value::Uninitialized => output.push_str("#<uninitialized>"),
        Value::Heap(index) => {
            if !active.insert(index) {
                output.push_str("#<cycle>");
                return Ok(());
            }
            pending.push(PrintTask::Leave(index));
            match vm.heap.get(value)? {
                Object::String(text) => {
                    if display {
                        output.push_str(text);
                    } else {
                        quoted_string(output, text);
                    }
                }
                Object::Symbol(text) => output.push_str(text),
                Object::Pair(car, cdr) => {
                    output.push('(');
                    pending.push(PrintTask::Text(")".into()));
                    pending.push(PrintTask::Tail(*cdr));
                    pending.push(PrintTask::Value(*car));
                }
                Object::Vector(values) => {
                    output.push_str("#(");
                    pending.push(PrintTask::Text(")".into()));
                    for (position, &value) in values.iter().enumerate().rev() {
                        pending.push(PrintTask::Value(value));
                        if position > 0 {
                            pending.push(PrintTask::Text(" ".into()));
                        }
                    }
                }
                Object::Bytevector(values) => {
                    output.push_str("#u8(");
                    for (position, byte) in values.iter().enumerate() {
                        if position > 0 {
                            output.push(' ');
                        }
                        output.push_str(&byte.to_string());
                    }
                    output.push(')');
                }
                Object::RecordType { name, .. } => {
                    output.push_str(&format!("#<record-type {name}>"))
                }
                Object::Record { descriptor, .. } => {
                    if let Object::RecordType { name, .. } = vm.heap.get(*descriptor)? {
                        output.push_str(&format!("#<record {name}>"));
                    }
                }
                Object::Primitive(name) => output.push_str(&format!("#<procedure {name}>")),
                Object::Closure(_) => output.push_str("#<procedure>"),
                Object::Cell(_) => output.push_str("#<cell>"),
                Object::Port(_) => output.push_str("#<port>"),
            }
        }
    }
    Ok(())
}

fn quoted_string(output: &mut String, text: &str) {
    output.push('"');
    for ch in text.chars() {
        match ch {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            c if c.is_control() => output.push_str(&format!("\\x{:x};", c as u32)),
            c => output.push(c),
        }
    }
    output.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vm() -> Vm {
        Vm::new(0, 0, vec!["test".into()])
    }

    fn initialized_float(text: &str) -> Value {
        let mut vm = Vm::new(0, 1, Vec::new());
        unsafe {
            crate::snail_const_atom(&mut vm, 0, 3, text.as_ptr(), text.len() as u32);
        }
        assert_eq!(vm.error(), None);
        vm.constant(0).unwrap()
    }

    #[test]
    fn floating_constants_and_numeric_reader_agree() {
        for text in ["1.25", "+inf.0", "-inf.0", "+nan.0"] {
            let mut vm = vm();
            let string = vm.alloc(Object::String(text.into()));
            let read = convert_number(&mut vm, "string->number", &[string]).unwrap();
            let Value::Float(literal) = initialized_float(text) else {
                panic!("expected float")
            };
            let Value::Float(read) = read else {
                panic!("expected float")
            };
            assert!(literal == read || (literal.is_nan() && read.is_nan()));
        }
    }

    #[test]
    fn integer_arithmetic_rejects_overflow_and_zero_division() {
        assert!(arithmetic("+", &[Value::Integer(i64::MAX), Value::Integer(1)]).is_err());
        assert!(arithmetic("-", &[Value::Integer(i64::MIN)]).is_err());
        assert!(arithmetic("/", &[Value::Integer(i64::MIN), Value::Integer(-1)]).is_err());
        assert!(arithmetic("quotient", &[Value::Integer(7), Value::Integer(0)]).is_err());
        assert!(arithmetic("/", &[Value::Float(7.0), Value::Float(0.0)]).is_err());
        assert_eq!(
            arithmetic("/", &[Value::Integer(9), Value::Integer(3)]).unwrap(),
            Value::Integer(3)
        );
        assert_eq!(
            arithmetic("/", &[Value::Integer(9), Value::Integer(2)]).unwrap(),
            Value::Float(4.5)
        );
        assert_eq!(
            arithmetic("modulo", &[Value::Integer(-7), Value::Integer(3)]).unwrap(),
            Value::Integer(2)
        );
        assert_eq!(
            arithmetic("modulo", &[Value::Integer(7), Value::Integer(-3)]).unwrap(),
            Value::Integer(-2)
        );
    }

    #[test]
    fn mixed_comparisons_preserve_large_integer_precision() {
        let exact = Value::Integer(9_007_199_254_740_993);
        let rounded = Value::Float(9_007_199_254_740_992.0);
        assert_eq!(
            numeric_compare(">", &[exact, rounded]).unwrap(),
            Value::Bool(true)
        );
        assert_eq!(
            numeric_compare("=", &[exact, rounded]).unwrap(),
            Value::Bool(false)
        );
        assert_eq!(
            numeric_compare(
                "<",
                &[
                    Value::Integer(i64::MAX),
                    Value::Float(9223372036854775808.0)
                ]
            )
            .unwrap(),
            Value::Bool(true)
        );
        assert_eq!(
            numeric_compare("=", &[Value::Float(f64::NAN), Value::Float(f64::NAN)]).unwrap(),
            Value::Bool(false)
        );
    }

    #[test]
    fn numeric_reader_does_not_silently_make_overflowing_integers_inexact() {
        let mut vm = vm();
        for text in ["9223372036854775808", "-9223372036854775809"] {
            let text = vm.alloc(Object::String(text.into()));
            assert!(
                convert_number(&mut vm, "string->number", &[text])
                    .unwrap_err()
                    .contains("overflow")
            );
        }
        let text = vm.alloc(Object::String("8000000000000000".into()));
        assert!(convert_number(&mut vm, "string->number", &[text, Value::Integer(16)]).is_err());
        let text = vm.alloc(Object::String("9.5e2".into()));
        assert_eq!(
            convert_number(&mut vm, "string->number", &[text]).unwrap(),
            Value::Float(950.0)
        );
        let text = vm.alloc(Object::String("NaN".into()));
        assert_eq!(
            convert_number(&mut vm, "string->number", &[text]).unwrap(),
            Value::Bool(false)
        );
    }

    #[test]
    fn string_indices_count_unicode_scalars_and_check_bounds() {
        let mut vm = vm();
        let text = vm.alloc(Object::String("aλ😀z".into()));
        assert_eq!(
            string(&mut vm, "string-length", &[text]).unwrap(),
            Value::Integer(4)
        );
        assert_eq!(
            string(&mut vm, "string-ref", &[text, Value::Integer(2)]).unwrap(),
            Value::Char('😀')
        );
        let part = string(
            &mut vm,
            "substring",
            &[text, Value::Integer(1), Value::Integer(3)],
        )
        .unwrap();
        assert_eq!(vm.string(part).unwrap(), "λ😀");
        assert!(
            string(
                &mut vm,
                "substring",
                &[text, Value::Integer(3), Value::Integer(1)]
            )
            .is_err()
        );
        assert!(string(&mut vm, "string-ref", &[text, Value::Integer(4)]).is_err());
        assert!(string(&mut vm, "string-ref", &[text, Value::Integer(-1)]).is_err());
    }

    #[test]
    fn record_fields_follow_names_and_descriptor_identity() {
        let mut vm = vm();
        let name = vm.intern("point");
        let x = vm.intern("x");
        let y = vm.intern("y");
        let names = vm.list(&[x, y]);
        let descriptor = record(&mut vm, "%make-record-type", &[name, names]).unwrap();
        let other_descriptor = record(&mut vm, "%make-record-type", &[name, names]).unwrap();
        let constructors = vm.list(&[y, x]);
        let values = vm.list(&[Value::Integer(20), Value::Integer(10)]);
        let instance =
            record(&mut vm, "%make-record", &[descriptor, constructors, values]).unwrap();
        assert_eq!(
            record(&mut vm, "%record-ref", &[descriptor, x, instance]).unwrap(),
            Value::Integer(10)
        );
        assert_eq!(
            record(&mut vm, "%record-ref", &[descriptor, y, instance]).unwrap(),
            Value::Integer(20)
        );
        assert_eq!(
            record(&mut vm, "%record?", &[other_descriptor, instance]).unwrap(),
            Value::Bool(false)
        );
        assert!(record(&mut vm, "%record-ref", &[other_descriptor, x, instance]).is_err());
        record(
            &mut vm,
            "%record-set!",
            &[descriptor, x, instance, Value::Integer(42)],
        )
        .unwrap();
        assert_eq!(
            record(&mut vm, "%record-ref", &[descriptor, x, instance]).unwrap(),
            Value::Integer(42)
        );
    }

    #[test]
    fn printing_handles_cycles_and_shared_acyclic_objects() {
        let mut vm = vm();
        let cycle = vm.alloc(Object::Pair(Value::Integer(1), Value::Nil));
        pair(&mut vm, "set-cdr!", &[cycle, cycle]).unwrap();
        assert_eq!(format_value(&vm, cycle, false).unwrap(), "(1 . #<cycle>)");
        let shared = vm.list(&[Value::Integer(2), Value::Integer(3)]);
        let vector = vm.alloc(Object::Vector(vec![shared, shared]));
        assert_eq!(format_value(&vm, vector, false).unwrap(), "#((2 3) (2 3))");
        let text = vm.alloc(Object::String("λ\n\"\\".into()));
        assert_eq!(format_value(&vm, text, true).unwrap(), "λ\n\"\\");
        assert_eq!(format_value(&vm, text, false).unwrap(), "\"λ\\n\\\"\\\\\"");
    }

    #[test]
    fn deep_printing_does_not_consume_the_host_call_stack() {
        let mut vm = vm();
        let mut value = Value::Integer(1);
        for _ in 0..20_000 {
            value = vm.alloc(Object::Pair(value, Value::Nil));
        }
        assert_eq!(format_value(&vm, value, false).unwrap().len(), 40_001);
    }
}
