//! Files kept in the runtime's memory, for a host without a file system, such
//! as a browser. The host turns memory files on before a program runs, puts
//! in each file the program reads, and takes out the files it wrote. Programs
//! open, read, write and test files exactly as they do on disk.
//!
//! The host and the runtime exchange paths and contents through one buffer in
//! linear memory: the host asks for room, writes into it, and calls `put`; or
//! writes a path, calls `get`, asks for the buffer again and reads the file.

use std::{cell::RefCell, collections::BTreeMap};

thread_local! {
    static MEMORY: RefCell<Option<BTreeMap<String, Vec<u8>>>> = const { RefCell::new(None) };
    static BUFFER: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

// ---- Files ----

pub(crate) fn enabled() -> bool {
    MEMORY.with_borrow(Option::is_some)
}

pub(crate) fn read(path: &str) -> Option<Vec<u8>> {
    MEMORY.with_borrow(|memory| memory.as_ref()?.get(path).cloned())
}

pub(crate) fn write(path: &str, bytes: Vec<u8>) {
    MEMORY.with_borrow_mut(|memory| {
        if let Some(files) = memory {
            files.insert(path.into(), bytes);
        }
    });
}

pub(crate) fn exists(path: &str) -> bool {
    MEMORY.with_borrow(|memory| {
        memory
            .as_ref()
            .is_some_and(|files| files.contains_key(path))
    })
}

// ---- Host transfer ----

#[unsafe(export_name = "snail:files/use-memory")]
pub extern "C" fn use_memory() {
    MEMORY.with_borrow_mut(|memory| *memory = Some(BTreeMap::new()));
}

/// Room for at least `length` bytes; the address changes only when it grows.
#[unsafe(export_name = "snail:files/buffer")]
pub extern "C" fn buffer(length: u32) -> u32 {
    BUFFER.with_borrow_mut(|buffer| {
        if buffer.len() < length as usize {
            buffer.resize(length as usize, 0);
        }
        buffer.as_mut_ptr() as u32
    })
}

/// Stores the file whose path is the buffer's first `path_length` bytes and
/// whose contents are the `data_length` bytes after them.
#[unsafe(export_name = "snail:files/put")]
pub extern "C" fn put(path_length: u32, data_length: u32) {
    let (path, data) = BUFFER.with_borrow(|buffer| {
        let (path, rest) = buffer.split_at(path_length as usize);
        (
            String::from_utf8_lossy(path).into_owned(),
            rest[..data_length as usize].to_vec(),
        )
    });
    write(&path, data);
}

/// Copies the file whose path is the buffer's first `path_length` bytes into
/// the buffer, returning its length, or -1 if there is no such file.
#[unsafe(export_name = "snail:files/get")]
pub extern "C" fn get(path_length: u32) -> i32 {
    let path = BUFFER.with_borrow(|buffer| {
        String::from_utf8_lossy(&buffer[..path_length as usize]).into_owned()
    });
    match read(&path) {
        Some(bytes) => {
            BUFFER.with_borrow_mut(|buffer| {
                buffer.clear();
                buffer.extend_from_slice(&bytes);
            });
            bytes.len() as i32
        }
        None => -1,
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::Port;

    // The buffer's address is a wasm32 one, so a native test fills the
    // buffer itself, as a host writes into it.
    fn put_file(path: &str, data: &str) {
        BUFFER.with_borrow_mut(|buffer| {
            buffer.clear();
            buffer.extend_from_slice(path.as_bytes());
            buffer.extend_from_slice(data.as_bytes());
        });
        put(path.len() as u32, data.len() as u32);
    }

    #[test]
    fn a_program_reads_what_the_host_put_and_the_host_gets_what_it_wrote() {
        use_memory();
        put_file("/lib/a.sld", "λ text");
        let mut input = Port::input_file("/lib/a.sld").expect("the file was put");
        assert_eq!(input.read_char(), Ok(Some('λ')));
        assert!(exists("/lib/a.sld") && !exists("/lib/b.sld"));
        let mut output = Port::output_file("/build/out.wat").expect("memory files accept any path");
        output.write("(module)").unwrap();
        output.close().unwrap();
        assert_eq!(read("/build/out.wat").as_deref(), Some(&b"(module)"[..]));
        assert!(Port::input_file("/missing").is_err());
    }
}
