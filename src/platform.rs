//! Default WASI handlers. The linker selects these through effect interfaces.
//! Scheme values remain roots in the node's engine; resources belong here.

use crate::abi::{Arguments, Kind, Root};
use crate::host::Port;
use crate::{
    arguments, bounds, datum, fail_message, finish, format_value, nonnegative, string_text,
};
use std::{
    cell::RefCell,
    time::{Instant, SystemTime, UNIX_EPOCH},
};

// ---- Command context ----

#[unsafe(export_name = "snail:initialize-environment")]
pub extern "C" fn initialize_environment() {
    if let Ok(directory) = std::env::var("SNAIL_CWD") {
        std::env::set_current_dir(directory)
            .unwrap_or_else(|error| fail_message(&error.to_string()));
    }
}

// ---- Diagnostics ----

/// The message borrows the linked library's shared linear memory for this call.
#[unsafe(export_name = "snail:report-error")]
pub unsafe extern "C" fn report_error(pointer: *const u8, length: usize) {
    let bytes = unsafe { std::slice::from_raw_parts(pointer, length) };
    eprintln!("snail-scheme: {}", String::from_utf8_lossy(bytes));
    std::process::exit(1)
}

#[unsafe(export_name = "snail:fail")]
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
        10 => "main must return an exit status in 0..255",
        _ => "WebAssembly runtime error",
    })
}

// ---- Host-owned resources ----

// Port wrappers use the ABI resource-kind assignment.
use crate::abi::PORT_KIND;

struct Host {
    ports: Vec<Port>,
    current: [Root; 3],
}

impl Host {
    fn new() -> Self {
        Self {
            ports: vec![Port::stdin(), Port::Stdout, Port::Stderr],
            // Each freshly created port receives its one owning GC wrapper.
            current: std::array::from_fn(|id| unsafe {
                Root::from_raw_extension(PORT_KIND, id as u32)
            }),
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

// ABI accessors never call Scheme or reenter Rust. Host borrows do not cross
// user callbacks. Resources are explicitly closed; GC is not a Rust finalizer.
thread_local! { static HOST: RefCell<Host> = RefCell::new(Host::new()); }

fn selected_port(args: &Arguments, index: usize, current: usize) -> Result<Root, String> {
    if index < args.len() {
        args.get(index)
    } else {
        Ok(HOST.with_borrow(|host| host.current[current].clone()))
    }
}

#[unsafe(export_name = "snail:open-input-file")]
pub extern "C" fn open_input_file(raw: u32) -> u32 {
    let args = arguments(raw, "open-input-file", 1, 1);
    finish(open_file(&args, true))
}

#[unsafe(export_name = "snail:open-output-file")]
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

#[unsafe(export_name = "snail:open-binary-input-file")]
pub extern "C" fn open_binary_input_file(raw: u32) -> u32 {
    let args = arguments(raw, "open-binary-input-file", 1, 1);
    finish((|| {
        let port = Port::binary_input_file(&string_text(&args.get(0)?)?)?;
        HOST.with_borrow_mut(|host| host.add_port(port))
    })())
}

#[unsafe(export_name = "snail:file-exists?")]
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

#[unsafe(export_name = "snail:open-output-string")]
pub extern "C" fn open_output_string(raw: u32) -> u32 {
    arguments(raw, "open-output-string", 0, 0);
    finish(HOST.with_borrow_mut(|host| host.add_port(Port::output_string())))
}

#[unsafe(export_name = "snail:get-output-string")]
pub extern "C" fn get_output_string(raw: u32) -> u32 {
    let args = arguments(raw, "get-output-string", 1, 1);
    finish(
        HOST.with_borrow_mut(|host| Ok(Root::string(host.port(&args.get(0)?)?.captured_output()?))),
    )
}

#[unsafe(export_name = "snail:close-port")]
pub extern "C" fn close_port(raw: u32) -> u32 {
    let args = arguments(raw, "close-port", 1, 1);
    finish(HOST.with_borrow_mut(|host| {
        host.port(&args.get(0)?)?.close()?;
        Ok(Root::unspecified())
    }))
}

/// Host finalization releases the Rust payload after its GC wrapper dies.
/// Resource IDs are never reused, so repeated/late notices cannot close a new port.
#[unsafe(export_name = "snail:drop-resource")]
pub extern "C" fn drop_resource(kind: u32, id: u32) {
    if kind != PORT_KIND {
        return;
    }
    let port = HOST.with_borrow_mut(|host| {
        host.ports.get_mut(id as usize).map(|slot| {
            std::mem::replace(
                slot,
                Port::Closed {
                    input: false,
                    binary: false,
                },
            )
        })
    });
    if let Some(mut port) = port {
        let _ = port.close();
    }
}

// ---- Reading and writing ----

#[unsafe(export_name = "snail:input-port?")]
pub extern "C" fn input_port(raw: u32) -> u32 {
    let args = arguments(raw, "input-port?", 1, 1);
    finish(args.get(0).map(|value| {
        Root::boolean(
            HOST.with_borrow_mut(|host| host.port(&value).is_ok_and(|port| port.is_input())),
        )
    }))
}

#[unsafe(export_name = "snail:output-port?")]
pub extern "C" fn output_port(raw: u32) -> u32 {
    let args = arguments(raw, "output-port?", 1, 1);
    finish(args.get(0).map(|value| {
        Root::boolean(
            HOST.with_borrow_mut(|host| host.port(&value).is_ok_and(|port| port.is_output())),
        )
    }))
}

#[unsafe(export_name = "snail:port?")]
pub extern "C" fn port_predicate(raw: u32) -> u32 {
    let args = arguments(raw, "port?", 1, 1);
    finish(
        args.get(0)
            .map(|value| Root::boolean(HOST.with_borrow_mut(|host| host.port(&value).is_ok()))),
    )
}

#[unsafe(export_name = "snail:input-port-open?")]
pub extern "C" fn input_port_open(raw: u32) -> u32 {
    let args = arguments(raw, "input-port-open?", 1, 1);
    finish(args.get(0).and_then(|value| {
        HOST.with_borrow_mut(|host| {
            host.port(&value)
                .map(|port| Root::boolean(port.is_input() && port.is_open()))
        })
    }))
}

#[unsafe(export_name = "snail:output-port-open?")]
pub extern "C" fn output_port_open(raw: u32) -> u32 {
    let args = arguments(raw, "output-port-open?", 1, 1);
    finish(args.get(0).and_then(|value| {
        HOST.with_borrow_mut(|host| {
            host.port(&value)
                .map(|port| Root::boolean(port.is_output() && port.is_open()))
        })
    }))
}

#[unsafe(export_name = "snail:textual-port?")]
pub extern "C" fn textual_port(raw: u32) -> u32 {
    let args = arguments(raw, "textual-port?", 1, 1);
    finish(args.get(0).and_then(|value| {
        HOST.with_borrow_mut(|host| {
            host.port(&value)
                .map(|port| Root::boolean(!port.is_binary()))
        })
    }))
}

#[unsafe(export_name = "snail:binary-port?")]
pub extern "C" fn binary_port(raw: u32) -> u32 {
    let args = arguments(raw, "binary-port?", 1, 1);
    finish(args.get(0).and_then(|value| {
        HOST.with_borrow_mut(|host| {
            host.port(&value)
                .map(|port| Root::boolean(port.is_binary()))
        })
    }))
}

#[unsafe(export_name = "snail:delete-file")]
pub extern "C" fn delete_file(raw: u32) -> u32 {
    let args = arguments(raw, "delete-file", 1, 1);
    finish((|| {
        std::fs::remove_file(string_text(&args.get(0)?)?).map_err(|error| error.to_string())?;
        Ok(Root::unspecified())
    })())
}

#[unsafe(export_name = "snail:flush-output-port")]
pub extern "C" fn flush_output_port(raw: u32) -> u32 {
    let args = arguments(raw, "flush-output-port", 0, 1);
    finish((|| {
        let port = selected_port(&args, 0, 1)?;
        HOST.with_borrow_mut(|host| host.port(&port)?.flush())?;
        Ok(Root::unspecified())
    })())
}

#[unsafe(export_name = "snail:write-string")]
pub extern "C" fn write_string(raw: u32) -> u32 {
    let args = arguments(raw, "write-string", 1, 4);
    finish(write_port_string(&args))
}

fn write_port_string(args: &Arguments) -> Result<Root, String> {
    let value = args.get(0)?;
    if value.kind() != Kind::String {
        return Err("expected a string".into());
    }
    let range = bounds(args, value.len()?, 2)?;
    let text = range
        .map(|index| value.char_at(index))
        .collect::<Result<String, _>>()?;
    let port = selected_port(args, 1, 1)?;
    HOST.with_borrow_mut(|host| host.port(&port)?.write(&text))?;
    Ok(Root::unspecified())
}

#[unsafe(export_name = "snail:read")]
pub extern "C" fn read(raw: u32) -> u32 {
    let args = arguments(raw, "read", 0, 1);
    finish((|| {
        let port = selected_port(&args, 0, 0)?;
        let datum = HOST.with_borrow_mut(|host| datum::read(host.port(&port)?.text_input()?))?;
        datum.map_or_else(|| Ok(Root::eof()), |value| value.into_root())
    })())
}

#[unsafe(export_name = "snail:open-input-string")]
pub extern "C" fn open_input_string(raw: u32) -> u32 {
    let args = arguments(raw, "open-input-string", 1, 1);
    finish((|| {
        let port = Port::input_string(string_text(&args.get(0)?)?);
        HOST.with_borrow_mut(|host| host.add_port(port))
    })())
}

#[unsafe(export_name = "snail:peek-char")]
pub extern "C" fn peek_char(raw: u32) -> u32 {
    let args = arguments(raw, "peek-char", 0, 1);
    finish((|| {
        let port = selected_port(&args, 0, 0)?;
        HOST.with_borrow_mut(|host| {
            Ok(host
                .port(&port)?
                .text_input()?
                .peek_char()?
                .map(Root::character)
                .unwrap_or_else(Root::eof))
        })
    })())
}

#[unsafe(export_name = "snail:read-line")]
pub extern "C" fn read_line(raw: u32) -> u32 {
    let args = arguments(raw, "read-line", 0, 1);
    finish((|| {
        let port = selected_port(&args, 0, 0)?;
        HOST.with_borrow_mut(|host| {
            Ok(host
                .port(&port)?
                .text_input()?
                .read_line()?
                .map(|text| Root::string(&text))
                .unwrap_or_else(Root::eof))
        })
    })())
}

#[unsafe(export_name = "snail:write-char")]
pub extern "C" fn write_char(raw: u32) -> u32 {
    let args = arguments(raw, "write-char", 1, 2);
    finish((|| {
        let text = args.get(0)?.as_character()?.to_string();
        let port = selected_port(&args, 1, 1)?;
        HOST.with_borrow_mut(|host| host.port(&port)?.write(&text))?;
        Ok(Root::unspecified())
    })())
}

#[unsafe(export_name = "snail:read-char")]
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

#[unsafe(export_name = "snail:read-string")]
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

#[unsafe(export_name = "snail:read-bytevector")]
pub extern "C" fn read_bytevector(raw: u32) -> u32 {
    let args = arguments(raw, "read-bytevector", 1, 2);
    finish((|| {
        let count = nonnegative(&args.get(0)?)?;
        let port = selected_port(&args, 1, 0)?;
        HOST.with_borrow_mut(|host| {
            Ok(match host.port(&port)?.read_bytes(count)? {
                Some(bytes) => Root::bytevector(&bytes),
                None => Root::eof(),
            })
        })
    })())
}

#[unsafe(export_name = "snail:display")]
pub extern "C" fn display(raw: u32) -> u32 {
    finish(output(&arguments(raw, "display", 1, 2), true))
}

#[unsafe(export_name = "snail:write")]
pub extern "C" fn write(raw: u32) -> u32 {
    finish(output(&arguments(raw, "write", 1, 2), false))
}

fn output(args: &Arguments, display: bool) -> Result<Root, String> {
    let text = format_value(args.get(0)?, display)?;
    let port = selected_port(args, 1, 1)?;
    HOST.with_borrow_mut(|host| host.port(&port)?.write(&text))?;
    Ok(Root::unspecified())
}

#[unsafe(export_name = "snail:newline")]
pub extern "C" fn newline(raw: u32) -> u32 {
    let args = arguments(raw, "newline", 0, 1);
    finish(write_newline(&args))
}

fn write_newline(args: &Arguments) -> Result<Root, String> {
    let port = selected_port(args, 0, 1)?;
    HOST.with_borrow_mut(|host| host.port(&port)?.write("\n"))?;
    Ok(Root::unspecified())
}

#[unsafe(export_name = "snail:%current-input-port")]
pub extern "C" fn current_input(raw: u32) -> u32 {
    current_port(raw, "%current-input-port", 0)
}
#[unsafe(export_name = "snail:%current-output-port")]
pub extern "C" fn current_output(raw: u32) -> u32 {
    current_port(raw, "%current-output-port", 1)
}
#[unsafe(export_name = "snail:%current-error-port")]
pub extern "C" fn current_error(raw: u32) -> u32 {
    current_port(raw, "%current-error-port", 2)
}

fn current_port(raw: u32, name: &str, index: usize) -> u32 {
    arguments(raw, name, 0, 0);
    HOST.with_borrow(|host| host.current[index].clone().into_handle())
}

#[unsafe(export_name = "snail:%set-current-input-port!")]
pub extern "C" fn set_current_input(raw: u32) -> u32 {
    set_current_port(raw, "%set-current-input-port!", 0)
}
#[unsafe(export_name = "snail:%set-current-output-port!")]
pub extern "C" fn set_current_output(raw: u32) -> u32 {
    set_current_port(raw, "%set-current-output-port!", 1)
}
#[unsafe(export_name = "snail:%set-current-error-port!")]
pub extern "C" fn set_current_error(raw: u32) -> u32 {
    set_current_port(raw, "%set-current-error-port!", 2)
}

fn set_current_port(raw: u32, name: &str, index: usize) -> u32 {
    let args = arguments(raw, name, 1, 1);
    finish(HOST.with_borrow_mut(|host| {
        let value = args.get(0)?;
        let port = host.port(&value)?;
        if !port.is_open()
            || !(if index == 0 {
                port.is_input()
            } else {
                port.is_output()
            })
        {
            return Err("expected an open port of the appropriate direction".into());
        }
        host.current[index] = value;
        Ok(Root::unspecified())
    }))
}

// ---- Process, clocks, tracing, and diagnostics ----

#[unsafe(export_name = "snail:get-environment-variable")]
pub extern "C" fn get_environment_variable(raw: u32) -> u32 {
    let args = arguments(raw, "get-environment-variable", 1, 1);
    finish((|| {
        let name = string_text(&args.get(0)?)?;
        match std::env::var(name) {
            Ok(value) => Ok(Root::string(&value)),
            Err(std::env::VarError::NotPresent) => Ok(Root::boolean(false)),
            Err(error) => Err(error.to_string()),
        }
    })())
}

#[unsafe(export_name = "snail:command-line")]
pub extern "C" fn command_line(raw: u32) -> u32 {
    arguments(raw, "command-line", 0, 0);
    let mut list = Root::nil();
    for argument in std::env::args().collect::<Vec<_>>().into_iter().rev() {
        list = Root::pair(&Root::string(&argument), &list);
    }
    list.into_handle()
}

#[unsafe(export_name = "snail:exit")]
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

// R7RS permits approximating TAI by UTC plus a constant. This offset has been
// 37 seconds since 2017; current-jiffy remains the clock for monotonic timing.
#[unsafe(export_name = "snail:current-second")]
pub extern "C" fn current_second(raw: u32) -> u32 {
    arguments(raw, "current-second", 0, 0);
    let time = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|time| time.as_secs_f64())
        .unwrap_or_else(|error| -error.duration().as_secs_f64());
    Root::real(time + 37.0).into_handle()
}

#[unsafe(export_name = "snail:current-jiffy")]
pub extern "C" fn current_jiffy(raw: u32) -> u32 {
    arguments(raw, "current-jiffy", 0, 0);
    thread_local! { static STARTED: Instant = Instant::now(); }
    let nanos = STARTED.with(|started| started.elapsed().as_nanos());
    finish(
        i64::try_from(nanos)
            .map(Root::integer)
            .map_err(|_| "monotonic clock exceeds integer range".into()),
    )
}

#[unsafe(export_name = "snail:jiffies-per-second")]
pub extern "C" fn jiffies_per_second(raw: u32) -> u32 {
    arguments(raw, "jiffies-per-second", 0, 0);
    Root::integer(1_000_000_000).into_handle()
}

#[unsafe(export_name = "snail:error")]
pub extern "C" fn error(raw: u32) -> u32 {
    let args = arguments(raw, "error", 1, usize::MAX);
    let texts = (0..args.len())
        .map(|i| args.get(i).and_then(|value| format_value(value, true)))
        .collect::<Result<Vec<_>, _>>();
    fail_message(&texts.unwrap_or_else(|error| fail_message(&error)).join(" "))
}
