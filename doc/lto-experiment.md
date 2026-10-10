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
