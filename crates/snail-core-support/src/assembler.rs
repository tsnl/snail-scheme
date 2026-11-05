//! WebAssembly assembly and static linking for tools written in Snail-Core: the
//! toolchain's runtime only, behind the `assembler` feature.
//!
//! Requests arrive through the compiler's String/Bytes staging. The result
//! stays here until the next request, and Snail-Core reads it a byte at a
//! time. No guest value is held across calls.

use std::cell::RefCell;

use crate::io::{checked, staged_text};
use wasm_encoder::{ExportSection, Module, RawSection, reencode::Reencode};
use wasm_fuse::{MergeOptions, Merger};
use wasmparser::{Parser, Payload};

// ---- Assembling ----

/// The binary module the text describes, or the parser's message, which
/// names the line and column of the problem.
pub fn assemble(text: &str) -> Result<Vec<u8>, String> {
    wat::parse_str(text).map_err(|error| error.to_string())
}

// ---- Linking ----

const ADAPTER: &str = r#"(module
  (import "snail.core.support" "snail:report-error" (func $report (param i32 i32)))
  (import "snail.core.support" "snail:io/close-all" (func $close (result i32)))
  (export "diagnostics/report-error" (func $report))
  (export "close-resources" (func $close)))"#;

/// Resolve the scalar ABI, then prune from the public exports. Internal exports
/// remain available until imports have been resolved, including re-export chains.
pub fn link(text: &str, runtime: &[u8]) -> Result<Vec<u8>, String> {
    let program = assemble(text)?;
    let adapter = assemble(ADAPTER)?;
    let merged = merge(
        &[
            ("snail.abi", &program),
            ("snail.core.support", runtime),
            ("snail.platform", &adapter),
        ],
        false,
    )?;
    merge(&[("program", &public_exports(&merged)?)], true)
}

fn merge(inputs: &[(&str, &[u8])], prune: bool) -> Result<Vec<u8>, String> {
    let mut merger = Merger::new(MergeOptions {
        prune_unused: prune,
        keep_names: true,
        ..MergeOptions::default()
    });
    for (name, bytes) in inputs {
        merger
            .add_module(*name, bytes)
            .map_err(|error| error.to_string())?;
    }
    merger.merge().map_err(|error| error.to_string())
}

// Export filtering changes no indices or instructions. All other sections can
// be copied verbatim; wasm-fuse does the subsequent reachability and remapping.
fn public_exports(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let mut module = Module::new();
    for payload in Parser::new(0).parse_all(bytes) {
        let payload = payload.map_err(|error| error.to_string())?;
        if let Payload::ExportSection(exports) = payload {
            let mut section = ExportSection::new();
            for export in exports {
                let export = export.map_err(|error| error.to_string())?;
                if !export.name.starts_with("snail:") && !export.name.starts_with("diagnostics/") {
                    wasm_encoder::reencode::RoundtripReencoder
                        .parse_export(&mut section, export)
                        .map_err(|error| error.to_string())?;
                }
            }
            module.section(&section);
        } else if let Some((id, range)) = payload.as_section() {
            module.section(&RawSection {
                id,
                data: &bytes[range],
            });
        }
    }
    Ok(module.finish())
}

// ---- Results ----

// The last result: the module on success, the message as UTF-8 on failure.
// A Wasm instance runs one call at a time.
thread_local! {
    static OUTPUT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

/// Assembles the staged text. Returns 0 when the output holds the module,
/// and 1 when it holds the message.
#[unsafe(export_name = "snail:assembler/assemble")]
pub extern "C" fn assemble_staged(count: u32) -> i32 {
    finish(staged_text(count).and_then(|text| assemble(&text)))
}

/// Links runtime bytes followed by UTF-8 program text, staged as a final Bytes.
///
/// # Safety
/// `input` points to a little-endian u32 length followed by that many readable
/// bytes. The compiler's Bytes staging owns this memory for the entire call.
#[unsafe(export_name = "snail:assembler/link")]
pub unsafe extern "C" fn link_staged(runtime_length: usize, input: *const u8) -> i32 {
    let length = u32::from_le(unsafe { input.cast::<u32>().read_unaligned() }) as usize;
    let request = unsafe { std::slice::from_raw_parts(input.add(4), length) };
    finish(link_request(runtime_length, request))
}

fn link_request(runtime_length: usize, request: &[u8]) -> Result<Vec<u8>, String> {
    let (runtime, text) = request
        .split_at_checked(runtime_length)
        .ok_or("runtime length exceeds input")?;
    let text = std::str::from_utf8(text).map_err(|error| error.to_string())?;
    link(text, runtime)
}

fn finish(result: Result<Vec<u8>, String>) -> i32 {
    let (status, output) = match result {
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

    #[test]
    fn links_public_exports_and_prunes_private_imports() {
        let runtime = assemble(
            r#"(module
          (memory (export "memory") 1)
          (func (export "_initialize"))
          (func (export "snail:report-error") (param i32 i32))
          (func (export "snail:io/close-all") (result i32) i32.const 0)
          (func (export "snail:answer") (result i32) i32.const 42))"#,
        )
        .unwrap();
        let program = r#"(module
          (type $box (struct (field i32)))
          (import "snail.core.support" "snail:answer" (func $answer (result i32)))
          (import "unused" "host-function" (func $unused))
          (global (export "yielding") (mut (ref null $box)) ref.null $box)
          (func (export "main") (export "user/function") (result i32) call $answer)
          (export "snail:unused" (func $unused))
          (export "diagnostics/unused" (func $unused)))"#;
        let bytes = link(program, &runtime).unwrap();
        wasmparser::Validator::new_with_features(wasmparser::WasmFeatures::all())
            .validate_all(&bytes)
            .unwrap();
        let mut exports = Vec::new();
        for payload in Parser::new(0).parse_all(&bytes) {
            match payload.unwrap() {
                Payload::ExportSection(section) => {
                    exports.extend(section.into_iter().map(|item| item.unwrap().name))
                }
                Payload::ImportSection(section) => assert_eq!(section.count(), 0),
                _ => {}
            }
        }
        exports.sort_unstable();
        assert_eq!(
            exports,
            [
                "_initialize",
                "close-resources",
                "main",
                "memory",
                "user/function",
                "yielding"
            ]
        );
        assert_eq!(bytes, link(program, &runtime).unwrap());
    }

    #[test]
    fn failed_requests_replace_output_and_allow_assembly() {
        assert_eq!(finish(link_request(1, &[])), 1);
        assert_eq!(finish(link_request(0, &[255])), 1);
        assert_eq!(finish(assemble("(module)")), 0);
        OUTPUT.with_borrow(|output| assert!(output.starts_with(b"\0asm")));
    }
}
