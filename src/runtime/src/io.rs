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

fn take_pathname() -> Result<String, String> {
    PATHNAME
        .with_borrow_mut(Option::take)
        .ok_or_else(|| "no pathname transfer is active".into())
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

#[unsafe(export_name = "snail:io/delete-file")]
pub extern "C" fn delete_file() {
    let result = take_pathname()
        .and_then(|path| std::fs::remove_file(&path).map_err(|error| format!("{path}: {error}")));
    checked(result);
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

#[unsafe(export_name = "snail:io/standard-output")]
pub extern "C" fn standard_output() -> i32 {
    STANDARD_OUTPUT as i32
}

#[unsafe(export_name = "snail:io/standard-input")]
pub extern "C" fn standard_input() -> i32 {
    STANDARD_INPUT as i32
}

fn check_output(id: u32) -> Result<(), String> {
    if id == STANDARD_OUTPUT {
        return Ok(());
    }
    FILES.with_borrow_mut(|files| {
        let port = files.get(id)?;
        if port.is_output() && port.is_open() {
            Ok(())
        } else {
            Err("expected an open output port".into())
        }
    })
}

#[unsafe(export_name = "snail:io/check-output")]
pub extern "C" fn check_output_port(id: u32) {
    checked(check_output(id));
}

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

// Only owned files use packets. Their private Lofi wrapper owns the pending
// characters; borrowed stdin keeps its shared host scalar cursor instead.
#[unsafe(export_name = "snail:io/read-packet")]
pub extern "C" fn read_packet(id: u32) -> i64 {
    let result = FILES.with_borrow_mut(|files| files.get(id)?.text_input()?.read_packet());
    checked(result)
}

#[unsafe(export_name = "snail:io/peek-character")]
pub extern "C" fn peek_code(id: u32) -> i32 {
    let result = if id == STANDARD_INPUT {
        flush_standard_output()
            .and_then(|()| INPUT.with_borrow_mut(|port| port.text_input()?.peek_char()))
    } else {
        FILES.with_borrow_mut(|files| files.get(id)?.text_input()?.peek_char())
    };
    checked(result).map_or(-1, |character| character as i32)
}

fn write_character(port: &mut Port, code: u32) -> Result<(), String> {
    let character = char::from_u32(code).ok_or("invalid Unicode scalar")?;
    let mut bytes = [0; 4];
    port.write(character.encode_utf8(&mut bytes))
}

#[unsafe(export_name = "snail:io/write-character")]
pub extern "C" fn write_code(id: u32, code: u32) {
    let result = if id == STANDARD_OUTPUT {
        write_character(&mut Port::Stdout, code)
    } else {
        FILES.with_borrow_mut(|files| write_character(files.get(id)?, code))
    };
    checked(result);
}

#[unsafe(export_name = "snail:io/flush")]
pub extern "C" fn flush(id: u32) {
    let result = if id == STANDARD_OUTPUT {
        flush_standard_output()
    } else {
        FILES.with_borrow_mut(|files| files.get(id)?.flush())
    };
    checked(result);
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
    fn standard_input_is_borrowed_and_preserves_lookahead_on_close() {
        let next = FILES.with_borrow(|files| files.next);
        assert_eq!(standard_input(), -3);
        INPUT.with_borrow_mut(|port| *port = Port::input_string("λ😀".into()));
        assert_eq!(peek_code(STANDARD_INPUT), 'λ' as i32);
        close(STANDARD_INPUT);
        assert_eq!(read_code(STANDARD_INPUT), 'λ' as i32);
        assert_eq!(peek_code(STANDARD_INPUT), '😀' as i32);
        assert_eq!(close_all(), 0);
        assert_eq!(read_code(STANDARD_INPUT), '😀' as i32);
        assert_eq!(read_code(STANDARD_INPUT), -1);
        assert_eq!(FILES.with_borrow(|files| files.next), next);
    }

    #[test]
    fn standard_output_is_borrowed_and_never_consumes_a_file_id() {
        assert_eq!(standard_output(), -2);
        let next = FILES.with_borrow(|files| files.next);
        assert!(check_output(STANDARD_OUTPUT).is_ok());
        close(STANDARD_OUTPUT);
        close(STANDARD_OUTPUT);
        assert!(check_output(STANDARD_OUTPUT).is_ok());
        assert_eq!(close_all(), 0);
        assert!(check_output(STANDARD_OUTPUT).is_ok());
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
    fn scalar_input_preserves_lookahead_and_distinguishes_unicode_from_eof() {
        let id = FILES.with_borrow_mut(|files| {
            let id = files.reserve_id().unwrap();
            files
                .live
                .insert(id as u32, Port::input_string("\0λ😀\u{10ffff}".into()));
            id as u32
        });
        for code in [0, 0x03bb, 0x1f600, 0x10ffff, -1, -1] {
            assert_eq!(peek_code(id), code);
            assert_eq!(peek_code(id), code);
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
