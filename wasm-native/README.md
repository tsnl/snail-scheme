# Wasm to native

This project lowers supported WebAssembly to x86-64 Linux machine code. Its
Scheme libraries run on Chibi and consume Wasm without a source compiler or
inferred source types. Binaryen optimization is mandatory before native lowering.

The single `snail-runtime` Cargo crate supplies shared scalar services on both
Wasm and native targets. Its native configuration adds WasmGC allocation, exact
root tracing, numeric traps, tables, and process ownership. The scalar services
retain their declared `snail.library` ABI. Rust providers own external resources
behind scalar handles; they do not retain managed guest references.

## Scheme build API

Add this project's `scheme/` directory to Chibi's search path:

```sh
chibi-scheme -I "$package/scheme" /absolute/path/to/build.scm
```

Set `package` to this directory's absolute path. The library's own dependencies
use that same search root and installed Chibi/SRFI libraries, so this command
works from outside the repository. A Lofi build additionally passes
`-I "$repo/src"`; see the repository's [`build.scm`](../build.scm).

```scheme
(import
 (wasm-native))

(define imports
  (list (make-native-import "host" "read" "host_read" '(i32) 'i64)))
(wasm-binary->llvm "program.wasm" imports "build/program" "build/program/module.ll")
(llvm-bitcode "build/program/module.ll" "build/program/module.bc")
(link-native-object runtime-root "build/program/module.bc" "entry.rs"
                    '(("host" "provider.rs")) "build/program")
```

`make-native-import` takes the Wasm module/name, native symbol, physical parameter
types, and physical result type. Supported scalar types are `i32`, `i64`, `f32`
and `f64`; a result may be `void`. `native-imports->bindings` returns the physical
declarations used by the provider checker. Duplicate import keys and mismatched
actual Wasm signatures fail before linking.

`wasm-binary->llvm` retains `optimized.wasm`, `optimized.wat`, `reader.scm` and
`native.trace.json` in the supplied directory. It returns the LLVM output path.
`llvm-bitcode` runs LLVM optimization and retains bitcode for shared optimization
with Rust at the final link. `llvm-object` additionally emits a real ELF machine
object for saved artifacts. Keeping these operations separate lets a host append
a fixed entry bridge before choosing the artifact format.

`link-native-object` takes this project's directory as `runtime-root`,
LLVM bitcode or an ELF machine object, an ordinary Rust crate-root entry file,
provider declarations, and a retained build directory.
Relative paths are resolved from the caller's working directory before Cargo
files are generated. The retained build directory is created when absent.
Providers are `(module-name rust-source-path)` pairs. Each compiles as a separate
Cargo dependency. Linker-plugin fat LTO optimizes guest bitcode together with the
Rust entry, runtime and providers. An ELF input links independently; its guest
bodies are already machine code and cannot participate in that optimization.
The returned executable is `program` in the retained directory. The custom entry
explicitly initializes the runtime and invokes the desired Wasm exports; no
source-language command policy is assumed.

`SNAIL_NATIVE_CPU` optionally selects a CPU spelling accepted by LLVM and Rust,
for example `x86-64-v3`. When unset, the portable compiler defaults are preserved.
The package passes it to guest optimization, saved-object code generation, and
the Rust entry, runtime and providers. Host build scripts and the process
supervisor keep their existing flags. An empty value is rejected at native
compilation; the compilers diagnose unsupported names. `native` is allowed for
ordinary builds but makes the result depend on the build host. CPU selection
preserves strict floating-point and trap semantics.

Linking a saved ELF object does not change its guest instructions or establish
which CPU originally produced it. The override applies to newly compiled Rust
code during that link. Callers remain responsible for running the resulting
program on a compatible CPU.

`rust-bindings` reads literal `#[unsafe(export_name = "name")] pub extern "C"`
scalar declarations. `runtime-bindings` describes the shared runtime's scalar
exports. `check-provider-bindings` verifies required declarations before linking.
`source-hashes`, `check-stable-inputs`, `rust-source-inputs` and `native-evidence`
support retained input and artifact evidence for a surrounding build command.
`native-evidence` accepts an optional final guest-source label. The repository
build command supplies `fresh` for newly compiled guest code and `imported` for
`--object`. Its `build.json` records guest and Rust CPU requests separately under
`native_cpu`: `null` means the unchanged compiler default for fresh code, while
an imported or unreported guest CPU is `unknown`. Failed builds retain the raw
requested spelling, including an invalid empty value.

## Native array representation

Arrays contain an eight-byte kind word, an eight-byte unsigned length, then
tightly packed elements at byte offset 16. Validated Wasm establishes the array
type and element width: one or two bytes for packed integers, four for `i32` and
`f32`, and eight for `i64`, `f64` and references.

LLVM lowering checks null and immediate tags before loading the length. Element
access then zero-extends the `i32` index, compares it unsigned against the length,
and computes the address with the known storage width. The checks occur after
operand evaluation and before their protected memory access. Packed extension,
truncation and floating-point bits retain their Wasm semantics. These operations
do not collect or change root publication; allocation, initialization and bulk
copy remain in Rust. The exported Rust `native_array_length` and
`native_array_slot` functions remain for previously emitted native objects.

The lowering computes synchronous collection effects over resolved Wasm direct
calls. Imports, dynamic calls, allocation and unfamiliar operations may collect;
that effect propagates to their callers. A recursive group with no collecting
path uses private local slots and omits root-frame publication. Wrappers and
module initialization remain conservative. Private slots retain normal parameter
and null initialization; noncollecting runtime helpers cannot invoke guest code.
GC stress injection keeps every function framed, including functions that cannot
collect in production.

Struct allocation calls carry LLVM's call-site `alwaysinline` hint. The private
Rust allocation method is also marked for inlining, so shared LTO can specialize
layout arithmetic and zero filling for each fixed size. Allocation preserves
collection, root publication, required zero initialization and failure handling.
The exported `native_alloc` C ABI handles arbitrary sizes and remains linkable
from independently compiled objects.

## Shared Wasm and host utilities

Libraries such as `(wasm-native wasm)`, `(wasm-native wasm-optimize)`,
`(wasm-native runtime-wasm)`, `(wasm-native process)`, `(wasm-native json)` and
`(wasm-native chromium-trace)` have no native-lowering imports. A Wasm-only client
can use these modules without loading LLVM emission or the native executor.
`optimize-wasm` preserves exports and uses the same Binaryen optimization flags
as native lowering. Traced low-level operations run within an explicit
`with-chromium-trace-to` scope; the public lowering call owns its own scope.

`build-wasm-runtime` takes the runtime root and builds the same Cargo crate for
`wasm32-wasip1`. `link-wasm-runtime` takes guest Wasm, output, runtime Wasm and a
diagnostic-pruning Boolean, then links the declared scalar services with Binaryen.

The optional `(wasm-native scalar-entry)` and `(wasm-native execute)` libraries
implement the existing fixed scalar invocation protocol. Saved objects retain
their ELF metadata, scalar kinds, ABI witnesses and opaque source-origin labels.
Each instantiated object runs in its own owned process. Source-language adapters
map their exported types and validate their origin labels before invoking it.

## Dependencies and checks

Binary input lowering requires Chibi, Binaryen `wasm-opt`/`wasm-dis`, and coreutils.
LLVM `opt` produces optimized bitcode; `llc` additionally emits saved ELF objects.
Structured Wasm assembly adds `wasm-as`; runtime Wasm
linking adds `wasm-merge`. Native linking requires Cargo, Rust's `rust-lld`, the
cached `libc` crate, and Linux libc startup/runtime objects plus `libgcc_s`.
The LLVM tools and Rust's bundled linker must accept compatible bitcode versions.
It does not invoke a C compiler driver. The current target is x86-64 Linux;
unsupported Wasm declarations and instructions fail explicitly. In particular,
native lowering does not implement linear memories, multivalue signatures or
parameterized blocks.

`SNAIL_NATIVE_LIBC` and `SNAIL_NATIVE_GCC` select the system library directories.
Native executable builds supply the Rust linker arguments and default to this
package's compiler wrapper, preserving an explicit `RUSTC_WRAPPER` setting.
Their explicit native target keeps LTO flags off host build scripts; the wrapper
supplies those scripts' linker. For direct Cargo commands, use the same wrapper:

```sh
export RUSTC_WRAPPER="$PWD/scripts/rustc-native"
cargo test --offline --features native-runtime
cargo fmt --all -- --check
chibi-scheme -D snail-tests -I scheme -I tests tests/host.scm
chibi-scheme -I scheme -I tests tests/standalone.scm
```

Run those commands from this directory. `tests/standalone.scm` builds an
independently authored Wasm module with a Rust scalar provider, links both LLVM
bitcode and a saved ELF object without its bitcode companion, runs each with
forced GC, checks a trap, and prints the retained directory. It uses only this
project's Scheme and test paths. An optional Node/V8 parity check runs the exact
optimized Wasm:

```sh
node tests/authored.mjs build/standalone-*/optimized.wasm
```

Choose the exact retained directory when several runs exist. The package can be
copied outside the enclosing repository and these checks run unchanged.
