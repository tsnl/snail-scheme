# Complete Ackermann comparison

All **56 planned processes pass** both original repetitions of `ack(3, 12)`,
with expected result `32765`. Production Snail/V8 takes **1.350× original
Chez time**. Native64 takes **32.04% less time than V8 on the identical
native-final Scheme Wasm**, and **7.76% less time than original Chez**.

## Workload medians

Each median uses seven retained fresh processes. One predetermined process
per system is discarded; every discarded result is also validated.

| System | Median (s) | Retained range (s) |
| --- | ---: | ---: |
| Snail / production Wasm / V8 | 1.109322 | 1.107966–1.291769 |
| Snail / native-final Scheme Wasm / V8 | 1.115234 | 1.106426–1.137488 |
| Snail / native64 | 0.757917 | 0.753577–0.761433 |
| Original source / Chez | 0.821724 | 0.812388–0.833238 |
| Rust / native / recursive | 0.864765 | 0.863853–0.865373 |
| Rust / native / explicit heap frames | 0.487954 | 0.487062–0.492907 |
| Rust / optimized Wasm / explicit heap frames / V8 | 1.872123 | 1.599396–2.285956 |

Ranges are observed minima/maxima, not confidence intervals. Every planned
sample remains, including the wider Rust/Wasm range and slower production-V8
observation. Full-precision workload/process statistics and ratios are in
[`independent-review.json`](independent-review.json).

Rust's recursive native implementation is a separate control from its existing
heap-frame implementation. Recursive Rust/Wasm still exceeds the default V8
stack on this full input; those failures remain in the
[correctness preparation](../2026-10-14-strict-ack-preparation/README.md).
Its heap-frame control uses an explicit pending-work vector. It is not a
successful recursive Rust/Wasm run. Scheme retains the original recurrence,
inner recursive call and tail update; these controls do not isolate code
generation from their different control flow and stack representation.

## Complete work and clock boundaries

The input remains the pinned upstream suite at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`: two repetitions, arguments 3 and
12, complete result 32765. No smaller input, closed formula, increased stack
or replacement algorithm is used for Scheme. The generated source and input
are byte-identical to the earlier experiment. The archived older optimized
Scheme artifact still fails under the current host; no causal bisect identifies
which intervening compiler change fixed that failure.

The [preparation](../2026-10-14-strict-ack-preparation/README.md) retains
raw/optimized Wasm and actual native correctness, additional runtime argument
cases, barrier observations, and disassembly retaining the recurrence. Native
uses the current allocator visibility changes. Its Scheme module passes through
mandatory Binaryen before both V8 execution and mechanical LLVM lowering.
Provider target and linkage still differ between the two executors.

Input parsing and module initialization precede each workload clock. Scheme/V8
includes the final assertion and `result.toString()`; native compares I64 values
inside its clock, then formats and cleans up afterward. Chez retains the
original recurrence and numeric predicate; its success frame does not print
the result. Rust retains its argument selection, recurrence and assertion,
then prints the result. Scalar opacity imports and Rust's `black_box` preserve
their documented different optimization boundaries. Process time separately
includes launch, initialization, capture and cleanup; subtracting workload time
does not measure pure startup.

## Coordinated execution and evidence

The window ran from **2026-10-14 20:27:05.975 UTC to 20:28:17.204 UTC**,
71.229 seconds. Other active agents held builds, guest execution, profiling,
compression and publication; static review/editing continued. The coordinator
polled its actual owned session to terminal exit zero, then independently
checked every record and frozen identity before releasing the next campaign.
This coordination does not claim an otherwise idle operating system.

Guests ran serially on CPU 5 with default V8 tiers, stack and GC policy.
Seven retained rounds rotate the systems so each occupies every position once.
There are seven predetermined discards and 49 retained observations, with no
replacements or retrospective exclusions. Every process has successful exit,
complete expected output, finite positive clocks, empty stderr, no timeout,
and completed process-group cleanup, leader reap and capture-handle closure.
Immediate before/after CPU policy and affinity agree; this does not establish
fixed frequency.

The [timing preparation](../2026-10-14-strict-ack-measurement-preparation/README.md)
freezes 250 identities, all seven exact commands and the complete eighteen-module
supervisor closure. All identities remain unchanged after the run. Its new
diagnostics validate explicit working-directory/stdin/environment settings;
the missing metadata in some older preparation records remains disclosed.

The independently written [`review.py`](review.py) rechecks every raw record,
complete output, schedule, commands, environment, cleanup and balanced medians.
A focused pinned simplify pass used a fresh explanation without code access,
followed by a boundary/identity review. The adjacent manifest and fixed directory
replay suffice; no generic archive reader is needed. Exhaustive frame dispatch
and the complete audit operation remain cohesive despite exceeding ten lines.
`artifacts.tar.xz` contains all raw records, host snapshots, the frozen timing
plan/runner/supervisor and independent review. Its adjacent `manifest.json`
identifies every member and the existing correctness archive containing the
executable controls. Verify the measurement archive without launching guests:

```sh
python3 -I -B benchmarks/results/2026-10-14-strict-ack-comparison/package.py
```

After unpacking the verified archive, `review.py CAMPAIGN PREPARATION`
recomputes the result without the original absolute paths. The additional
`--check-live-identities` option requires every frozen artifact at its original
path. Execution replay requires the pinned tools and a separately coordinated
quiet window.

This adds Ackermann to historical strict coverage: **42 of 57 measured
workloads**, **41 with paired Chez controls**, across separate compiler
checkpoints. It is not a complete-suite rerun on one revision.
