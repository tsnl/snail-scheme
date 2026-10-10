//! Checked Scheme operations. Allocation here never triggers collection; the
//! calling VM handler publishes its results before the next safepoint.

use crate::{
    host,
    object::*,
    vm::{Allocation, Runtime},
};
use std::{cmp::Ordering, collections::HashSet};

// ---- Builtin identities and allocation effects ----

// Every builtin's spelling and managed-allocation effect are declared together.
// Rust-owned strings/vectors may grow in nonallocating operations; only Scheme
// heap allocation requires an Allocation capability and a preceding safepoint.
macro_rules! builtins {
    ($($variant:ident => ($name:literal, $allocates:literal)),* $(,)?) => {
        #[derive(Clone, Copy, Debug, Eq, PartialEq)]
        pub(crate) enum Builtin { $($variant),* }

        impl Builtin {
            #[cfg(test)]
            const ALL: &'static [Self] = &[$(Self::$variant),*];

            pub(crate) fn from_name(name: &str) -> Result<Self, String> {
                match name {
                    "call/cc" => Ok(Self::CallWithCurrentContinuation),
                    $($name => Ok(Self::$variant),)*
                    _ => Err(format!("unknown primitive: {name}")),
                }
            }

            pub(crate) fn name(self) -> &'static str {
                match self { $(Self::$variant => $name),* }
            }

            pub(crate) fn may_allocate(self) -> bool {
                match self { $(Self::$variant => $allocates),* }
            }
        }
    };
}

builtins! {
    Add => ("+", true),
    Subtract => ("-", true),
    Multiply => ("*", true),
    Divide => ("/", true),
    Quotient => ("quotient", true),
    Remainder => ("remainder", true),
    Modulo => ("modulo", true),
    NumericEqual => ("=", false),
    Less => ("<", false),
    LessEqual => ("<=", false),
    Greater => (">", false),
    GreaterEqual => (">=", false),
    Eq => ("eq?", false),
    Eqv => ("eqv?", false),
    IsBoolean => ("boolean?", false),
    IsNumber => ("number?", false),
    IsReal => ("real?", false),
    IsInexact => ("inexact?", false),
    IsInteger => ("integer?", false),
    IsExactInteger => ("exact-integer?", false),
    IsPair => ("pair?", false),
    IsNull => ("null?", false),
    IsSymbol => ("symbol?", false),
    IsString => ("string?", false),
    IsChar => ("char?", false),
    IsVector => ("vector?", false),
    IsBytevector => ("bytevector?", false),
    IsProcedure => ("procedure?", false),
    Cons => ("cons", true),
    Car => ("car", false),
    Cdr => ("cdr", false),
    SetCar => ("set-car!", false),
    SetCdr => ("set-cdr!", false),
    Vector => ("vector", true),
    MakeVector => ("make-vector", true),
    VectorRef => ("vector-ref", false),
    VectorSet => ("vector-set!", false),
    VectorLength => ("vector-length", true),
    Bytevector => ("bytevector", true),
    BytevectorLength => ("bytevector-length", true),
    BytevectorRef => ("bytevector-u8-ref", false),
    BytevectorSet => ("bytevector-u8-set!", false),
    String => ("string", true),
    StringRef => ("string-ref", false),
    StringLength => ("string-length", true),
    StringAppend => ("string-append", true),
    Substring => ("substring", true),
    StringEqual => ("string=?", false),
    StringToSymbol => ("string->symbol", false),
    SymbolToString => ("symbol->string", true),
    StringToNumber => ("string->number", true),
    NumberToString => ("number->string", true),
    StringContains => ("string-contains", true),
    CharToInteger => ("char->integer", false),
    IntegerToChar => ("integer->char", false),
    CharEqual => ("char=?", false),
    CharLess => ("char<?", false),
    CharLessEqual => ("char<=?", false),
    CharGreater => ("char>?", false),
    CharGreaterEqual => ("char>=?", false),
    CharCiEqual => ("char-ci=?", false),
    IsCharAlphabetic => ("char-alphabetic?", false),
    IsCharNumeric => ("char-numeric?", false),
    IsCharWhitespace => ("char-whitespace?", false),
    MakeRecordType => ("%make-record-type", true),
    MakeRecord => ("%make-record", true),
    IsRecord => ("%record?", false),
    RecordRef => ("%record-ref", false),
    RecordSet => ("%record-set!", false),
    TraceBegin => ("%trace-begin", false),
    TraceEnd => ("%trace-end", false),
    CollectGarbage => ("collect-garbage", false),
    GcStatistics => ("gc-statistics", true),
    Values => ("values", false),
    CallWithValues => ("call-with-values", false),
    CallWithCurrentContinuation => ("call-with-current-continuation", true),
    Apply => ("apply", false),
    Error => ("error", false),
    OpenInputFile => ("open-input-file", true),
    OpenOutputFile => ("open-output-file", true),
    ClosePort => ("close-port", false),
    ReadChar => ("read-char", false),
    ReadString => ("read-string", true),
    IsEof => ("eof-object?", false),
    OpenOutputString => ("open-output-string", true),
    GetOutputString => ("get-output-string", true),
    Display => ("display", false),
    Write => ("write", false),
    Newline => ("newline", false),
    CurrentInputPort => ("%current-input-port", false),
    CurrentOutputPort => ("%current-output-port", false),
    CurrentErrorPort => ("%current-error-port", false),
    SetCurrentInputPort => ("%set-current-input-port!", false),
    SetCurrentOutputPort => ("%set-current-output-port!", false),
    SetCurrentErrorPort => ("%set-current-error-port!", false),
    CommandLine => ("command-line", true),
    Exit => ("exit", false),
    CurrentJiffy => ("current-jiffy", true),
    JiffiesPerSecond => ("jiffies-per-second", false),
}

// ---- Callable boundaries ----

pub(crate) enum PrimitiveResult {
    Value(Value),
    Invoke(Value, Vec<Value>),
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

pub(crate) fn invoke(
    vm: &mut Runtime,
    op: Builtin,
    args: &[Value],
) -> Result<PrimitiveResult, String> {
    use Builtin::*;
    let name = op.name();
    let value = match op {
        NumericEqual | Less | LessEqual | Greater | GreaterEqual => numeric_compare(vm, op, args)?,
        Eq | Eqv => {
            arity(name, args, 2, 2)?;
            Value::boolean(equivalent(vm, args[0], args[1]))
        }
        IsBoolean | IsNumber | IsReal | IsInexact | IsInteger | IsExactInteger | IsPair
        | IsNull | IsSymbol | IsString | IsChar | IsVector | IsBytevector | IsProcedure => {
            arity(name, args, 1, 1)?;
            predicate(vm, op, args[0])
        }
        Car | Cdr | SetCar | SetCdr => pair(vm, op, args)?,
        VectorRef | VectorSet => vector_access(vm, op, args)?,
        BytevectorRef | BytevectorSet => bytevector_access(vm, op, args)?,
        StringRef | StringEqual | StringToSymbol => string_access(vm, op, args)?,
        CharToInteger | IntegerToChar | CharEqual | CharLess | CharLessEqual | CharGreater
        | CharGreaterEqual | CharCiEqual | IsCharAlphabetic | IsCharNumeric | IsCharWhitespace => {
            character(vm, op, args)?
        }
        IsRecord | RecordRef | RecordSet => record_access(vm, op, args)?,
        TraceBegin => {
            arity(name, args, 1, 1)?;
            snail_trace::begin(vm.string(args[0])?);
            Value::UNSPECIFIED
        }
        TraceEnd => {
            arity(name, args, 0, 0)?;
            snail_trace::end();
            Value::UNSPECIFIED
        }
        CollectGarbage => {
            arity(name, args, 0, 0)?;
            return Ok(PrimitiveResult::Collect);
        }
        Values | CallWithValues => return Err(format!("{name} requires VM control")),
        Apply => {
            arity(name, args, 2, usize::MAX)?;
            let mut arguments = args[1..args.len() - 1].to_vec();
            arguments.extend(vm.list_values(args[args.len() - 1])?);
            return Ok(PrimitiveResult::Invoke(args[0], arguments));
        }
        Error => {
            arity(name, args, 1, usize::MAX)?;
            let messages = args
                .iter()
                .map(|v| format_value(vm, *v, true))
                .collect::<Result<Vec<_>, _>>()?;
            return Err(messages.join(" "));
        }
        ClosePort | ReadChar | IsEof | Display | Write | Newline | CurrentInputPort
        | CurrentOutputPort | CurrentErrorPort | SetCurrentInputPort | SetCurrentOutputPort
        | SetCurrentErrorPort | Exit | JiffiesPerSecond => return host::invoke(vm, op, args),
        _ => return Err(format!("{} requires an allocation capability", op.name())),
    };
    Ok(PrimitiveResult::Value(value))
}

pub(crate) fn invoke_allocating(
    mut vm: Allocation<'_>,
    op: Builtin,
    args: &[Value],
) -> Result<PrimitiveResult, String> {
    use Builtin::*;
    let value = match op {
        Add | Subtract | Multiply | Divide | Quotient | Remainder | Modulo => {
            arithmetic_values(&mut vm, op, args)?
        }
        Cons => {
            arity(op.name(), args, 2, 2)?;
            vm.alloc(crate::object::Pair(args[0], args[1]))
        }
        Vector | MakeVector | VectorLength => vector(&mut vm, op, args)?,
        Bytevector | BytevectorLength => bytevector(&mut vm, op, args)?,
        String | StringLength | StringAppend | Substring | SymbolToString | StringToNumber
        | NumberToString | StringContains => string(&mut vm, op, args)?,
        MakeRecordType | MakeRecord => record(&mut vm, op, args)?,
        GcStatistics => {
            arity(op.name(), args, 0, 0)?;
            gc_statistics(&mut vm)?
        }
        CallWithCurrentContinuation => {
            arity(op.name(), args, 1, 1)?;
            return Err("call-with-current-continuation requires VM control".into());
        }
        OpenInputFile | OpenOutputFile | ReadString | OpenOutputString | GetOutputString
        | CommandLine | CurrentJiffy => return host::invoke_allocating(&mut vm, op, args),
        _ => {
            return Err(format!(
                "{} does not require an allocation capability",
                op.name()
            ));
        }
    };
    Ok(PrimitiveResult::Value(value))
}

// ---- Numbers and predicates ----

fn arithmetic_values(
    vm: &mut Allocation<'_>,
    op: Builtin,
    args: &[Value],
) -> Result<Value, String> {
    let number = arithmetic(vm, op, args)?;
    Ok(match number {
        Number::Integer(n) => vm.integer(n),
        Number::Float(n) => vm.float(n),
    })
}

fn equivalent(vm: &Runtime, left: Value, right: Value) -> bool {
    match (vm.heap.number(left), vm.heap.number(right)) {
        (Ok(a), Ok(b)) => a == b,
        _ => left == right,
    }
}

fn arithmetic(vm: &Runtime, op: Builtin, args: &[Value]) -> Result<Number, String> {
    use Builtin::*;
    let identity = matches!(op, Add | Multiply);
    let minimum = if identity { 0 } else { 1 };
    if matches!(op, Quotient | Remainder | Modulo) {
        arity(op.name(), args, 2, 2)?;
        let a = args[0].integer(&vm.heap)?;
        let b = args[1].integer(&vm.heap)?;
        let value = if op == Quotient {
            a.checked_div(b)
        } else {
            a.checked_rem(b)
        }
        .ok_or_else(|| format!("{}: division by zero or integer overflow", op.name()))?;
        return Ok(Number::Integer(
            if op == Modulo && value != 0 && (value < 0) != (b < 0) {
                value + b
            } else {
                value
            },
        ));
    }
    arity(op.name(), args, minimum, usize::MAX)?;
    // Decode each argument once; no argument-number vector or heap allocation.
    // Exact arithmetic stays exact until an inexact operand/nonintegral division.
    let (mut result, rest) = if identity || args.len() == 1 {
        (
            Number::Integer(if matches!(op, Add | Subtract) { 0 } else { 1 }),
            args,
        )
    } else {
        (vm.heap.number(args[0])?, &args[1..])
    };
    for &value in rest {
        result = numeric_step(op, result, vm.heap.number(value)?)?;
    }
    Ok(result)
}

fn numeric_step(op: Builtin, left: Number, right: Number) -> Result<Number, String> {
    let name = op.name();
    if let (Number::Integer(a), Number::Integer(b)) = (left, right) {
        let exact = match op {
            Builtin::Add => a.checked_add(b),
            Builtin::Subtract => a.checked_sub(b),
            Builtin::Multiply => a.checked_mul(b),
            Builtin::Divide => {
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
    Ok(Number::Float(match op {
        Builtin::Add => a + b,
        Builtin::Subtract => a - b,
        Builtin::Multiply => a * b,
        Builtin::Divide => {
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

fn numeric_compare(vm: &Runtime, op: Builtin, args: &[Value]) -> Result<Value, String> {
    arity(op.name(), args, 2, usize::MAX)?;
    let mut previous = vm.heap.number(args[0])?;
    let mut matches = true;
    for &value in &args[1..] {
        let next = vm.heap.number(value)?;
        matches &= number_matches(op, previous, next);
        previous = next;
    }
    // Deliberately inspect every operand even after a false comparison, so a
    // later non-number still raises the same checked argument error.
    Ok(Value::boolean(matches))
}

fn number_matches(op: Builtin, left: Number, right: Number) -> bool {
    let comparison = match (left, right) {
        (Number::Integer(a), Number::Integer(b)) => Some(a.cmp(&b)),
        (Number::Integer(a), Number::Float(b)) => compare_integer_float(a, b),
        (Number::Float(a), Number::Integer(b)) => {
            compare_integer_float(b, a).map(Ordering::reverse)
        }
        (Number::Float(a), Number::Float(b)) => a.partial_cmp(&b),
    };
    match op {
        Builtin::NumericEqual => comparison == Some(Ordering::Equal),
        Builtin::Less => comparison == Some(Ordering::Less),
        Builtin::Greater => comparison == Some(Ordering::Greater),
        Builtin::LessEqual => matches!(comparison, Some(Ordering::Less | Ordering::Equal)),
        Builtin::GreaterEqual => matches!(comparison, Some(Ordering::Greater | Ordering::Equal)),
        _ => unreachable!(),
    }
}

fn predicate(vm: &Runtime, op: Builtin, value: Value) -> Value {
    Value::boolean(match op {
        Builtin::IsBoolean => value.is_boolean(),
        Builtin::IsNumber | Builtin::IsReal => vm.heap.number(value).is_ok(),
        Builtin::IsInexact => vm.heap.find::<Float>(value).is_some(),
        Builtin::IsInteger => match vm.heap.number(value) {
            Ok(Number::Integer(_)) => true,
            Ok(Number::Float(n)) => n.is_finite() && n.fract() == 0.0,
            Err(_) => false,
        },
        Builtin::IsExactInteger => value.as_integer(&vm.heap).is_some(),
        Builtin::IsNull => value == Value::NIL,
        Builtin::IsChar => value.as_character().is_some(),
        Builtin::IsPair => vm.heap.find::<Pair>(value).is_some(),
        Builtin::IsSymbol => value.as_symbol().is_some(),
        Builtin::IsString => vm.heap.find::<Text>(value).is_some(),
        Builtin::IsVector => vm.heap.find::<Vector>(value).is_some(),
        Builtin::IsBytevector => vm.heap.find::<Bytevector>(value).is_some(),
        Builtin::IsProcedure => {
            vm.heap.find::<Closure>(value).is_some()
                || vm.heap.find::<Primitive>(value).is_some()
                || vm.heap.find::<Continuation>(value).is_some()
        }
        _ => unreachable!(),
    })
}

// ---- Pairs and vectors ----

fn pair(vm: &mut Runtime, op: Builtin, args: &[Value]) -> Result<Value, String> {
    let count = if matches!(op, Builtin::Car | Builtin::Cdr) {
        1
    } else {
        2
    };
    arity(op.name(), args, count, count)?;
    let Pair(car, cdr) = vm.heap.get_mut(args[0])?;
    match op {
        Builtin::Car => Ok(*car),
        Builtin::Cdr => Ok(*cdr),
        Builtin::SetCar => {
            *car = args[1];
            Ok(Value::UNSPECIFIED)
        }
        Builtin::SetCdr => {
            *cdr = args[1];
            Ok(Value::UNSPECIFIED)
        }
        _ => unreachable!(),
    }
}

fn vector(vm: &mut Allocation<'_>, op: Builtin, args: &[Value]) -> Result<Value, String> {
    if op == Builtin::Vector {
        return Ok(vm.alloc(Vector(args.to_vec())));
    }
    if op == Builtin::VectorLength {
        arity(op.name(), args, 1, 1)?;
        let length = vm.heap.get::<Vector>(args[0])?.0.len();
        return length_value(vm, length);
    }
    arity(op.name(), args, 1, 2)?;
    let length = args[0].index(&vm.heap)?;
    let fill = args.get(1).copied().unwrap_or(Value::UNSPECIFIED);
    let mut elements = Vec::new();
    elements
        .try_reserve_exact(length)
        .map_err(|_| "make-vector: allocation too large")?;
    elements.resize(length, fill);
    Ok(vm.alloc(Vector(elements)))
}

fn vector_access(vm: &mut Runtime, op: Builtin, args: &[Value]) -> Result<Value, String> {
    let count = if op == Builtin::VectorRef { 2 } else { 3 };
    arity(op.name(), args, count, count)?;
    let index = args[1].index(&vm.heap)?;
    let element = vm
        .heap
        .get_mut::<Vector>(args[0])?
        .0
        .get_mut(index)
        .ok_or("vector index out of range")?;
    if op == Builtin::VectorRef {
        Ok(*element)
    } else {
        *element = args[2];
        Ok(Value::UNSPECIFIED)
    }
}

fn byte(vm: &Runtime, value: Value) -> Result<u8, String> {
    u8::try_from(value.integer(&vm.heap)?).map_err(|_| "expected a byte between 0 and 255".into())
}

fn bytevector(vm: &mut Allocation<'_>, op: Builtin, args: &[Value]) -> Result<Value, String> {
    if op == Builtin::Bytevector {
        let bytes = args
            .iter()
            .map(|&v| byte(vm, v))
            .collect::<Result<Vec<_>, _>>()?;
        return Ok(vm.alloc(Bytevector(bytes)));
    }
    arity(op.name(), args, 1, 1)?;
    let length = vm.heap.get::<Bytevector>(args[0])?.0.len();
    length_value(vm, length)
}

fn bytevector_access(vm: &mut Runtime, op: Builtin, args: &[Value]) -> Result<Value, String> {
    let count = if op == Builtin::BytevectorRef { 2 } else { 3 };
    arity(op.name(), args, count, count)?;
    let index = args[1].index(&vm.heap)?;
    let new_byte = if op == Builtin::BytevectorSet {
        byte(vm, args[2])?
    } else {
        0
    };
    let element = vm
        .heap
        .get_mut::<Bytevector>(args[0])?
        .0
        .get_mut(index)
        .ok_or("bytevector index out of range")?;
    if op == Builtin::BytevectorRef {
        Ok(Value::fixnum(i64::from(*element)).unwrap())
    } else {
        *element = new_byte;
        Ok(Value::UNSPECIFIED)
    }
}

fn length_value(vm: &mut Allocation<'_>, length: usize) -> Result<Value, String> {
    i64::try_from(length)
        .map(|n| vm.integer(n))
        .map_err(|_| "length exceeds integer range".into())
}

fn char_value(value: Value) -> Result<char, String> {
    value
        .as_character()
        .ok_or_else(|| "expected a character".into())
}

// ---- Strings ----

fn string(vm: &mut Allocation<'_>, op: Builtin, args: &[Value]) -> Result<Value, String> {
    match op {
        Builtin::String => {
            let text = args
                .iter()
                .map(|&v| char_value(v))
                .collect::<Result<std::string::String, _>>()?;
            Ok(vm.alloc(Text::new(text)))
        }
        Builtin::StringAppend => {
            let parts = args
                .iter()
                .map(|&v| vm.string(v))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(vm.alloc(Text::new(parts.concat())))
        }
        Builtin::StringToNumber | Builtin::NumberToString => convert_number(vm, op, args),
        Builtin::StringContains => string_contains(vm, args),
        Builtin::SymbolToString => {
            arity(op.name(), args, 1, 1)?;
            let text = vm.symbol_name(args[0])?.to_owned();
            Ok(vm.alloc(Text::new(text)))
        }
        Builtin::StringLength => {
            arity(op.name(), args, 1, 1)?;
            let length = vm.string(args[0])?.chars().count();
            length_value(vm, length)
        }
        Builtin::Substring => {
            arity(op.name(), args, 3, 3)?;
            let text = vm.string(args[0])?;
            let start = string_byte_offset(text, args[1].index(&vm.heap)?)
                .ok_or("substring indices out of range")?;
            let end = string_byte_offset(text, args[2].index(&vm.heap)?)
                .ok_or("substring indices out of range")?;
            let part = text
                .get(start..end)
                .ok_or("substring indices out of range")?
                .to_owned();
            Ok(vm.alloc(Text::new(part)))
        }
        _ => unreachable!(),
    }
}

fn string_access(vm: &mut Runtime, op: Builtin, args: &[Value]) -> Result<Value, String> {
    match op {
        Builtin::StringEqual => {
            arity(op.name(), args, 2, usize::MAX)?;
            let first = vm.string(args[0])?;
            let mut equal = true;
            for &value in &args[1..] {
                equal &= first == vm.string(value)?;
            }
            Ok(Value::boolean(equal))
        }
        Builtin::StringToSymbol => {
            arity(op.name(), args, 1, 1)?;
            let name = vm.string(args[0])?.to_owned();
            Ok(vm.intern(&name))
        }
        Builtin::StringRef => {
            arity(op.name(), args, 2, 2)?;
            vm.string(args[0])?
                .chars()
                .nth(args[1].index(&vm.heap)?)
                .map(Value::character)
                .ok_or_else(|| "string index out of range".into())
        }
        _ => unreachable!(),
    }
}

fn string_byte_offset(text: &str, index: usize) -> Option<usize> {
    text.char_indices()
        .map(|(offset, _)| offset)
        .chain([text.len()])
        .nth(index)
}

fn string_contains(vm: &mut Allocation<'_>, args: &[Value]) -> Result<Value, String> {
    arity("string-contains", args, 2, 3)?;
    let text = vm.string(args[0])?;
    let pattern = vm.string(args[1])?;
    let start = match args.get(2) {
        Some(n) => n.index(&vm.heap)?,
        None => 0,
    };
    let byte_start =
        string_byte_offset(text, start).ok_or("string-contains: start index out of range")?;
    let found = text[byte_start..]
        .find(pattern)
        .map(|index| start + text[byte_start..byte_start + index].chars().count());
    match found {
        Some(index) => length_value(vm, index),
        None => Ok(Value::FALSE),
    }
}

fn gc_statistics(vm: &mut Allocation<'_>) -> Result<Value, String> {
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

fn convert_number(vm: &mut Allocation<'_>, op: Builtin, args: &[Value]) -> Result<Value, String> {
    arity(op.name(), args, 1, 2)?;
    let radix = match args.get(1) {
        Some(v) => v.integer(&vm.heap)?,
        None => 10,
    };
    if !matches!(radix, 2 | 8 | 10 | 16) {
        return Err("unsupported numeric radix".into());
    }
    if op == Builtin::StringToNumber {
        let (text, radix) = strip_radix_prefix(vm.string(args[0])?, radix as u32);
        match i64::from_str_radix(text, radix) {
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
            let float = parse_float(text);
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
    Ok(vm.alloc(Text::new(text)))
}

fn strip_radix_prefix(text: &str, radix: u32) -> (&str, u32) {
    let radix = match text.as_bytes().get(..2) {
        Some([b'#', b'b' | b'B']) => 2,
        Some([b'#', b'o' | b'O']) => 8,
        Some([b'#', b'd' | b'D']) => 10,
        Some([b'#', b'x' | b'X']) => 16,
        _ => return (text, radix),
    };
    // A prefix overrides the supplied radix. Two ASCII bytes end on a UTF-8 boundary.
    (&text[2..], radix)
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

fn character(vm: &mut Runtime, op: Builtin, args: &[Value]) -> Result<Value, String> {
    let comparison = matches!(
        op,
        Builtin::CharEqual
            | Builtin::CharLess
            | Builtin::CharLessEqual
            | Builtin::CharGreater
            | Builtin::CharGreaterEqual
            | Builtin::CharCiEqual
    );
    arity(
        op.name(),
        args,
        if comparison { 2 } else { 1 },
        if comparison { usize::MAX } else { 1 },
    )?;
    if op == Builtin::IntegerToChar {
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
    Ok(match op {
        Builtin::CharToInteger => Value::fixnum(i64::from(chars[0] as u32)).unwrap(),
        Builtin::IsCharAlphabetic => Value::boolean(chars[0].is_alphabetic()),
        Builtin::IsCharNumeric => Value::boolean(chars[0].is_numeric()),
        Builtin::IsCharWhitespace => Value::boolean(chars[0].is_whitespace()),
        _ => Value::boolean(chars.windows(2).all(|p| match op {
            Builtin::CharEqual => p[0] == p[1],
            Builtin::CharLess => p[0] < p[1],
            Builtin::CharLessEqual => p[0] <= p[1],
            Builtin::CharGreater => p[0] > p[1],
            Builtin::CharGreaterEqual => p[0] >= p[1],
            // Baseline case-insensitive comparison uses Unicode lowercase.
            Builtin::CharCiEqual => p[0].to_lowercase().eq(p[1].to_lowercase()),
            _ => unreachable!(),
        })),
    })
}

fn symbol_name(vm: &Runtime, value: Value) -> Result<String, String> {
    Ok(vm.symbol_name(value)?.to_owned())
}

fn symbol_list(vm: &Runtime, value: Value) -> Result<Vec<String>, String> {
    vm.list_values(value)?
        .iter()
        .map(|&v| symbol_name(vm, v))
        .collect()
}

// ---- Records ----

fn record(vm: &mut Allocation<'_>, op: Builtin, args: &[Value]) -> Result<Value, String> {
    let count = if op == Builtin::MakeRecordType { 2 } else { 3 };
    arity(op.name(), args, count, count)?;
    if op == Builtin::MakeRecordType {
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
    let names = symbol_list(vm, args[1])?;
    let values = vm.list_values(args[2])?;
    let fields = constructor_fields(field_names, &names, values)?;
    Ok(vm.alloc(Record {
        descriptor: args[0],
        fields,
    }))
}

fn record_access(vm: &mut Runtime, op: Builtin, args: &[Value]) -> Result<Value, String> {
    let count = match op {
        Builtin::IsRecord => 2,
        Builtin::RecordSet => 4,
        _ => 3,
    };
    arity(op.name(), args, count, count)?;
    let RecordType {
        fields: field_names,
        ..
    } = vm.heap.get::<RecordType>(args[0])?;
    if op == Builtin::IsRecord {
        return Ok(Value::boolean(matches!(vm.heap.get::<Record>(args[1]),
            Ok(Record { descriptor, .. }) if *descriptor == args[0])));
    }
    let field = vm.symbol_name(args[1])?;
    let index = field_names
        .iter()
        .position(|name| name == field)
        .ok_or("unknown record field")?;
    let Record { descriptor, fields } = vm.heap.get_mut(args[2])?;
    if *descriptor != args[0] {
        return Err("record belongs to a different record type".into());
    }
    if op == Builtin::RecordRef {
        Ok(fields[index])
    } else {
        fields[index] = args[3];
        Ok(Value::UNSPECIFIED)
    }
}

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

// ---- Printing ----

enum PrintTask {
    Value(Value),
    Tail(Value),
    Text(String),
    Leave(usize),
}

/// Printing uses its own work stack, so deeply nested datums and cycles cannot
/// recurse through the host stack. Repeated acyclic references print normally.
pub(crate) fn format_value(vm: &Runtime, value: Value, display: bool) -> Result<String, String> {
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
    vm: &Runtime,
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
    } else if value.as_symbol().is_some() {
        output.push_str(vm.symbol_name(value)?);
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
    vm: &Runtime,
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
    if let Some(text) = vm.heap.find::<Text>(value) {
        let text = text.as_str();
        if display {
            output.push_str(text);
        } else {
            quoted_string(output, text);
        }
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

fn print_opaque(vm: &Runtime, value: Value, output: &mut String) -> Result<(), String> {
    if let Some(RecordType { name, .. }) = vm.heap.find::<RecordType>(value) {
        output.push_str(&format!("#<record-type {name}>"));
    } else if let Some(Record { descriptor, .. }) = vm.heap.find::<Record>(value) {
        output.push_str(&format!(
            "#<record {}>",
            vm.heap.get::<RecordType>(*descriptor)?.name
        ));
    } else if let Some(Primitive(name)) = vm.heap.find::<Primitive>(value) {
        output.push_str(&format!("#<procedure {}>", name.name()));
    } else if vm.heap.find::<Closure>(value).is_some() {
        output.push_str("#<procedure>");
    } else if vm.heap.find::<Continuation>(value).is_some() {
        output.push_str("#<continuation>");
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

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allocation_effects_route_every_builtin_to_its_implementation() {
        let mut vm = vm();
        // Four invalid values avoid host I/O while reaching each dispatch arm.
        let args = [Value::UNSPECIFIED; 4];
        for &op in Builtin::ALL {
            let result = if op.may_allocate() {
                invoke_allocating(vm.allocation(), op, &args)
            } else {
                invoke(&mut vm, op, &args)
            };
            if let Err(error) = result {
                assert!(
                    !error.contains("allocation capability"),
                    "{}: {error}",
                    op.name()
                );
            }
        }
    }

    #[test]
    fn continuation_alias_and_procedure_predicate_share_the_vm_contract() {
        let op = Builtin::from_name("call/cc").unwrap();
        assert_eq!(
            op,
            Builtin::from_name("call-with-current-continuation").unwrap()
        );
        assert!(op.may_allocate());
        let mut vm = vm();
        let saved = vm.allocation().alloc(Continuation {
            stack: vec![],
            frames: 0,
        });
        assert_eq!(call(&mut vm, "procedure?", &[saved]).unwrap(), Value::TRUE);
        assert_eq!(format_value(&vm, saved, false).unwrap(), "#<continuation>");
    }

    fn integer(value: i64) -> Value {
        Value::fixnum(value).unwrap()
    }

    fn vm() -> Runtime {
        Runtime::for_test(vec!["test".into()])
    }

    fn call(vm: &mut Runtime, name: &str, args: &[Value]) -> Result<Value, String> {
        let op = Builtin::from_name(name)?;
        let result = if op.may_allocate() {
            invoke_allocating(vm.allocation(), op, args)
        } else {
            invoke(vm, op, args)
        }?;
        match result {
            PrimitiveResult::Value(value) => Ok(value),
            _ => panic!("expected a single value"),
        }
    }

    fn number_values(vm: &mut Runtime, numbers: &[Number]) -> Vec<Value> {
        let mut allocation = vm.allocation();
        numbers
            .iter()
            .map(|number| match *number {
                Number::Integer(n) => allocation.integer(n),
                Number::Float(n) => allocation.float(n),
            })
            .collect()
    }

    fn arithmetic_numbers(name: &str, args: &[Number]) -> Result<Number, String> {
        let mut vm = vm();
        let values = number_values(&mut vm, args);
        arithmetic(&vm, Builtin::from_name(name)?, &values)
    }

    fn compare_numbers(name: &str, args: &[Number]) -> Result<Value, String> {
        let mut vm = vm();
        let values = number_values(&mut vm, args);
        numeric_compare(&vm, Builtin::from_name(name)?, &values)
    }

    #[test]
    fn comparisons_validate_later_operands_even_after_a_false_result() {
        let mut vm = vm();
        let args = [integer(2), integer(1), Value::FALSE];
        assert!(call(&mut vm, "<", &args).is_err());
        let left = vm.allocation().alloc(Text::new("a".into()));
        let right = vm.allocation().alloc(Text::new("b".into()));
        assert!(call(&mut vm, "string=?", &[left, right, Value::FALSE]).is_err());
    }

    fn initialized_float(text: &str) -> f64 {
        let mut vm = crate::vm::Vm::new(0, 1, Vec::new());
        unsafe {
            crate::snail_const_atom(&mut vm, 0, 3, text.as_ptr(), text.len() as u32);
        }
        assert_eq!(vm.error(), None);
        {
            let value = vm.constant(0).unwrap();
            vm.allocation([]).heap.get::<Float>(value).unwrap().0
        }
    }

    #[test]
    fn substring_search_returns_character_indices_and_honors_start() {
        let mut vm = vm();
        let text = vm.allocation().alloc(Text::new("aλ😀λ".into()));
        let pattern = vm.allocation().alloc(Text::new("λ".into()));
        let empty = vm.allocation().alloc(Text::new(String::new()));
        assert_eq!(
            string_contains(&mut vm.allocation(), &[text, pattern]).unwrap(),
            integer(1)
        );
        assert_eq!(
            string_contains(&mut vm.allocation(), &[text, pattern, integer(2)]).unwrap(),
            integer(3)
        );
        assert_eq!(
            string_contains(&mut vm.allocation(), &[text, pattern, integer(4)]).unwrap(),
            Value::FALSE
        );
        assert_eq!(
            string_contains(&mut vm.allocation(), &[text, empty, integer(4)]).unwrap(),
            integer(4)
        );
        assert!(string_contains(&mut vm.allocation(), &[text, pattern, integer(5)]).is_err());
    }

    #[test]
    fn floating_constants_and_numeric_reader_agree() {
        for text in ["1.25", "+inf.0", "-inf.0", "+nan.0"] {
            let mut vm = vm();
            let string = vm.allocation().alloc(Text::new(text.into()));
            let read = call(&mut vm, "string->number", &[string]).unwrap();
            let literal = initialized_float(text);
            let read = vm.heap.get::<Float>(read).unwrap().0;
            assert!(literal == read || (literal.is_nan() && read.is_nan()));
        }
    }

    #[test]
    fn numeric_reader_honors_radix_prefixes() {
        let mut vm = vm();
        for (text, expected) in [
            ("#b+11", 3),
            ("#B10", 2),
            ("#o17", 15),
            ("#O10", 8),
            ("#d19", 19),
            ("#D10", 10),
            ("#x10ffff", 1_114_111),
            ("#X-ff", -255),
            ("#x7fffffffffffffff", i64::MAX),
            ("#x-8000000000000000", i64::MIN),
        ] {
            let text = vm.allocation().alloc(Text::new(text.into()));
            let value = call(&mut vm, "string->number", &[text, integer(2)]).unwrap();
            assert_eq!(value.integer(&vm.heap).unwrap(), expected);
        }
        let text = vm.allocation().alloc(Text::new("#d1.5".into()));
        let value = call(&mut vm, "string->number", &[text, integer(16)]).unwrap();
        assert_eq!(vm.heap.get::<Float>(value).unwrap().0, 1.5);
        assert!(call(&mut vm, "string->number", &[text, integer(3)]).is_err());
    }

    #[test]
    fn numeric_reader_rejects_malformed_radix_prefixes() {
        let mut vm = vm();
        for text in [
            "#", "#x", "#xg", "#x1.5", "#b102", "#x#d10", "#e10", "+#x1", " #x1", "#λ", "λ",
        ] {
            let text = vm.allocation().alloc(Text::new(text.into()));
            assert_eq!(
                call(&mut vm, "string->number", &[text]).unwrap(),
                Value::FALSE
            );
        }
        for text in ["#x8000000000000000", "#x-8000000000000001"] {
            let text = vm.allocation().alloc(Text::new(text.into()));
            assert!(
                call(&mut vm, "string->number", &[text])
                    .unwrap_err()
                    .contains("overflow")
            );
        }
    }

    #[test]
    fn integer_arithmetic_rejects_overflow_and_zero_division() {
        assert!(arithmetic_numbers("+", &[Number::Integer(i64::MAX), Number::Integer(1)]).is_err());
        assert!(arithmetic_numbers("-", &[Number::Integer(i64::MIN)]).is_err());
        assert!(
            arithmetic_numbers("/", &[Number::Integer(i64::MIN), Number::Integer(-1)]).is_err()
        );
        assert!(arithmetic_numbers("quotient", &[Number::Integer(7), Number::Integer(0)]).is_err());
        assert!(arithmetic_numbers("/", &[Number::Float(7.0), Number::Float(0.0)]).is_err());
        assert_eq!(
            arithmetic_numbers("/", &[Number::Integer(9), Number::Integer(3)]).unwrap(),
            Number::Integer(3)
        );
        assert_eq!(
            arithmetic_numbers("/", &[Number::Integer(9), Number::Integer(2)]).unwrap(),
            Number::Float(4.5)
        );
        assert_eq!(
            arithmetic_numbers("modulo", &[Number::Integer(-7), Number::Integer(3)]).unwrap(),
            Number::Integer(2)
        );
        assert_eq!(
            arithmetic_numbers("modulo", &[Number::Integer(7), Number::Integer(-3)]).unwrap(),
            Number::Integer(-2)
        );
    }

    #[test]
    fn mixed_comparisons_preserve_large_integer_precision() {
        let exact = Number::Integer(9_007_199_254_740_993);
        let rounded = Number::Float(9_007_199_254_740_992.0);
        assert_eq!(
            compare_numbers(">", &[exact, rounded]).unwrap(),
            Value::boolean(true)
        );
        assert_eq!(
            compare_numbers("=", &[exact, rounded]).unwrap(),
            Value::boolean(false)
        );
        assert_eq!(
            compare_numbers(
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
            compare_numbers("=", &[Number::Float(f64::NAN), Number::Float(f64::NAN)]).unwrap(),
            Value::boolean(false)
        );
    }

    #[test]
    fn numeric_reader_does_not_silently_make_overflowing_integers_inexact() {
        let mut vm = vm();
        for text in ["9223372036854775808", "-9223372036854775809"] {
            let text = vm.allocation().alloc(Text::new(text.into()));
            assert!(
                call(&mut vm, "string->number", &[text])
                    .unwrap_err()
                    .contains("overflow")
            );
        }
        let text = vm.allocation().alloc(Text::new("8000000000000000".into()));
        assert!(call(&mut vm, "string->number", &[text, integer(16)]).is_err());
        let text = vm.allocation().alloc(Text::new("9.5e2".into()));
        let value = call(&mut vm, "string->number", &[text]).unwrap();
        assert_eq!(vm.heap.get::<Float>(value).unwrap().0, 950.0);
        let text = vm.allocation().alloc(Text::new("NaN".into()));
        assert_eq!(
            call(&mut vm, "string->number", &[text]).unwrap(),
            Value::boolean(false)
        );
    }

    #[test]
    fn string_indices_count_unicode_scalars_and_check_bounds() {
        let mut vm = vm();
        let text = vm.allocation().alloc(Text::new("aλ😀z".into()));
        assert_eq!(call(&mut vm, "string-length", &[text]).unwrap(), integer(4));
        assert_eq!(
            call(&mut vm, "string-ref", &[text, integer(2)]).unwrap(),
            Value::character('😀')
        );
        let part = call(&mut vm, "substring", &[text, integer(1), integer(3)]).unwrap();
        assert_eq!(vm.string(part).unwrap(), "λ😀");
        let empty = call(&mut vm, "substring", &[text, integer(4), integer(4)]).unwrap();
        assert_eq!(vm.string(empty).unwrap(), "");
        for (start, end) in [(3, 1), (0, 5), (5, 5), (-1, 0)] {
            assert!(call(&mut vm, "substring", &[text, integer(start), integer(end)]).is_err());
        }
        assert!(call(&mut vm, "string-ref", &[text, integer(4)]).is_err());
        assert!(call(&mut vm, "string-ref", &[text, integer(-1)]).is_err());
        let combining = vm.allocation().alloc(Text::new("e\u{301}".into()));
        let mark = call(&mut vm, "substring", &[combining, integer(1), integer(2)]).unwrap();
        assert_eq!(vm.string(mark).unwrap(), "\u{301}");
    }

    #[test]
    fn string_construction_and_interning_preserve_inputs() {
        let mut vm = vm();
        let first = vm.allocation().alloc(Text::new("aλ".into()));
        let same = vm.allocation().alloc(Text::new("aλ".into()));
        let second = vm.allocation().alloc(Text::new("😀z".into()));
        let joined = call(&mut vm, "string-append", &[first, second]).unwrap();
        assert_eq!(vm.string(joined).unwrap(), "aλ😀z");
        let empty = call(&mut vm, "string-append", &[]).unwrap();
        assert_eq!(vm.string(empty).unwrap(), "");
        assert_eq!(
            call(&mut vm, "string=?", &[first, same]).unwrap(),
            Value::TRUE
        );
        assert_eq!(
            call(&mut vm, "string=?", &[first, second]).unwrap(),
            Value::FALSE
        );
        assert!(call(&mut vm, "string=?", &[first, second, integer(0)]).is_err());
        let symbol = call(&mut vm, "string->symbol", &[first]).unwrap();
        assert_eq!(call(&mut vm, "string->symbol", &[same]).unwrap(), symbol);
        let restored = call(&mut vm, "symbol->string", &[symbol]).unwrap();
        assert_eq!(vm.string(restored).unwrap(), "aλ");
        assert_eq!(vm.string(first).unwrap(), "aλ");
        assert_eq!(vm.string(second).unwrap(), "😀z");
    }

    #[test]
    fn record_fields_follow_names_and_descriptor_identity() {
        let mut vm = vm();
        let name = vm.intern("point");
        let x = vm.intern("x");
        let y = vm.intern("y");
        let names = vm.allocation().list(&[x, y]);
        let descriptor = call(&mut vm, "%make-record-type", &[name, names]).unwrap();
        let other_descriptor = call(&mut vm, "%make-record-type", &[name, names]).unwrap();
        let constructors = vm.allocation().list(&[y, x]);
        let values = vm.allocation().list(&[integer(20), integer(10)]);
        let instance = call(&mut vm, "%make-record", &[descriptor, constructors, values]).unwrap();
        assert_eq!(
            call(&mut vm, "%record-ref", &[descriptor, x, instance]).unwrap(),
            integer(10)
        );
        assert_eq!(
            call(&mut vm, "%record-ref", &[descriptor, y, instance]).unwrap(),
            integer(20)
        );
        assert_eq!(
            call(&mut vm, "%record?", &[other_descriptor, instance]).unwrap(),
            Value::boolean(false)
        );
        assert!(call(&mut vm, "%record-ref", &[other_descriptor, x, instance]).is_err());
        call(
            &mut vm,
            "%record-set!",
            &[descriptor, x, instance, integer(42)],
        )
        .unwrap();
        assert_eq!(
            call(&mut vm, "%record-ref", &[descriptor, x, instance]).unwrap(),
            integer(42)
        );
    }

    #[test]
    fn printing_handles_cycles_and_shared_acyclic_objects() {
        let mut vm = vm();
        let cycle = vm.allocation().alloc(Pair(integer(1), Value::NIL));
        call(&mut vm, "set-cdr!", &[cycle, cycle]).unwrap();
        assert_eq!(format_value(&vm, cycle, false).unwrap(), "(1 . #<cycle>)");
        let shared = vm.allocation().list(&[integer(2), integer(3)]);
        let vector = vm.allocation().alloc(Vector(vec![shared, shared]));
        assert_eq!(format_value(&vm, vector, false).unwrap(), "#((2 3) (2 3))");
        let text = vm.allocation().alloc(Text::new("λ\n\"\\".into()));
        assert_eq!(format_value(&vm, text, true).unwrap(), "λ\n\"\\");
        assert_eq!(format_value(&vm, text, false).unwrap(), "\"λ\\n\\\"\\\\\"");
    }

    #[test]
    fn deep_printing_does_not_consume_the_host_call_stack() {
        let mut vm = vm();
        let mut value = integer(1);
        for _ in 0..20_000 {
            value = vm.allocation().alloc(Pair(value, Value::NIL));
        }
        assert_eq!(format_value(&vm, value, false).unwrap().len(), 40_001);
    }
}
