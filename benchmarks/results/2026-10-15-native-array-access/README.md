# Checked native array access

This is generated-code evidence for one native-lowering change, with no timing
samples. Array length and element addresses now use checked LLVM operations
instead of calling opaque Rust helpers. Allocation, root publication, reference
type tests, arithmetic checks and benchmark source remain unchanged.

The before compiler is `82eb3b518e71457cf80820203c243f386ee7a65e`.
The changed `wasm-native/scheme/wasm-native/llvm.sld` has SHA-256
`f4003b68f56a9297b1f727cf8291fb902cc04998764390be9461eed961adaa4e`;
its before hash is
`67d6ffc9b79aeee2315fbd5cbbcc1bb370abf58836bd395d2b2f70057b552fdd`.
The Rust array access exports remain available to previously emitted objects.

## Inputs and construction

Both versions lower the exact same raw SFIR Wasm from the frozen validation
campaign `/tmp/sfir-unchecked-baseline-20261015`, revision
`729cb5231f28de519e42e29d1ddce578870a5e8c`. Despite that directory's name, its
compiler still emitted checked arithmetic. Inputs are
`validation/{array1,bv2string,gcbench}/program.wasm.raw.wasm`; physical imports
come from the corresponding retained scalar providers and shared runtime ABI.

The public `wasm-binary->llvm` API runs mandatory Binaryen 132 optimization;
`llvm-object` then runs LLVM 22.1.8 with `opt -passes=default<O3>` and
`llc -O=3 -mtriple=x86_64-unknown-linux-gnu -relocation-model=pic
-function-sections -data-sections -filetype=obj`. The optimized Wasm hashes are
identical before and after for all three cases. The paired Wasm, LLVM and object
hashes are in [comparison.json](comparison.json).

Full artifacts, tool command journals and local reproduction scripts are retained
under `/tmp/snail-native-array-access-20261015/build/array-access-ablation/`.
`before/` and `after/` each contain all three modules and complete object
disassembly. They were built with `BINARYEN_CORES=1`.

## Generated operations

These are static call-site counts in emitted LLVM, not dynamic execution counts:

| Case | Array slot calls | Array length calls | Root enter/leave | Array new / object allocation | Reference tests |
| --- | --- | --- | --- | --- | --- |
| array1 | 3 → 0 | 2 → 0 | 14 / 18, unchanged | 3 / 26, unchanged | 7, unchanged |
| bv2string | 21 → 0 | 5 → 0 | 33 / 47, unchanged | 7 / 70, unchanged | 6, unchanged |
| gcbench | 2 → 0 | 1 → 0 | 22 / 29, unchanged | 1 / 54, unchanged | 16, unchanged |

[Disassembly excerpts](disassembly.txt) retain the corresponding object code.
Array1 fill replaces the call at `f.3+0x85` with a checked scaled store at
`f.3+0x91`. Reverse copy replaces two calls at `f.4+0x9f/+0xb1` with checked
loads/stores at `f.4+0xbf/+0xc4`. Null, immediate-tag and unsigned bounds checks
remain visible. The bytevector store uses scale one; the GCbench floating-point
store uses scale eight. Zero-capacity root calls and closure type checks remain.

The guest is already machine code when Cargo links the Rust runtime. These
direct operations expose array addressing to LLVM without changing that build
boundary. Performance effects require a later controlled measurement.

## Execution and validation

The changed native objects execute the original canonical workloads correctly:
array1 returns `1000000`, bv2string and gcbench return `1`, with the expected
barrier counts and no surviving descendants. [execution.json](execution.json)
records these checks without treating their durations as measurements.

`make test`, `make check`, Rust formatting, the full native suite, linked-Wasm
math checks and the bytevector suite pass. The native suite includes 58 Rust
runtime tests, forced collection, packed integers, references, floating-point
bits, resource cleanup and instance ordering. New dynamic-reference probes cover
null, immediate tags, empty arrays, unsigned high indices and operand side
effects before traps on direct and Binaryen-optimized native code. V8 checks the
corresponding valid-Wasm cases. The native ABI also checks all 32 length bits
using a header-only probe without a multi-gigabyte allocation.

The bytevector suite compares all 1,112,064 Unicode scalars with an independent
Rust encoding oracle on raw Wasm, optimized Wasm and native code. The oracle has
13,344,768 bytes and SHA-256
`4de506fd1785aacfd9ab96b80e3d7e8a509935b3ea588d87a5487baf4e302d6e`.

The first full native attempt finished every assertion but exited 70 when Chibi
re-read a trailing delimiter in the unchanged test launcher. A tiny independent
fork/exit probe reproduced corruption of the parent's script position; a child
that immediately executes a fresh process does not reproduce it. The separate
harness fix `e9ab667a` replaces the forked Scheme build work with immediate exec,
retaining concurrent builds, raw logs, terminal statuses and supervisor cleanup
records. A pending rerun was stopped with status 143 after this diagnosis. The
corrected full native run then completed with status 0. These attempts remain in
`native/`, `native-rerun/` and `native-fixed/` under the retained artifact directory;
the failed attempt is not counted as an aggregate pass.
