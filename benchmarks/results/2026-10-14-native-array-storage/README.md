# Native array storage: same-Wasm bytevector comparison

Storing native arrays at their Wasm element widths reduces `bv2string` workload
time by **5.13%**, from **1.03104 s** to **0.97820 s**. The packed native build
still takes **1.042×** as long as V8 on their exact common optimized Wasm.
This is one workload on one host; it is not a suite-wide native speedup.

| System | Median seconds | Retained range | Samples |
| --- | ---: | ---: | ---: |
| V8, common final Wasm | 0.938474 | 0.937358–0.941498 | 6 |
| Native, eight-byte array slots | 1.031044 | 1.029605–1.033510 | 6 |
| Native, Wasm-width array slots | 0.978197 | 0.978010–0.981035 | 6 |

All 21 scheduled processes passed. The first process per system was excluded
in advance; the remaining rounds cover all six system-order permutations.
No later samples were removed. Full process times, raw stdout/stderr, commands,
identity checks and cleanup outcomes are in [measurements](measurements/).
[summary.json](summary.json) contains the unrounded summaries.

## What changed

Commit `d2e0b13` changes mechanical native lowering and its array helpers. Wasm
i8/i16 arrays use one/two bytes per element, i32/f32 four, and i64/f64/reference
arrays eight. Allocation, indexed access, overlapping copies and static arrays
agree on the stride. Struct fields remain eight-byte slots. Reference scanning,
roots and the public scalar C ABI are unchanged.

Both native executables were built through `build-native --wasm`, including
mandatory Binaryen optimization. [Build identity checks](build-identity.json)
establish byte-identical final Wasm, C provider objects and Rust runtime archives;
the entry source is also unchanged. The shared final Wasm SHA-256 is
`2463c3f837b5133d6a622fe0d690da47cffb464bbda63d2f90f000b27649e41e`.
V8 executes that exact module. The earlier bytevector comparison used a different
once-optimized module for V8, so its V8 times are not reused here.

The complete source, canonical 100 iterations, original 1000/1000 inputs,
numeric failure-count predicate, reset behavior and opacity calls are unchanged.
The native providers retain opacity while omitting diagnostic counters.
The separate strict compiler constant/readiness optimization is absent.

## Separate allocation diagnostic

With allocation statistics enabled, both executables pass the complete workload
and make **801,730** allocation requests. Requested payload bytes, including
object headers, fall from **1,601,725,128** to **512,663,528**, a **67.99%**
reduction. Collections fall from **192** to **62** with the same default heap
policy. The counters cover the whole process; they are not restricted to the
workload clock. Their instrumented durations are excluded from the clean results.

The raw [diagnostic records](diagnostic-validation.json) also retain mark/sweep
times and heap-state counters. Those timings do not isolate allocation, filling,
page touching or mutator access costs. The clean campaign establishes the total
effect of the representation change, not its individual causes. The modest time
reduction despite much smaller payloads is consistent with substantial remaining
computation; it does not measure how much the independent constant-propagation
change will help.

## Checks and focused clarity review

The full native integration suite passed, including shared Rust externs, roots,
callbacks, weak cleanup, I/O and resource ownership. After the final test-only
additions, the semantics subset passed again on raw Wasm, direct native lowering
and the production Binaryen/native path. `make test` and `make check` passed.
[validation.json](validation.json) identifies the retained execution records.

The storage fixtures check physical payload widths, truncation and signed
extension, overlapping copies in both directions, bounds/null traps including
zero-length copies, static identity, mutation, float NaN/negative-zero bits,
operand-stack reference survival during a later allocating operand and permanent
static reference roots. Nondefault f32 constant expressions use the existing
ordinary module-initialization fallback; the test does not claim they are folded
into static storage. Reference arrays keep the layout the collector already scans.

A fresh Astra explainer first reasoned from Wasm array behavior without repository
files or implementation details. Informed critique then checked the proposed
constant-stride layout, widened bounds arithmetic, native byte order, static
identity, initialization and GC lifetimes. Inspection confirmed that the actual
allocation size feeds collector accounting and sweep extents. A per-object stride
field and new GC layout metadata were unnecessary: validated array operations
already know the storage width, and only eight-byte reference arrays are scanned.

The final implementation follows that model directly. The small exhaustive fill
dispatch and test sequences remain cohesive; no additional generic layout layer
was introduced. Review stopped after the operations and lifetime invariants were
explicit and the affected behavior executed successfully.

## Measurement conditions

The [plan](timing-plan.md) and [frozen identities](timing-plan.json) preceded the
[quiet-window release](quiet-window.json). The runner is byte-identical to the
previously reviewed bytevector runner. Processes ran serially on CPU 5, an Intel
Core Ultra 7 270K Plus, with Node 24.19.0/V8 13.6, Binaryen 132 and LLVM 22.1.8.
Agents held builds, tests and compression throughout the approximately 22-second
campaign. Internal clocks exclude setup and include work/JIT triggered during
the benchmark; fresh-process startup is reported separately.

[Before](host-before.json) and [after](host-after.json) host snapshots both show
`intel_pstate` with the `powersave` policy, an 800 MHz–5.5 GHz allowed range and
turbo enabled. Frequency was not fixed. All owned process groups had no executing
members after cleanup; adopted zombies are considered stopped, not reaped by the
runner. Frozen identities were checked before every process and after completion.

The local preserved artifact paths and hashes are recorded with the build and
measurement records. The accompanying archive provides the changed native build,
baseline executable/module, exact host/entry/provider inputs and validation
records; earlier complete source/correctness evidence remains in the linked
[bytevector preparation](../2026-10-14-strict-bv2string-preparation/README.md).

The archive contains 506 regular files, is 6,020,088 bytes, and has SHA-256
`93650be98554d9016e3d18b1d0dc85350c31ef5da98ace41a6b0ebd946922046`.
All archived bytes verified before and after actual relocated full-count runs
of both native executables and common-Wasm V8; their raw correctness records are
in [replay](replay/) and are excluded from the clean timing summary.

Restore and verify without executing workloads:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/native-array-storage-restored \
  --report benchmarks/results/2026-10-14-native-array-storage
```
