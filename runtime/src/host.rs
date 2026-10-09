//! Host services for the std-based native/WASI executable adapter.
//!
//! Ports are Scheme objects, but all operating-system access stays here. The VM
//! explicitly roots the three current ports. A future no_std adapter can replace
//! these services without changing the generated-code ABI.

use crate::{
    heap::Object,
    primitives::{PrimitiveResult, arity, format_value},
    value::Value,
    vm::Vm,
};
use std::{
    fs::File,
    io::{Read, Write},
    time::Instant,
};

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

pub(crate) fn primitive(
    vm: &mut Vm,
    name: &str,
    args: &[Value],
) -> Option<Result<PrimitiveResult, String>> {
    if !matches!(
        name,
        "open-input-file"
            | "open-output-file"
            | "close-port"
            | "read-char"
            | "eof-object?"
            | "open-output-string"
            | "get-output-string"
            | "display"
            | "write"
            | "newline"
            | "%current-input-port"
            | "%current-output-port"
            | "%current-error-port"
            | "%set-current-input-port!"
            | "%set-current-output-port!"
            | "%set-current-error-port!"
            | "command-line"
            | "exit"
            | "current-jiffy"
            | "jiffies-per-second"
    ) {
        return None;
    }
    Some(invoke(vm, name, args))
}

fn invoke(vm: &mut Vm, name: &str, args: &[Value]) -> Result<PrimitiveResult, String> {
    let value = match name {
        "open-input-file" | "open-output-file" | "open-output-string" => open_port(vm, name, args)?,
        "close-port" => {
            arity(name, args, 1, 1)?;
            close_port(port_mut(vm, args[0])?)?;
            Value::Unspecified
        }
        "read-char" => {
            arity(name, args, 0, 1)?;
            let handle = args.first().copied().unwrap_or(vm.host.input);
            read_char(port_mut(vm, handle)?)?
        }
        "eof-object?" => {
            arity(name, args, 1, 1)?;
            Value::Bool(args[0] == Value::Eof)
        }
        "get-output-string" => {
            arity(name, args, 1, 1)?;
            let Port::Output { buffer, .. } = port_mut(vm, args[0])? else {
                return Err("get-output-string: expected a string output port".into());
            };
            let text = buffer.clone();
            vm.alloc(Object::String(text))
        }
        "display" | "write" | "newline" => output(vm, name, args)?,
        "%current-input-port" | "%current-output-port" | "%current-error-port" => {
            arity(name, args, 0, 0)?;
            match name {
                "%current-input-port" => vm.host.input,
                "%current-output-port" => vm.host.output,
                _ => vm.host.error,
            }
        }
        "%set-current-input-port!" | "%set-current-output-port!" | "%set-current-error-port!" => {
            set_current_port(vm, name, args)?;
            Value::Unspecified
        }
        "command-line" => {
            arity(name, args, 0, 0)?;
            let arguments = vm.argv.clone();
            let strings: Vec<Value> = arguments
                .into_iter()
                .map(|s| vm.alloc(Object::String(s)))
                .collect();
            vm.list(&strings)
        }
        "exit" => {
            arity(name, args, 0, 1)?;
            let code = match args.first() {
                None | Some(Value::Bool(true)) => 0,
                Some(Value::Bool(false)) => 1,
                Some(value) => {
                    i32::try_from(value.integer()?).map_err(|_| "exit status out of range")?
                }
            };
            return Ok(PrimitiveResult::Exit(code));
        }
        "current-jiffy" => {
            arity(name, args, 0, 0)?;
            let ticks = i64::try_from(vm.host.started.elapsed().as_nanos())
                .map_err(|_| "monotonic clock exceeds integer range")?;
            Value::Integer(ticks)
        }
        "jiffies-per-second" => {
            arity(name, args, 0, 0)?;
            Value::Integer(1_000_000_000)
        }
        _ => unreachable!(),
    };
    Ok(PrimitiveResult::Values(vec![value]))
}

fn port_mut(vm: &mut Vm, value: Value) -> Result<&mut Port, String> {
    match vm.heap.get_mut(value)? {
        Object::Port(port) => Ok(port),
        _ => Err("expected a port".into()),
    }
}

fn open_port(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    let port = if name == "open-output-string" {
        arity(name, args, 0, 0)?;
        Port::Output {
            buffer: String::new(),
            closed: false,
        }
    } else {
        arity(name, args, 1, 1)?;
        let path = vm.string(args[0])?;
        if name == "open-input-file" {
            let text =
                std::fs::read_to_string(&path).map_err(|e| format!("{name}: {path}: {e}"))?;
            Port::Input {
                chars: text.chars().collect(),
                offset: 0,
                closed: false,
            }
        } else {
            let file = File::create(&path).map_err(|e| format!("{name}: {path}: {e}"))?;
            Port::FileOutput(Some(file))
        }
    };
    Ok(vm.alloc(Object::Port(port)))
}

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
                Ok(Value::Char(ch))
            } else {
                Ok(Value::Eof)
            }
        }
        Port::Stdin => read_stdin_char(),
        _ => Err("read-char: expected an input port".into()),
    }
}

/// Decode one UTF-8 scalar without buffering past it or waiting for stdin EOF.
fn read_stdin_char() -> Result<Value, String> {
    let mut input = std::io::stdin().lock();
    let mut bytes = [0_u8; 4];
    loop {
        match input.read(&mut bytes[..1]) {
            Ok(0) => return Ok(Value::Eof),
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
        .map(Value::Char)
        .ok_or_else(|| "read-char: empty UTF-8 character".into())
}

fn output(vm: &mut Vm, name: &str, args: &[Value]) -> Result<Value, String> {
    let (text, handle) = if name == "newline" {
        arity(name, args, 0, 1)?;
        ("\n".into(), args.first().copied().unwrap_or(vm.host.output))
    } else {
        arity(name, args, 1, 2)?;
        (
            format_value(vm, args[0], name == "display")?,
            args.get(1).copied().unwrap_or(vm.host.output),
        )
    };
    write_port(port_mut(vm, handle)?, &text)?;
    Ok(Value::Unspecified)
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

fn set_current_port(vm: &mut Vm, name: &str, args: &[Value]) -> Result<(), String> {
    arity(name, args, 1, 1)?;
    let port = port_mut(vm, args[0])?;
    if name == "%set-current-input-port!" {
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
        if name == "%set-current-output-port!" {
            vm.host.output = args[0];
        } else {
            vm.host.error = args[0];
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_ports_consume_characters_and_reject_reads_after_close() {
        let mut port = Port::Input {
            chars: vec!['λ', '😀'],
            offset: 0,
            closed: false,
        };
        assert_eq!(read_char(&mut port).unwrap(), Value::Char('λ'));
        assert_eq!(read_char(&mut port).unwrap(), Value::Char('😀'));
        assert_eq!(read_char(&mut port).unwrap(), Value::Eof);
        assert_eq!(read_char(&mut port).unwrap(), Value::Eof);
        close_port(&mut port).unwrap();
        assert!(read_char(&mut port).is_err());
    }

    #[test]
    fn string_ports_capture_output_and_reject_writes_after_close() {
        let mut vm = Vm::new(0, 0, Vec::new());
        let port = open_port(&mut vm, "open-output-string", &[]).unwrap();
        let text = vm.alloc(Object::String("λ".into()));
        output(&mut vm, "display", &[text, port]).unwrap();
        output(&mut vm, "newline", &[port]).unwrap();
        let PrimitiveResult::Values(values) =
            invoke(&mut vm, "get-output-string", &[port]).unwrap()
        else {
            panic!("get-output-string must return a value");
        };
        assert_eq!(vm.string(values[0]).unwrap(), "λ\n");
        close_port(port_mut(&mut vm, port).unwrap()).unwrap();
        assert!(output(&mut vm, "newline", &[port]).is_err());
    }
}
