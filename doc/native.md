# Native execution through Wasm

`(snail-scheme native)` optimizes the generated Scheme module with Binaryen,
reads its folded disassembly into datums, lowers those datums to LLVM, and links
an x86-64 Linux executable with the native Rust runtime and BDWGC. Portable
Wasm uses the same Scheme-module optimization, then links Rust and optimizes the
complete program. AWI import/export names remain intact in the shared pass.

```scheme
(import (scheme base) (snail-scheme build) (snail-scheme native))
(build-native "." "examples/fibonacci.scm" "build/fibonacci")
(run-command "fibonacci" '("build/fibonacci"))
```

`build-native` publishes an executable; `run-script` uses a private execution
directory. The interpreter recipe and installation data live in `build.scm`.
Bootstrap with `chibi-scheme -h512M -I src build.scm`. The resulting
`build/snail-scheme -Isrc build.scm` rebuilds the interpreter without Chibi,
using Binaryen and its installed native Scheme datum reader.
The CLI accepts `-I DIRECTORY` or `-IDIRECTORY` before the script; each option
prepends a search directory. `--` ends option parsing, and arguments after the
script are passed literally.
See the [build chapter](book/builds.md) and [inline CLI ABI](book/platforms/native-cli.md).

Native builds require Cargo, Binaryen, Clang/LLD, BDWGC headers/library and the
C math library; Chibi is needed for bootstrap. The Nix shell supplies these.
`CLANG` and `LLD` override the compiler and linker paths. `WASM_AS`, `WASM_OPT`
and `WASM_DIS` override Binaryen executables. The CLI checks these tools before
compiling a script, while help remains independent of them. See
[installation and preflight](backend.md#build-and-run).
`BDWGC_INCLUDE` and `BDWGC_LIB` identify a separate collector installation; the
latter adds both a link path and runtime library search path. Translation, `-O3`
optimization and LLVM LTO happen automatically. Successful builds publish
atomically; failures preserve existing output and report the directory retaining
`module.ll` and optimized Scheme intermediates. There is no arbitrary
`.wasm`-to-native entry point or native Wasm binary reader.

## Compiler stages

`source-file->wasm` returns a complete folded module datum, including the quoted
runtime and AWI helper definitions. Neither consumer mutates it.
`wasm-optimize.sld` assembles and optimizes it before LLVM lowering.
`wasm-read.sld` converts WAT byte escapes and integer-spelled floats into Scheme
spelling, preserving negative zero and avoiding the reader's integer range limit,
then reads one declaration at a time with the host datum reader.
`wasm-resolve.sld` canonicalizes complete ordered final recursion groups.
Its keys use member positions for internal edges and canonical identities for
earlier groups, retaining field mutability, nullability and packed widths.
Equal groups share member identities; a singleton stays distinct from a similar
member of a larger group. Forward references within a group are supported;
nonfinal/subtyping declarations remain unsupported. Explicit function type uses
retain their declared identity after validating their inline signature.

Function bodies are normalized one at a time into flat evaluation order, then
`llvm.sld` emits LLVM. Operands evaluate left to right before their operation;
LLVM's stack holds SSA values, so later mutation cannot change an earlier read.
Labels enter scope for control bodies, excluding an `if` condition. Shadowing,
unnamed controls and the implicit function label determine branch depths. Dead
instructions still preserve control nesting; only live incoming edges resume
emission. Entry-block slots represent locals and result joins; LLVM promotes them
to SSA. The resolver is an adapter for trusted compiler output, not a general
WAT parser or Wasm validator. Unsupported declarations and instructions fail.

Names beginning `cold.` request LLVM's `cold` optimization hint. This keeps the
runtime's wide/inexact numeric fallback from dictating the hot integer path's
layout. It introduces no type facts or removed checks; LLVM decides inlining.

`llvmlite.sld` composes immutable output fragments without repeated formatting.
Only one function's body is buffered so allocations can precede it in the entry
block. Finite f64 literals use round-tripping decimal spelling, preserving
negative zero and subnormals; infinities and NaNs use LLVM hex literals,
including explicit NaN signs and payload bits from Binaryen.
Initialization creates tables, evaluates globals and active element segments,
and invokes any module start function before the native CLI calls `snail:main`.

Every guest function uses LLVM [`tailcc`](https://llvm.org/docs/LangRef.html#call-instruction).
Wasm tail instructions emit `tail call`
immediately followed by return, including reference and table calls. This gives
proper native tail calls across different signatures. LLVM 22's x86-64 lowering
of `musttail call tailcc` lost growing stack arguments in a verified small
reproduction; `tail call tailcc` follows the convention's guaranteed-tail path.
`tests/native-datums.scm` guards this boundary with two million alternating
calls, integer/reference/floating arguments, and a 256 KiB native stack limit.

## Representations and roots

Null is zero; i31 references are the zero-extended 32-bit word `(input << 1) | 1`.
The wrapping shift discards input bit 31, exactly as `ref.i31` requires. Extraction
truncates to i32 and shifts right arithmetically or logically for `i31.get_s` or
`i31.get_u`, after checking null. Global initializers and dynamic construction
use this same canonical encoding, so reference equality is ordinary i64 equality.
Other references are uncompressed pointers. Heap objects begin with a type and
category word. Struct fields occupy eight-byte slots; arrays add a length word
and eight-byte element slots. Packed fields load/store their specified width.
Supported constant global object graphs become distinct static structs and
arrays, including nested references, text, and vectors. Their declared field
mutability is retained, and writable static storage is scanned by BDWGC.
Initial graphs remain live for the module lifetime, including children later
overwritten in mutable objects. Unsupported initializers fall back to runtime
construction; constant arrays are bounded to 65,536 elements. Function references
point to static descriptors containing their Wasm type identity and native code
pointer. Indirect calls check bounds, null, and the expected type identity.

BDWGC scans objects, tables, globals, and native stacks/registers. Interior-pointer
recognition is enabled before collector initialization, so a field address held
across an allocating operand keeps its object alive. There is no moving collector
and no separate shadow-root stack. The collector and optimizer must preserve
live uncompressed pointers under this restricted ABI; forced-collection tests
exercise locals, allocating operands, tables, callbacks, and tail transfers.

Rust links as a native archive. Imports under `snail.rust` and `snail.cli` retain
their `snail:` names and scalar signatures. Rust's AWI calls bind to the lowered
Scheme exports. Files, subprocesses and environment access use Rust's native
standard library, with no Wasm linear memory or WASI adapter. One instance per
OS process is supported; multiple actors need explicit instance selection.

Collector callbacks queue only resource kinds and IDs. They never enter Rust:
an allocation may occur while a Rust `RefCell` is borrowed. The host
drains a finite queued batch only after guest execution returns. Held finalizer
records do not retain their watched wrapper. The ordinary executable polls after
`snail:main`; custom C hosts must call `native_poll_finalizers` only with no active
guest frames. A long-running call or process exit may defer cleanup indefinitely;
explicit close remains the prompt resource-release mechanism. There is no Scheme
collection/statistics API; portable Wasm does not expose those operations.

## Coverage and boundaries

The converter covers operations emitted by the current Scheme compiler and its quoted runtime:

| Area | Implemented behavior |
| --- | --- |
| Control | Blocks, loops, if, branches, branch tables, returns, direct/reference/indirect calls and tail calls |
| Numeric | Scalar i32/i64/f64 arithmetic used by the runtime, comparisons, shifts, rotations, bit counts, conversions, sign extension, IEEE bit reinterpretation |
| GC | Final struct/array types, ordered recursive groups, allocation, fields/elements, packed access, copy, reference tests/casts, i31 |
| Tables | Nullable table32, active function elements, get/set, size/grow, indirect-call checks |
| Host | Native Rust AWI services and deferred resource finalizers |

Integer division, float truncation, reference casts, and array/table bounds
trap at Wasm boundaries rather than relying on LLVM undefined behavior. A trap
prints `WebAssembly trap` and exits with status 1. Programs execute with ordinary
native process permissions; the native backend is not a Wasm security sandbox.

This is not an implementation of every Wasm proposal. Subtyping, externref,
multivalue function/block signatures, block parameters, linear memories/data segments, SIMD, threads, exceptions, and stack switching are
unsupported. Additional scalar/array/table instructions outside the emitted
subset also fail explicitly. Declarative element segments establish validation
facts and need no runtime action. Scheme multiple values already use GC packets and
do not require Wasm multivalue signatures. Unsupported imports and mismatched
host signatures are diagnosed before native linking.

## Checks and measurements

`scripts/test-backend --target both` builds and runs each Scheme fixture through
both backends. `scripts/test-native` gives both consumers the same datum fixture,
compares results, checks thirteen traps, proper tail calls, float boundaries,
recursive type identity, shadowed labels and evaluation order. It checks that
printing and repeated lowering preserve the datum. Forced collection exercises
Rust-retained roots, reentrant callbacks and actual resource cleanup.
`scripts/test-binaryen` compares original and optimized modules in V8 and native
execution, covering recursive identity, indirect-call traps, eager typed select,
escaped names and float bits. `scripts/test-self-host` checks dependency
preflight, CLI behavior and publication, then uses Binaryen while blocking
Chibi and Python during a rebuild and runs its replacement. Set
`SNAIL_NATIVE_GC_INTERVAL=N` for diagnostic collection every N native allocations;
leave it unset for ordinary execution.

`make benchmark` and `benchmarks/native` run all 57 pinned R7RS workloads
across Snail native, Chez, Guile, and Chibi. Builds finish before rotating
three measured rounds on a fixed core. Workload timers exclude compilation
and process startup. Every requested case, including failures, appears in
`build/r7rs-report/results.json`, its table, and the per-workload plots.
See [the benchmark guide](../BENCHMARKS.md) for scope and reproduction.
