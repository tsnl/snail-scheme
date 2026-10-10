# Rust numeric instruction experiment

This branch moves the seven binary numeric VM instruction bodies to
`runtime/src/instructions.rs`: add, subtract, equality, and four ordered
comparisons. Lowering, binding proofs, operand evaluation, stack representation,
and generic numeric fallback are unchanged. This is an experiment with the
compiler-to-Rust instruction interface, not a port of every VM instruction.

Rust receives the same raw VM/state pointers and immutable builtin index as the
LLVM handlers. It reads the two published stack words, checks fixnum tags,
computes a checked result, and publishes the accumulator/count before popping
two arguments. Tagged signed words preserve comparison order. Decoded signed31
addition/subtraction fits signed32; `Value::fixnum` checks the signed31 result
range and encodes it. Nonfixnums and overflowing fixnum results call the existing
numeric service with the operands still rooted. That service roots a/c and
polls before borrowing arguments. The fast path preserves the frame/environment.

The raw pointers intentionally may alias. Creating simultaneous `&mut Vm` and
`&mut State` references would introduce an invalid exclusivity promise. Stack
pointers are consumed before fallback; the state address remains stable. A
non-inlined fallback helper bounds the handler's code size without claiming
boxed or floating-point arithmetic is rare.

## Reproduce

The compiler retains LLVM handlers by default. Compile with Chibi's
`-D snail-rust-numeric` feature to emit Rust declarations for the experiment.
Both languages use the same runtime source tree.

```sh
taskset -c 3 benchmarks/rust-instructions --build-only
taskset -c 2 benchmarks/rust-instructions --measure-only --samples 8
```

The four configurations are LLVM and Rust handlers, each with ordinary release
linking or shared LTO. The harness delegates exact flags and bitcode assembly to
`benchmarks/lto`; native means `i686-unknown-linux-musl`. Shared LTO uses Rust fat
LTO, embedded bitcode, linker-plugin LTO, rust-lld, and linker LTO O3. Scheme IR
receives the usual O2 preprocessing in every configuration. No type inference
or workload specialization is introduced.

Every executable is built before timing. Each receives one warmup, then eight
rounds rotate all four configurations through execution order. Each sample runs
64 repetitions and validates the workload checksum. Program-internal timing
excludes process startup and build time. CPU2 affinity is inherited by each
process. Raw samples, source/artifact hashes, tool versions, commands, flags,
build durations, linked bitcode, optimized IR, and regenerated assembly are
retained in `build/rust-instructions`. The [final JSON report](../benchmarks/results/2026-10-09-rust-instructions.json)
retains the portable provenance and measurements.

## Native CPU result

| Handler language | Ordinary linking s | Shared LTO s |
| --- | ---: | ---: |
| LLVM | 0.456158 | 0.399002 |
| Rust | 0.538862 | 0.386479 |

These are median times for the same 64 repetitions of recursive Fibonacci. Rust
with shared LTO is 3.1% faster than LLVM with shared LTO in this run; the larger
15.3% improvement against ordinary LLVM includes changing the link pipeline.
Ordinary Rust calls are 18.1% slower than ordinary LLVM handlers. The matched
shared-LTO control is essential: this does not establish an intrinsic language
advantage, nor does one CPU workload predict boxed arithmetic, allocation-heavy
workloads, or a port of the remaining instructions.

## Inlining evidence and portability

The saved Rust-linked module contains 43 numeric handler calls in `snail_program`
before shared LTO and zero afterward. The LLVM control has zero before and after,
since its handlers already inline during Scheme O2 preprocessing. Optimized Rust
program blocks contain direct stack loads, tag tests, arithmetic/comparisons, and
state stores; the numeric handler symbols/calls are absent from regenerated
assembly. The fallback remains a distinct call on exceptional paths.

An [optional exploratory control](../benchmarks/results/2026-10-09-rust-instructions-unhinted.json)
used plain exported Rust functions, which did not inline automatically: with the fallback
kept separate, a diagnostic replay reported addition cost 110 against a cold
call-site threshold of 45. All 43 instruction calls survived; that exploratory
shared-LTO build measured 0.419547 s. The generated dispatch structure affects
inlining heuristics even though dynamic execution makes these operations hot.

Explicit `#[inline(always)]` matches the LLVM handlers' existing `alwaysinline`
contract and eliminates all 43 calls. Rust 1.95 emits a misleading warning that
inline attributes are ignored on exported functions, while its LLVM output
actually retains `alwaysinline`; this was independently checked on a minimal
exported-function probe and then in the final linked artifact. The module
suppresses that warning locally and documents the observation. Other Rust/LLVM
versions must be checked again. The measured toolchains are Rust 1.95.0 with
LLVM 22.1.2 and external LLVM 22.1.8. Compatible bitcode tooling, 32-bit targets,
and shared LTO remain requirements for this result, not assumptions that ordinary
linking can recover these optimizations.

## Review and validation

The simplify skill's independent behavioral review confirmed the single
read/check/compute/publish transition and fallback lifetime constraints. We
rejected wider arithmetic as unnecessary after proving the signed32 bounds,
and retained the exhaustive seven-operation match and the atomic state update
together rather than splitting them for line count. The fixed operation enum
is eliminated by Rust before linking; it adds no runtime dispatch.

`make test`, `make check`, native32 Rust tests (47), Rust formatting, and CLI
native/WASI integration checks passed. Ordinary native and WASI backend
integration fixtures passed under GC stress,
including the Cartesian numeric boundary matrix, boxed/inexact fallback,
noncommutative argument order, primitive rebinding, multiple values, overflow
and type errors, captured environment survival, and reusable continuations.
Shared-LTO validation passed the numeric, rebinding, error, and continuation
fixtures on both targets under GC stress;
WASI is a correctness check only, with no performance claim.

## Remaining production work

This experiment supports extending the instruction interface, but validates only
these seven operations. A full migration would port each remaining LLVM handler
with its current register/stack contract and precise safepoint rules, then remove
the duplicate handler emitter. The LLVM backend would retain program control
flow, labels, operand loads, calls to Rust instruction exports, constant data,
and linking declarations. Object/service operations still need distinct reviews
for stack resizing, errors, closure captures, and continuation restoration.

The normal runner would need a supported shared-LTO build path rather than the
experiment's `LLVM_LLC` bitcode adapter, compatible Rust/LLVM/LLD tool discovery,
and explicit target/link settings for native32 and WASI. It must keep WASI's
final irreducible-control-flow repair enabled, and retain an ordinary-linking
mode for correctness/debugging. Production code should establish and test a
supported forced-inlining contract instead of assuming this compiler warning's
current behavior is permanent. Artifact checks should confirm instruction calls
actually disappear across toolchain updates. Native performance evaluation must
then include memory, GC, I/O, and boxed/inexact-heavy programs before making the
new pipeline the default. No full migration or default-build change is landed
by this experiment.
