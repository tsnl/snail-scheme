# Frozen seven-system reader comparison

The plan runs complete Sum1 at count 25 and complete Read1 at count 2,500.
For each workload, the seven systems are production linked Wasm on V8, V8 on
the exact native-final Scheme module with a separate Rust/WASI provider,
native execution of that Scheme module with native Rust scalar exports,
original Chez, adapted Chez, optimized Rust/Wasm on V8 and Rust native.

`timing-plan.json` freezes 112 fresh processes. Each workload has seven
predetermined discarded processes followed by seven retained rounds. Each
retained round rotates the seven systems by one position, so every system
occupies every position once. Sum1's complete campaign precedes Read1's.
All samples run serially on CPU 5 with a 120-second per-process bound.
There are no replacement samples or post-hoc exclusions. A failure retains the
partial campaign and stops execution for inspection.

The workload clock surrounds the original count loop and final predicate.
Configuration parsing, module initialization and compilation are before it;
output formatting and terminal cleanup are after it. Every counted worker's
real file open, character/datum reads through EOF and close remain inside it.
V8 uses `process.hrtime.bigint` around the exported bench call, including that
call's argument/ABI transition. Native uses `clock_gettime(CLOCK_MONOTONIC)`
around the same bench call. Chez retains the original harness's jiffy clock and
predicate placement. Rust retains its existing `Instant` start and elapsed
report boundary, including its original initial-result construction and final
assertion. Both Rust algorithms/storage representations remain separate
controls as described in the preparation report.

The additional process clock starts immediately before `Popen` and ends after
capture, intermediate status recording, leader reaping and bounded process-group
cleanup. It includes supervision and those record writes, not just the child's
own lifetime. Cleanup sends SIGKILL to owned survivors, tolerates a vanished
leader, and checks `/proc` for no executing group members; zombies count as
stopped. An interrupted or failed process never becomes a valid sample.

The native opacity provider is compiled without counter increments. Existing
native runtime resource/array/root-depth bookkeeping remains at the frozen
default basis. Both native-final Wasm files, their generated LLVM, provider
objects, native executables and native Rust archive are identified separately
from the production linked Wasm modules. Only the Scheme module is identical
in the native/V8 module control. Target-specific Rust provider and linkage
differences remain explicit.

The runner checks frozen identities and the recorded inherited environment
before every sample and after the campaign. It rejects `NODE_OPTIONS`,
`NODE_V8_COVERAGE`, `NODE_DEBUG`, `NODE_DEBUG_NATIVE`, `LD_PRELOAD`,
`SNAIL_NATIVE_GC_INTERVAL`, `SNAIL_GC_STATS`, `SNAIL_GC_HEAP_BYTES` and
`SNAIL_GC_MIN_BYTES`. It records the CPU model, affinity, governor, frequency
policy, sibling topology and load immediately before and after the campaign.
The OS file cache is uncontrolled and already warmed by preparation/discard
runs; fresh processes do not imply cold files or warmed retained V8 instances.

Running `python3 measure-seven.py` only verifies the freeze. Execution requires
the parent's explicit coordinated quiet-window release and a new output path:

```sh
python3 measure-seven.py --run --output /tmp/NEW-READER-CAMPAIGN
```

Every stdout/stderr, exit status, timeout/cleanup result, exact command,
environment, order, workload time and process time is retained. Strict outputs
must return the original predicate flag; native also checks exact file-close
counts. Chez output framing must report success. Rust output must match the
complete validated sum or ordered list before its timing record. Medians and
ranges use only the seven predetermined retained samples per system/workload.
