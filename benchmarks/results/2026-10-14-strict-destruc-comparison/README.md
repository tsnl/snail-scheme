# Complete Destruc comparison

| Variant | Median seconds | Range |
| --- | ---: | ---: |
| Strict Snail on V8 | 3.268198 | 3.258614–3.281674 |
| Original Chez | 0.966358 | 0.953148–0.986220 |
| Adapted-source Chez | 2.432523 | 2.429777–2.440152 |
| Rust/Wasm | 2.800290 | 2.714737–2.876892 |

Strict Snail takes 3.382× original Chez time, 1.344× adapted Chez time and
1.167× Rust/Wasm time on all 4,000 original calls to `destructive(600,50)`.
Adapted Chez itself takes 2.517× original Chez time. Source/helper and
representation changes already have a cost on the same Chez runtime; this
four-system comparison does not attribute the whole original-Chez gap to code
generation or causally isolate Ref cells. Every final predicate checks all ten
rows, all 60 item values and every list end.

## Source, ownership and retained work

The [preparation](../2026-10-14-strict-destruc/README.md) preserves construction
of ten outer nodes, all 600 descending refill/redistribution steps, both length
scans, prefix writes, actual suffix transfers and complete final result. Two
concrete mutable-list instances carry fresh head/tail Refs and empty/integer
Item variants. Rigid All helpers implement access, length, construction and
append. These wrappers, tags, empty objects and accessor/predicate operations
differ from original mutable Scheme pairs and immediate integers. Original
Chez is unchanged; adapted Chez shares the strict source adaptations.

The source fixes the two effectful splice operands in the order observed by
original/adapted Chez diagnostics: source split before target search, followed
by the final tail store. Scheme leaves argument evaluation order unspecified;
disjoint row spines make the final values independent of that choice. The
preparation's 112 executions include complete values, all-node graphs, actual
identity, ordered stores, independent-model and wrong-predicate checks.
Diagnostic registries and observers stay outside the timed artifact.

Exact canonical optimized Wasm retains descending/repeat loops, both consumed
opaque inputs, refill allocations, append/length walks, prefix stores, suffix
stores and the full predicate. Separate function/constructor/store observations
match the independent model at counts 1, 2 and 4,000; they are executed Wasm
sites rather than V8 physical-allocation or performance measurements. The
frozen compiler/build basis is `2def9941eb85f211e116e6955799fdc9ef561da8`, with
all 52 files unchanged. Source/preparation checkpoint
`92a491a4aaec7bc1a880d86204b81ed2cab1ffcb` introduces no compiler changes. Later
String-backend integration checks preserve this kernel and remain separate from
the frozen measured artifact.

Rust uses ten Vec slots with uniquely owned linked Box cells and inline
empty/integer payloads. Actual detached suffix cells transfer without copying;
the existing native pointer test supports that identity. Source and target rows
remain disjoint, permitting unique ownership. Rust mutates the source before
the destination as the explicit strict kernel does, while scanning destination
length earlier. Prompt cleanup traverses discarded Box chains, whereas Scheme
removes references and uses GC. The previous Rust result survives construction
of its replacement; its cleanup is timed.

Rust's final conversion to generic Datum rows, including decimal integer atoms,
and complete equality occur inside timing. Scheme compares its actual returned
rows directly. The final Rust owned rows and datums survive clock capture and
reporting, then clean up afterward. These existing predicate/lifetime differences
are retained. The parent independently restored all 61 Rust handoff blobs,
checked unchanged hashes and executed relocated count-one Rust/original Chez
checks; `parent-rust-handoff-review.json` preserves that record. The handoff also
keeps 33 supplemental complete-value/wrong-output executions and exact optimized
Wasm retention evidence. A fresh mutable-list no-file explanation and complete
runtime identity/allocation trace for Rust remain explicitly unclaimed.

## Timing, artifacts and replay

All 20 clean executions pass: one discarded round and four retained cyclic
rotations, each implementation appearing once in every ordinal position. The
CPU 5 quiet window pauses agent-controlled builds, tests, workloads, profiles
and compression; unrelated system activity remains possible. The driver clears
NODE_OPTIONS, uses fresh processes and default Node 24.19/V8 tiering, and enables
no validation counters or profiler. Chez is 10.4.1. All 115 source/artifact/host/
tool/driver identities match before and after the batch.

Compilation, process startup, input/expected decoding and module initialization
precede workload timing. All repetitions and the full final supplied predicate
are timed. Strict returns acceptance flag `1` after checking the complete rows;
Rust prints the complete matching structure after capturing its stopped clock.
Expected data decoding remains unchanged.
Process elapsed times are recorded separately.

`clean.json`, `freeze.json`, `quiet-window.json` and `measure-matched.py` preserve
the raw records and exact measurement driver byte for byte. `summary.json`
derives the table and ratios from four retained samples per system. No new clean
timings or frozen-program rebuilds were performed while preparing this report.

`artifacts.tar.xz` includes 221 strict-preparation files and all 61 Rust handoff
files: exact source, original input/expected structure, canonical/spec/host,
compiled original/adapted Chez modules, raw/optimized Wasm, 52 compiler/build
files, build/validation records, source patches, independent oracles, separate
retention diagnostics and tool provenance. It also includes raw measurement
records/driver, the independent parent handoff check and an original-path map.
External Nix/system tools are identified by exact path/hash rather than vendored;
the Rust build record's missing verbose rustc log/full inherited environment
remain disclosed in its provenance.

All 290 members restore and hash-verify. Four separate restored count-one
executions pass their complete final predicates, with every member and external
tool still matching afterward. `replay-check.json` records those exact commands,
stdin and outputs; these are correctness probes, not timing samples. The original
input/spec remain count 4,000, with only the separate replay spec/stdin selecting
one repetition. The original two inputs and complete expected rows are retained.

Restore and verify without executing a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/destruc-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-destruc-comparison
```

`manifest.json` checks every member and the archive SHA256. Resolve `files/` and
`replay/` entries from the restored `replay/plan.json` beneath that directory,
retain pinned external tools, and use its cwd/stdin/result contract. A new clean
campaign requires remapped frozen paths, unshortened original input and a
coordinated quiet window; correctness probes cannot enter performance medians.

This adds Destruc to historical strict measured coverage: 30 of 57 workloads
at their recorded compiler checkpoints, including 29 paired Chez comparisons.
Existing String tradeoffs and earlier reports remain unchanged. This is not a
whole-suite rerun or whole-suite performance claim.

`checks.json` records the passing `make check`, inventory/diff checks, raw-record
identity checks and recomputed medians. It keeps the four relocated result
checks separate from the retained clean observations.
