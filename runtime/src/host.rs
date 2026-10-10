//! Host services for the std-based native/WASI executable adapter.
//!
//! Ports are Scheme objects, but all operating-system access stays here. The VM
//! explicitly roots the three current ports. A future no_std adapter can replace
//! these services without changing the generated-code ABI.

use crate::{
    object::*,
    primitives::{Arguments, Builtin, PrimitiveResult, arity, format_value},
    vm::{Allocation, Runtime},
};
use std::{
    fs::File,
    io::{Read, Write},
    time::Instant,
};

// ---- Host state and port data ----

#[derive(Debug)]
pub enum Port {
    Input {
        chars: Vec<char>,
        offset: usize,
        closed: bool,
    },
    Output {
        buffer: String,
        closed: bool,
    },
    FileOutput(Option<File>),
    Closed,
    Stdin,
    Stdout,
    Stderr,
}

pub struct Host {
    pub input: Value,
    pub output: Value,
    pub error: Value,
    pub started: Instant,
}

impl Host {
    pub fn new(input: Value, output: Value, error: Value) -> Self {
        Self {
            input,
            output,
            error,
            started: Instant::now(),
        }
    }
}

// ---- Callable boundaries ----

// Only the allocating entry point receives managed-allocation permission.
// Both calls run to completion without collection; Rust-owned I/O buffers do
// not need a capability because their allocation never enters the Scheme GC.
pub(crate) fn invoke(
    vm: &mut Runtime,
    op: Builtin,
    args: Arguments<'_>,
) -> Result<PrimitiveResult, String> {
    use Builtin::*;
    let value = match op {
        ClosePort => {
            arity(op, args, 1, 1)?;
            close_port(port_mut(vm, args[0])?)?;
            Value::UNSPECIFIED
        }
        ReadChar => {
            arity(op, args, 0, 1)?;
            let handle = args.first().copied().unwrap_or(vm.host.input);
            read_char(port_mut(vm, handle)?)?
        }
        IsEof => {
            arity(op, args, 1, 1)?;
            Value::boolean(args[0] == Value::EOF)
        }
        Display | Write | Newline => output(vm, op, args)?,
        CurrentInputPort | CurrentOutputPort | CurrentErrorPort => {
            arity(op, args, 0, 0)?;
            match op {
                CurrentInputPort => vm.host.input,
                CurrentOutputPort => vm.host.output,
                _ => vm.host.error,
            }
        }
        SetCurrentInputPort | SetCurrentOutputPort | SetCurrentErrorPort => {
            set_current_port(vm, op, args)?;
            Value::UNSPECIFIED
        }
        Exit => return Ok(PrimitiveResult::Exit(exit_status(vm, args)?)),
        JiffiesPerSecond => {
            arity(op, args, 0, 0)?;
            Value::fixnum(1_000_000_000).unwrap()
        }
        _ => unreachable!("nonallocating host dispatch: {}", op.name()),
    };
    Ok(PrimitiveResult::Value(value))
}

pub(crate) fn invoke_allocating(
    vm: &mut Allocation<'_>,
    op: Builtin,
    args: Arguments<'_>,
) -> Result<PrimitiveResult, String> {
    use Builtin::*;
    let value = match op {
        OpenInputFile | OpenOutputFile | OpenOutputString => open_port(vm, op, args)?,
        ReadString => read_port_string(vm, args)?,
        GetOutputString => output_string(vm, args)?,
        CommandLine => command_line(vm, args)?,
        CurrentJiffy => current_jiffy(vm, args)?,
        _ => unreachable!("allocating host dispatch: {}", op.name()),
    };
    Ok(PrimitiveResult::Value(value))
}

fn exit_status(vm: &Runtime, args: Arguments<'_>) -> Result<i32, String> {
    arity(Builtin::Exit, args, 0, 1)?;
    match args.first() {
        None | Some(&Value::TRUE) => Ok(0),
        Some(&Value::FALSE) => Ok(1),
        Some(value) => {
            i32::try_from(value.integer(&vm.heap)?).map_err(|_| "exit status out of range".into())
        }
    }
}

fn command_line(vm: &mut Allocation<'_>, args: Arguments<'_>) -> Result<Value, String> {
    arity(Builtin::CommandLine, args, 0, 0)?;
    let arguments = vm.argv.clone();
    let strings: Vec<Value> = arguments
        .into_iter()
        .map(|s| vm.alloc(Text::new(s)))
        .collect();
    Ok(vm.list(&strings))
}

fn current_jiffy(vm: &mut Allocation<'_>, args: Arguments<'_>) -> Result<Value, String> {
    arity(Builtin::CurrentJiffy, args, 0, 0)?;
    let ticks = i64::try_from(vm.host.started.elapsed().as_nanos())
        .map_err(|_| "monotonic clock exceeds integer range")?;
    Ok(vm.integer(ticks))
}

// ---- Managed port construction and access ----

fn port_mut(vm: &mut Runtime, value: Value) -> Result<&mut Port, String> {
    vm.heap.get_mut::<Port>(value)
}

fn open_port(vm: &mut Allocation<'_>, op: Builtin, args: Arguments<'_>) -> Result<Value, String> {
    let port = if op == Builtin::OpenOutputString {
        arity(op, args, 0, 0)?;
        Port::Output {
            buffer: String::new(),
            closed: false,
        }
    } else {
        arity(op, args, 1, 1)?;
        let path = vm.string(args[0])?;
        if op == Builtin::OpenInputFile {
            let text =
                std::fs::read_to_string(path).map_err(|e| format!("{}: {path}: {e}", op.name()))?;
            Port::Input {
                chars: text.chars().collect(),
                offset: 0,
                closed: false,
            }
        } else {
            let file = File::create(path).map_err(|e| format!("{}: {path}: {e}", op.name()))?;
            Port::FileOutput(Some(file))
        }
    };
    Ok(vm.alloc(port))
}

fn read_port_string(vm: &mut Allocation<'_>, args: Arguments<'_>) -> Result<Value, String> {
    arity(Builtin::ReadString, args, 1, 2)?;
    let count = args[0].index(&vm.heap)?;
    let handle = args.get(1).copied().unwrap_or(vm.host.input);
    Ok(match read_string(port_mut(vm, handle)?, count)? {
        Some(text) => vm.alloc(Text::new(text)),
        None => Value::EOF,
    })
}

fn output_string(vm: &mut Allocation<'_>, args: Arguments<'_>) -> Result<Value, String> {
    arity(Builtin::GetOutputString, args, 1, 1)?;
    let Port::Output { buffer, .. } = port_mut(vm, args[0])? else {
        return Err("get-output-string: expected a string output port".into());
    };
    let text = buffer.clone();
    Ok(vm.alloc(Text::new(text)))
}

// ---- Port I/O ----

fn close_port(port: &mut Port) -> Result<(), String> {
    match port {
        Port::Input { closed, .. } | Port::Output { closed, .. } => *closed = true,
        Port::FileOutput(file) => {
            if let Some(mut file) = file.take() {
                file.flush().map_err(|e| e.to_string())?;
            }
        }
        Port::Closed => {}
        Port::Stdout => {
            std::io::stdout().flush().map_err(|e| e.to_string())?;
            *port = Port::Closed;
        }
        Port::Stderr => {
            std::io::stderr().flush().map_err(|e| e.to_string())?;
            *port = Port::Closed;
        }
        Port::Stdin => {
            *port = Port::Closed;
        }
    }
    Ok(())
}

fn read_char(port: &mut Port) -> Result<Value, String> {
    match port {
        Port::Input { closed: true, .. } | Port::Closed => Err("read-char: port is closed".into()),
        Port::Input { chars, offset, .. } => {
            if let Some(&ch) = chars.get(*offset) {
                *offset += 1;
                Ok(Value::character(ch))
            } else {
                Ok(Value::EOF)
            }
        }
        Port::Stdin => read_stdin_char(),
        _ => Err("read-char: expected an input port".into()),
    }
}

fn read_string(port: &mut Port, count: usize) -> Result<Option<String>, String> {
    match port {
        Port::Input {
            chars,
            offset,
            closed: false,
        } => {
            let end = offset.saturating_add(count).min(chars.len());
            if count > 0 && *offset == end {
                return Ok(None);
            }
            let text = chars[*offset..end].iter().collect();
            *offset = end;
            Ok(Some(text))
        }
        Port::Stdin => read_stdin_string(count),
        Port::Input { closed: true, .. } | Port::Closed => {
            Err("read-string: port is closed".into())
        }
        _ => Err("read-string: expected an input port".into()),
    }
}

fn read_stdin_string(count: usize) -> Result<Option<String>, String> {
    let mut text = String::new();
    for _ in 0..count {
        let value = read_stdin_char()?;
        if value == Value::EOF {
            break;
        }
        text.push(value.as_character().unwrap());
    }
    Ok(if count > 0 && text.is_empty() {
        None
    } else {
        Some(text)
    })
}

/// Decode one UTF-8 scalar without buffering past it or waiting for stdin EOF.
fn read_stdin_char() -> Result<Value, String> {
    let mut input = std::io::stdin().lock();
    let mut bytes = [0_u8; 4];
    loop {
        match input.read(&mut bytes[..1]) {
            Ok(0) => return Ok(Value::EOF),
            Ok(_) => break,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(format!("read-char: {e}")),
        }
    }
    let length = match bytes[0] {
        0x00..=0x7f => 1,
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => return Err("read-char: invalid UTF-8".into()),
    };
    input
        .read_exact(&mut bytes[1..length])
        .map_err(|e| format!("read-char: {e}"))?;
    let text = std::str::from_utf8(&bytes[..length]).map_err(|e| format!("read-char: {e}"))?;
    text.chars()
        .next()
        .map(Value::character)
        .ok_or_else(|| "read-char: empty UTF-8 character".into())
}

fn output(vm: &mut Runtime, op: Builtin, args: Arguments<'_>) -> Result<Value, String> {
    let (text, handle) = if op == Builtin::Newline {
        arity(op, args, 0, 1)?;
        ("\n".into(), args.first().copied().unwrap_or(vm.host.output))
    } else {
        arity(op, args, 1, 2)?;
        (
            format_value(vm, args[0], op == Builtin::Display)?,
            args.get(1).copied().unwrap_or(vm.host.output),
        )
    };
    write_port(port_mut(vm, handle)?, &text)?;
    Ok(Value::UNSPECIFIED)
}

fn write_port(port: &mut Port, text: &str) -> Result<(), String> {
    match port {
        Port::Output { closed: true, .. } | Port::FileOutput(None) | Port::Closed => {
            Err("write: port is closed".into())
        }
        Port::FileOutput(Some(file)) => file.write_all(text.as_bytes()).map_err(|e| e.to_string()),
        Port::Output { buffer, .. } => {
            buffer.push_str(text);
            Ok(())
        }
        Port::Stdout => {
            let mut output = std::io::stdout().lock();
            output
                .write_all(text.as_bytes())
                .and_then(|_| output.flush())
                .map_err(|e| e.to_string())
        }
        Port::Stderr => {
            let mut output = std::io::stderr().lock();
            output
                .write_all(text.as_bytes())
                .and_then(|_| output.flush())
                .map_err(|e| e.to_string())
        }
        _ => Err("write: expected an output port".into()),
    }
}

fn set_current_port(vm: &mut Runtime, op: Builtin, args: Arguments<'_>) -> Result<(), String> {
    arity(op, args, 1, 1)?;
    let port = port_mut(vm, args[0])?;
    if op == Builtin::SetCurrentInputPort {
        if !matches!(port, Port::Stdin | Port::Input { closed: false, .. }) {
            return Err("expected an open input port".into());
        }
        vm.host.input = args[0];
    } else {
        if !matches!(
            port,
            Port::Stdout
                | Port::Stderr
                | Port::Output { closed: false, .. }
                | Port::FileOutput(Some(_))
        ) {
            return Err("expected an open output port".into());
        }
        if op == Builtin::SetCurrentOutputPort {
            vm.host.output = args[0];
        } else {
            vm.host.error = args[0];
        }
    }
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bulk_reads_count_unicode_scalars_and_keep_eof_distinct_from_empty() {
        let mut port = Port::Input {
            chars: "aλ😀z".chars().collect(),
            offset: 0,
            closed: false,
        };
        assert_eq!(read_string(&mut port, 0).unwrap(), Some(String::new()));
        assert_eq!(read_string(&mut port, 2).unwrap(), Some("aλ".into()));
        assert_eq!(read_string(&mut port, 99).unwrap(), Some("😀z".into()));
        assert_eq!(read_string(&mut port, 1).unwrap(), None);
        assert_eq!(read_string(&mut port, 0).unwrap(), Some(String::new()));
        close_port(&mut port).unwrap();
        assert!(read_string(&mut port, 0).is_err());
    }

    #[test]
    fn input_ports_consume_characters_and_reject_reads_after_close() {
        let mut port = Port::Input {
            chars: vec!['λ', '😀'],
            offset: 0,
            closed: false,
        };
        assert_eq!(read_char(&mut port).unwrap(), Value::character('λ'));
        assert_eq!(read_char(&mut port).unwrap(), Value::character('😀'));
        assert_eq!(read_char(&mut port).unwrap(), Value::EOF);
        assert_eq!(read_char(&mut port).unwrap(), Value::EOF);
        close_port(&mut port).unwrap();
        assert!(read_char(&mut port).is_err());
    }

    #[test]
    fn string_ports_capture_output_and_reject_writes_after_close() {
        let mut vm = Runtime::for_test(Vec::new());
        let port = open_port(
            &mut vm.allocation(),
            Builtin::OpenOutputString,
            Arguments(&[]),
        )
        .unwrap();
        let text = vm.allocation().alloc(Text::new("λ".into()));
        output(&mut vm, Builtin::Display, Arguments(&[port, text])).unwrap();
        output(&mut vm, Builtin::Newline, Arguments(&[port])).unwrap();
        let PrimitiveResult::Value(value) = invoke_allocating(
            &mut vm.allocation(),
            Builtin::GetOutputString,
            Arguments(&[port]),
        )
        .unwrap() else {
            panic!("get-output-string must return a value");
        };
        assert_eq!(vm.string(value).unwrap(), "λ\n");
        close_port(port_mut(&mut vm, port).unwrap()).unwrap();
        assert!(output(&mut vm, Builtin::Newline, Arguments(&[port])).is_err());
    }
}
