# Frozen seven-system Matrix timing plan

Status: awaiting parent review and a coordinated quiet-window release. Preparing
this plan does not authorize its clean clocks. One campaign will execute exactly
56 serial fresh processes: one discarded seven-system round followed by seven
retained rounds. Each retained round rotates the first system by one position,
so every system occupies each position once. No in-process warmup or replacement
sample is added. An error aborts and retains the partial campaign.

Every process receives the original count **2,500**, columns **5**, invariant
size **5**, and complete expected five matrices. The frozen artifacts are from
`build/matrix-attempt5` on compiler basis `3dcce40`. The systems are:

| System | Selected artifact and execution |
| --- | --- |
| Snail/V8 | mandatory Binaryen-optimized `matrix/strict.wasm`, clean `host.mjs` |
| Snail/V8, native-final module | exact `matrix/native-timing/native.native-r2n6qggl/optimized.wasm` used to generate native LLVM, same clean host |
| Native Snail | `matrix/native-timing/native`, compiled from that native-final module with non-counting opacity provider |
| Original Chez | compiled `matrix/program.so`, unchanged original kernel and benchmark harness |
| Adapted Chez | compiled `matrix/same-source-chez/program.so`, same typed kernel edits as Snail |
| Native Rust | unchanged reference compiled to `matrix/rust-reference/matrix.native` |
| Rust/Wasm on V8 | explicit-feature Binaryen-optimized `matrix/rust-reference/matrix.wasm`, frozen WASI host |

Rust is a validated algorithm/layout control; its internal program and allocation
strategy differ as described in the preparation report. Raw Wasm artifacts
remain correctness controls and are not selected for this timing campaign.
The native build further optimizes its Wasm input. The production V8 and
native-final modules have different identities; only the second V8 control and
native Snail share the same final Wasm bytes. Production V8 remains the primary
Scheme artifact for the Chez/Rust comparisons. One additional count-2,500
correctness run validates the native-final module on V8 before this plan is
frozen. The superseded six-system plan was never timed.

## Timer boundaries

Both Snail/V8 controls use `process.hrtime.bigint()` immediately before the exported
`bench(2500)` call and ends after checking its result flag in the host. The
complete ordered predicate executes inside `bench`. File input, expected-value
construction, compilation, instantiation and `main` occur before the workload
clock. Printing occurs after it. Both opacity functions are identity calls
without diagnostic counter increments.

Native Snail uses `CLOCK_MONOTONIC` immediately around `bench(2500)`, including
the full result predicate. Module/runtime initialization, expected-value input,
`main` and count parsing are outside that clock. JSON output and native cleanup
follow it. The separately validated provider retains external opacity calls and
has no counter increments; successful output has result 1 and barriers 0.

Both Chez programs use the original common harness's integer-jiffy interval:
`j0` precedes the 2,500-call loop, then the original complete predicate and ending
`current-second` read precede `j1`. Input, expected-data conversion and the
flushed `Running` line precede `j0`; reporting follows `j1`. Both programs use
the same monotonic nanosecond clock adaptation. The shared `t0` wall-style read
also precedes `j0`; only the jiffy result is summarized.

Both Rust programs start `Instant::now()` after parsing all input and expected
data. The loop, per-call `black_box` boundaries and full `assert_eq!` execute
before `report` captures `start.elapsed()`. Formatting the complete matrices and
printing occur after that capture. V8/WASI compilation and instantiation precede
the Rust clock. The historical CSV label says `rust-wasm` for both targets.

The external process clock starts immediately before `Popen` and ends after
output capture, final group cleanup and leader reap. It therefore includes
startup, JIT, output and cleanup that are outside the workload clock. The two
clocks will be reported separately.

## Identities, supervision and acceptance

The machine-readable plan records exact absolute argv/cwd/stdin paths, tool and
artifact SHA-256 identities, the actual native-final Wasm/module.ll/provider
object/Rust runtime archive/build record, complete expected Rust result text, compiler/source
basis, environment, pre-campaign CPU model/governor and available affinity.
Each child is pinned to CPU 5 with `taskset`. Identity checks run before the
campaign, before every sample and after the final sample. The input, artifacts,
runner and plan remain unchanged through the campaign. No build, compression,
archive replay or competing agent benchmark runs in the coordinated window.

The runner rejects inherited `NODE_OPTIONS`, `NODE_V8_COVERAGE`, `NODE_DEBUG`,
`NODE_DEBUG_NATIVE`, `LD_PRELOAD`, `SNAIL_NATIVE_GC_INTERVAL`, `SNAIL_GC_STATS`,
`SNAIL_GC_HEAP_BYTES` and `SNAIL_GC_MIN_BYTES`, including empty values. These are
the native runtime's actual GC controls at the frozen basis. It also records
`LD_LIBRARY_PATH`, locale and timezone and requires the same inherited values
throughout. `BINARYEN_CORES=1` is explicitly recorded, though no compilation
occurs in the campaign.

Each process has its own session/process group and a 300-second communication
deadline. The frozen Matrix supervisor kills the whole group on timeout,
tolerates a vanished leader, allows up to 10 seconds to drain pipes and always
performs a bounded five-second group cleanup. The runner's final block repeats
that cleanup even if capture fails, then allows 10 seconds to reap the leader.
Each cleanup polls `/proc` for executing members; zombie/dead states count as
stopped. Both normal leader exit and timeout receive this treatment, including
children that closed their pipes. A nonempty final group is a failed sample.
This is a bounded group guarantee, not a promise about processes that deliberately
escape the owned session. There are no such benchmark children here.

Every sample preserves argv, cwd, environment, process-group ID, stdout, stderr,
return status, timeout, cleanup and both clocks. Acceptance requires terminal
exit zero, no stderr, a finite nonnegative workload duration and exact output
framing. Snail must return its complete predicate's true flag; Chez must emit its
canonical successful CSV line; Rust must emit every expected matrix element in
order before its successful CSV line. Python validation uses explicit exceptions,
not optimization-sensitive assertions.

Review-only verification starts no guest:

```sh
python3 benchmarks/results/2026-10-14-strict-matrix-preparation/measure-seven.py
```

After the separate release, the one planned campaign is:

```sh
python3 benchmarks/results/2026-10-14-strict-matrix-preparation/measure-seven.py \
  --run --output build/matrix-seven-system-campaign-20261014
```

Preparation validation durations are never included in the campaign summary.
