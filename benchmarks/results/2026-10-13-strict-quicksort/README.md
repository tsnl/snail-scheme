# Canonical quicksort with strict Wasm and two Chez controls

Strict Wasm takes **24.7% more elapsed time than original Chez** and **26.0%
more than adapted Chez** for the complete canonical quicksort workload in this
quiet window.

| System | Retained median (range), s | Strict / system |
| --- | ---: | ---: |
| Strict Wasm | 2.202591 (2.202343–2.202923) | |
| Original Chez | 1.765799 (1.764360–1.774582) | 1.247362 |
| Adapted Chez | 1.748681 (1.740909–1.758901) | 1.259573 |

[All 12 observations](results.json) pass: one discarded full trio and three
retained rotating trios, fresh processes, CPU 5 and default V8 tiering. Each
retained system occupies each position once. The discarded trio does not warm
the retained processes. No failed, timed-out, shortened or replacement samples
occurred. [Summary](summary.json) independently recomputes the medians, ranges
and ratios. The parent and Rust worker held builds/tests and other CPU work
throughout the authorized [23.432-second window](timing-window.json).

The pinned input remains **2,500 repetitions**, **10,000 elements** and random
values below **1,000,000**, including its unused final `ignored` datum. The
six-state F64 generator prepares one base vector before timing. Each iteration
maps the identity procedure over every element into a fresh vector and sorts
that copy. The final timed predicate checks all adjacent pairs until the first
inversion. Strict's three opacity calls occur before timing. Loading,
instantiation and initialization are excluded; any lazy V8 compilation or
tiering during execution is included.

`quick-1`, `partition`, the RNG arithmetic and all six seed transitions remain
byte-identical. [Preparation](prepared.json) freezes the exact sources and
binaries; its archive includes the extracted original/adapted kernels, exact
source equality proof and complete adaptation patch. Initially false procedure
bindings become concrete refs containing typed trap stubs, with all real
procedures installed before generation. A vector ref preserves seed replacement.
Native numeric conversion bindings sit outside the RNG equations. The element
mapper uses the first mapped value to initialize every fresh vector slot, then
maps/stores elements one through n-1. Those initialization writes are timed in
both strict and adapted Chez. The adapted Chez control shares that mapper,
short-circuit predicate and ref-adapted kernel. Its complete patch records the
mapper name and predicate wrapper edits;
the original Chez program remains intact. Static type knowledge, arithmetic,
representations and host support differ across the systems. Original and
adapted Chez retain the upstream generic `hide`; strict uses pre-timer Boolean
opacity imports and retains static procedure/type knowledge. The comparisons
do not isolate collector, representation, engine or individual-check costs.

[Correctness](correctness-summary.json) records **86 expected outcomes**:
32 positive raw/optimized Wasm checks, 12 expected Wasm rejections, six canonical
Chez checks, and 36 complete-output Chez checks/rejections. Both Wasm artifacts
and both Chez controls execute counts 1, 2 and 2,500 at the original vector size.
Small sorting probes compare every value, multiplicity and length, preserve the
source vector and require fresh copies for nonempty inputs. Empty sorting is a
supplemental case; copy identity and the canonical continuation predicate do not
promise empty-vector behavior. Independent checks cover all 10,000 RNG outputs,
seed reset/read, and first/middle/last adjacent inversions. Changed, shortened
and lengthened expected sort/RNG vectors are rejected by both implementations;
expected length never determines RNG generation length. Correctness runtimes in
the archived command records are not performance samples.

[Static inspection](retention-audit.json) follows the exact optimized timed path:
the repeat loop calls a mapper that allocates an I64 array and visits each source
element, then calls the recursive sort. It retains both directional scans,
partition swaps/pivot restoration, the smaller-partition branch and the final
adjacent loads/checks. There are no `array.copy` instruction sites. The RNG's two
F64 truncations and six seed stores remain in untimed initialization. These are
static instruction sites, with no V8 machine-code, tier attribution or dynamic
instruction/allocation counts. The canonical sortedness predicate alone does
not prove permutation preservation; opacity-call counts do not establish work
retention.

[History](preparation-history.json) preserves three failed preparations and
their corrections: an imported `vector-map` name conflict, an empty-vector copy
identity assumption, and a supplemental Chez RNG oracle that accepted a shortened
correct prefix because it generated according to expected length. The archive
keeps each failed source, binary and command result. All corrected checks pass;
these failures occurred during preparation, before the clean timing batch.

All **51 compiler files** match preparation compiler base
`5894df771cace27507e0f1ab15f6dd320d2a6ad4` byte-for-byte. Timing uses driver
commit `86d49d4d7f36b00f48724f3fe63854a2afe2413d`; these are separate provenance
identities.
[Identity](compiler-identity.json), [environment](environment.json) and
[metadata](measurement-metadata.json) preserve source/tool hashes and default
Node 24.19.0 / V8 13.6.233.17-node.51, Binaryen 132 and Chez 10.4.1 at level 2.
The runner/parser, Python and taskset are frozen too.
[Regression checks](prior-port-regression.json) show all 18 previous case
specifications and generated strict sources unchanged.
[Independent review](independent-review.json) records the parent's fresh
no-files Sol explanation/debate and subsequent source/hash review, accepted
before timing. It kept the cohesive RNG transition and protocol helpers without
manufactured refactoring. All 443 preparation files were independently restored
and hash-verified by the parent; the [neutral behavioral brief](simplify-behavioral-brief.md)
is preserved.

[Coverage](coverage.json) reconciles **20 passing measured ports/slices**, the
prior Ackermann default-stack failure and **36 unported** workloads out of 57.
Historical reports stay intact; no full-suite mean is reported.

Restore and verify the complete archive from the repository root:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-quicksort-replay \
  --report benchmarks/results/2026-10-13-strict-quicksort
```

[Replay checks](replay-check.json) preserve the eight bounded preparation-stage
raw/optimized Wasm and original/adapted Chez executions and verify every file in
the expanded final archive. The unchanged timed payload hashes still match
preparation. The archive includes all failed preparations, corrected checks,
exact binaries, compiler/tool identities, static audit and complete observations.

To repeat timing after coordinating another quiet window, use the recorded
driver version matching the hash in restored `prepared.json`:

```sh
env -u NODE_OPTIONS python3 benchmarks/strict-suite/measure.py measure \
  --output /tmp/strict-quicksort-replay/strict-quicksort-frozen-final-5894df7 \
  --cpu 5 --rounds 3
```

This overwrites only the restored `results.json`; the archive retains the
original observations.
