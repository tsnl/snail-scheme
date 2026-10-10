# Native execution through Wasm

`(snail-scheme native)` translates Wasm to LLVM and links an x86-64 Linux
executable. It supports two runtime arrangements: a complete Rust-linked Wasm
module, and the CLI's Scheme Wasm module importing a native Rust archive. Both
use the same translator, AWI ownership rules, and BDWGC collector.

The native CLI is built by `chibi-scheme -I src build.scm`. Its `main.scm` handler
accepts a script, compiles it, executes it, and returns its status. The resulting
`build/snail-scheme build.scm` rebuilds the interpreter. See the
[build chapter](book/builds.md) and [inline CLI ABI](book/platforms/native-cli.md).

For complete linked Wasm, the existing library workflow remains:

```scheme
(import (scheme base) (snail-scheme build) (snail-scheme native))
(build-wasm "." "examples/fibonacci.scm" "build/fibonacci.wasm")
(wasm-file->native-file "." "build/fibonacci.wasm" "build/fibonacci")
(run-command "fibonacci" '("build/fibonacci"))
```

The supported native target is x86-64 Linux. In addition to the Wasm build
toolchain, install Clang, LLD, BDWGC headers/library, and the C math library.
The repository's Nix shell includes these. `WASM_OPT` and `CLANG` override tool
paths; `BDWGC_INCLUDE` and `BDWGC_LIB` optionally identify a separate collector
installation. The latter adds a runtime library search path as well as a linker
path. Translation, `-O3` optimization, and shared LLVM LTO happen automatically.
Successful builds publish the executable atomically; failures preserve any
existing output and print the directory retaining the Wasm/LLVM intermediates.

## Compiler stages

Binaryen validates the binary and canonicalizes equivalent types, using the
same explicit feature set as the portable build. The bounded reader in
`wasm-binary.sld` records numeric declarations and function ranges in one shared
bytevector. `llvm.sld` indexes those declarations, then decodes each function's
flat instructions directly into LLVM. There is no disassembly, instruction tree,
or text-to-number conversion. This library consumes no Scheme IR or Scheme
binding information; unsupported Wasm operations fail explicitly.

`llvmlite.sld` preserves integers, names, quoted bytes, and float bit patterns as
immutable operands. Nested lists compose output fragments; a single writer
prints them without intermediate concatenation or repeated numeric formatting.
Only one function's body is buffered, so its allocations can precede it in the
entry block. Float bits never pass through the host's floating-point parser.

Locals and block-result joins use entry-block slots. The compile-time operand
stack holds already evaluated SSA operands, so a later mutation cannot change
an earlier read. Lexical branch targets retain an optional result slot and a
live-incoming-edge flag. Dead instructions are decoded without emitting values;
only a target reached by a live edge can resume emission. LLVM promotes slots
to SSA and optimizes the complete module together with the C host. Initialization
allocates memory and tables, evaluates globals, copies active data/element
segments, and invokes the
Wasm start function before the host calls the exported `_start`, or the CLI
handler adapter `snail:main` for a command.

Every guest function uses LLVM [`tailcc`](https://llvm.org/docs/LangRef.html#call-instruction).
Wasm tail instructions emit `tail call`
immediately followed by return, including reference and table calls. This gives
proper native tail calls across different signatures. LLVM 22's x86-64 lowering
of `musttail call tailcc` lost growing stack arguments in a verified small
reproduction; `tail call tailcc` follows the convention's guaranteed-tail path.
`tests/native-semantics.wat` guards this boundary with two million alternating
calls, integer/reference/floating arguments, and a 256 KiB native stack limit.

## Representations and roots

Null is zero; i31 references are odd words containing a signed 31-bit integer;
other references are uncompressed pointers. Heap objects begin with a type and
category word. Struct fields occupy eight-byte slots; arrays add a length word
and eight-byte element slots. Packed fields load/store their specified width.
Immutable, numeric-only global structs have distinct static objects, preserving
reference identity while exposing constant atoms to LLVM. Function references
point to static descriptors containing their Wasm type identity and native code
pointer. Indirect calls check bounds, null, and the expected type identity.

BDWGC scans objects, tables, globals, and native stacks/registers. Interior-pointer
recognition is enabled before collector initialization, so a field address held
across an allocating operand keeps its object alive. There is no moving collector
and no separate shadow-root stack. The collector and optimizer must preserve
live uncompressed pointers under this restricted ABI; forced-collection tests
exercise locals, allocating operands, tables, callbacks, and tail transfers.

When translating a complete Rust-linked Wasm module, Rust linear memory is a
separate, unscanned 4 GiB address reservation. Growth
commits zeroed pages without moving its base. Rust addresses remain wasm32
offsets; memory bounds use widened arithmetic so offsets cannot wrap through a
check. Loads and stores allow byte alignment. Rust retains Scheme values through
owned AWI handles in the scanned reference table, exactly as under a Wasm engine.

The native CLI instead links Rust's native archive directly. Scheme imports
under `snail.rust` and `snail.cli` retain their `snail:` symbol names and scalar
signatures. Rust's AWI calls bind to the translated Scheme exports. Files,
subprocesses, and environment access use Rust's native standard library, with no
WASI shim on this route. This first host supports one instance per OS process;
multiple actors sharing a process still need explicit instance selection.

Collector callbacks queue only resource kinds and IDs. They never enter Rust:
an allocation may occur while a translated Rust `RefCell` is borrowed. The host
drains a finite queued batch only after guest execution returns. Held finalizer
records do not retain their watched wrapper. The ordinary executable polls after
`_start` or `snail:main`; custom C hosts must call `native_poll_finalizers` only with no active
guest frames. A long-running call or `proc_exit` may defer cleanup indefinitely;
explicit close remains the prompt resource-release mechanism. There is no Scheme
collection/statistics API; portable Wasm does not expose those operations.

## Coverage and boundaries

The converter covers operations emitted by the current linked compiler/runtime:

| Area | Implemented behavior |
| --- | --- |
| Control | Blocks, loops, if, branches, branch tables, returns, direct/reference/indirect calls and tail calls |
| Numeric | Scalar i32/i64/f32/f64 arithmetic used by the runtime, comparisons, shifts, rotations, bit counts, conversions, sign extension, IEEE bit reinterpretation |
| GC | Final struct/array types, recursive type groups, allocation, fields/elements, packed access, copy, reference tests/casts, i31 |
| Memory | One unshared wasm32 memory, active data, size/grow, loads/stores, fill/copy |
| Tables | Nullable table32, active function elements, get/set, size/grow, indirect-call checks |
| Host | Native CLI AWI imports, or WASIp1 arguments/environment, clocks, descriptor I/O/stat/seek/close, preopens, path open/stat/mkdir, process exit, AWI finalizers |

Integer division, float truncation, reference casts, and memory/array/table bounds
trap at Wasm boundaries rather than relying on LLVM undefined behavior. A trap
prints `WebAssembly trap` and exits with status 1. WASI returns scalar error codes
and writes its specified layouts into guest memory. The native host exposes the
working directory and optional trace directory, and executes with ordinary
native process permissions; it is not a Wasm security sandbox.

This is not an implementation of every Wasm proposal. Subtyping, externref,
multivalue function/block signatures, block parameters, passive segments, memory64,
multiple/shared memories, SIMD, threads, exceptions, and stack switching are
unsupported. Additional scalar/array/table instructions outside the emitted
subset also fail explicitly. Declarative element segments establish validation
facts and need no runtime action. Scheme multiple values already use GC packets and
do not require Wasm multivalue signatures. Unsupported imports and mismatched
host signatures are diagnosed before native linking.

## Checks and measurements

`scripts/test-backend --target both` builds each Scheme fixture once, then
executes its exact linked binary in Node and as native code. `scripts/test-native`
compares a separate Wasm semantics fixture under both engines, checks twelve
traps and proper tail calls, forces collection at every allocation, verifies
Rust-retained Scheme roots and Rust-to-Scheme callbacks, and checks actual Rust
resource cleanup. `scripts/test-self-host` separately exercises direct native
Rust linkage, the CLI handler, and rebuilding without Chibi. Set `SNAIL_NATIVE_GC_INTERVAL=N` for diagnostic collection every
N native object allocations; leave it unset for ordinary execution.

`benchmarks/native` builds the complete canonical Fibonacci workload in all
implementations before rotating eight rounds on a fixed core. The native and
V8 cases use the same Rust-linked module and Scheme outer loops. The internal
timer excludes compilation, process startup, checks, and output. Raw samples,
commands, hashes, and scope are saved to `build/native-benchmark/results.json`.
See [the benchmark report](../BENCHMARKS.md) for measured results and the older
bounded experiment's distinct scope.
