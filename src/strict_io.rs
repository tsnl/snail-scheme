//! Scalar text-file services for the strict Scheme library.
//!
//! Rust owns files, never Scheme values. IDs are issued once and never reused.
//! Scheme closes explicitly; the invocation host calls close-all after a trap.
//! A trapped instance is terminal. There is no GC finalization of these files.

use crate::{fail_message, host::Port};
use std::{cell::RefCell, collections::BTreeMap, path::Path};

// ---- Owned resources and synchronous pathname transfer ----

#[derive(Default)]
struct OutputFiles {
    next: u32,
    live: BTreeMap<u32, Port>,
}

thread_local! {
    static FILES: RefCell<OutputFiles> = RefCell::new(OutputFiles::default());
    static PATHNAME: RefCell<Option<String>> = const { RefCell::new(None) };
}

impl OutputFiles {
    fn reserve_id(&mut self) -> Result<i32, String> {
        let id = i32::try_from(self.next).map_err(|_| "output port IDs exhausted")?;
        self.next += 1;
        Ok(id)
    }

    fn get(&mut self, id: u32) -> Result<&mut Port, String> {
        self.live
            .get_mut(&id)
            .ok_or_else(|| "unknown or closed output port".into())
    }

    fn take(&mut self, id: u32) -> Result<Port, String> {
        self.live
            .remove(&id)
            .ok_or_else(|| "unknown or closed output port".into())
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
// never call Scheme, and the Scheme loop performs no user callbacks. Reentry or
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

fn open_file(path: String) -> Result<i32, String> {
    // Exhaustion is checked before creating or truncating a file. Failed opens
    // consume an ID too; no old integer can ever acquire a different resource.
    let id = FILES.with_borrow_mut(OutputFiles::reserve_id)?;
    let port = Port::output_file(&path)?;
    FILES.with_borrow_mut(|files| files.live.insert(id as u32, port));
    Ok(id)
}

#[unsafe(export_name = "snail:io/open-output-file")]
pub extern "C" fn open_output_file() -> i32 {
    checked(take_pathname().and_then(open_file))
}

// ---- Character writes and explicit resource release ----

fn write_character(port: &mut Port, code: u32) -> Result<(), String> {
    let character = char::from_u32(code).ok_or("invalid Unicode scalar")?;
    let mut bytes = [0; 4];
    port.write(character.encode_utf8(&mut bytes))
}

#[unsafe(export_name = "snail:io/write-character")]
pub extern "C" fn write_code(id: u32, code: u32) {
    let result = FILES.with_borrow_mut(|files| write_character(files.get(id)?, code));
    checked(result);
}

fn release_file(mut port: Port) -> Result<(), String> {
    let result = port.close();
    // Port.close retains its payload if flushing fails. Drop it before any
    // nonreturning diagnostic: a Wasm trap does not run Rust destructors.
    drop(port);
    #[cfg(all(feature = "native-runtime", not(target_arch = "wasm32"), not(test)))]
    crate::native::resource_released();
    result
}

#[unsafe(export_name = "snail:io/close")]
pub extern "C" fn close(id: u32) {
    let result = FILES.with_borrow_mut(|files| files.take(id));
    checked(result.and_then(release_file));
}

fn release_all() -> Result<(), String> {
    PATHNAME.with_borrow_mut(Option::take);
    let ports = FILES.with_borrow_mut(|files| std::mem::take(&mut files.live));
    let mut result = Ok(());
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

// The host uses this nontrapping cleanup after arbitrary Scheme traps. It must
// preserve an earlier failure, and must not resume Scheme in that instance.
// Returned close errors do not prevent later closes; a trapping host import can.
#[unsafe(export_name = "snail:io/close-all")]
pub extern "C" fn close_all() -> i32 {
    i32::from(release_all().is_err())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

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
    fn absent_and_stale_ids_never_alias_new_resources() {
        let mut files = OutputFiles::default();
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
        let mut files = OutputFiles {
            next: i32::MAX as u32,
            ..OutputFiles::default()
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
