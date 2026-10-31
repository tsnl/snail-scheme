//! The files a program links, `link-file` in (snail shell resource), as
//! host/browser/load.mjs gives them on Node and in the page.
//!
//! A module asks for each file it links by importing a function from
//! "snail.runtime.link" named for the SHA-256 of the file's bytes, in hex,
//! which answers the file's handle. A handle is only that name: a task
//! reads the file through
//! "snail.runtime.resource", starting the read under a ticket of (snail
//! shell task), and then finishing the ticket for the file's length and
//! reading the bytes held until the next finish. This host reads the file
//! from `resources/DIGEST` beside the payload when the read starts, the
//! first time it is asked for, and wakes the ticket between turns
//! (program.rs's `drive`), since a ticket may not wake before its task
//! waits on it. A file that cannot be read traps the task that finishes it.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use wasmtime::{Caller, Linker, Module, format_err};

use crate::program::Host;

// ---- Reading ----

/// The files a program links, by handle, a file's position among the names
/// its modules link; what each read answers, by ticket; and the bytes the
/// last finish holds.
#[derive(Default)]
pub struct Files {
    resources: PathBuf,
    names: Vec<String>,
    read: Vec<Option<Vec<u8>>>,
    answers: HashMap<i64, Result<usize, String>>,
    waking: Vec<i64>,
    held: usize,
}

impl Files {
    /// The files `names` link, read from `resources/` in `directory`, the
    /// payload's, as tasks ask for them.
    pub fn new(directory: &Path, names: &[String]) -> Files {
        Files {
            resources: directory.join("resources"),
            names: names.to_vec(),
            read: vec![None; names.len()],
            ..Files::default()
        }
    }

    /// Reads the file `handle` names, unless it has been, and answers
    /// `ticket` with it once the ticket is woken.
    fn start(&mut self, ticket: i64, handle: i32) -> wasmtime::Result<()> {
        let index = usize::try_from(handle)
            .ok()
            .filter(|index| *index < self.names.len())
            .ok_or_else(|| format_err!("no linked file {handle}"))?;
        let answer = match &self.read[index] {
            Some(_) => Ok(index),
            None => {
                let name = &self.names[index];
                std::fs::read(self.resources.join(name))
                    .map(|bytes| {
                        self.read[index] = Some(bytes);
                        index
                    })
                    .map_err(|error| format!("cannot read the linked file {name}: {error}"))
            }
        };
        self.answers.insert(ticket, answer);
        self.waking.push(ticket);
        Ok(())
    }

    /// The length of the file `ticket` read, whose bytes are held from now
    /// until the next finish.
    fn finish(&mut self, ticket: i64) -> wasmtime::Result<i32> {
        let answer = self
            .answers
            .remove(&ticket)
            .ok_or_else(|| format_err!("a ticket was finished before its read completed"))?;
        self.held = answer.map_err(|message| format_err!("{message}"))?;
        Ok(i32::try_from(self.bytes().len())?)
    }

    fn byte(&self, index: i32) -> wasmtime::Result<i32> {
        let byte = usize::try_from(index)
            .ok()
            .and_then(|index| self.bytes().get(index));
        byte.map(|byte| i32::from(*byte))
            .ok_or_else(|| format_err!("no byte {index} in linked file {}", self.held))
    }

    fn bytes(&self) -> &[u8] {
        self.read
            .get(self.held)
            .and_then(Option::as_deref)
            .unwrap_or(&[])
    }

    /// The tickets of the reads started since the last call, to wake.
    pub fn take_waking(&mut self) -> Vec<i64> {
        std::mem::take(&mut self.waking)
    }
}

/// Each file `modules` link, by name, in the order they first name it.
pub fn linked_names<'a>(modules: impl IntoIterator<Item = &'a Module>) -> Vec<String> {
    let mut names: Vec<String> = Vec::new();
    for module in modules {
        for import in module
            .imports()
            .filter(|import| import.module() == "snail.runtime.link")
        {
            if !names.iter().any(|name| name == import.name()) {
                names.push(import.name().to_string());
            }
        }
    }
    names
}

// ---- Imports ----

/// Defines "snail.runtime.link" NAME for each of `names`, answering its
/// handle, and the `resource` effect's reads over the files the store
/// holds.
pub fn define(linker: &mut Linker<Host>, names: &[String]) -> wasmtime::Result<()> {
    for (handle, name) in (0..).zip(names) {
        linker.func_wrap("snail.runtime.link", name, move || -> i32 { handle })?;
    }
    linker.func_wrap(
        "snail.runtime.resource",
        "read",
        |mut caller: Caller<'_, Host>, ticket: i64, handle: i32| {
            caller.data_mut().files.start(ticket, handle)
        },
    )?;
    linker.func_wrap(
        "snail.runtime.resource",
        "finish",
        |mut caller: Caller<'_, Host>, ticket: i64| caller.data_mut().files.finish(ticket),
    )?;
    linker.func_wrap(
        "snail.runtime.resource",
        "byte",
        |caller: Caller<'_, Host>, index: i32| caller.data().files.byte(index),
    )?;
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    // The digests of b"hello" and of [1, 2, 30], the bytes the payloads
    // below hold under them.
    const GREETING: &str = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824";
    const PIXEL: &str = "32e3ea041d71f3b22a7424935466262cf12aa55c103be694c4eec92a9e607918";

    // A module that links two files, one of them twice.
    const LINKING: &str = r#"(module
        (import "snail.runtime.link" "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" (func $greeting (result i32)))
        (import "snail.runtime.link" "32e3ea041d71f3b22a7424935466262cf12aa55c103be694c4eec92a9e607918" (func $pixel (result i32)))
        (import "snail.runtime.link" "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" (func $again (result i32))))"#;

    // A payload directory of its own holding the files `files` names.
    fn payload(name: &str, files: &[(&str, &[u8])]) -> PathBuf {
        let directory =
            std::env::temp_dir().join(format!("snail-test-{}-{name}", std::process::id()));
        for (file, bytes) in files {
            let path = directory.join("resources").join(file);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, bytes).unwrap();
        }
        directory
    }

    fn names() -> Vec<String> {
        vec![GREETING.to_string(), PIXEL.to_string()]
    }

    #[test]
    fn each_name_is_linked_once_in_the_order_first_named() {
        let engine = crate::engine::engine().unwrap();
        let module = Module::new(&engine, wat::parse_str(LINKING).unwrap()).unwrap();
        assert_eq!(linked_names([&module]), names());
    }

    #[test]
    fn a_read_answers_its_ticket_once_woken_and_holds_the_bytes() {
        let directory = payload("reading", &[(GREETING, b"hello"), (PIXEL, &[1, 2, 30])]);
        let mut files = Files::new(&directory, &names());
        files.start(7, 1).unwrap();
        files.start(8, 0).unwrap();
        assert_eq!(files.take_waking(), [7, 8]);
        assert_eq!(files.finish(8).unwrap(), 5);
        assert_eq!(files.finish(7).unwrap(), 3);
        assert_eq!(files.byte(2).unwrap(), 30);
        assert!(files.byte(3).is_err());
        assert!(files.finish(7).is_err());
        std::fs::remove_dir_all(directory).unwrap();
    }

    // A build never rewrites a file under its digest; this one does, to
    // see when the host reads it.
    #[test]
    fn a_file_is_read_when_first_asked_for_and_kept() {
        let directory = payload("lazy", &[(GREETING, b"hello")]);
        let file = directory.join("resources").join(GREETING);
        let mut files = Files::new(&directory, &names());
        std::fs::write(&file, "later").unwrap();
        files.start(1, 0).unwrap();
        std::fs::write(&file, "changed").unwrap();
        files.start(2, 0).unwrap();
        files.finish(1).unwrap();
        assert_eq!(files.byte(0).unwrap(), i32::from(b'l'));
        assert_eq!(files.finish(2).unwrap(), 5);
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn a_file_that_cannot_be_read_fails_the_finish_naming_it() {
        let directory = payload("unreadable", &[(GREETING, b"hello")]);
        let mut files = Files::new(&directory, &names());
        files.start(3, 1).unwrap();
        let error = files.finish(3).err().unwrap();
        assert!(
            error
                .to_string()
                .starts_with(&format!("cannot read the linked file {PIXEL}: "))
        );
        assert!(files.start(4, 2).is_err());
        std::fs::remove_dir_all(directory).unwrap();
    }
}
