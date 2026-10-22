//! WebAssembly text to a binary module, in-process: the assembler a toolchain
//! running as Wasm uses instead of Binaryen's `wasm-as`, under Node's WASI or
//! in a browser.
//!
//! The parsing and encoding are the `wat` crate's. This crate adds the
//! smallest interface a host can drive through linear memory: write the text
//! into an input buffer, assemble it, and read the module, or the error
//! message, from an output buffer.

// Ordinary cargo tests exercise `assemble` without a Wasm engine.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

use std::cell::RefCell;

// ---- Module initialization ----

// A reactor initializer, as in the runtime, so wasm-ld does not wrap each
// export in constructor calls. The host calls it once, before any export.
#[cfg(target_arch = "wasm32")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn _initialize() {
    unsafe extern "C" {
        fn __wasm_call_ctors();
    }
    unsafe { __wasm_call_ctors() };
}

// ---- Assembling ----

/// The binary module the text describes, or the parser's message, which
/// names the line and column of the problem.
pub fn assemble(text: &str) -> Result<Vec<u8>, String> {
    wat::parse_str(text).map_err(|error| error.to_string())
}

// ---- Buffers ----

// The text the host wrote, and the last result: the module on success, the
// message on failure. A Wasm instance runs one call at a time.
struct Buffers {
    input: Vec<u8>,
    output: Vec<u8>,
}

thread_local! {
    static BUFFERS: RefCell<Buffers> = const { RefCell::new(Buffers { input: Vec::new(), output: Vec::new() }) };
}

/// Makes room for `length` bytes of text and returns where the host writes
/// them. The address is valid until the next call.
#[unsafe(export_name = "snail:assembler/input")]
pub extern "C" fn input(length: usize) -> *mut u8 {
    BUFFERS.with_borrow_mut(|buffers| {
        buffers.input.clear();
        buffers.input.resize(length, 0);
        buffers.input.as_mut_ptr()
    })
}

/// Assembles the input. Returns 0 when the output holds the module, and 1
/// when it holds a message, because the input was not UTF-8 or not valid
/// text.
#[unsafe(export_name = "snail:assembler/assemble")]
pub extern "C" fn assemble_input() -> i32 {
    BUFFERS.with_borrow_mut(|buffers| {
        let result = std::str::from_utf8(&buffers.input)
            .map_err(|error| error.to_string())
            .and_then(assemble);
        let (status, output) = match result {
            Ok(module) => (0, module),
            Err(message) => (1, message.into_bytes()),
        };
        buffers.output = output;
        status
    })
}

#[unsafe(export_name = "snail:assembler/output")]
pub extern "C" fn output() -> *const u8 {
    BUFFERS.with_borrow(|buffers| buffers.output.as_ptr())
}

#[unsafe(export_name = "snail:assembler/output-length")]
pub extern "C" fn output_length() -> usize {
    BUFFERS.with_borrow(|buffers| buffers.output.len())
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

    #[test]
    fn exports_drive_the_buffers() {
        let text = b"(module (func (export \"f\")))";
        let pointer = input(text.len());
        unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), pointer, text.len()) };
        assert_eq!(assemble_input(), 0);
        let module = unsafe { std::slice::from_raw_parts(output(), output_length()) };
        assert_eq!(&module[0..4], b"\0asm");
    }
}
