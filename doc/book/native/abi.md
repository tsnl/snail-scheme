# ABI and representation

`define-extern` supplies the exact Wasm module, name and signature. The native
driver maps `snail.library` to actual exported Rust C symbols and resolves the
selected platform aliases to those providers. It reads their signatures from the
same Rust sources Cargo builds. This deliberately closed reader accepts literal
export names and explicit scalar types; unsupported syntax or aliases fail.
Lowering compares the complete provider signature with the Wasm declaration
before emitting a call. Linker symbol resolution alone cannot check a C signature.

`--rust-provider MODULE SOURCE.rs` adds a Rust provider crate. The ABI reader
accepts literal `#[unsafe(export_name = "symbol")]` attributes on public
`extern "C"` functions with explicit scalar parameters and results. Comments
and string contents do not declare exports. Type aliases, macro-generated
exports, pointers, variadics and aggregates are outside this closed interface.
Cargo compiles the same source as an ordinary dependency, with one shared Rust
runtime and standard library. There are no C headers or C compilation steps.

| Lofi/Wasm value | Rust carrier at the C ABI |
| --- | --- |
| I32, Bool, Char / i32 | `i32` or `u32` |
| I64 / i64 | `i64` or `u64` |
| F32 / f32 | `f32` |
| F64 / f64 | `f64` |
| Unit / no result | No result |

Bool and Unicode Char use full 32-bit carriers. A scalar i64 is never silently
converted to a pointer. The source declaration is a trusted foreign contract;
ABI checks do not establish the safety of arbitrary native code.

Native pointers, Wasm memory32 offsets, managed references and ABI root handles
are separate representations. The one native diagnostic boundary explicitly
takes a native byte pointer and `size_t`; it does not reuse the memory32 import.
A future Vulkan/foreign-pointer adapter must declare pointer ownership, lifetime,
nullability and any scalar handle encoding explicitly. This restoration installs
direct scalar C linkage; it does not install a Vulkan API or infer pointer types.


## Managed storage

Null, tagged i31 values and aligned object addresses are distinct. Struct fields
use eight-byte slots. Arrays have an eight-byte kind word and eight-byte length,
then packed elements at offset 16: one byte for i8, two for i16, four for i32/f32,
and eight for i64/f64/references. Static arrays share this layout.

Lowering checks null/immediate tags, zero-extends the i32 index, checks it against
the length, then computes the address at the known stride. Array allocation and
copying use the same stride. Numeric payloads are never traced. A zero-bit-pattern
initializer uses the allocator's cleared payload directly; negative zero and NaN
payloads still use the width-specific fill path.

Reference type identities retain canonical recursive groups and parent chains;
sibling casts trap. Mutable literal graphs may form cycles at runtime.
