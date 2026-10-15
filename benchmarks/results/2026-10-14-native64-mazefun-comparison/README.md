# Current native64 and V8 on full Mazefun

| Executor | Median workload seconds | Range | Median process seconds |
| --- | ---: | ---: | ---: |
| V8, WasmGC | 0.669531 | 0.668314–0.675105 | 0.693473 |
| Native LLVM, in-house Immix | 1.251347 | 1.245028–1.256001 | 1.254139 |

The restored production native64 target takes **1.869× V8's workload time** on
the same optimized Mazefun program, or 86.9% longer. Launch-through-exit process
time gives a ratio of 1.808×. Four retained fresh-process observations per target
each run the original 10,000 iterations at 11 × 11. This bounded comparison
does not identify allocation, root bookkeeping, collection or code generation
as the cause, and does not establish performance across the suite.

## Same production program

The [strict Mazefun preparation](../2026-10-14-strict-mazefun/README.md) supplies
the unchanged source, original canonical input and complete expected grid.
Its source SHA-256 is
`54f0d9483a76b020c248378a2275dc596105e0f259a31a9efcaa9db0efa8c924`.
The program preserves the original `make-maze` algorithm and iteration order,
two runtime dimension barriers per iteration, and the original final predicate:
result kind, row count, row lengths and all 121 cell marks. The 134 imported
expectation carriers describe that complete nested grid; they are decoded during
setup into Scheme lists. The timed predicate traverses those lists after the loop.

Native compiler/runtime sources are frozen at
`37e66db9e0e8315e75d4d81844e02ba5d462346b`. The production command
`scripts/build-native --wasm --entry-c entry.c --c-provider benchmark ...`
consumes the preparation's optimized program and **runs mandatory Binaryen
optimization again**. This changes the artifact from 25,252 to 42,595 bytes;
bounded WAT review records recursive inlining, type/layout changes and dead
closure-field removal. The full diff and opcode counts are retained. Both
executors consume the resulting common bytes:

- Common optimized Wasm:
  `24c2a941a3721de8340f435259cc9184868e81ec0c3ca73a939fa73c10caf442`.
- Native executable:
  `b93d36ca76fdea9e05a6c20f410a9cf417f831b9ad0261e19a03bb8d3b625e10`.
- Earlier preparation Wasm, retained as provenance:
  `90463bc162ca1c78b29bc92f90a18f029fbbf27852bd84a0fa1d5b105b204f0b`.

Native mechanically lowers this common Wasm to LLVM and links the unchanged
precise Immix collector, shared Rust native archive and explicit scalar C
provider. It uses 64-bit managed-reference slots, explicit roots, the default
256-MiB virtual arena and 8-MiB minimum allocation budget, without prefaulting or
forced collection. The pure program imports only `input_i64`, `expected_i64`
and `hide_i64`, so current Node executes the exact common Wasm directly with the
frozen JavaScript host. There is no service or math provider to link on that path.
Historical Mazefun V8 timings use different program bytes and are not reused here.

The C header declares the actual I32/I64 carriers. `benchmark.c` is compiled
separately without LTO: the guest cannot fold its input or identity results
through provider inlining. `benchmark-values.h` carries the verified canonical
grid and is explicitly hashed in the measurement freeze, alongside the provider
and entry. No program-specific primitive emulation or compiler/runtime
optimization was introduced.

## Timing and correctness

One initial V8/native pair is excluded from the summaries but retained and
validated. Four subsequent pairs alternate V8/native and native/V8, giving each
executor two first and two second positions. **All ten outcomes pass** the full
result predicate. Every process is pinned to logical CPU 5 with a fresh working
directory. Agent-controlled builds, diagnostics, tests, profiling, compression
and replay were held. Lightweight source reading/editing and uncontrolled system
or desktop activity remain possible.

Node 24.19.0 uses default V8 tiering. Native uses Clang/LLD 22.1.8; the build uses
Binaryen 132 and the unchanged production Rust provider. Node options, coverage
and debug variables, and native GC/test overrides are cleared. No counters,
tracing or profiling are active in measured processes. Raw commands, status,
stdout and stderr are saved before validation; the campaign has no retries,
replacement samples or outlier removal.

Both hosts initialize the runtime/module and call Scheme `main` before the
workload clock. The clock encloses `bench(10000)` and its host success check;
`bench` includes the complete final grid predicate. Native uses
`CLOCK_MONOTONIC`, then performs terminal cleanup and JSON output after its
clock. Node uses `process.hrtime.bigint()` and includes result conversion and
assertion before stopping its clock, then writes JSON. Process elapsed time is
recorded separately from immediately before subprocess launch through captured
exit. These small host-clock differences remain part of the comparison.

Before timing, plain native and V8 full-count correctness runs passed. Separate
diagnostic executions record **20,000 dimension-boundary calls**, two input
reads and 134 expectation reads. Native cumulative setup/workload snapshots
show that all expectation reads occur before the clock; V8 records zero setup
barriers. Both executors reject a deliberately changed final expected cell.
The native counters and expectation flip exist only in a separately compiled
provider/entry; V8 validation uses the host's diagnostic mode. Their durations
are excluded, and the production executable's identity is unchanged.

These are boundary observations, not current-artifact physical allocation
counts or a census of internal maze work. The earlier preparation retains its
broader source-fidelity, ordered-trace, full-output, predicate and internal-site
checks. Those internal counts describe the earlier input artifact. They are
not attributed to this reoptimized program or to either executor's physical
allocations. No additional internal observer campaign was run.

All **444** frozen source, input, artifact, host, helper and tool identities
match before and after timing. `clean.json` retains every observation;
`summary.json` gives samples, ranges, medians and ratios. The focused independent
explanation and informed critique are recorded in `measurement-review.md`.
Four retained samples per target support a descriptive comparison, without
significance estimates or collector-causality claims.

## Replay

`artifacts.tar.xz` preserves the common Wasm, native executable, original strict
preparation and compiler sources, current native/Rust source inputs, C ABI
provider/header/grid, LLVM, exact Rust archive, build records, WAT diff,
diagnostics and raw timing records. Every archive member is a regular file
checked by the manifest. Pinned tools and dynamic libraries remain external
dependencies with recorded paths and hashes.

```sh
python3 benchmarks/strict-suite/replay.py /tmp/native64-mazefun-replay \
  --report benchmarks/results/2026-10-14-native64-mazefun-comparison
```

Resolve `files/` paths in `replay-plan.json` beneath the restored directory and
keep the pinned external tools/libraries available. Each correctness execution
uses a new directory and retains the full 10,000 × 11 × 11 contract. Actual
relocated execution outcomes appear in `replay-check.json`; their timings are
excluded from the clean campaign. A new performance campaign requires remapped
frozen paths and a new coordinated quiet window.

The production build and all plain workload executions succeeded. Two controlled
negative executions intentionally exit with failure after the changed expectation.
A report-only metadata inspection raised an `AttributeError` while treating the
frozen identity list as a mapping; its error and correction are retained in
`preparation-errors.json`. It did not execute or modify a workload.
