//! The files a program links, `link-bytes` in (snail shell resource), as
//! host/browser/load.mjs gives them on Node and in the page.
//!
//! A module asks for each file it links by importing a function from
//! "snail.runtime.link" named for the file, which answers the file's handle, and
//! reads the file by handle through "snail.runtime.resource". Every file the
//! program's modules name is read from `resources/NAME` beside the payload
//! before any module is instantiated, so reading one is a lookup, and a
//! payload whose file cannot be read fails to load rather than when the
//! program first reads it.

use std::path::Path;

use wasmtime::{Caller, Linker, Module, format_err};

use crate::program::Host;

// ---- Reading ----

/// The bytes of each file a program links, indexed by handle: a handle is
/// the file's position among the names its modules link.
#[derive(Default)]
pub struct Files(Vec<Vec<u8>>);

impl Files {
    /// Reads each named file from `resources/` in `directory`, the
    /// payload's, in the order of `names`.
    pub fn read(directory: &Path, names: &[String]) -> wasmtime::Result<Files> {
        let resources = directory.join("resources");
        let read = |name: &String| {
            std::fs::read(resources.join(name))
                .map_err(|error| format_err!("cannot read the linked file {name}: {error}"))
        };
        Ok(Files(
            names.iter().map(read).collect::<wasmtime::Result<_>>()?,
        ))
    }

    fn get(&self, handle: i32) -> wasmtime::Result<&[u8]> {
        let file = usize::try_from(handle)
            .ok()
            .and_then(|index| self.0.get(index));
        file.map(Vec::as_slice)
            .ok_or_else(|| format_err!("no linked file {handle}"))
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

/// Defines "snail.runtime.link" NAME for each of `names`, answering its handle,
/// and the `resource` effect, a file's length and its bytes by handle,
/// over the files the store holds.
pub fn define(linker: &mut Linker<Host>, names: &[String]) -> wasmtime::Result<()> {
    for (handle, name) in (0..).zip(names) {
        linker.func_wrap("snail.runtime.link", name, move || -> i32 { handle })?;
    }
    linker.func_wrap(
        "snail.runtime.resource",
        "length",
        |caller: Caller<'_, Host>, handle: i32| {
            Ok(i32::try_from(caller.data().files.get(handle)?.len())?)
        },
    )?;
    linker.func_wrap("snail.runtime.resource", "byte", byte)?;
    Ok(())
}

fn byte(caller: Caller<'_, Host>, handle: i32, index: i32) -> wasmtime::Result<i32> {
    let file = caller.data().files.get(handle)?;
    let byte = usize::try_from(index)
        .ok()
        .and_then(|index| file.get(index));
    byte.map(|byte| i32::from(*byte))
        .ok_or_else(|| format_err!("no byte {index} in linked file {handle}"))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::tests::module_file;
    use crate::program;

    // A program that links two files, one of them twice, and answers the
    // first's length plus the second's last byte.
    const LINKING: &str = r#"(module
        (import "snail.runtime.link" "main/data/greeting.txt" (func $greeting (result i32)))
        (import "snail.runtime.link" "lib/data/pixel.png" (func $pixel (result i32)))
        (import "snail.runtime.link" "main/data/greeting.txt" (func $again (result i32)))
        (import "snail.runtime.resource" "length" (func $length (param i32) (result i32)))
        (import "snail.runtime.resource" "byte" (func $byte (param i32 i32) (result i32)))
        (memory (export "memory") 1)
        (func (export "_initialize"))
        (func (export "main") (result i32)
          (i32.add (call $length (call $greeting))
                   (call $byte (call $pixel) (i32.sub (call $length (call $pixel)) (i32.const 1)))))
        (func (export "close-resources") (result i32) (i32.const 0)))"#;

    // A directory of its own holding the program and the files it links.
    fn payload(name: &str) -> (std::path::PathBuf, String) {
        let program = module_file(name, LINKING);
        let directory = Path::new(&program).with_extension("payload");
        std::fs::create_dir_all(directory.join("resources/main/data")).unwrap();
        std::fs::create_dir_all(directory.join("resources/lib/data")).unwrap();
        let moved = directory.join("program.wasm");
        std::fs::rename(&program, &moved).unwrap();
        (directory, moved.to_string_lossy().into_owned())
    }

    #[test]
    fn each_name_is_linked_once_in_the_order_first_named() {
        let engine = crate::engine::engine().unwrap();
        let module = Module::new(&engine, wat::parse_str(LINKING).unwrap()).unwrap();
        assert_eq!(
            linked_names([&module]),
            ["main/data/greeting.txt", "lib/data/pixel.png"]
        );
    }

    #[test]
    fn linked_files_are_read_from_resources_beside_the_program() {
        let (directory, program) = payload("linking");
        std::fs::write(directory.join("resources/main/data/greeting.txt"), "hello").unwrap();
        std::fs::write(directory.join("resources/lib/data/pixel.png"), [1, 2, 30]).unwrap();
        assert_eq!(program::run(&program, &[]), 35);
        std::fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn a_file_that_cannot_be_read_fails_the_load_naming_it() {
        let (directory, _) = payload("unreadable");
        std::fs::write(directory.join("resources/main/data/greeting.txt"), "hello").unwrap();
        let names = [
            "main/data/greeting.txt".to_string(),
            "lib/data/pixel.png".to_string(),
        ];
        let error = Files::read(&directory, &names).err().unwrap();
        assert!(
            error
                .to_string()
                .starts_with("cannot read the linked file lib/data/pixel.png: ")
        );
        std::fs::remove_dir_all(directory).unwrap();
    }
}
