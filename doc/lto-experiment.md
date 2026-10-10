# Cross-language LTO experiment

This experiment compares three release build configurations without changing
Scheme lowering, runtime representation, or collection scheduling. It tests
whether LLVM can optimize across the emitted Scheme/Rust boundary, and how much
that helps the current runtime. It does not measure the proposed static builtin
layouts or allocation-capability safepoints.

## Reproduce

Use the normal backend dependencies, plus LLVM `clang`, `ld.lld`, `wasm-ld`, and
`llvm-dis`, compatible with rustc's LLVM. The initial experiment used Rust
1.95.0 (LLVM 22.1.2), external LLVM 22.1.8, Node 24.15.0, and Chez 10.4.1.
The experiment currently specifies x86-64 Linux and `wasm32-wasip1`.

```sh
benchmarks/lto --chez scheme --json build/lto/results.json
benchmarks/lto cpu --target native --snail-only --samples 3
```

`NODE` chooses the WASI execution engine; `--chez` chooses the reference runtime.
Unset `RUSTFLAGS`, `CARGO_ENCODED_RUSTFLAGS`, `LLVM_LLC`, `CARGO_PROFILE_*`, and
`SNAIL_GC_STRESS` for a controlled run. Cargo builds offline. `build/lto/cargo`
contains separate caches for each variant; clear it when changing toolchains.
The benchmark sources and compiler output are identical across the variants:

| Variant | Generated Scheme | Rust and final link |
| --- | --- | --- |
| `baseline` | O2 LLVM to native/WASM object | Ordinary release |
| `rust-lto` | Same O2 target object | Rust fat LTO |
| `cross-lto` | Same O2 LLVM, assembled to bitcode | Rust linker-plugin fat LTO; LLD LTO O3 |

All variants use explicit target triples. Release retains the repository's
`panic = "abort"` setting. These are comparisons of full build configurations:
linker LTO runs additional optimization on the Scheme module, and whole-program
optimization may change inlining and code generation choices.

The script uses the runner's `LLVM_LLC` hook to assemble verified bitcode into
its usual `scheme.o` path. LLD recognizes that format and combines it with Rust
bitcode. This adapter is confined to the experiment; the ordinary build pipeline
still emits a machine-code object. Cross-language builds retain linked pre-LTO
and optimized bitcode under `build/lto/linked` for inspection with `llvm-dis`.

Keep WASM's normal irreducible-control-flow repair enabled in the final linker.
The runner's earlier reducibility check applies only to the Scheme module before
LTO; it cannot justify skipping a backend pass on the transformed linked module.

## Measurement boundaries

Build every executable before timing any of them. Each benchmark group warms
all variants once, then rotates their process execution order through four
rounds. With Chez included, each of the four participants occupies each ordinal
position once. CPU, memory, and GC use 16 repetitions; I/O uses four. Every run
checks its workload answer, and the harness validates every printed checksum.

Reported durations come from each program's internal timer. They exclude Scheme
and Rust compilation, linking, process startup, and initial WASM module loading.
Node uses a fresh process per sample; engine tiering during timed execution is
still part of that WASI result. Chez is the separately compiled native reference,
not a fourth LTO variant or a WASM implementation. GC reports include collection
counts and collection time.

The JSON retains individual measurements, ordering, compiler flags, source and
artifact hashes, tool versions, build durations, and medians. Four samples are
an initial comparison; differences comparable to their spread are inconclusive.
Build durations include Cargo/build-script work and differ in cache state, so
use them as observed costs rather than a controlled compiler-throughput study.

## Measured result

The [raw samples and provenance](../benchmarks/results/2026-10-09-lto.json)
were collected against unchanged compiler/runtime sources at `98f2013`. Values
below are median milliseconds for the fixed repetition counts above. The last
column is shared-LTO Snail runtime divided by native Chez runtime; smaller is
better. Native and WASI are separate execution environments.

| Target/workload | Baseline ms | Rust LTO ms | Shared LTO ms | Baseline/shared speedup | Shared/Chez ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| native/cpu | 2024.88 | 1581.58 | 1487.11 | 1.36× | 204.3× |
| wasm/cpu | 3123.04 | 2826.88 | 2735.50 | 1.14× | 375.6× |
| native/memory | 2160.53 | 1936.19 | 1858.29 | 1.16× | 223.2× |
| wasm/memory | 3610.48 | 3241.12 | 3206.82 | 1.13× | 386.2× |
| native/io | 54.34 | 52.99 | 52.53 | 1.03× | 1.8× |
| wasm/io | 78.17 | 75.84 | 78.54 | 1.00× | 2.7× |
| native/gc | 298.39 | 270.21 | 255.34 | 1.17× | 109.1× |
| wasm/gc | 485.96 | 436.75 | 430.82 | 1.13× | 179.9× |

LTO helps, but does not close the performance gap. Most of the CPU gain already
comes from Rust-only LTO; sharing the Scheme module adds about 6% native speedup
beyond that. I/O changes are small enough to treat cautiously, especially the
WASI result. The raw report includes every sample and its range. All GC samples
performed collections, and all 128 timed runs passed their checksum checks.

Observed Cargo build costs were approximately 0.8–1.1 seconds without LTO,
1.5–3.3 seconds with Rust-only LTO, and 11–18 seconds for shared native LTO.
Shared WASI LTO took 72–112 seconds per benchmark. These observations include
cache effects and are not matched cold-build timings. Shared LTO therefore
remains an explicit experiment rather than the default build configuration.

## What crossed the language boundary

The CPU probe's optimized Scheme module called `snail_rt_enter` before each VM
instruction. In the linked optimized module, the first such call is replaced by
direct loads of the VM's halted/stress flags and allocation counters, a threshold
comparison, and a conditional call to `Vm::collect`. The subsequent instruction
body is still reachable. This is evidence of actual cross-language inlining,
not merely a missing or renamed symbol.

That optimization removes an ABI call; it does not remove the safepoint's work.
Other service calls remain, as do dynamic primitive dispatch, heap ownership-map
lookups, and builtin objects represented as trait objects. LTO cannot be assumed
to convert those data structures into the proposed direct builtin layout.

## Why the remaining Rust calls did not inline

A follow-up [artifact audit](../benchmarks/results/2026-10-09-inlining.json)
shows substantially more inlining than the single entry-service example above.
These are static call sites in the CPU benchmark's generated `snail_program`,
not execution counts or shares of runtime. Native and WASI have the same counts:

| Rust service | Before shared LTO | After |
| --- | ---: | ---: |
| `snail_rt_enter` | 2,211 | 0 |
| `snail_rt_result` | 898 | 0 |
| `snail_rt_uninitialized` | 814 | 0 |
| `snail_rt_push` | 672 | 0 |
| `snail_rt_slot` | 898 | 381 |
| `snail_rt_call` | 389 | 389 |
| `snail_rt_single` | 717 | 717 |

Replaying LLVM's LTO optimizer on the saved preoptimization bitcode reports
that the large remaining services are too costly to inline. With full cost
diagnostics, native `snail_rt_call` costs 755–950 against a threshold of 250,
`Vm::dispatch` costs 2,655/250, and the generic primitive dispatcher costs
42,350/250. WASI reports the same reason, with slightly different costs. These
numbers are heuristic units, not machine instruction counts. A specialized
primitive-dispatch call has a smaller cost but still exceeds its threshold.

The reasons are visible in the retained code: argument extraction still uses
allocation and copying; procedure lookup still uses the ownership map and
virtual type identification; primitive names are cloned and dispatched through
string comparisons. Inlining those operations does not by itself replace them
with fixed-layout object accesses. The earlier CPU profile predates LTO and
must not be presented as a profile of this residual cost.

The audit distinguishes actual linked-artifact call counts from diagnostics
obtained by replay. To reproduce diagnostics against the saved CPU module:

```sh
opt build/lto/linked/native/cpu/*.0.0.preopt.bc '-passes=lto<O3>' \
  -mcpu=x86-64 -inline-cost-full -disable-output \
  -pass-remarks-output=build/lto/native-inline.yaml -pass-remarks-filter=inline
```

Use `-mcpu=generic` for the WASI module. Matching the target matters: omitting
it from this standalone replay produces misleading attribute-conflict remarks
against Rust's explicit CPU attributes, unlike the actual linked build.

## Matched static fixnum probe

The full-runtime experiment did not implement direct LLVM builtin object
operations. A separate diagnostic now compares checked 32-bit fixnum addition:
[Rust](../tests/codegen-fixnum.rs) against a
[`llvmlite` definition](../tests/emit-codegen-fixnum.scm). Run it with:

```sh
NODE=/path/to/node scripts/check-static-codegen
```

Both functions accept arbitrary `u32` operands, reject non-fixnums and sums
outside the signed 31-bit range, and return a decoded `i64` sum or `i64::MIN`
as an error sentinel. That is a probe ABI, not a proposed Scheme representation.
Identically shaped LLVM callers are retained with `noinline`; their small
implementations receive no forced-inline attribute and are available to shared
LTO. The native command passes LLVM bitcode under an `.o` filename so clang
forwards it to LLD instead of compiling it separately before the link.

Both implementations inline completely into their callers on native and WASI.
The script verifies that those caller definitions remain and contain no calls,
then executes 65,585 boundary and deterministic input pairs against an independent
oracle on each target. Saved caller bodies and hashes are in the audit JSON;
full IR and regenerated target assembly remain under `build/static-codegen`.

The generated instructions are not identical: Rust uses 32-bit signed shifts
and addition before extending the sum; the `llvmlite` version retains wider
shifts and arithmetic. This wrapper currently lacks `sext`, so the probe spells
signed decoding using `zext`, `shl`, and `ashr`. This is an IR-shape difference,
not a surviving Rust call. No timing or equal-performance claim follows from
this small check. It does establish successful Rust inlining for a checked
primitive with dynamic inputs, while leaving boxed-object layouts, allocation,
and the whole-runtime performance comparison for their own experiments.

## Following representation work

Static Rust builtin operations with exposed bitcode remain a viable direction.
Their exact performance must be measured after implementing the intended layouts;
the current-runtime LTO result cannot answer that question on its own. Keep
allocation as an explicit runtime-provided service even if LTO later inlines a
particular implementation. Generated LLVM continues to be composed through
`llvmlite`.

The requested representation reference is `origin/v3` at
`041877ac4e421cab432f198ae563ce8e55743a05`, especially
`inc/ss-core/object.0.hh`, `object.1.hh`, `object.hh`, and `src/ss-core/object.cc`.
Its pair payload has direct `car`/`cdr` fields and its boxed objects carry kind
information. Port those representations rather than designing unrelated ones.
The original explicitly requires 64-bit words: an immediate float32 plus its tag
cannot fit unchanged into 32 bits. Its C++ virtual header and `std::vector`
payload also need explicit Rust/32-bit adaptations. These are unresolved porting
details, not features implemented by this experiment.

The allocation-capability contract is recorded separately in
[Rust interop](rust-interop.md#proposed-allocation-capability): collect outside
allocating Rust callables, never while their unrooted intermediates are live.
`gc_mark` means object-field tracing by the collector, not reference counting.
