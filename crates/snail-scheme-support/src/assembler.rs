//! WebAssembly assembly and static linking for tools written in `snail-scheme`: the
//! toolchain's runtime only, behind the `assembler` feature.
//!
//! Requests arrive through the compiler's String/Bytes staging. The result
//! stays here until the next request, and `snail-scheme` reads it a byte at a
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
    let linked = merge(&[("program", &public_exports(&merged)?)], true)?;
    validate_program(&linked)?;
    Ok(linked)
}

// Validate the delivered artifact, after the linker remaps both tables and
// types. Every executable host can disable GC and typed function references.
fn validate_program(bytes: &[u8]) -> Result<(), String> {
    use wasmparser::{Validator, WasmFeatures};
    let features = WasmFeatures::all() - WasmFeatures::GC - WasmFeatures::FUNCTION_REFERENCES;
    Validator::new_with_features(features)
        .validate_all(bytes)
        .map(|_| ())
        .map_err(|error| error.to_string())
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
                if host_export(export.name) {
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

// Descriptors and root operations implement the host view of managed values.
// All other scalar services become private once the program is linked.
fn host_export(name: &str) -> bool {
    name.starts_with("snail:abi/")
        || name.starts_with("snail:foreign/")
        || name.starts_with("snail:global/")
        || matches!(
            name,
            "snail:table"
                | "snail:gc/roots"
                | "snail:gc/release-roots"
                | "snail:gc/checkpoint"
                | "snail:gc/restore"
                | "snail:gc/host-check"
                | "snail:gc/code-new"
                | "snail:gc/dead-code"
        )
        || (!name.starts_with("snail:") && !name.starts_with("diagnostics/"))
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

    // A closure's environment is an address. The table checks the signature
    // of its entry on the tail call.
    const PROGRAM: &str = r#"(module
  (type $fn (func (param i32 i64) (result i64)))
  (table 1 funcref) (elem (i32.const 0) $add)
  (memory 1)
  (func $add (type $fn) (param $self i32) (param $x i64) (result i64)
    (i64.add (local.get $x) (i64.load offset=8 (local.get $self))))
  (func (export "main") (result i64)
    (i64.store offset=8 (i32.const 16) (i64.const 1))
    (return_call_indirect (type $fn) (i32.const 16) (i64.const 41) (i32.const 0))))"#;

    #[test]
    fn assembles_linear_closures_and_tail_calls() {
        let module = assemble(PROGRAM).expect("the program assembles");
        validate_program(&module).unwrap();
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
          (import "snail.core.support" "snail:answer" (func $answer (result i32)))
          (import "unused" "host-function" (func $unused))
          (global (export "yielding") (mut i32) i32.const 0)
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
