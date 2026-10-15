# Strict array1 vectors against original Chez, October 13

The strict typed port of pinned upstream `array1` takes **5.279 seconds**
against **6.800 seconds** for the original compiled Chez program, about
**22.4% less elapsed time** in this paired window. The original workload stays
`go(500, 1000000)`, with one outer harness invocation and expected result
`1000000`. Exact Wasm and V8 code retain its allocation, fill, and copy work.

| Workload | Strict Wasm median | Original Chez median | Strict / Chez time |
| --- | ---: | ---: | ---: |
| array1 | 5.278793 s | 6.799784 s | 0.776318× |

Retained ranges are 5.230716–5.331047 seconds for strict and 6.776265–6.863444
seconds for Chez. Node 24.19.0 / V8 13.6.233.17, Binaryen 132, and Chez 10.4.1
at optimization level 2 run in fresh processes on CPU 5 of an Intel Core Ultra
7 270K Plus, with default V8 tiering. The discarded pair is strict/Chez;
three retained pairs follow as Chez/strict, strict/Chez, Chez/strict. All four
pairs give a 2:2 balance of the first system; the retained set gives 2:1.
Parent builds and tests finished before the authorized quiet timing window.

All eight full-size observations pass, with no failures, timeouts, shortened
counts, or replacement samples. Eight raw/optimized preparation checks also
pass, covering empty and singleton vectors, repeated copying, and zero repeats.
[Raw observations](results.json), [summary](summary.json), and
[environment](environment.json) preserve commands, outputs, process/workload
times, tool paths and hashes, and configuration.

## Source and timing

The port preserves the increasing fill loop, decreasing element-by-element
copy loop, and inner repeat loop. It adds explicit zero fills to both
`make-vector` calls and changes `go`'s initial empty-list result to I64 zero.
The original positive count replaces that initial result; zero and negative
repeat counts differ from upstream and are outside the equivalence claim.
All original integer values and intermediates fit I64. Storage is inferred as
`Vector I64`, one mutable WasmGC array of native I64 elements.

Inputs load before the strict timer. The two original hide sites use typed
scalar identity imports inside it. One `bench(1)` call, all 500 vector passes,
opacity calls, and final scalar validation are timed. Chez preserves its
complete original kernel, hide, timed harness, compatibility prelude, and
result predicate. Startup, compilation, and instantiation are excluded;
runtime tiering and collection remain included. Harness and numeric-type
differences prevent isolating collector or inference performance from this ratio.

## Retained work and limits

The [code audit](code-audit.json) binds findings to exact artifact hashes.
Optimized Wasm retains two allocation sites in the inner repeat worker,
increasing indexed stores, decreasing indexed loads/stores, and all repeat
branches. A separate full-size default-tier V8 diagnostic on the exact timed
Wasm emits Liftoff allocation and zero-initialization loops, plus Liftoff and
TurboFan versions of both element workers. TurboFan keeps eight-byte indexed
loads/stores, index steps, and tail jumps. No bulk-copy substitution or
elimination was observed. Environment casts, readiness checks, and closure
loads remain. Static code does not measure dynamic allocation/instruction
counts, time by tier, or the cost of individual checks.

A same-source level-2 Chez diagnostic using
[`#%$assembly-output`](https://github.com/cisco/ChezScheme/blob/main/s/cpnanopass.ss)
retains two `make-vector` calls and the fill, copy, and inner repeat loops.
Its object differs from the timed object; two normal same-option recompilations
also differ. The archive preserves this identity limit and every object/command;
no instruction-identity claim is made for the timed Chez binary.

Historical [complete-suite observations](../2026-10-12-native-v8/summary.csv)
record old Wasm at 10.666520 seconds and Chez at 6.864126 seconds. Current strict
is about 2.02× faster than that old Wasm result, from source revision `5c277ab`
and a different window. This context does not attribute the change to vectors alone.

## Provenance, coverage, and replay

Frozen feature `1a4d2e204d86b8c7ce32f325e7c159cab4637c5d` is cherry-picked as
measurement commit `d47d1d5cf55b31e34808fb41910b6cf22ec80ad9`. All 50 compiler
source/build files match the feature byte-for-byte; [identity](compiler-identity.json)
and snapshots preserve their hashes. Upstream is clean at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. The
[focused review](review.md) records the bounded simplify pass.

[Cumulative coverage](coverage.json) is 13 measured strict ports or slices:
this array workload, ten prior kernels, and separate `cat`/`wc` slices.
Ackermann's prior default-stack failure remains visible; 43 of 57 workloads
remain unported. Historical reports stay unchanged; no full-suite mean is added.

The archive and manifest preserve original/generated sources, exact inputs,
compiler snapshots, raw/optimized Wasm, Chez objects, disassembly, tools/hashes,
and all observations and checks. Restore and verify every file with:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-array1-replay \
  --report benchmarks/results/2026-10-13-strict-vector-array1
```

[Replay checks](replay-check.json) verify restoration and execute raw/optimized
Wasm and the original Chez payload with small behavior inputs. Original-size
inputs and timed payload hashes remain intact. To rerun the complete paired batch
with the recorded tools, run this from the repository root; it overwrites
restored `results.json`:

```sh
python3 benchmarks/strict-suite/measure.py measure \
  --output /tmp/strict-array1-replay/strict-array1 --cpu 5 --rounds 3
```
