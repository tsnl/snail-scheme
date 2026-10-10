//! Rust services for the application Wasm interface (AWI).
//!
//! Every exported primitive borrows a rooted argument vector and returns one
//! owned result handle. Rust sees table indices, never WasmGC pointers. The
//! same library is linked into the portable Wasm module before optional native
//! compilation; the WebAssembly engine owns Scheme memory and collection.

// Native builds run pure helper tests; the callable surface exists in Wasm only.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

pub mod awi;
mod host;
mod interop_example;
pub mod trace;

use crate::awi::{Arguments, Kind, Root};
use host::Port;
use std::{cell::RefCell, time::Instant};

// ---- Module initialization ----

// Export a reactor initializer so wasm-ld does not wrap each exported function
// in constructor/destructor calls. The linked Wasm entry calls it once, before
// Scheme or Rust runs. All callable Rust services share this runtime.
#[cfg(target_arch = "wasm32")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn _initialize() {
    unsafe extern "C" {
        fn __wasm_call_ctors();
    }
    unsafe { __wasm_call_ctors() };
}

// ---- Foreign call boundaries ----

fn arguments(raw: u32, name: &str, min: usize, max: usize) -> Arguments {
    // The generated wrapper owns this argument-vector root for the whole call.
    let args = unsafe { Arguments::borrow(raw) };
    args.check(name, min, max)
        .unwrap_or_else(|error| fail_message(&error));
    args
}

fn finish(result: Result<Root, String>) -> u32 {
    result
        .unwrap_or_else(|error| fail_message(&error))
        .into_handle()
}

fn fail_message(message: &str) -> ! {
    eprintln!("snail-scheme: {message}");
    std::process::exit(1)
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:fail"))]
pub extern "C" fn core_failure(code: u32) -> u32 {
    fail_message(match code {
        1 => "expected a number",
        2 => "exact integer overflow",
        3 => "index or value out of range",
        4 => "wrong number of arguments",
        5 => "expected a single value",
        6 => "read of an uninitialized binding",
        7 => "call/cc is not supported by the Wasm backend",
        8 => "incorrect value type",
        9 => "division by zero",
        _ => "WebAssembly runtime error",
    })
}

// ---- Host-owned resources ----

const PORT_KIND: u32 = 1;

struct Host {
    ports: Vec<Port>,
    current: [Root; 3],
    started: Instant,
}

impl Host {
    fn new() -> Self {
        Self {
            ports: vec![Port::Stdin, Port::Stdout, Port::Stderr],
            // Each freshly created port receives its one owning GC wrapper.
            current: std::array::from_fn(|id| unsafe {
                Root::from_raw_extension(PORT_KIND, id as u32)
            }),
            started: Instant::now(),
        }
    }

    fn port(&mut self, value: &Root) -> Result<&mut Port, String> {
        let (kind, id) = value.extension_parts()?;
        if kind != PORT_KIND {
            return Err("expected a port".into());
        }
        self.ports
            .get_mut(id as usize)
            .ok_or_else(|| "invalid port resource".into())
    }

    fn add_port(&mut self, port: Port) -> Result<Root, String> {
        let id = u32::try_from(self.ports.len()).map_err(|_| "too many ports")?;
        self.ports.push(port);
        // IDs are fresh and never reused; this is the resource's only wrapper.
        Ok(unsafe { Root::from_raw_extension(PORT_KIND, id) })
    }
}

// AWI accessors never call Scheme or reenter Rust. Host borrows do not cross
// user callbacks. Resources are explicitly closed; GC is not a Rust finalizer.
thread_local! { static HOST: RefCell<Host> = RefCell::new(Host::new()); }

fn selected_port(args: &Arguments, index: usize, current: usize) -> Result<Root, String> {
    if index < args.len() {
        args.get(index)
    } else {
        Ok(HOST.with_borrow(|host| host.current[current].clone()))
    }
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:open-input-file"))]
pub extern "C" fn open_input_file(raw: u32) -> u32 {
    let args = arguments(raw, "open-input-file", 1, 1);
    finish(open_file(&args, true))
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:open-output-file"))]
pub extern "C" fn open_output_file(raw: u32) -> u32 {
    let args = arguments(raw, "open-output-file", 1, 1);
    finish(open_file(&args, false))
}

fn open_file(args: &Arguments, input: bool) -> Result<Root, String> {
    let path = string_text(&args.get(0)?)?;
    let port = if input {
        Port::input_file(&path)?
    } else {
        Port::output_file(&path)?
    };
    HOST.with_borrow_mut(|host| host.add_port(port))
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:file-exists?"))]
pub extern "C" fn file_exists(raw: u32) -> u32 {
    let args = arguments(raw, "file-exists?", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| string_text(&value))
            .and_then(|path| {
                std::path::Path::new(&path)
                    .try_exists()
                    .map(Root::boolean)
                    .map_err(|error| error.to_string())
            }),
    )
}

#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:open-output-string")
)]
pub extern "C" fn open_output_string(raw: u32) -> u32 {
    arguments(raw, "open-output-string", 0, 0);
    finish(HOST.with_borrow_mut(|host| host.add_port(Port::output_string())))
}

#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:get-output-string")
)]
pub extern "C" fn get_output_string(raw: u32) -> u32 {
    let args = arguments(raw, "get-output-string", 1, 1);
    finish(
        HOST.with_borrow_mut(|host| Ok(Root::string(host.port(&args.get(0)?)?.captured_output()?))),
    )
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:close-port"))]
pub extern "C" fn close_port(raw: u32) -> u32 {
    let args = arguments(raw, "close-port", 1, 1);
    finish(HOST.with_borrow_mut(|host| {
        host.port(&args.get(0)?)?.close()?;
        Ok(Root::unspecified())
    }))
}

/// Host finalization releases the Rust payload after its GC wrapper dies.
/// Resource IDs are never reused, so repeated/late notices cannot close a new port.
#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:drop-resource"))]
pub extern "C" fn drop_resource(kind: u32, id: u32) {
    if kind != PORT_KIND {
        return;
    }
    let port = HOST.with_borrow_mut(|host| {
        host.ports
            .get_mut(id as usize)
            .map(|slot| std::mem::replace(slot, Port::Closed))
    });
    if let Some(mut port) = port {
        let _ = port.close();
    }
}

// ---- Reading and writing ----

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:read-char"))]
pub extern "C" fn read_char(raw: u32) -> u32 {
    let args = arguments(raw, "read-char", 0, 1);
    finish(HOST.with_borrow_mut(|host| {
        let port = if args.len() == 0 {
            host.current[0].clone()
        } else {
            args.get(0)?
        };
        Ok(host
            .port(&port)?
            .read_char()?
            .map(Root::character)
            .unwrap_or_else(Root::eof))
    }))
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:read-string"))]
pub extern "C" fn read_string(raw: u32) -> u32 {
    let args = arguments(raw, "read-string", 1, 2);
    finish(read_port_string(&args))
}

fn read_port_string(args: &Arguments) -> Result<Root, String> {
    let count =
        usize::try_from(args.get(0)?.as_integer()?).map_err(|_| "expected a nonnegative length")?;
    let port = selected_port(args, 1, 0)?;
    HOST.with_borrow_mut(|host| {
        Ok(match host.port(&port)?.read_string(count)? {
            Some(text) => Root::string(&text),
            None => Root::eof(),
        })
    })
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:display"))]
pub extern "C" fn display(raw: u32) -> u32 {
    finish(output(&arguments(raw, "display", 1, 2), true))
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:write"))]
pub extern "C" fn write(raw: u32) -> u32 {
    finish(output(&arguments(raw, "write", 1, 2), false))
}

fn output(args: &Arguments, display: bool) -> Result<Root, String> {
    let text = format_value(args.get(0)?, display)?;
    let port = selected_port(args, 1, 1)?;
    HOST.with_borrow_mut(|host| host.port(&port)?.write(&text))?;
    Ok(Root::unspecified())
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:newline"))]
pub extern "C" fn newline(raw: u32) -> u32 {
    let args = arguments(raw, "newline", 0, 1);
    finish(write_newline(&args))
}

fn write_newline(args: &Arguments) -> Result<Root, String> {
    let port = selected_port(args, 0, 1)?;
    HOST.with_borrow_mut(|host| host.port(&port)?.write("\n"))?;
    Ok(Root::unspecified())
}

#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:%current-input-port")
)]
pub extern "C" fn current_input(raw: u32) -> u32 {
    current_port(raw, "%current-input-port", 0)
}
#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:%current-output-port")
)]
pub extern "C" fn current_output(raw: u32) -> u32 {
    current_port(raw, "%current-output-port", 1)
}
#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:%current-error-port")
)]
pub extern "C" fn current_error(raw: u32) -> u32 {
    current_port(raw, "%current-error-port", 2)
}

fn current_port(raw: u32, name: &str, index: usize) -> u32 {
    arguments(raw, name, 0, 0);
    HOST.with_borrow(|host| host.current[index].clone().into_handle())
}

#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:%set-current-input-port!")
)]
pub extern "C" fn set_current_input(raw: u32) -> u32 {
    set_current_port(raw, "%set-current-input-port!", 0)
}
#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:%set-current-output-port!")
)]
pub extern "C" fn set_current_output(raw: u32) -> u32 {
    set_current_port(raw, "%set-current-output-port!", 1)
}
#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:%set-current-error-port!")
)]
pub extern "C" fn set_current_error(raw: u32) -> u32 {
    set_current_port(raw, "%set-current-error-port!", 2)
}

fn set_current_port(raw: u32, name: &str, index: usize) -> u32 {
    let args = arguments(raw, name, 1, 1);
    finish(HOST.with_borrow_mut(|host| {
        let value = args.get(0)?;
        let port = host.port(&value)?;
        if !(if index == 0 {
            port.is_input()
        } else {
            port.is_output()
        }) {
            return Err("expected an open port of the appropriate direction".into());
        }
        host.current[index] = value;
        Ok(Root::unspecified())
    }))
}

// ---- Process, clocks, tracing, and diagnostics ----

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:command-line"))]
pub extern "C" fn command_line(raw: u32) -> u32 {
    arguments(raw, "command-line", 0, 0);
    let mut list = Root::nil();
    for argument in std::env::args().collect::<Vec<_>>().into_iter().rev() {
        list = Root::pair(&Root::string(&argument), &list);
    }
    list.into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:exit"))]
pub extern "C" fn exit(raw: u32) -> u32 {
    let args = arguments(raw, "exit", 0, 1);
    std::process::exit(exit_status(&args).unwrap_or_else(|error| fail_message(&error)))
}

fn exit_status(args: &Arguments) -> Result<i32, String> {
    if args.len() == 0 {
        return Ok(0);
    }
    let value = args.get(0)?;
    if value.kind() == Kind::Boolean {
        return Ok(i32::from(!value.as_bool()?));
    }
    i32::try_from(value.as_integer()?).map_err(|_| "exit status out of range".into())
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:current-jiffy"))]
pub extern "C" fn current_jiffy(raw: u32) -> u32 {
    arguments(raw, "current-jiffy", 0, 0);
    let nanos = HOST.with_borrow(|host| host.started.elapsed().as_nanos());
    finish(
        i64::try_from(nanos)
            .map(Root::integer)
            .map_err(|_| "monotonic clock exceeds integer range".into()),
    )
}

#[cfg_attr(
    target_arch = "wasm32",
    unsafe(export_name = "snail:jiffies-per-second")
)]
pub extern "C" fn jiffies_per_second(raw: u32) -> u32 {
    arguments(raw, "jiffies-per-second", 0, 0);
    Root::integer(1_000_000_000).into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:%trace-begin"))]
pub extern "C" fn trace_begin(raw: u32) -> u32 {
    let args = arguments(raw, "%trace-begin", 1, 1);
    let name = args
        .get(0)
        .and_then(|value| string_text(&value))
        .unwrap_or_else(|error| fail_message(&error));
    trace::begin(&name);
    Root::unspecified().into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:%trace-end"))]
pub extern "C" fn trace_end(raw: u32) -> u32 {
    arguments(raw, "%trace-end", 0, 0);
    trace::end();
    Root::unspecified().into_handle()
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:error"))]
pub extern "C" fn error(raw: u32) -> u32 {
    let args = arguments(raw, "error", 1, usize::MAX);
    let texts = (0..args.len())
        .map(|i| args.get(i).and_then(|value| format_value(value, true)))
        .collect::<Result<Vec<_>, _>>();
    fail_message(&texts.unwrap_or_else(|error| fail_message(&error)).join(" "))
}

fn string_text(value: &Root) -> Result<String, String> {
    if value.kind() != Kind::String {
        return Err("expected a string".into());
    }
    value.text()
}

// ---- Numeric text ----

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:string->number"))]
pub extern "C" fn string_to_number(raw: u32) -> u32 {
    finish(parse_number(&arguments(raw, "string->number", 1, 2)))
}
#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:number->string"))]
pub extern "C" fn number_to_string(raw: u32) -> u32 {
    finish(format_number(&arguments(raw, "number->string", 1, 2)))
}

fn radix(args: &Arguments) -> Result<u32, String> {
    let radix = if args.len() == 2 {
        args.get(1)?.as_integer()?
    } else {
        10
    };
    if matches!(radix, 2 | 8 | 10 | 16) {
        Ok(radix as u32)
    } else {
        Err("unsupported numeric radix".into())
    }
}

fn parse_number(args: &Arguments) -> Result<Root, String> {
    let text = string_text(&args.get(0)?)?;
    let (text, radix) = strip_radix_prefix(&text, radix(args)?);
    match i64::from_str_radix(text, radix) {
        Ok(number) => Ok(Root::integer(number)),
        Err(error)
            if matches!(
                error.kind(),
                std::num::IntErrorKind::PosOverflow | std::num::IntErrorKind::NegOverflow
            ) =>
        {
            Err("string->number: integer overflow".into())
        }
        Err(_) => Ok(if radix == 10 {
            parse_float(text)
                .map(Root::real)
                .unwrap_or_else(|| Root::boolean(false))
        } else {
            Root::boolean(false)
        }),
    }
}

fn format_number(args: &Arguments) -> Result<Root, String> {
    let radix = radix(args)?;
    let value = args.get(0)?;
    let text = match value.kind() {
        Kind::Integer => integer_text(value.as_integer()?, radix),
        Kind::Real if radix == 10 => float_text(value.as_real()?),
        Kind::Real => return Err("inexact number requires decimal radix".into()),
        _ => return Err("expected a number".into()),
    };
    Ok(Root::string(&text))
}

fn integer_text(number: i64, radix: u32) -> String {
    let magnitude = number.unsigned_abs();
    let digits = match radix {
        2 => format!("{magnitude:b}"),
        8 => format!("{magnitude:o}"),
        16 => format!("{magnitude:x}"),
        _ => magnitude.to_string(),
    };
    if number < 0 {
        format!("-{digits}")
    } else {
        digits
    }
}

fn strip_radix_prefix(text: &str, radix: u32) -> (&str, u32) {
    let radix = match text.as_bytes().get(..2) {
        Some([b'#', b'b' | b'B']) => 2,
        Some([b'#', b'o' | b'O']) => 8,
        Some([b'#', b'd' | b'D']) => 10,
        Some([b'#', b'x' | b'X']) => 16,
        _ => return (text, radix),
    };
    (&text[2..], radix)
}

fn parse_float(text: &str) -> Option<f64> {
    match text {
        "+inf.0" => Some(f64::INFINITY),
        "-inf.0" => Some(f64::NEG_INFINITY),
        "+nan.0" | "-nan.0" => Some(f64::NAN),
        _ if text.contains(['.', 'e', 'E']) => text.parse().ok(),
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

// ---- Unicode and substring search ----

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:char-alphabetic?"))]
pub extern "C" fn char_alphabetic(raw: u32) -> u32 {
    let args = arguments(raw, "char-alphabetic?", 1, 1);
    finish(
        args.get(0)
            .and_then(|v| v.as_character())
            .map(|c| Root::boolean(c.is_alphabetic())),
    )
}
#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:char-numeric?"))]
pub extern "C" fn char_numeric(raw: u32) -> u32 {
    let args = arguments(raw, "char-numeric?", 1, 1);
    finish(
        args.get(0)
            .and_then(|v| v.as_character())
            .map(|c| Root::boolean(c.is_numeric())),
    )
}
#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:char-whitespace?"))]
pub extern "C" fn char_whitespace(raw: u32) -> u32 {
    let args = arguments(raw, "char-whitespace?", 1, 1);
    finish(
        args.get(0)
            .and_then(|v| v.as_character())
            .map(|c| Root::boolean(c.is_whitespace())),
    )
}
#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:char-ci=?"))]
pub extern "C" fn char_ci_equal(raw: u32) -> u32 {
    finish(compare_folded_chars(&arguments(
        raw,
        "char-ci=?",
        2,
        usize::MAX,
    )))
}

fn compare_folded_chars(args: &Arguments) -> Result<Root, String> {
    let mut previous = args.get(0)?.as_character()?;
    let mut equal = true;
    for index in 1..args.len() {
        let current = args.get(index)?.as_character()?;
        equal &= previous.to_lowercase().eq(current.to_lowercase());
        previous = current;
    }
    Ok(Root::boolean(equal))
}

#[cfg_attr(target_arch = "wasm32", unsafe(export_name = "snail:string-contains"))]
pub extern "C" fn string_contains(raw: u32) -> u32 {
    finish(find_substring(&arguments(raw, "string-contains", 2, 3)))
}

fn find_substring(args: &Arguments) -> Result<Root, String> {
    let text = args.get(0)?;
    let pattern = args.get(1)?;
    if text.kind() != Kind::String || pattern.kind() != Kind::String {
        return Err("string-contains: expected strings".into());
    }
    let start = if args.len() == 3 {
        usize::try_from(args.get(2)?.as_integer()?).map_err(|_| "negative start index")?
    } else {
        0
    };
    let length = text.len()?;
    if start > length {
        return Err("string-contains: start index out of range".into());
    }
    // Only the pattern is copied; the haystack stays in the GC heap.
    let pattern = (0..pattern.len()?)
        .map(|i| pattern.char_at(i))
        .collect::<Result<Vec<_>, _>>()?;
    let found = find_characters(length, &pattern, start, |i| text.char_at(i))?;
    Ok(found
        .map(|i| Root::integer(i as i64))
        .unwrap_or_else(|| Root::boolean(false)))
}

fn find_characters(
    length: usize,
    pattern: &[char],
    start: usize,
    mut at: impl FnMut(usize) -> Result<char, String>,
) -> Result<Option<usize>, String> {
    if pattern.len() > length - start {
        return Ok(None);
    }
    for offset in start..=length - pattern.len() {
        let mut matches = true;
        for (index, expected) in pattern.iter().enumerate() {
            if at(offset + index)? != *expected {
                matches = false;
                break;
            }
        }
        if matches {
            return Ok(Some(offset));
        }
    }
    Ok(None)
}

// ---- Datum printing ----

enum PrintTask {
    Value(Root),
    Tail {
        value: Root,
        slow: Root,
        advance: bool,
    },
    Text(&'static str),
    Leave,
}

/// Pending work avoids Rust recursion. A list tail uses Floyd's cycle check,
/// so a long flat list does not retain or scan every earlier pair as an ancestor.
fn format_value(value: Root, display: bool) -> Result<String, String> {
    let mut output = String::new();
    let mut pending = vec![PrintTask::Value(value)];
    let mut active = Vec::new();
    while let Some(task) = pending.pop() {
        match task {
            PrintTask::Text(text) => output.push_str(text),
            PrintTask::Leave => {
                active.pop();
            }
            PrintTask::Value(value) => {
                print_value(value, display, &mut output, &mut pending, &mut active)?
            }
            PrintTask::Tail {
                value,
                slow,
                advance,
            } => print_tail(value, slow, advance, &mut output, &mut pending, &mut active)?,
        }
    }
    Ok(output)
}

fn print_tail(
    value: Root,
    slow: Root,
    advance: bool,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut Vec<Root>,
) -> Result<(), String> {
    if value.kind() == Kind::Nil {
        return Ok(());
    }
    if value.kind() != Kind::Pair {
        output.push_str(" . ");
        pending.push(PrintTask::Value(value));
        return Ok(());
    }
    if value.same(&slow) || active.iter().any(|ancestor| value.same(ancestor)) {
        output.push_str(" . #<cycle>");
        return Ok(());
    }
    let slow = if advance { slow.cdr()? } else { slow };
    output.push(' ');
    pending.push(PrintTask::Tail {
        value: value.cdr()?,
        slow,
        advance: !advance,
    });
    active.push(value.clone());
    pending.push(PrintTask::Leave);
    pending.push(PrintTask::Value(value.car()?));
    Ok(())
}

fn print_value(
    value: Root,
    display: bool,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut Vec<Root>,
) -> Result<(), String> {
    match value.kind() {
        Kind::Unspecified => output.push_str("#<unspecified>"),
        Kind::Uninitialized => output.push_str("#<uninitialized>"),
        Kind::Nil => output.push_str("()"),
        Kind::Eof => output.push_str("#<eof>"),
        Kind::Boolean => output.push_str(if value.as_bool()? { "#t" } else { "#f" }),
        Kind::Integer => output.push_str(&value.as_integer()?.to_string()),
        Kind::Real => output.push_str(&float_text(value.as_real()?)),
        Kind::Character => print_character(output, value.as_character()?, display),
        Kind::String if !display => quote_string(output, &value.text()?),
        Kind::String | Kind::Symbol => output.push_str(&value.text()?),
        Kind::Pair | Kind::Vector => print_container(value, output, pending, active)?,
        Kind::Bytevector => {
            output.push_str("#u8(");
            for i in 0..value.len()? {
                if i > 0 {
                    output.push(' ');
                }
                output.push_str(&value.byte_at(i)?.to_string());
            }
            output.push(')');
        }
        Kind::Procedure => output.push_str("#<procedure>"),
        Kind::Record => output.push_str("#<record>"),
        Kind::Extension => output.push_str(if value.extension_parts()?.0 == PORT_KIND {
            "#<port>"
        } else {
            "#<extension>"
        }),
        Kind::Values => output.push_str("#<values>"),
    }
    Ok(())
}

fn print_container(
    value: Root,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut Vec<Root>,
) -> Result<(), String> {
    if active.iter().any(|ancestor| value.same(ancestor)) {
        output.push_str("#<cycle>");
        return Ok(());
    }
    active.push(value.clone());
    pending.push(PrintTask::Leave);
    pending.push(PrintTask::Text(")"));
    if value.kind() == Kind::Pair {
        output.push('(');
        pending.push(PrintTask::Tail {
            value: value.cdr()?,
            slow: value.clone(),
            advance: false,
        });
        pending.push(PrintTask::Value(value.car()?));
    } else {
        output.push_str("#(");
        for index in (0..value.len()?).rev() {
            pending.push(PrintTask::Value(value.at(index)?));
            if index > 0 {
                pending.push(PrintTask::Text(" "));
            }
        }
    }
    Ok(())
}

fn print_character(output: &mut String, character: char, display: bool) {
    if display {
        output.push(character);
        return;
    }
    output.push_str("#\\");
    match character {
        ' ' => output.push_str("space"),
        '\n' => output.push_str("newline"),
        '\t' => output.push_str("tab"),
        '\r' => output.push_str("return"),
        _ => output.push(character),
    }
}

fn quote_string(output: &mut String, text: &str) {
    output.push('"');
    for character in text.chars() {
        match character {
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
    fn numeric_text_preserves_sign_radix_and_nonfinite_values() {
        assert_eq!(integer_text(i64::MIN, 16), "-8000000000000000");
        assert_eq!(strip_radix_prefix("#Xff", 10), ("ff", 16));
        assert_eq!(strip_radix_prefix("λ", 8), ("λ", 8));
        assert_eq!(float_text(-0.0), "-0.0");
        assert_eq!(float_text(f64::INFINITY), "+inf.0");
        assert!(parse_float("+nan.0").unwrap().is_nan());
        assert_eq!(parse_float("3"), None);
        assert_eq!(parse_float("3.5"), Some(3.5));
    }

    #[test]
    fn substring_search_counts_scalars_without_copying_the_haystack() {
        let text: Vec<_> = "aλ😀λ".chars().collect();
        let find = |pattern: &str, start| {
            find_characters(
                text.len(),
                &pattern.chars().collect::<Vec<_>>(),
                start,
                |i| Ok(text[i]),
            )
            .unwrap()
        };
        assert_eq!(find("λ", 0), Some(1));
        assert_eq!(find("λ", 2), Some(3));
        assert_eq!(find("λ", 4), None);
        assert_eq!(find("", 4), Some(4));
        assert_eq!(find("😀λ", 0), Some(2));
    }

    #[test]
    fn printed_strings_and_characters_keep_scheme_escaping() {
        let mut text = String::new();
        quote_string(&mut text, "λ\n\"\\");
        assert_eq!(text, "\"λ\\n\\\"\\\\\"");
        text.clear();
        print_character(&mut text, '\n', false);
        assert_eq!(text, "#\\newline");
        text.clear();
        print_character(&mut text, '😀', true);
        assert_eq!(text, "😀");
    }
}
