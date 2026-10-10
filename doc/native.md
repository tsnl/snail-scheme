# Native execution of linked Wasm

`(snail-scheme native)` exports `wasm-file->native-file(root, input, output)`.
It consumes the same final Rust-linked binary that `run-wasm` executes. Both the
Scheme and Rust portions become LLVM; Rust is never rebuilt for a native target.
The compiler remains hosted by Chibi.

```scheme
(import (scheme base) (snail-scheme build) (snail-scheme native))
(build-wasm "." "examples/fibonacci.scm" "build/fibonacci.wasm")
(wasm-file->native-file "." "build/fibonacci.wasm" "build/fibonacci")
(run-command "fibonacci" '("build/fibonacci"))
```

The supported native target is x86-64 Linux. In addition to the Wasm build
toolchain, install Clang, LLD, BDWGC headers/library, and the C math library.
The repository's Nix shell includes these. `WASM_DIS` and `CLANG` override tool
paths; `BDWGC_INCLUDE` and `BDWGC_LIB` optionally identify a separate collector
installation. The latter adds a runtime library search path as well as a linker
path. Translation, `-O3` optimization, and shared LLVM LTO happen automatically.
Successful builds publish the executable atomically; failures preserve any
existing output and print the directory retaining the WAT/LLVM intermediates.

## Compiler stages

Binaryen validates and disassembles the binary. `wat.sld` reads Binaryen's folded
text with its byte escapes and numeric atoms. `llvm.sld` records declarations
and native layouts in one pass, then traverses function expressions directly.
Its inputs contain no Scheme IR or Scheme binding information. WAT operators
select explicit LLVM operations or C host helpers; unsupported operations fail.

Locals and block-result joins use entry-block slots. Structured labels retain
their optional result slots, and a terminated expression stops operand emission.
Operands execute left to right. LLVM promotes slots to SSA and optimizes the
complete module together with the C host. Initialization allocates memory and
tables, evaluates globals, copies active data/element segments, and invokes the
Wasm start function before the host calls the exported `_start`.

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

Rust linear memory is a separate, unscanned 4 GiB address reservation. Growth
commits zeroed pages without moving its base. Rust addresses remain wasm32
offsets; memory bounds use widened arithmetic so offsets cannot wrap through a
check. Loads and stores allow byte alignment. Rust retains Scheme values through
owned AWI handles in the scanned reference table, exactly as under a Wasm engine.

Collector callbacks queue only resource kinds and IDs. They never enter Rust:
an allocation may occur while a translated Rust `RefCell` is borrowed. The host
drains a finite queued batch only after guest execution returns. Held finalizer
records do not retain their watched wrapper. The ordinary executable polls after
`_start`; custom C hosts must call `native_poll_finalizers` only with no active
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
| Host | WASIp1 arguments/environment, clocks, descriptor I/O/stat/seek/close, preopens, path open/stat/mkdir, process exit, AWI finalizers |

Integer division, float truncation, reference casts, and memory/array/table bounds
trap at Wasm boundaries rather than relying on LLVM undefined behavior. A trap
prints `WebAssembly trap` and exits with status 1. WASI returns scalar error codes
and writes its specified layouts into guest memory. The native host exposes the
working directory and optional trace directory, and executes with ordinary
native process permissions; it is not a Wasm security sandbox.

This is not an implementation of every Wasm proposal. Subtyping, externref,
multivalue function/block signatures, passive/declarative segments, memory64,
multiple/shared memories, SIMD, threads, exceptions, and stack switching are
unsupported. Additional scalar/array/table instructions outside the emitted
subset also fail explicitly. Scheme multiple values already use GC packets and
do not require Wasm multivalue signatures. Unsupported imports and mismatched
host signatures are diagnosed before native linking.

## Checks and measurements

`scripts/test-backend --target both` builds each Scheme fixture once, then
executes its exact linked binary in Node and as native code. `scripts/test-native`
compares a separate Wasm semantics fixture under both engines, checks twelve
traps and proper tail calls, forces collection at every allocation, verifies
Rust-retained Scheme roots and Rust-to-Scheme callbacks, and checks actual Rust
resource cleanup. Set `SNAIL_NATIVE_GC_INTERVAL=N` for diagnostic collection every
N native object allocations; leave it unset for ordinary execution.

`benchmarks/native` builds the complete canonical Fibonacci workload in all
implementations before rotating eight rounds on a fixed core. The native and
V8 cases use the same Rust-linked module and Scheme outer loops. The internal
timer excludes compilation, process startup, checks, and output. Raw samples,
commands, hashes, and scope are saved to `build/native-benchmark/results.json`.
See [the benchmark report](../BENCHMARKS.md) for measured results and the older
bounded experiment's distinct scope.
