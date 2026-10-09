//! Checked Scheme operations. Allocation here never triggers collection; the
//! calling VM handler publishes its results before the next safepoint.

use crate::{host, object::*, vm::Vm};
use std::{cmp::Ordering, collections::HashSet};

pub(crate) enum PrimitiveResult {
    Values(Vec<Value>),
    Invoke(Value, Vec<Value>),
    CallWithValues(Value, Value),
    Exit(i32),
    Collect,
}

pub(crate) fn arity<T>(name: &str, args: &[T], min: usize, max: usize) -> Result<(), String> {
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
        "+" | "-" | "*" | "/" | "quotient" | "remainder" | "modulo" => {
            arithmetic_values(vm, name, args)?
        }
        "=" | "<" | "<=" | ">" | ">=" => numeric_compare(name, &numeric_arguments(vm, args)?)?,
        "eq?" | "eqv?" => {
            arity(name, args, 2, 2)?;
            Value::boolean(equivalent(vm, args[0], args[1]))
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
        | "string->symbol" | "symbol->string" | "string->number" | "number->string"
        | "string-contains" => string(vm, name, args)?,
        "char->integer" | "integer->char" | "char=?" | "char<?" | "char<=?" | "char>?"
        | "char>=?" | "char-ci=?" | "char-alphabetic?" | "char-numeric?" | "char-whitespace?" => {
            character(vm, name, args)?
        }
        "%make-record-type" | "%make-record" | "%record?" | "%record-ref" | "%record-set!" => {
            record(vm, name, args)?
        }
        "collect-garbage" => {
            arity(name, args, 0, 0)?;
            return Ok(PrimitiveResult::Collect);
        }
        "gc-statistics" => {
            arity(name, args, 0, 0)?;
            gc_statistics(vm)?
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

fn numeric_arguments(vm: &Vm, args: &[Value]) -> Result<Vec<Number>, String> {
    args.iter().map(|v| vm.heap.number(*v)).collect()
}

fn arithmetic_values(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    let value = arithmetic(name, &numeric_arguments(vm, args)?)?;
    Ok(match value {
        Number::Integer(n) => vm.integer(n),
        Number::Float(n) => vm.float(n),
    })
}

fn equivalent(vm: &Vm, left: Value, right: Value) -> bool {
    match (vm.heap.number(left), vm.heap.number(right)) {
        (Ok(a), Ok(b)) => a == b,
        _ => left == right,
    }
}

fn arithmetic(name: &str, args: &[Number]) -> Result<Number, String> {
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
        return Ok(Number::Integer(
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
        (Number::Integer(if name == "+" { 0 } else { 1 }), args)
    } else if args.len() == 1 {
        (Number::Integer(if name == "-" { 0 } else { 1 }), args)
    } else {
        (args[0], &args[1..])
    };
    rest.iter()
        .try_fold(initial, |acc, &value| numeric_step(name, acc, value))
}

fn numeric_step(name: &str, left: Number, right: Number) -> Result<Number, String> {
    if let (Number::Integer(a), Number::Integer(b)) = (left, right) {
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
                    return Ok(Number::Float(a as f64 / b as f64));
                }
            }
            _ => unreachable!(),
        };
        return exact
            .map(Number::Integer)
            .ok_or_else(|| format!("{name}: integer overflow"));
    }
    let a = left.real();
    let b = right.real();
    Ok(Number::Float(match name {
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

fn numeric_compare(name: &str, args: &[Number]) -> Result<Value, String> {
    arity(name, args, 2, usize::MAX)?;
    let matches = args.windows(2).all(|pair| {
        let comparison = match (pair[0], pair[1]) {
            (Number::Integer(a), Number::Integer(b)) => Some(a.cmp(&b)),
            (Number::Integer(a), Number::Float(b)) => compare_integer_float(a, b),
            (Number::Float(a), Number::Integer(b)) => {
                compare_integer_float(b, a).map(Ordering::reverse)
            }
            (Number::Float(a), Number::Float(b)) => a.partial_cmp(&b),
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
    Ok(Value::boolean(matches))
}

fn predicate(vm: &Vm, name: &str, value: Value) -> Value {
    Value::boolean(match name {
        "boolean?" => value.is_boolean(),
        "number?" | "real?" => vm.heap.number(value).is_ok(),
        "inexact?" => vm.heap.find::<Float>(value).is_some(),
        "integer?" => match vm.heap.number(value) {
            Ok(Number::Integer(_)) => true,
            Ok(Number::Float(n)) => n.is_finite() && n.fract() == 0.0,
            Err(_) => false,
        },
        "exact-integer?" => value.as_integer(&vm.heap).is_some(),
        "null?" => value == Value::NIL,
        "char?" => value.as_character().is_some(),
        "pair?" => vm.heap.find::<Pair>(value).is_some(),
        "symbol?" => vm.heap.find::<Symbol>(value).is_some(),
        "string?" => vm.heap.find::<Text>(value).is_some(),
        "vector?" => vm.heap.find::<Vector>(value).is_some(),
        "bytevector?" => vm.heap.find::<Bytevector>(value).is_some(),
        "procedure?" => {
            vm.heap.find::<Closure>(value).is_some() || vm.heap.find::<Primitive>(value).is_some()
        }
        _ => unreachable!(),
    })
}

fn pair(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    let count = if matches!(name, "car" | "cdr") { 1 } else { 2 };
    arity(name, args, count, count)?;
    if name == "cons" {
        return Ok(vm.alloc(Pair(args[0], args[1])));
    }
    let Pair(car, cdr) = vm.heap.get_mut(args[0])?;
    match name {
        "car" => Ok(*car),
        "cdr" => Ok(*cdr),
        "set-car!" => {
            *car = args[1];
            Ok(Value::UNSPECIFIED)
        }
        "set-cdr!" => {
            *cdr = args[1];
            Ok(Value::UNSPECIFIED)
        }
        _ => unreachable!(),
    }
}

fn vector(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    if name == "vector" {
        return Ok(vm.alloc(Vector(args.to_vec())));
    }
    if name == "make-vector" {
        arity(name, args, 1, 2)?;
        let length = args[0].index(&vm.heap)?;
        let fill = args.get(1).copied().unwrap_or(Value::UNSPECIFIED);
        let mut elements = Vec::new();
        elements
            .try_reserve_exact(length)
            .map_err(|_| "make-vector: allocation too large")?;
        elements.resize(length, fill);
        return Ok(vm.alloc(Vector(elements)));
    }
    let count = match name {
        "vector-length" => 1,
        "vector-ref" => 2,
        _ => 3,
    };
    arity(name, args, count, count)?;
    let length = vm.heap.get::<Vector>(args[0])?.0.len();
    if name == "vector-length" {
        return length_value(vm, length);
    }
    let index = args[1].index(&vm.heap)?;
    let Vector(elements) = vm.heap.get_mut::<Vector>(args[0])?;
    let element = elements.get_mut(index).ok_or("vector index out of range")?;
    if name == "vector-ref" {
        Ok(*element)
    } else {
        *element = args[2];
        Ok(Value::UNSPECIFIED)
    }
}

fn byte(vm: &Vm, value: Value) -> Result<u8, String> {
    u8::try_from(value.integer(&vm.heap)?).map_err(|_| "expected a byte between 0 and 255".into())
}

fn bytevector(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    if name == "bytevector" {
        let bytes = args
            .iter()
            .map(|&v| byte(vm, v))
            .collect::<Result<Vec<_>, _>>()?;
        return Ok(vm.alloc(Bytevector(bytes)));
    }
    let count = match name {
        "bytevector-length" => 1,
        "bytevector-u8-ref" => 2,
        _ => 3,
    };
    arity(name, args, count, count)?;
    let length = vm.heap.get::<Bytevector>(args[0])?.0.len();
    if name == "bytevector-length" {
        return length_value(vm, length);
    }
    let index = args[1].index(&vm.heap)?;
    let new_byte = if name == "bytevector-u8-set!" {
        byte(vm, args[2])?
    } else {
        0
    };
    let Bytevector(bytes) = vm.heap.get_mut::<Bytevector>(args[0])?;
    let element = bytes
        .get_mut(index)
        .ok_or("bytevector index out of range")?;
    if name == "bytevector-u8-ref" {
        Ok(Value::fixnum(i64::from(*element)).unwrap())
    } else {
        *element = new_byte;
        Ok(Value::UNSPECIFIED)
    }
}

fn length_value(vm: &mut Vm, length: usize) -> Result<Value, String> {
    i64::try_from(length)
        .map(|n| vm.integer(n))
        .map_err(|_| "length exceeds integer range".into())
}

fn char_value(value: Value) -> Result<char, String> {
    value
        .as_character()
        .ok_or_else(|| "expected a character".into())
}

fn string(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    match name {
        "string" => {
            let text = args
                .iter()
                .map(|&v| char_value(v))
                .collect::<Result<String, _>>()?;
            Ok(vm.alloc(Text(text)))
        }
        "string-append" => {
            let parts = args
                .iter()
                .map(|&v| vm.string(v))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(vm.alloc(Text(parts.concat())))
        }
        "string=?" => {
            arity(name, args, 2, usize::MAX)?;
            let texts = args
                .iter()
                .map(|&v| vm.string(v))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(Value::boolean(
                texts.windows(2).all(|pair| pair[0] == pair[1]),
            ))
        }
        "string->number" | "number->string" => convert_number(vm, name, args),
        "string-contains" => string_contains(vm, args),
        "string->symbol" => {
            arity(name, args, 1, 1)?;
            Ok(vm.intern(&vm.string(args[0])?))
        }
        "symbol->string" => {
            arity(name, args, 1, 1)?;
            let Symbol(symbol) = vm.heap.get(args[0])?;
            let text = symbol.clone();
            Ok(vm.alloc(Text(text)))
        }
        "string-length" => {
            arity(name, args, 1, 1)?;
            length_value(vm, vm.string(args[0])?.chars().count())
        }
        "string-ref" => {
            arity(name, args, 2, 2)?;
            vm.string(args[0])?
                .chars()
                .nth(args[1].index(&vm.heap)?)
                .map(Value::character)
                .ok_or_else(|| "string index out of range".into())
        }
        "substring" => {
            arity(name, args, 3, 3)?;
            let text: Vec<char> = vm.string(args[0])?.chars().collect();
            let start = args[1].index(&vm.heap)?;
            let end = args[2].index(&vm.heap)?;
            let part = text
                .get(start..end)
                .ok_or("substring indices out of range")?;
            Ok(vm.alloc(Text(part.iter().collect())))
        }
        _ => unreachable!(),
    }
}

fn string_contains(vm: &mut Vm, args: &[Value]) -> Result<Value, String> {
    arity("string-contains", args, 2, 3)?;
    let text = &vm.heap.get::<Text>(args[0])?.0;
    let pattern = &vm.heap.get::<Text>(args[1])?.0;
    let start = match args.get(2) {
        Some(n) => n.index(&vm.heap)?,
        None => 0,
    };
    let byte_start = text
        .char_indices()
        .map(|(index, _)| index)
        .chain([text.len()])
        .nth(start)
        .ok_or("string-contains: start index out of range")?;
    let found = text[byte_start..]
        .find(pattern)
        .map(|index| start + text[byte_start..byte_start + index].chars().count());
    match found {
        Some(index) => length_value(vm, index),
        None => Ok(Value::FALSE),
    }
}

fn gc_statistics(vm: &mut Vm) -> Result<Value, String> {
    let stats = vm.gc_statistics();
    let counts = [
        stats.collections,
        stats.total_nanoseconds,
        stats.max_nanoseconds,
        stats.allocated,
        stats.reclaimed,
        stats.live as u64,
        stats.peak as u64,
    ];
    let values = counts
        .into_iter()
        .map(|n| {
            i64::try_from(n)
                .map(|n| vm.integer(n))
                .map_err(|_| "GC statistic exceeds i64 range")
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(vm.alloc(Vector(values)))
}

fn convert_number(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    arity(name, args, 1, 2)?;
    let radix = match args.get(1) {
        Some(v) => v.integer(&vm.heap)?,
        None => 10,
    };
    if !matches!(radix, 2 | 8 | 10 | 16) {
        return Err("unsupported numeric radix".into());
    }
    if name == "string->number" {
        let text = vm.string(args[0])?;
        match i64::from_str_radix(&text, radix as u32) {
            Ok(n) => return Ok(vm.integer(n)),
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
                return Ok(vm.float(n));
            }
        }
        return Ok(Value::boolean(false));
    }
    let text = match vm.heap.number(args[0])? {
        Number::Integer(n) => {
            let magnitude = n.unsigned_abs();
            let digits = match radix {
                2 => format!("{magnitude:b}"),
                8 => format!("{magnitude:o}"),
                16 => format!("{magnitude:x}"),
                _ => magnitude.to_string(),
            };
            if n < 0 { format!("-{digits}") } else { digits }
        }
        Number::Float(n) if radix == 10 => float_text(n),
        Number::Float(_) => return Err("inexact number requires decimal radix".into()),
    };
    Ok(vm.alloc(Text(text)))
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

fn character(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
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
        return u32::try_from(args[0].integer(&vm.heap)?)
            .ok()
            .and_then(char::from_u32)
            .map(Value::character)
            .ok_or_else(|| "integer->char: invalid Unicode scalar value".into());
    }
    let chars = args
        .iter()
        .map(|&v| char_value(v))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(match name {
        "char->integer" => vm.integer(i64::from(chars[0] as u32)),
        "char-alphabetic?" => Value::boolean(chars[0].is_alphabetic()),
        "char-numeric?" => Value::boolean(chars[0].is_numeric()),
        "char-whitespace?" => Value::boolean(chars[0].is_whitespace()),
        _ => Value::boolean(chars.windows(2).all(|p| match name {
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
    Ok(vm.heap.get::<Symbol>(value)?.0.clone())
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
        return Ok(vm.alloc(RecordType { name, fields }));
    }
    let RecordType {
        fields: field_names,
        ..
    } = vm.heap.get::<RecordType>(args[0])?;
    if name == "%record?" {
        return Ok(Value::boolean(matches!(vm.heap.get::<Record>(args[1]),
            Ok(Record { descriptor, .. }) if *descriptor == args[0])));
    }
    if name == "%make-record" {
        let names = symbol_list(vm, args[1])?;
        let values = vm.list_values(args[2])?;
        let fields = constructor_fields(field_names, &names, values)?;
        return Ok(vm.alloc(Record {
            descriptor: args[0],
            fields,
        }));
    }
    let field = symbol_name(vm, args[1])?;
    let index = field_names
        .iter()
        .position(|name| name == &field)
        .ok_or("unknown record field")?;
    let Record { descriptor, fields } = vm.heap.get_mut(args[2])?;
    if *descriptor != args[0] {
        return Err("record belongs to a different record type".into());
    }
    if name == "%record-ref" {
        Ok(fields[index])
    } else {
        fields[index] = args[3];
        Ok(Value::UNSPECIFIED)
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
    let mut fields = vec![Value::UNSPECIFIED; field_names.len()];
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
            PrintTask::Tail(Value::NIL) => {}
            PrintTask::Tail(value) => {
                if let Ok(Pair(car, cdr)) = vm.heap.get(value) {
                    let index = value.address().unwrap();
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
    if let Some(text) = immediate_text(value) {
        output.push_str(text);
    } else if let Ok(number) = vm.heap.number(value) {
        output.push_str(&match number {
            Number::Integer(n) => n.to_string(),
            Number::Float(n) => float_text(n),
        });
    } else if let Some(ch) = value.as_character() {
        print_character(output, ch, display);
    } else {
        print_object(vm, value, display, output, pending, active)?;
    }
    Ok(())
}

fn immediate_text(value: Value) -> Option<&'static str> {
    match value {
        Value::NIL => Some("()"),
        Value::TRUE => Some("#t"),
        Value::FALSE => Some("#f"),
        Value::EOF => Some("#<eof>"),
        Value::UNSPECIFIED => Some("#<unspecified>"),
        Value::UNINITIALIZED => Some("#<uninitialized>"),
        _ => None,
    }
}

fn print_character(output: &mut String, ch: char, display: bool) {
    if display {
        output.push(ch);
        return;
    }
    output.push_str("#\\");
    match ch {
        ' ' => output.push_str("space"),
        '\n' => output.push_str("newline"),
        '\t' => output.push_str("tab"),
        '\r' => output.push_str("return"),
        _ => output.push(ch),
    }
}

fn print_object(
    vm: &Vm,
    value: Value,
    display: bool,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut HashSet<usize>,
) -> Result<(), String> {
    let address = value.address().ok_or("invalid tagged value")?;
    if !active.insert(address) {
        output.push_str("#<cycle>");
        return Ok(());
    }
    pending.push(PrintTask::Leave(address));
    if let Some(Text(text)) = vm.heap.find::<Text>(value) {
        if display {
            output.push_str(text);
        } else {
            quoted_string(output, text);
        }
    } else if let Some(Symbol(text)) = vm.heap.find::<Symbol>(value) {
        output.push_str(text);
    } else if let Some(Pair(car, cdr)) = vm.heap.find::<Pair>(value) {
        output.push('(');
        pending.push(PrintTask::Text(")".into()));
        pending.push(PrintTask::Tail(*cdr));
        pending.push(PrintTask::Value(*car));
    } else if let Some(Vector(values)) = vm.heap.find::<Vector>(value) {
        print_vector(output, pending, values);
    } else if let Some(Bytevector(bytes)) = vm.heap.find::<Bytevector>(value) {
        output.push_str("#u8(");
        output.push_str(
            &bytes
                .iter()
                .map(u8::to_string)
                .collect::<Vec<_>>()
                .join(" "),
        );
        output.push(')');
    } else {
        print_opaque(vm, value, output)?;
    }
    Ok(())
}

fn print_vector(output: &mut String, pending: &mut Vec<PrintTask>, values: &[Value]) {
    output.push_str("#(");
    pending.push(PrintTask::Text(")".into()));
    for (position, &value) in values.iter().enumerate().rev() {
        pending.push(PrintTask::Value(value));
        if position > 0 {
            pending.push(PrintTask::Text(" ".into()));
        }
    }
}

fn print_opaque(vm: &Vm, value: Value, output: &mut String) -> Result<(), String> {
    if let Some(RecordType { name, .. }) = vm.heap.find::<RecordType>(value) {
        output.push_str(&format!("#<record-type {name}>"));
    } else if let Some(Record { descriptor, .. }) = vm.heap.find::<Record>(value) {
        output.push_str(&format!(
            "#<record {}>",
            vm.heap.get::<RecordType>(*descriptor)?.name
        ));
    } else if let Some(Primitive(name)) = vm.heap.find::<Primitive>(value) {
        output.push_str(&format!("#<procedure {name}>"));
    } else if vm.heap.find::<Closure>(value).is_some() {
        output.push_str("#<procedure>");
    } else if vm.heap.find::<Cell>(value).is_some() {
        output.push_str("#<cell>");
    } else if vm.heap.find::<host::Port>(value).is_some() {
        output.push_str("#<port>");
    } else {
        return Err("invalid heap reference".into());
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

    fn integer(value: i64) -> Value {
        Value::fixnum(value).unwrap()
    }

    fn vm() -> Vm {
        Vm::new(0, 0, vec!["test".into()])
    }

    fn initialized_float(text: &str) -> f64 {
        let mut vm = Vm::new(0, 1, Vec::new());
        unsafe {
            crate::snail_const_atom(&mut vm, 0, 3, text.as_ptr(), text.len() as u32);
        }
        assert_eq!(vm.error(), None);
        vm.heap.get::<Float>(vm.constant(0).unwrap()).unwrap().0
    }

    #[test]
    fn substring_search_returns_character_indices_and_honors_start() {
        let mut vm = vm();
        let text = vm.alloc(Text("aλ😀λ".into()));
        let pattern = vm.alloc(Text("λ".into()));
        let empty = vm.alloc(Text(String::new()));
        assert_eq!(
            string_contains(&mut vm, &[text, pattern]).unwrap(),
            integer(1)
        );
        assert_eq!(
            string_contains(&mut vm, &[text, pattern, integer(2)]).unwrap(),
            integer(3)
        );
        assert_eq!(
            string_contains(&mut vm, &[text, pattern, integer(4)]).unwrap(),
            Value::FALSE
        );
        assert_eq!(
            string_contains(&mut vm, &[text, empty, integer(4)]).unwrap(),
            integer(4)
        );
        assert!(string_contains(&mut vm, &[text, pattern, integer(5)]).is_err());
    }

    #[test]
    fn floating_constants_and_numeric_reader_agree() {
        for text in ["1.25", "+inf.0", "-inf.0", "+nan.0"] {
            let mut vm = vm();
            let string = vm.alloc(Text(text.into()));
            let read = convert_number(&mut vm, "string->number", &[string]).unwrap();
            let literal = initialized_float(text);
            let read = vm.heap.get::<Float>(read).unwrap().0;
            assert!(literal == read || (literal.is_nan() && read.is_nan()));
        }
    }

    #[test]
    fn integer_arithmetic_rejects_overflow_and_zero_division() {
        assert!(arithmetic("+", &[Number::Integer(i64::MAX), Number::Integer(1)]).is_err());
        assert!(arithmetic("-", &[Number::Integer(i64::MIN)]).is_err());
        assert!(arithmetic("/", &[Number::Integer(i64::MIN), Number::Integer(-1)]).is_err());
        assert!(arithmetic("quotient", &[Number::Integer(7), Number::Integer(0)]).is_err());
        assert!(arithmetic("/", &[Number::Float(7.0), Number::Float(0.0)]).is_err());
        assert_eq!(
            arithmetic("/", &[Number::Integer(9), Number::Integer(3)]).unwrap(),
            Number::Integer(3)
        );
        assert_eq!(
            arithmetic("/", &[Number::Integer(9), Number::Integer(2)]).unwrap(),
            Number::Float(4.5)
        );
        assert_eq!(
            arithmetic("modulo", &[Number::Integer(-7), Number::Integer(3)]).unwrap(),
            Number::Integer(2)
        );
        assert_eq!(
            arithmetic("modulo", &[Number::Integer(7), Number::Integer(-3)]).unwrap(),
            Number::Integer(-2)
        );
    }

    #[test]
    fn mixed_comparisons_preserve_large_integer_precision() {
        let exact = Number::Integer(9_007_199_254_740_993);
        let rounded = Number::Float(9_007_199_254_740_992.0);
        assert_eq!(
            numeric_compare(">", &[exact, rounded]).unwrap(),
            Value::boolean(true)
        );
        assert_eq!(
            numeric_compare("=", &[exact, rounded]).unwrap(),
            Value::boolean(false)
        );
        assert_eq!(
            numeric_compare(
                "<",
                &[
                    Number::Integer(i64::MAX),
                    Number::Float(9223372036854775808.0)
                ]
            )
            .unwrap(),
            Value::boolean(true)
        );
        assert_eq!(
            numeric_compare("=", &[Number::Float(f64::NAN), Number::Float(f64::NAN)]).unwrap(),
            Value::boolean(false)
        );
    }

    #[test]
    fn numeric_reader_does_not_silently_make_overflowing_integers_inexact() {
        let mut vm = vm();
        for text in ["9223372036854775808", "-9223372036854775809"] {
            let text = vm.alloc(Text(text.into()));
            assert!(
                convert_number(&mut vm, "string->number", &[text])
                    .unwrap_err()
                    .contains("overflow")
            );
        }
        let text = vm.alloc(Text("8000000000000000".into()));
        assert!(convert_number(&mut vm, "string->number", &[text, integer(16)]).is_err());
        let text = vm.alloc(Text("9.5e2".into()));
        let value = convert_number(&mut vm, "string->number", &[text]).unwrap();
        assert_eq!(vm.heap.get::<Float>(value).unwrap().0, 950.0);
        let text = vm.alloc(Text("NaN".into()));
        assert_eq!(
            convert_number(&mut vm, "string->number", &[text]).unwrap(),
            Value::boolean(false)
        );
    }

    #[test]
    fn string_indices_count_unicode_scalars_and_check_bounds() {
        let mut vm = vm();
        let text = vm.alloc(Text("aλ😀z".into()));
        assert_eq!(
            string(&mut vm, "string-length", &[text]).unwrap(),
            integer(4)
        );
        assert_eq!(
            string(&mut vm, "string-ref", &[text, integer(2)]).unwrap(),
            Value::character('😀')
        );
        let part = string(&mut vm, "substring", &[text, integer(1), integer(3)]).unwrap();
        assert_eq!(vm.string(part).unwrap(), "λ😀");
        assert!(string(&mut vm, "substring", &[text, integer(3), integer(1)]).is_err());
        assert!(string(&mut vm, "string-ref", &[text, integer(4)]).is_err());
        assert!(string(&mut vm, "string-ref", &[text, integer(-1)]).is_err());
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
        let values = vm.list(&[integer(20), integer(10)]);
        let instance =
            record(&mut vm, "%make-record", &[descriptor, constructors, values]).unwrap();
        assert_eq!(
            record(&mut vm, "%record-ref", &[descriptor, x, instance]).unwrap(),
            integer(10)
        );
        assert_eq!(
            record(&mut vm, "%record-ref", &[descriptor, y, instance]).unwrap(),
            integer(20)
        );
        assert_eq!(
            record(&mut vm, "%record?", &[other_descriptor, instance]).unwrap(),
            Value::boolean(false)
        );
        assert!(record(&mut vm, "%record-ref", &[other_descriptor, x, instance]).is_err());
        record(
            &mut vm,
            "%record-set!",
            &[descriptor, x, instance, integer(42)],
        )
        .unwrap();
        assert_eq!(
            record(&mut vm, "%record-ref", &[descriptor, x, instance]).unwrap(),
            integer(42)
        );
    }

    #[test]
    fn printing_handles_cycles_and_shared_acyclic_objects() {
        let mut vm = vm();
        let cycle = vm.alloc(Pair(integer(1), Value::NIL));
        pair(&mut vm, "set-cdr!", &[cycle, cycle]).unwrap();
        assert_eq!(format_value(&vm, cycle, false).unwrap(), "(1 . #<cycle>)");
        let shared = vm.list(&[integer(2), integer(3)]);
        let vector = vm.alloc(Vector(vec![shared, shared]));
        assert_eq!(format_value(&vm, vector, false).unwrap(), "#((2 3) (2 3))");
        let text = vm.alloc(Text("λ\n\"\\".into()));
        assert_eq!(format_value(&vm, text, true).unwrap(), "λ\n\"\\");
        assert_eq!(format_value(&vm, text, false).unwrap(), "\"λ\\n\\\"\\\\\"");
    }

    #[test]
    fn deep_printing_does_not_consume_the_host_call_stack() {
        let mut vm = vm();
        let mut value = integer(1);
        for _ in 0..20_000 {
            value = vm.alloc(Pair(value, Value::NIL));
        }
        assert_eq!(format_value(&vm, value, false).unwrap().len(), 40_001);
    }
}
