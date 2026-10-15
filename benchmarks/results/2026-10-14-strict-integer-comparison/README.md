# Complete exact-integer comparison

All **144 planned processes pass** the complete pi and Chudnovsky results.
Production Snail/V8 takes **10.497× original Chez time for pi** and **8.264×
for Chudnovsky**. Native takes **19.88% and 8.28% less time** than V8 executing
the identical native-final Scheme Wasm. The new Integer library is functional,
but these workloads expose a substantial performance gap against native bigint
implementations.

## Workload medians

Each median uses eight retained fresh processes. One predetermined process
per system/workload is discarded; every discarded result is also validated.

| System | Pi (s) | Chudnovsky (s) |
| --- | ---: | ---: |
| Snail / production Wasm / V8 | 2.243027 | 0.716851 |
| Snail / native-final Scheme Wasm / V8 | 2.225084 | 0.718222 |
| Snail / native64 | 1.782729 | 0.658789 |
| Original source / Chez | 0.213676 | 0.086746 |
| Adapted source / Chez native bigints | 0.213659 | 0.086244 |
| Same checked limb library / Chez | 44.629659 | 12.012418 |
| Rust / native | 0.127835 | 0.052900 |
| Rust / optimized Wasm / V8 | 0.434312 | 0.177955 |

| System | Pi retained range (s) | Chudnovsky retained range (s) |
| --- | ---: | ---: |
| Snail / production Wasm / V8 | 2.229252–2.259311 | 0.711601–0.730296 |
| Snail / native-final Scheme Wasm / V8 | 2.200078–2.245079 | 0.712792–0.722948 |
| Snail / native64 | 1.780806–1.787924 | 0.657918–0.659698 |
| Original source / Chez | 0.213227–0.214742 | 0.086406–0.086920 |
| Adapted source / Chez native bigints | 0.213375–0.213857 | 0.085982–0.087204 |
| Same checked limb library / Chez | 44.517027–44.669409 | 11.933600–12.119401 |
| Rust / native | 0.127593–0.128265 | 0.052766–0.053541 |
| Rust / optimized Wasm / V8 | 0.432509–0.435838 | 0.176653–0.179365 |

Ranges are observed minima/maxima, not confidence intervals. Full-precision
medians, ranges, process durations and ratios are in
[`independent-review.json`](independent-review.json). Snail/V8 takes 5.165×
Rust/Wasm time on pi and 4.028× on Chudnovsky. The common-module native/V8 time
ratios are 0.8012 and 0.9172; provider targets and linkage still differ.

## What the controls establish

The original and adapted native-bigint Chez results are close. The recorded
source adaptations preserve the numerical work on these inputs without a large
observed timing change in that control. Strict Scheme instead uses the reusable
Integer library: immutable nominal values backed by private I32 arrays of
30-bit limbs, I64 intermediates, schoolbook multiplication, normalized long
division and integer square-root iteration.

The same-limb Chez control executes that arithmetic body with general Chez
vectors/scalars and explicit I32/I64 range checks. Snail's concrete arrays and
proved machine arithmetic have different costs. Its much slower result therefore
does not isolate a compiler advantage. It helps expose the importance of the
arithmetic implementation and its scalar/storage boundary.

Rust uses the independent reference and `num-bigint` 0.4.8. Bounded precision
and term controls use u32; the full Chudnovsky constant cube stays u64. It retains
`black_box`, native allocation/ownership and its own bigint implementation.
These are useful complete-workload controls, with different representations
and arithmetic. No run here measures time inside individual operations or
collection. Profiling and isolated library changes are needed to attribute the
remaining gap.

## Complete work and timing boundaries

Inputs remain the pinned upstream suite at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Pi performs all **100 repetitions**,
all three original algorithms, and ten precision rows from 50 through 500
digits. Every original rounding-difference column is preserved. Chudnovsky
performs all **1,000 repetitions**, complete binary splitting and all ten exact
results. The strict/adapted sources have recorded explicit conversions,
constant lifting and square-root extraction; original Chez uses the unchanged
source. Full ledgers are in the
[arithmetic preparation](../2026-10-14-strict-integer/README.md).

Input and expected-value parsing, module initialization and expected conversion
precede each workload clock. The original repetition loop and one final complete
numerical predicate are inside it. Decimal rendering follows it. Three Scheme
scalar opacity calls per iteration remain inside the clock and their returned
arguments feed the real numerical work. Process time separately includes launch,
initialization, output and supervision; its difference from workload time is not
a measurement of pure startup.

The [control preparation](../2026-10-14-strict-integer-controls/README.md)
retains count 0/1/2/full tests, rejected mutations of the first and last expected
components, and separate probes observing every complete iteration. Its
optimized Wasm, V8 code captures and native disassembly retain both repetition
loops and numerical paths. Those instrumented probes and captures are separate
from this campaign's production artifacts.

## Coordinated execution and evidence

The window ran from **2026-10-14 20:02:28.978 UTC to 20:12:36.826 UTC**,
607.848 seconds. Other active agents held builds, guest execution, profiling,
compression and publication; static review/editing continued. The coordinator
polled the actual owned tool session to terminal exit zero before releasing
the holds. This coordination does not claim an otherwise idle operating system.

Guests ran serially on CPU 5, with default V8 tiers and GC policy. Eight retained
rounds rotate the system order so each system occupies every position once per
workload. Pi precedes Chudnovsky. There are 16 predetermined discards and 128
retained processes, no replacements or retrospective exclusions. Every capture
has successful exit, complete expected output, one finite clock, empty stderr,
no timeout and completed owned-process-group cleanup. Immediate before/after
CPU policy and affinity agree; this does not establish fixed frequency.

The [reviewed timing preparation](../2026-10-14-strict-integer-measurement-preparation/README.md)
freezes 107 identities, all sixteen exact commands, the complete eighteen-module
supervisor closure and environment guards. All remain unchanged after the run.
The independently written [`review.py`](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-integer-comparison/review.py) rechecks all 144 individual
records, complete result framing, command/environment/schedule fields, cleanup,
balanced positions and medians against the recorded campaign summary. It also
checked every live frozen identity before packaging.

These are the previously prepared artifacts, including the native allocator
inlining annotations. Integrating their reports at `7479b2f` and preparation at
`610b21e` does not replace them with new builds. Exact source, compiler and tool
identities are retained in the preceding control archives. The pinned tools are
Node 24.19.0 / V8 13.6, Binaryen 132, Chez 10.4.1, Rust 1.95.0 and Clang/LLD
22.1.8. Every timed Scheme and Rust Wasm has passed through Binaryen.

`artifacts.tar.xz` contains every raw process record, host snapshots, plan,
runner, frozen supervisor sources and independent review. `manifest.json`
identifies every member and the four existing control archives containing the
executables, original/adapted sources, LLVM, inputs and preparation evidence.
No new copies of those control archives are required. Verify the measurement
bundle without launching any guest:

```sh
python3 -I -B benchmarks/results/2026-10-14-strict-integer-comparison/package.py
```

After unpacking the verified bundle, `review.py CAMPAIGN PREPARATION` recomputes
its results without the original absolute paths. `--check-live-identities`
additionally requires every frozen tool/artifact at its recorded path. Execution
replay requires those pinned dependencies and an explicit quiet window.

This adds pi and Chudnovsky to historical strict coverage: **41 of 57 measured
workloads**, **40 with paired Chez controls**, across separate compiler
checkpoints. It is not a complete-suite rerun on one compiler revision.
