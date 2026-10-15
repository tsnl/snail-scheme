# Complete Lattice comparison

| Variant | Median seconds | Range |
| --- | ---: | ---: |
| Strict Snail on V8 | 1.913494 | 1.910548–1.920355 |
| Original Chez | 1.161967 | 1.159207–1.165932 |
| Adapted-source Chez | 1.272272 | 1.269153–1.276701 |
| Rust/Wasm | 1.054272 | 1.050562–1.057001 |

Strict Snail takes 1.647× original Chez time, 1.504× adapted Chez time and
1.815× Rust/Wasm time for the original ten invocations of `run(44)`, each
returning 120549. All 20 executions pass: one discarded round and four retained
cyclic rotations, with each system appearing once in every ordinal position.
These are measurements of complete source programs with their documented
representations and call/ownership policies, not an isolated compiler comparison.

## Source and retained work

The [preparation](../2026-10-14-strict-lattice/README.md) preserves lower-lattice
materialization, the four preliminary counts, both ordered constraint scans,
recursive enumeration, branch-result lists, summation, destructive reversal and
append's last-tail sharing. Lattices and bindings are parametric products;
mutable lists have closed empty/node variants and explicit Ref tails. Finite
I64 codes replace comparison symbols, with the original membership-list walks
and short-circuit order. Generic operations retain rigid All contracts and
comparator closures. Additional Ref/empty objects and closure/record layouts
change physical allocation costs. The original Chez source is unchanged; the
adapted control shares these source adaptations and list helpers. No compiler
change was introduced by this port.

The preparation records all 36 passing behavior checks, complete small-poset
elements/comparison matrices, branch and callback order, destructive reversal
identity, shared elements and append-tail identity. Its separate instrumented
retention evidence verifies the exact ten full searches and recursive work;
observer modules and probes never enter these timing artifacts. All 52 frozen
compiler/build files match compiler checkpoint
`2def9941eb85f211e116e6955799fdc9ef561da8`. The final r3 source/preparation
checkpoint is `4f1dedc1cdb7fbdeebeb3a6534ff038b4d023afa`.

The frozen Rust reference executes the same monotone-map search and componentwise
partial order, constructs l2/l3/l4 inside each invocation, and retains all four
discarded counts before the selected count. It uses false/true enum leaves,
vectors of Rc elements and persistent Rc assignment tails. One assignment node
combines the source/target binding and previous tail that original Scheme stores
in two cons cells. Direct enum comparison replaces per-lattice comparator closures;
vector selection/flattening replaces list reversal and append, and does not
preserve result-list spine sharing. Target elements and assignment tails remain
shared. Rust promptly reclaims owned/refcounted objects, while Scheme relies on
GC; vector count summation and numeric domains also differ.

Parent independently inspected the actual Rust source, its source-comparison
account and the strict/original source before timing. Historical full-count and
fresh alternate/count-one/wrong-result checks support Rust's scalar predicate.
Exact Rust disassembly retains lower-lattice construction, all four discarded
counts, comparison constraints, recursive search and the outer loop. Rust applies
black_box to the problem, returned count and preliminary counts. No complete
l3/l4 payload or comparison-matrix dump from the timed Rust Wasm is claimed,
and the historical fresh no-file explanation remains pending. These limitations
remain in its frozen handoff rather than being inferred away from a matching
count. Inputs outside the checked canonical domains are not claimed equivalent.

## Timing, verification and replay

The coordinated CPU 5 window paused agent-controlled builds, tests, workloads,
profiles and archive compression. It covered a preceding separate String batch
and this lattice batch; unrelated system activity remains possible. Lattice
ran from `2026-10-14T09:07:33.943159+00:00` to
`2026-10-14T09:08:01.594112+00:00`. The 81 frozen source/artifact/host/tool/driver
identities match before and after every completed batch. Node 24.19 uses default
V8 tiering; NODE_OPTIONS is removed and no profiler or validation counters are
enabled. Chez is 10.4.1. Compilation, process startup and module initialization
are outside workload timing; process elapsed times are recorded separately.

All ten repetitions and each final supplied predicate stay inside their workload
timers. Strict quoted base/tag lists and module inputs initialize before timing;
the lattice constructions and preliminary counts remain per invocation. Rust
allocates its base elements inside each invocation, parses the problem there,
and parses/checks the expected value before clock capture. Original Chez parses
input before its timer. Rust's Result/CSV and the strict JSON formatting follow
clock capture. The report does not add full-result validation to timed work.

`clean.json`, `freeze.json`, `quiet-window.json` and `measure-matched.py` preserve
the raw observations and exact driver byte for byte. `summary.json` derives the
table from four retained samples per system. The joint quiet record's later
resource follow-up belongs to String, not lattice timing. The archive includes
137 preparation files, all 29 Rust handoff files, exact programs/specifications,
original/adapted Chez sources and compiled modules, 52 compiler/build sources,
build/validation/retention records, Node/WASI hosts, measurement driver and a
path map. External Nix/system tools are identified by hash/path rather than
vendored; the Rust historical build lacks a full inherited environment and
verbose rustc log, as its provenance records disclose.

All 174 archive members were restored and hash-verified. Separate count-one
replays of the four restored systems returned 120549, with all member and
external-tool hashes still matching afterward. `replay-check.json` retains
their commands/stdin/stdout/stderr; these are correctness probes, not performance
samples. The original archive input/spec remain count ten. Only the separate
`replay/spec-count1.json` and process stdin select one repetition.

Restore and verify without executing a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/lattice-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-lattice-comparison
```

`manifest.json` checks every member and the archive SHA256. `path-map.json`
preserves the original provenance paths; `replay/plan.json` gives all four
count-one commands with archive-relative paths and unchanged external tools.
Resolve its `files/` and `replay/` paths beneath the restored directory, use the
recorded cwd/stdin and check its expected result/CSV case. A new clean campaign
requires remapped frozen paths and a coordinated quiet window with unshortened
input; replay probes cannot be included in performance medians.

This adds lattice to historical strict measured coverage: 29 of 57 workloads
at their recorded compiler checkpoints, including 28 paired Chez comparisons.
It does not establish whole-suite performance or a full rerun on one compiler.
