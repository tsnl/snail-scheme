# Bounded WasmGC → LLVM → BDWGC experiment

`translate.py` accepts an actual `.wasm` binary and emits LLVM for x86-64 Linux.
It has no dependency on Scheme, HIR, or the Snail runtime. Binaryen's `wasm-dis`
decodes the binary into folded expressions and canonicalizes equivalent simple
types. The translator then records declarations and emits functions: two passes,
one module, no intermediate compiler IR.

This is a feasibility and performance experiment, not a general Wasm compiler.
The production Snail compiler is unchanged. In the proposed architecture, Snail
would emit WASM in place of MIR; this native translator would remain independent.

## Representations and collection

Native integers and floats use LLVM `i32`, `i64`, and `double`. References travel
as machine words: zero is null, an odd word is an immediate signed31 value, and
an aligned allocation address is a GC struct. Heap pointers are never shifted
or compressed. A struct has an eight-byte header and eight-byte field slots.
The header's canonical type number implements `ref.test` and `ref.cast`.
It is not a tracing descriptor.

`struct.new` calls the externally linked `GC_malloc`. `wasm_init` enables
interior-pointer recognition, initializes BDWGC, then evaluates global
initializers. All structs use scanned, zero-filled allocations. Collection may
happen on any allocation; live native pointers and pointers in heap fields
must remain discoverable. LLVM can retain an interior field address across an
allocating operand, so interior-pointer recognition is required. Integer data
can conservatively retain garbage, as with ordinary BDWGC clients.

There is no manual operand stack, shadow root stack, or per-instruction GC poll.
Functions use native `fastcc` calls; supported tail calls use `musttail` with
matching lowered parameter and result types. Local slots are LLVM allocas which
the optimizer promotes to SSA. Conditionals join reachable values with phi nodes.

The independent clarity review kept the direct expression dispatch and explicit
LLVM blocks. Declaration collection, exhaustive instruction dispatch, numeric
mapping tables, and atomic control-flow/object emission exceed the ten-line
function target where splitting would hide the operation. No general visitor,
type inference, or additional IR was introduced.

## Reproduce

First build the [WasmGC numeric experiment](../wasmgc/README.md), then:

```sh
python3 experiments/wasm-llvm/build.py
build/wasm-llvm/cpu 64
python3 experiments/wasmgc/measure.py
```

The builder translates and verifies LLVM, compiles with Clang `-O3`, links
BDWGC, and executes the checks. It records commands and input hashes in
`build/wasm-llvm/build-commands.json`. Recorded tools are Binaryen 132,
LLVM/Clang 22.1.8, and BDWGC 8.2.12. `WASM_DIS`, `WASM_AS`, `CLANG`, `OPT`,
`BDWGC_INCLUDE`, and `BDWGC_LIB` override the tool and library paths.
The C runner and translated module are compiled separately, without LTO.

The native adapter executes the same Fibonacci workload as the Wasm engine
adapters: 64 repetitions of inputs 22–25, weighted by `n + 1`, checksum
`269118144`. Initialization, warmup, compilation, and process startup are outside
the reported monotonic timer. The common measurement driver rotates eight
rounds pinned to CPU2. Native LLVM consumes the raw Wasm module; V8 and Wasmtime
also receive a Binaryen `-O3` variant. The existing native SSA control is i686,
while this experiment and the Wasm engines are x86-64; this is not an isolated
calling-convention or architecture comparison.

## Tests

- `check.py` mirrors all 43 numeric and tail-call checks from the Wasm experiment,
  including boxed integers, exact/inexact comparisons, NaNs, eight trap cases,
  and two million tail calls. Native traps terminate forked children with SIGILL.
- `gc-test.wat` retains objects across allocating non-tail calls and explicit
  collections. The optimized executable has roots in six callee-saved registers,
  two stack spill slots, a caller-held tree, and a generated global. This was
  checked in disassembly, not inferred from source locals.
- `runner.c` records actual BDWGC allocation and collection counters, checks live
  objects after collection, and confirms unreachable objects are finalized.
  Bookkeeping hides its pointers so the test itself does not root those objects.
  The observed run returned 1083, made 21 observations, allocated about 4.2 MB,
  performed 26 collections, and finalized eight objects.
- `semantics.wat` and `semantics.c` check equivalent structural type declarations,
  signed/unsigned i31 boundaries, and evaluation of a store's value before a
  null-destination trap.

These tests support the bounded prototype; they do not establish correctness
for every optimization or every Wasm feature.

## Deliberate limits

Input must be valid Wasm. Supported declarations are simple struct/function
types, functions, globals, selected test imports, and an unused memory
declaration. Supported instructions are the explicit cases in `translate.py`:
structured conditionals/blocks, locals/globals, direct calls, matching-signature
tail calls, basic numeric operations, i31, references, and fixed structs.
Unsupported encountered declarations/instructions fail. Unreachable expressions
after a terminating instruction need not be translated.

There are no arrays, tables, indirect calls, recursive type groups, subtyping,
branches to block labels, general loops, exceptions, module instances, or linear
memory operations. Terminating expressions nested inside operands are outside
the subset; the emitter rejects attempts to continue a terminated LLVM block.
The unused memory export is not materialized. This cannot
yet translate the separate Rust interop module, which uses linear memory and a
reference table. Imports are limited to the collector test's `env.collect` and
`env.observe`; exports receive C ABI wrappers. Sanitized symbol collisions fail.

The next production direction is to use an existing translator. In particular,
[Wastrel](https://codeberg.org/andywingo/wastrel) compiles WasmGC through C and
[already offers BDWGC selection](https://wingolog.org/archives/2026/04/09/wastrel-milestone-full-hoot-support-with-generational-gc-as-a-treat).
It has been used for a full Hoot Scheme REPL. Our subsequent throwaway checkout
at `ad0b577df0773a1fc825b2a2455e23bf03ea9dcc` also compiled this Fibonacci module
with no Wastrel source changes. The
[eight-round comparison](../../benchmarks/results/2026-10-10-wastrel.json)
measured Wastrel at 0.04801 seconds (`-O3` + LTO, Nix register clearing disabled),
versus 0.04695 for this translator and 0.03015 for Chez. Default Wastrel with
Nix's GCC `-O2` + LTO measured 0.05263 seconds. Wastrel also passed a separate
allocating-tree test with actual BDWGC collections. Preserve this translator as
an experimental reference; future native backend improvements should target
Wastrel.
Its current C backend is GCC-oriented: its author reports that Clang rejects
the heterogeneous tail-call signatures it emits. See the
[representation design](https://wingolog.org/archives/2026/02/09/six-thoughts-on-generating-c)
and [compilation discussion](https://wingolog.org/archives/2026/03/31/wastrelly-wabbits).
WAMR's `wamrc` is another LLVM AOT candidate, but needs WAMR's runtime and its
GC implementation. Ordinary Wasm AOT support alone is insufficient for these
WasmGC binaries. Wastrel was tested in a throwaway `/tmp` checkout; no submodule
or production dependency was added.
