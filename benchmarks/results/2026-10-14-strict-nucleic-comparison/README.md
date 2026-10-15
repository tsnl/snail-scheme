# Complete Nucleic comparison

For all 50 original searches, Snail on V8 takes 0.220574 seconds: 3.359× faster
than original Chez and 3.470× faster than the same adapted kernel on Chez.
Native LLVM takes 0.297789 seconds, 1.350× the V8 time. These are this workload's
results on the frozen compiler, not a suite-wide speed claim.

| System | Median workload seconds | Retained range, seconds |
| --- | ---: | ---: |
| Snail WasmGC / V8 | 0.220574 | 0.219904–0.220798 |
| Snail LLVM / native | 0.297789 | 0.297556–0.300718 |
| Original Chez | 0.740948 | 0.739438–0.744603 |
| Adapted kernel / Chez | 0.765314 | 0.764343–0.766127 |

All 20 fresh-process observations passed the original ratio predicate; no sample
was replaced. One complete four-system round was discarded before four retained
rounds. Retained system order rotates through all four positions exactly once.
Every process uses CPU 5, the original input `50`, `()` and
`33.797594890762724`, and a 30-second process bound. Builds, other measurements
and compression were held by the collaborating agents for this campaign. All
329 recorded file/tool identities matched before and after the complete batch.
Raw outputs, process durations, workload durations, commands and order are in
[results.json](results.json). No Rust timing control is included: its source was
inspected but not validated for this comparison.

## Matched work and timing boundaries

The [complete preparation report](../2026-10-14-strict-nucleic/README.md)
freezes every coordinate and constant, reversible source edits, the untouched
Chez control, the adapted shared kernel, and complete ordered-result checks.
All 50 searches remain. Separate probes check 50 pseudoknot solutions and 179
anticodon solutions with every variable ID, nucleotide identity index and all
transform coordinates. Database, geometry, mutation, signed-zero and numeric
predicate cases pass original/adapted Chez, raw/optimized linked Wasm and actual
native execution. The complete final result agrees exactly; small Wasm
transcendental differences in intermediate coordinates are recorded explicitly.

V8 instantiates the already compiled module and initializes its database before
the workload clock. The clock surrounds only the exported worker, including its
final ratio predicate; output and resource cleanup follow. The native entry
similarly initializes the module and parses count before CLOCK_MONOTONIC begins,
then calls `worker(count)`, stops the clock, prints JSON and performs cleanup.
In the unchanged Chez harness, j0 precedes the repetition loop and j1 follows
successful `ok?` evaluation, so the original predicate is timed there too.
Process startup, loading and initialization remain outside all workload clocks;
process elapsed durations are retained separately.

The timing entry reuses the exact validated LLVM module, the separately compiled
non-LTO scalar provider object, the shared Rust static library and production
link flags. Only clock/output/exit handling changes. Counts 1, 2 and 50 pass,
and expected 30.0 is rejected before the clean campaign. The first entry version
included count parsing inside its clock; its raw preparation remains archived,
and the measured version moves that parsing outside. Production Wasm and native
translation both use mandatory Binaryen optimization. The native preparation
runs Binaryen again and therefore has its own optimized-Wasm identity.

The source uses base variants, mutable F64 geometry vectors and shared assignment
Refs. Original Chez has heterogeneous vectors; adapted Chez uses corresponding
helpers. The additional Ref/product layout and different collector, compiler and
primitive costs remain part of the comparison. Same kernel does not mean equal
allocation or representation cost. The original `math-atan2` branches remain
Scheme code, while sine, cosine and unary atan use the shared scalar Rust library
for both Snail targets. This compiler basis predates the parent's separate empty
constructor-sharing experiment and later Bytevector work.

Static inspection retains the per-iteration call into the complete search and
maximum reduction, and Wasm correctness runs observe all 50 barriers. Complete
ordered solutions plus unchanged traversal/comparison code do not establish
identical rounding-sensitive internal pruning decisions. This result also does
not isolate one allocation, GC or transcendental implementation cost.

## Frozen execution and archive

The reviewed driver rejects and records `NODE_OPTIONS`, `NODE_V8_COVERAGE`,
`NODE_DEBUG`, `NODE_DEBUG_NATIVE`, `LD_PRELOAD` and native GC overrides. All were
absent. A timeout would terminate the owned process group, retain captured
output and stop the campaign without replacement samples. The campaign uses
default V8 tiering and the native collector's default configuration.

The compiler basis is `94787a48e33c416c7f36774e84768d81f15020ce`; upstream is
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. The benchmark driver/helper were
uncommitted during preparation and timing. The archive freezes their actual
bytes, including the helper before its publication-only trailing-blank-line
trim. That trim changes no Python AST or generated Scheme. Exact identities
and the mapping from original absolute paths to archived regular files are in
[identities.json](identities.json). Tool executables are identified by path and
hash; they are not redistributed in the archive.

The archive contains all timed binaries, complete source/input, native entry,
LLVM/provider/runtime inputs, exact original/adapted Chez programs, preparation
records, the reviewed driver/plan and every clean observation. The larger
preparation archive separately retains every compiler failure, diagnostic and
complete-value observation.

Restore and verify every archived regular file without running the campaign:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-nucleic-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-nucleic-comparison
```

The original executed command was:

```sh
python3 build/nucleic-timing-preparation/campaign.py \
  build/nucleic-timing-preparation/campaign-plan.json \
  build/nucleic-timing-preparation/results.json
```

Run only in a coordinated quiet window with the recorded paths restored or
explicitly remapped. The driver refuses to overwrite an existing campaign record.
