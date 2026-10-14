# Prepared canonical quicksort strict port

The complete quicksort port passes correctness checks and static inspection of
its optimized Wasm. **Independent review and quiet-window timing are pending.**
There are no performance observations, medians or speedup claims in this report.

The pinned input remains **2,500 repetitions**, **10,000 elements** and random
values below **1,000,000**, including its unused final `ignored` datum. The
six-state F64 generator prepares one base vector before timing. Each iteration
maps the identity procedure over every element into a fresh vector and sorts
that copy. The final timed predicate checks all adjacent pairs until the first
inversion. Strict's three opacity calls occur before timing. Loading,
instantiation and initialization are excluded; any lazy V8 compilation or
tiering during execution will be included.

`quick-1`, `partition`, the RNG arithmetic and all six seed transitions remain
byte-identical. [Preparation](prepared.json) freezes the exact sources and
binaries; its archive includes the extracted original/adapted kernels, exact
source equality proof and complete adaptation patch. Initially false procedure
bindings become concrete refs containing typed trap stubs, with all real
procedures installed before generation. A vector ref preserves seed replacement.
Native numeric conversion bindings sit outside the RNG equations. The adapted
Chez control shares the element mapper, short-circuit predicate and ref-adapted
kernel. Its complete patch records the mapper name and predicate wrapper edits;
the original Chez program remains intact. Static type knowledge, arithmetic,
representations and host support differ across the systems.

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
no timing attempts occurred.

All **51 compiler files** match
`5894df771cace27507e0f1ab15f6dd320d2a6ad4` byte-for-byte.
[Identity](compiler-identity.json), [environment](environment.json) and
[metadata](measurement-metadata.json) preserve source/tool hashes and default
Node 24.19.0 / V8 13.6.233.17-node.51, Binaryen 132 and Chez 10.4.1 at level 2.
The runner/parser, Python and taskset are frozen too.
[Regression checks](prior-port-regression.json) show all 18 previous case
specifications and generated strict sources unchanged. The parent will use the
[neutral behavioral brief](simplify-behavioral-brief.md) for a fresh independent
simplify explanation and code review before timing.

[Coverage](coverage.json) retains **19 passing measured ports/slices** and the
prior Ackermann default-stack failure. Quicksort is prepared and pending
measurement; **36 workloads remain unported**. Historical reports stay intact.

Restore and verify the complete archive from the repository root:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-quicksort-replay \
  --report benchmarks/results/2026-10-13-strict-quicksort
```

[Replay checks](replay-check.json) verify every archived file and execute bounded
raw/optimized Wasm and original/adapted Chez behavior checks using the same
binaries. The recorded driver hash must match before a later measurement. After
independent review and coordinated quiet-window authorization, the planned batch
is one discarded full trio and three retained rotating trios, fresh processes,
CPU 5 and default V8 tiering. No shortened or replacement samples are allowed.
