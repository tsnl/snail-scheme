//! Scalar text-file services for the Lofi library.
//!
//! Rust owns files, never managed values. IDs are issued once and never reused.
//! Lofi closes explicitly; the invocation host calls close-all after a trap.
//! A trapped instance is terminal. There is no GC finalization of these files.
//! Standard streams have reserved borrowed IDs, outside the owned-file registry.

use crate::{
    fail_message,
    host::{Port, flush_standard_output},
};
use std::{cell::RefCell, collections::BTreeMap, path::Path};

const STANDARD_OUTPUT: u32 = (-2_i32) as u32;
const STANDARD_INPUT: u32 = (-3_i32) as u32;

// ---- Owned resources and synchronous pathname transfer ----

#[derive(Default)]
struct Files {
    next: u32,
    live: BTreeMap<u32, Port>,
}

thread_local! {
    static FILES: RefCell<Files> = RefCell::new(Files::default());
    static PATHNAME: RefCell<Option<String>> = const { RefCell::new(None) };
    // One shared reader preserves lookahead across every borrowed stdin alias.
    static INPUT: RefCell<Port> = RefCell::new(Port::stdin());
}

impl Files {
    fn reserve_id(&mut self) -> Result<i32, String> {
        let id = i32::try_from(self.next).map_err(|_| "file port IDs exhausted")?;
        self.next += 1;
        Ok(id)
    }

    fn get(&mut self, id: u32) -> Result<&mut Port, String> {
        self.live
            .get_mut(&id)
            .ok_or_else(|| "unknown or closed file port".into())
    }

    fn take(&mut self, id: u32) -> Result<Port, String> {
        self.live
            .remove(&id)
            .ok_or_else(|| "unknown or closed file port".into())
    }
}

// WASI has no working directory of its own; the host passes it as SNAIL_CWD
// and relative paths are resolved against it.
fn take_pathname() -> Result<String, String> {
    let path = PATHNAME
        .with_borrow_mut(Option::take)
        .ok_or("no pathname transfer is active")?;
    Ok(match std::env::var("SNAIL_CWD") {
        Ok(directory) if !path.starts_with('/') => format!("{directory}/{path}"),
        _ => path,
    })
}

fn append_character(text: &mut String, code: u32) -> Result<(), String> {
    text.push(char::from_u32(code).ok_or("invalid Unicode scalar")?);
    Ok(())
}

// One instance runs one invocation at a time. These private transfer operations
// never call guest code, and the Lofi loop performs no user callbacks. Reentry or
// concurrent invocation during a transfer is outside this provider's contract.
#[unsafe(export_name = "snail:io/path-begin")]
pub extern "C" fn path_begin() {
    PATHNAME.with_borrow_mut(|path| *path = Some(String::new()));
}

#[unsafe(export_name = "snail:io/path-character")]
pub extern "C" fn path_character(code: u32) {
    let result = PATHNAME.with_borrow_mut(|path| {
        append_character(path.as_mut().ok_or("no pathname transfer is active")?, code)
    });
    checked(result);
}

// ---- Filesystem operations consume their pathname on every outcome ----

#[unsafe(export_name = "snail:io/file-exists")]
pub extern "C" fn file_exists() -> i32 {
    let result = take_pathname().and_then(|path| {
        Path::new(&path)
            .try_exists()
            .map(i32::from)
            .map_err(|error| format!("{path}: {error}"))
    });
    checked(result)
}

fn open_output(path: String) -> Result<i32, String> {
    // Exhaustion is checked before creating or truncating a file. Failed opens
    // consume an ID too; no old integer can ever acquire a different resource.
    let id = FILES.with_borrow_mut(Files::reserve_id)?;
    let port = Port::output_file(&path)?;
    FILES.with_borrow_mut(|files| files.live.insert(id as u32, port));
    Ok(id)
}

#[unsafe(export_name = "snail:io/open-output-file")]
pub extern "C" fn open_output_file() -> i32 {
    checked(take_pathname().and_then(open_output))
}

fn open_input(path: String) -> Result<i32, String> {
    let id = FILES.with_borrow_mut(Files::reserve_id)?;
    let port = Port::input_file(&path)?;
    FILES.with_borrow_mut(|files| files.live.insert(id as u32, port));
    Ok(id)
}

#[unsafe(export_name = "snail:io/open-input-file")]
pub extern "C" fn open_input_file() -> i32 {
    checked(take_pathname().and_then(open_input))
}

// ---- Scalar character reads and writes ----

// Unicode scalars are nonnegative and fit in I32. Only EOF becomes -1;
// malformed UTF-8 and read failures take the ordinary fatal cleanup path.
#[unsafe(export_name = "snail:io/read-character")]
pub extern "C" fn read_code(id: u32) -> i32 {
    let result = if id == STANDARD_INPUT {
        // A prompt written without a newline appears before input is awaited.
        flush_standard_output().and_then(|()| INPUT.with_borrow_mut(Port::read_char))
    } else {
        FILES.with_borrow_mut(|files| files.get(id)?.read_char())
    };
    checked(result).map_or(-1, |character| character as i32)
}

// A byte of a binary file, from 0 to 255, or -1 at EOF. Standard input is
// text only.
#[unsafe(export_name = "snail:io/read-byte")]
pub extern "C" fn read_byte(id: u32) -> i32 {
    let result = FILES.with_borrow_mut(|files| files.get(id)?.read_byte());
    checked(result).map_or(-1, i32::from)
}

fn write_character(port: &mut Port, code: u32) -> Result<(), String> {
    let character = char::from_u32(code).ok_or("invalid Unicode scalar")?;
    let mut bytes = [0; 4];
    port.write(character.encode_utf8(&mut bytes))
}

// ---- Staged text ----

// Rust cannot read Lofi's managed strings, so a call that takes text is
// preceded by `stage`: Lofi copies the scalars, four bytes each, to the address
// it returns, and the call receives their count. The address is valid until
// the next `stage`, and Lofi stages just before the call that reads it. The
// buffer only grows, so zeroing it costs no more than the longest text.
thread_local! {
    static STAGED: RefCell<Vec<u32>> = const { RefCell::new(Vec::new()) };
}

#[unsafe(export_name = "snail:io/stage")]
pub extern "C" fn stage(count: u32) -> u32 {
    STAGED.with_borrow_mut(|staged| {
        if staged.len() < count as usize {
            staged.resize(count as usize, 0);
        }
        staged.as_mut_ptr() as u32
    })
}

fn staged_text(count: u32) -> Result<String, String> {
    STAGED.with_borrow(|staged| {
        let scalars = staged
            .get(..count as usize)
            .ok_or("more text than was staged")?;
        let mut text = String::with_capacity(scalars.len());
        for &code in scalars {
            text.push(char::from_u32(code).ok_or("invalid Unicode scalar")?);
        }
        Ok(text)
    })
}

/// The staged text to a port, all at once.
#[unsafe(export_name = "snail:io/write-string")]
pub extern "C" fn write_string(id: u32, count: u32) {
    let result = staged_text(count).and_then(|text| {
        if id == STANDARD_OUTPUT {
            Port::Stdout.write(&text)
        } else {
            FILES.with_borrow_mut(|files| files.get(id)?.write(&text))
        }
    });
    checked(result);
}

/// The console effect's default: one scalar to buffered standard output.
#[unsafe(export_name = "snail:io/console-write")]
pub extern "C" fn console_write(code: u32) {
    checked(write_character(&mut Port::Stdout, code));
}

/// The console effect's default: the next scalar of standard input, or -1.
#[unsafe(export_name = "snail:io/console-read")]
pub extern "C" fn console_read() -> i32 {
    read_code(STANDARD_INPUT)
}

// ---- Command-line arguments ----

// The arguments never change during an invocation, so Lofi reads them as
// total functions: a count, then each argument one scalar at a time.
fn argument(index: i32) -> Result<String, String> {
    usize::try_from(index)
        .ok()
        .and_then(|index| std::env::args().nth(index))
        .ok_or_else(|| format!("no command-line argument {index}"))
}

#[unsafe(export_name = "snail:process/argument-count")]
pub extern "C" fn argument_count() -> i32 {
    i32::try_from(std::env::args().count()).unwrap_or(i32::MAX)
}

#[unsafe(export_name = "snail:process/argument-length")]
pub extern "C" fn argument_length(index: i32) -> i32 {
    let result =
        argument(index).map(|text| i32::try_from(text.chars().count()).unwrap_or(i32::MAX));
    checked(result)
}

#[unsafe(export_name = "snail:process/argument-character")]
pub extern "C" fn argument_character(index: i32, position: i32) -> u32 {
    let result = argument(index).and_then(|text| {
        usize::try_from(position)
            .ok()
            .and_then(|position| text.chars().nth(position))
            .map(u32::from)
            .ok_or_else(|| format!("no character {position} in argument {index}"))
    });
    checked(result)
}

// ---- Explicit resource release ----

fn release_file(mut port: Port) -> Result<(), String> {
    let result = port.close();
    // Port.close retains its payload if flushing fails. Drop it before any
    // nonreturning diagnostic: a Wasm trap does not run Rust destructors.
    drop(port);
    result
}

#[unsafe(export_name = "snail:io/close")]
pub extern "C" fn close(id: u32) {
    // Closing a borrowed stream is deliberately a no-op, including raw calls.
    // It never detaches an owned resource or closes the process descriptor.
    if matches!(id, STANDARD_OUTPUT | STANDARD_INPUT) {
        return;
    }
    let result = FILES.with_borrow_mut(|files| files.take(id));
    checked(result.and_then(release_file));
}

fn release_all() -> Result<(), String> {
    let flushed = flush_standard_output();
    crate::datum::close_all();
    PATHNAME.with_borrow_mut(Option::take);
    let ports = FILES.with_borrow_mut(|files| std::mem::take(&mut files.live));
    let mut result = flushed;
    for port in ports.into_values() {
        let closed = release_file(port);
        if result.is_ok() {
            result = closed;
        }
    }
    result
}

fn checked<T>(result: Result<T, String>) -> T {
    result.unwrap_or_else(|error| {
        // Every caller ended its RefCell borrow and disposed of removed files.
        // Keep the original failure even if another file also fails to close.
        let _ = release_all();
        fail_message(&error)
    })
}

// The host uses this nontrapping cleanup after arbitrary guest traps. It must
// preserve an earlier failure, and must not resume guest code in that instance.
// Returned close errors do not prevent later closes; a trapping host import can.
// A failed cleanup, such as buffered output that cannot be written, is
// reported on stderr as well as through the nonzero result.
#[unsafe(export_name = "snail:io/close-all")]
pub extern "C" fn close_all() -> i32 {
    match release_all() {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("lofi: {error}");
            1
        }
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn standard_input_is_borrowed_and_survives_close() {
        let next = FILES.with_borrow(|files| files.next);
        INPUT.with_borrow_mut(|port| *port = Port::input_string("λ😀".into()));
        close(STANDARD_INPUT);
        assert_eq!(read_code(STANDARD_INPUT), 'λ' as i32);
        assert_eq!(close_all(), 0);
        assert_eq!(read_code(STANDARD_INPUT), '😀' as i32);
        assert_eq!(read_code(STANDARD_INPUT), -1);
        assert_eq!(FILES.with_borrow(|files| files.next), next);
    }

    #[test]
    fn standard_output_is_borrowed_and_never_consumes_a_file_id() {
        let next = FILES.with_borrow(|files| files.next);
        close(STANDARD_OUTPUT);
        close(STANDARD_OUTPUT);
        assert_eq!(close_all(), 0);
        assert_eq!(FILES.with_borrow(|files| files.next), next);
        assert!(FILES.with_borrow_mut(|files| files.get(STANDARD_OUTPUT).is_err()));
    }

    #[test]
    fn unicode_characters_are_encoded_without_replacement() {
        let mut path = String::new();
        let mut port = Port::output_string();
        for code in [0, 0x03bb, 0x1f600, 0x10ffff] {
            append_character(&mut path, code).unwrap();
            write_character(&mut port, code).unwrap();
        }
        assert_eq!(path, "\0λ😀\u{10ffff}");
        assert_eq!(port.captured_output().unwrap(), path);
        for code in [0xd800, 0xdfff, 0x110000, u32::MAX] {
            assert!(append_character(&mut path, code).is_err());
            assert!(write_character(&mut port, code).is_err());
        }
        assert_eq!(port.captured_output().unwrap(), path);
    }

    #[test]
    fn scalar_input_distinguishes_unicode_from_eof() {
        let id = FILES.with_borrow_mut(|files| {
            let id = files.reserve_id().unwrap();
            files
                .live
                .insert(id as u32, Port::input_string("\0λ😀\u{10ffff}".into()));
            id as u32
        });
        for code in [0, 0x03bb, 0x1f600, 0x10ffff, -1, -1] {
            assert_eq!(read_code(id), code);
        }
        close(id);
        assert!(FILES.with_borrow_mut(|files| files.get(id).is_err()));
    }

    #[test]
    fn absent_and_stale_ids_never_alias_new_resources() {
        let mut files = Files::default();
        let first = files.reserve_id().unwrap() as u32;
        files.live.insert(first, Port::output_string());
        release_file(files.take(first).unwrap()).unwrap();
        assert!(files.get(first).is_err());
        assert!(files.take(first).is_err());
        let second = files.reserve_id().unwrap() as u32;
        files.live.insert(second, Port::output_string());
        assert_ne!(first, second);
        assert!(files.get(first).is_err());
        assert!(files.get(u32::MAX).is_err());
        assert!(files.get(second).is_ok());
    }

    #[test]
    fn id_exhaustion_does_not_wrap() {
        let mut files = Files {
            next: i32::MAX as u32,
            ..Files::default()
        };
        assert_eq!(files.reserve_id().unwrap(), i32::MAX);
        assert!(files.reserve_id().is_err());
        assert!(files.reserve_id().is_err());
        assert_eq!(files.next, i32::MAX as u32 + 1);
    }

    #[test]
    fn consuming_and_cleanup_remove_temporary_paths_and_live_ports() {
        path_begin();
        path_character(0x03bb);
        assert_eq!(take_pathname().unwrap(), "λ");
        assert!(take_pathname().is_err());
        path_begin();
        FILES.with_borrow_mut(|files| {
            let id = files.reserve_id().unwrap();
            files.live.insert(id as u32, Port::output_string());
        });
        assert_eq!(close_all(), 0);
        assert!(take_pathname().is_err());
        assert!(FILES.with_borrow(|files| files.live.is_empty()));
    }
}
