# Frozen six-system timing plan

Status: prepared for parent review; **no clean samples have been run**. The
machine-readable `timing-plan.json` supplies exact argv, working directory,
stdin, source/input/artifact/tool identities and the 42-process schedule.
Execution requires the separately coordinated quiet-window release.

All processes use the unchanged input: count 100, 1,000 stress roundtrips,
maximum size 1,000, expected failure count zero. Each process performs 100,100
roundtrips and 300,300 conversion operations. No timer receives a reduced input,
multiplied iteration count or internal warmup. Each sample is a fresh process.

| System | Selected artifact | Workload clock |
| --- | --- | --- |
| Strict Snail / V8 | Production Binaryen-optimized `strict.wasm` | `process.hrtime.bigint()` around `bench(100)` and the host result assertion |
| Strict Snail / native | `timing-native/native`, built from that same optimized Wasm | `CLOCK_MONOTONIC` immediately around `bench(100)` |
| Original source / Chez | `program.so` | Original harness's integer-jiffy interval around its 100 calls and original predicate |
| Adapted source / Chez | `same-source-chez/program.so` | Identical original harness clock boundary |
| Rust / native | Unchanged release `target/release/bv2string` | Original `Instant` around the 100-call loop, assertion, and entry to `report` |
| Rust / Wasm / V8 | Explicit-feature Binaryen `-O3` `bv2string.wasm` | Same original Rust `Instant`, implemented through WASI monotonic time |

Strict V8 file loading, instantiation, main initialization and input construction
precede the start clock. The host's integer result conversion and assertion are
inside this particular clock; JSON output is outside. Use the ordinary host
without `--validate`, so neither setup nor per-call barriers increment counters.

Native host/module initialization, guest main and command-line count parsing
precede its start clock. The guest's acceptance predicate is inside `bench`.
The final clock read precedes JSON formatting, barrier-count reading and
`native_finish` cleanup. Use the non-counting provider artifact; retain and hash
the separate counting provider used during correctness validation. Its two
foreign opacity calls per invocation remain present.

Chez program loading, datum reads, benchmark-name construction, the `Running`
line and its flush precede `j0`. The reported interval includes all 100 thunks,
the final predicate and the ending `current-second` read before `j1`. The
monotonic-jiffy shim uses integer nanoseconds. Elapsed/CSV printing follows `j1`.
Original and adapted programs use the same clock shim and harness.

Rust datum parsing precedes `Instant::now`. Each original loop retains
`black_box` inputs and result; the final expected-result assertion occurs before
`report` reads `start.elapsed()`. Formatting and stdout writes follow that read.
Native and WASI share this unchanged source. V8 module compilation,
instantiation and WASI initialization are outside the Rust workload clock. Raw
Rust and raw Scheme artifacts are retained correctness controls; the table
selects optimized artifacts for measurement.

## Process schedule and validation

Use CPU 5 via the frozen `taskset` executable, default V8 tiering and no
diagnostic/observer host. Reject `NODE_OPTIONS`, `NODE_V8_COVERAGE`, `NODE_DEBUG`,
`NODE_DEBUG_NATIVE`, `LD_PRELOAD`, `SNAIL_NATIVE_GC_INTERVAL`, `SNAIL_GC_STATS`,
`SNAIL_GC_HEAP_BYTES` and `SNAIL_GC_MIN_BYTES` if present, including empty values.
Record those variables, loader search path and locale/timezone settings, and
reject changes from the frozen inherited environment. Confirm CPU availability and
record the host model, frequency governor and affinity before starting. All
agents must acknowledge that compilation, probes, compression, tests and other
measurements are stopped. Run processes serially with no overlap.

One complete six-system round is discarded according to this plan, followed by
six retained rounds. Retained round zero uses the table order; each subsequent
round rotates that order left by one. Every system occupies every retained
position exactly once. There are six discarded and 36 retained process samples.
Keep all samples, including the discarded first round, with explicit labels.
Do not replace outliers or select a favorable subset.

Immediately before every process, check the immutable preparation manifest,
the selected executable/module/host, input/specification, tool binaries and
source identities against `timing-plan.json`. Record command, cwd, affinity,
relevant environment, start time, owned process-group ID and raw stdout/stderr
before parsing. Each process has a 300-second deadline and a separate monotonic
process clock from launch through capture, kill signaling, leader reaping and
the bounded group check. It is diagnostic context,
not the workload clock.

Use the tested supervisor's `start_new_session=True`. Kill any remaining owned
group after normal exit as well as timeout and tolerate an already vanished
leader. Allow at most ten seconds to drain capture, ten seconds to reap the
leader, and five seconds to establish that `/proc` contains no live members of
the owned process group. Zombies count as stopped; this is an executing-process
check, not a claim that all adopted process-table entries have disappeared.
Record this result separately from merely sending SIGKILL. Do not infer cleanup
from closed stdout/stderr. This ownership assumes tools remain in their assigned
group; none of the selected commands intentionally detach.

Require exit zero, empty stderr, exact output framing, a finite nonnegative
elapsed time, and the canonical accepted result. Strict V8 reports result
`"1"` with null barrier fields. Native reports numeric result 1 and barriers 0.
Chez prints its exact `bv2string:1000:1000:100` name and no failure text. Rust
prints `Result: 0` and its exact `bv2string:100` CSV name; its inherited
`rust-wasm` label is used even for the native executable, so identify the system
by the frozen command. Full trace probes and compiler inspection occur outside
the timing window.

Abort on identity drift, timeout, cleanup failure, invalid framing or result.
Retain every started attempt and mark the campaign incomplete; do not publish
complete-campaign medians or silently rerun a failed sample. After a fully valid
campaign, report workload and process medians and ranges over the six retained
samples per system, with all raw samples and the quiet-window record available.
