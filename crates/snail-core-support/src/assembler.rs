//! WebAssembly text to a binary module, for tools written in Snail-Core: the
//! toolchain's runtime only, behind the `assembler` feature.
//!
//! The text arrives staged, as any final String does. The module, or the
//! parser's message, stays here until the next assembly, and Snail-Core
//! reads it a byte at a time, so no guest value is held across calls.

use std::cell::RefCell;

use crate::io::{checked, staged_text};

// ---- Assembling ----

/// The binary module the text describes, or the parser's message, which
/// names the line and column of the problem.
fn assemble(text: &str) -> Result<Vec<u8>, String> {
    wat::parse_str(text).map_err(|error| error.to_string())
}

// The last result: the module on success, the message as UTF-8 on failure.
// A Wasm instance runs one call at a time.
thread_local! {
    static OUTPUT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

/// Assembles the staged text. Returns 0 when the output holds the module,
/// and 1 when it holds the message.
#[unsafe(export_name = "snail:assembler/assemble")]
pub extern "C" fn assemble_staged(count: u32) -> i32 {
    let (status, output) = match assemble(&checked(staged_text(count))) {
        Ok(module) => (0, module),
        Err(message) => (1, message.into_bytes()),
    };
    OUTPUT.with_borrow_mut(|buffer| *buffer = output);
    status
}

#[unsafe(export_name = "snail:assembler/output-length")]
pub extern "C" fn output_length() -> i32 {
    OUTPUT.with_borrow(|buffer| {
        checked(i32::try_from(buffer.len()).map_err(|_| "a module of 2 GiB or more".to_string()))
    })
}

#[unsafe(export_name = "snail:assembler/output-byte")]
pub extern "C" fn output_byte(index: i32) -> i32 {
    OUTPUT.with_borrow(|buffer| {
        let byte = usize::try_from(index)
            .ok()
            .and_then(|index| buffer.get(index).copied());
        i32::from(checked(
            byte.ok_or_else(|| format!("no output byte at {index}")),
        ))
    })
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    // The constructs the compiler relies on: a recursion group of GC types,
    // a subtype, a cast and a tail call through a function reference.
    const PROGRAM: &str = r#"(module
  (rec
    (type $fn (func (param (ref $closure)) (param i64) (result i64)))
    (type $closure (sub (struct (field (ref $fn))))))
  (type $box (sub final $closure (struct (field (ref $fn)) (field i64))))
  (elem declare func $add)
  (func $add (type $fn) (param $self (ref $closure)) (param $x i64) (result i64)
    (i64.add (local.get $x) (struct.get $box 1 (ref.cast (ref $box) (local.get $self)))))
  (func (export "main") (result i64)
    (local $c (ref $closure))
    (local.set $c (struct.new $box (ref.func $add) (i64.const 1)))
    (return_call_ref $fn (local.get $c) (i64.const 41) (struct.get $closure 0 (local.get $c)))))"#;

    #[test]
    fn assembles_gc_types_casts_and_tail_calls() {
        let module = assemble(PROGRAM).expect("the program assembles");
        assert_eq!(&module[0..4], b"\0asm");
    }

    #[test]
    fn reports_where_the_text_is_wrong() {
        let message = assemble("(module\n  (func (result i32) (i32.bogus)))")
            .expect_err("an unknown instruction");
        assert!(
            message.contains(":2:"),
            "the message names line 2: {message}"
        );
    }
}
