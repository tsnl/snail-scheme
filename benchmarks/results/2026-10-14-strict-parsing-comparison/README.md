# Complete Parsing seven-system comparison

The complete canonical **2,500 parses of the 28,300-byte input** pass on all
seven systems. Production Snail on V8 takes a median **2.361375 seconds**;
native64 takes **1.481803 seconds**. Native takes **38.0704% less time** than
V8 executing the exact optimized Wasm consumed by native lowering. Original
Chez takes **1.195848 seconds**, and the unchanged Rust native reference takes
**0.626001 seconds**.

| System | Median seconds | Minimum–maximum seconds | Median / original Chez |
| --- | ---: | ---: | ---: |
| Snail production linked Wasm on V8 | 2.361375272 | 2.339855802–2.409878979 | 1.974645 |
| Snail native64 | 1.481803339 | 1.454220037–1.513300287 | 1.239123 |
| Snail exact native-final Wasm on V8 | 2.392722683 | 2.349865758–2.420172026 | 2.000858 |
| Original Chez | 1.195848294 | 1.191951946–1.204230809 | 1.000000 |
| Exactly adapted Chez | 1.971950837 | 1.962102439–1.984540812 | 1.648997 |
| Rust native | 0.626001002 | 0.617839269–0.630025323 | 0.523479 |
| Rust Binaryen-optimized Wasm on V8 | 0.759768657 | 0.747129069–0.768416944 | 0.635339 |

Each row retains all seven observations. Ratios divide medians without
intermediate rounding and describe this workload on one host. These cyclic
rotations balance positions, without an adjacency-balance or statistical-
confidence claim. Preparation clocks supply no clean performance samples.

This adds one complete benchmark to historical measured coverage: **47 of
57**, including **46 original-Chez-paired comparisons**. Those accumulated
results span successive compiler revisions. This campaign freshly measures
Parsing at the basis below; it does not remeasure the preceding coverage.

Compiler/library/collector basis is
**8930aaa66961a65f118e40513bf072c5607961a0**. The isolated worktree retains
that basis, including the growing precise native collector. Newer numeric or
compiler-foundation changes are outside this frozen campaign. The timing host
adds the narrow scalar UTF-8 interface described below; its uncommitted diff
and actual bytes are retained explicitly.

## Original input and timed boundary

The original **2,500 parses** use the complete **28,300-byte file** and final
proper-list predicate **`(should return this list)`**. One timed worker loads
the complete file with the original list-based character loader, reverses the
character list and builds the string, then runs the original generated scanner
and recursive LL(1) grammar 2,500 times. Its original final predicate compares
the last result, including every symbol and the proper ending. No per-parse
assertion was added. Configuration and expectation setup precede timing;
data loading, its port close and final predicate remain inside it.

Canonical configuration SHA-256 is
`54a0dc1122568ac11949b12d4afb421c19193445dcd69bdbfd20e5bf25d17d65`.
Data SHA-256 is
`839b948cd52f26d0873a60087dfe99038d2f6ef985a044ad32d431c45c40fdd8`.
Fresh regeneration reproduces all eight complete current source/input files
from the reviewed integration at 4c191323d08272591fc1346fdb1cbd53fa464b70.

The [separate correctness preparation](../2026-10-14-strict-parsing-preparation/README.md)
documents the counted reversible source edits, original scanner quirks,
identity/reset observations and bounded numerical domain. Its historical
author basis is 45214e3. Current compiled Wasm is byte-identical to the parent's
fresh reviewed integration, with all 42 scanner states and original control
flow retained. Ordered observations and source-operation counters remain
diagnostic evidence and contribute no clean timings.

## Seven controls and current preparation

The seven systems are production Binaryen-optimized linked Wasm on V8,
native64, V8 on the exact native lowering input, original Chez, exactly adapted
Chez, Rust native and Rust Binaryen-optimized Wasm on V8. Native mechanically
lowers the actual optimized Wasm to LLVM with the current collector. All
production Wasm paths retain mandatory Binaryen.

Native and both Chez artifacts were freshly built from the frozen current
sources. Adapted Chez contains the identical typed parser kernel and current
Datum/reader bodies and scalar compatibility services. Rust source/binaries
retain the previously validated author control; fresh execution is distinct
from a fresh Rust build. Its independent state machine, LinkedList loader,
interned Rc symbols, immutable Rc pairs and destruction schedule remain
separate representation choices. These controls do not isolate collector,
layout, scalar-service or generated-code costs.

The native opacity provider returns its original value without incrementing a
counter. Native frames require `barriers=0`, `setup_closed=1`,
`worker_closed=1`, `closed=2`. Configuration closes before worker entry; the
timed worker closes the complete data port before parsing begins; final cleanup
closes no leaked files. The identical-module V8 control uses the exact optimized
Wasm actually consumed by LLVM. Its scalar-provider export/import closure and
runtime identities were independently checked.

The timing host provides `benchmark.write_character`. It checks a Unicode
scalar, encodes UTF-8 and makes one synchronous `fs.writeSync` call. A short
write reports failure. An actual Node/Wasm fixture verifies ASCII/NUL, all
UTF-8 width boundaries, lambda, emoji and the maximum scalar. Its WAT/module,
exact byte captures and terminal record are retained. Canonical success has no
diagnostic prefix.

Preparation session 45868 reached exit zero at terminal chunk `5e3cae`. All seven
complete canonical frames and an additional raw-Wasm frame pass. Thirty-six
current predicate controls pass on raw/optimized/native and adapted Chez:
counts one/two, wrong last symbol, zero counts and their wrong expectation,
nested/mixed values, missing ending and extra ending. Complete source/input
identity and the current preparation are kept separate from historical author
artifacts and their failed observer-import attempts.

## Fixed campaign and evidence checks

The [frozen plan](timing-plan.json) has SHA-256
**e1c5470b6f25c516b30aa3c20110fb7ac0715b75363f7226c128cfa60fffbd78**.
It records 919 content identities, actual commands/tools/imports/libraries/Chez
heaps, full inputs, relevant environment, CPU5, default runtime/GC settings,
120-second timeout, seven discarded warmups and seven cyclic rotations.
This is 56 fresh serial processes and 49 retained observations. Each system
occupies each retained position once; no adjacency balance is claimed. Every
retained observation contributes to its median/range and descriptive ratios.
There is no trimming, replacement or adaptive stopping.

The [runner](measure-seven.py) owns each original process group through actual
leader wait status, descendant inspection, bounded cleanup and durable regular
stdout/stderr byte captures. Parsing follows terminal evidence and closed
handles. Unexpected executing descendants invalidate an attempt even when
cleanup stops them. The frozen guests do not daemonize; original-group
inspection does not establish absence of arbitrary escaped descendants.

The [independent reviewer](review-raw.py) imports no runner and starts no guests.
It independently derives the proper-list expectation from canonical input,
checks all scheduled invocation/environment/process/capture fields and exact
frames, and recomputes all medians/ranges and ratio directions. Rust's full
serialized result is compared independently. Success integers and Chez
success frames rely on separately reviewed full predicates and negative
fixtures. Hashes establish byte identity and recorded consistency, rather
than independently witnessing every historical process event.

Protocol replay passes all seven complete frames and rejects 43 corruptions,
including duplicate JSON keys, partial output, boolean/float success values and
nonpositive clocks. Actual synthetic byte/exit/timeout/orphan/SIGTERM records
remain retained, with all tested original groups quiescent. The parent
[plan audit](parent-plan-review.json), actual chunk `f401c5`, exit `0`, verified all 919
identities, 56 rows/positions, seven canonical terminal frames and exact native
lowering input. The [fresh simplify review](simplify-review.md) records the
independent behavioral model and informed debate.

Ambient environment remains in memory for child execution. Archived evidence
contains only the explicit and relevant fixed settings, without unrelated
session or credential variables. Freeze/readiness files retain their original
premeasurement stage. A failed campaign preserves its attempt and stops before
another row. Archive compression requires actual runner termination and parent
release of the quiet window.

The parent [released the quiet window](coordination.json) only after foundation
session 48141 and numeric sessions `11985`/`56497` had actually exited successfully.
Both feature agents held builds and workloads; compiler work remained source
only. The runner then executed all 56 fixed processes without a retry or sample
replacement. Its [actual tool transcript](clean-run-tool-transcript.json)
records session 11066, terminal chunk `c43e4a` and exit `0`. The parent released the
window after that completion.

[Independent raw review](independent-review.json) then passed at actual
chunk `2fe20d`, exit `0`. It checked all 56 raw capture triples, all 919 frozen identities,
full frames, schedule/position counts and every median/range and ratio. The
[parent's separate raw replay](parent-raw-review.json) passed at actual chunk
`3e3c5f`, exit zero, and retains its own limited scope. No clean sample was rerun
for either review.

Verify frozen identities without starting a guest:

    python3 -B benchmarks/results/2026-10-14-strict-parsing-comparison/measure-seven.py

The `--run` action requires the exact plan hash, fresh output directory and
explicit coordinated-release label. Replaying on another host requires fresh
artifacts/environment/import identities and a newly reviewed plan. Recorded
paths preserve their original execution locations.

Independently replay the completed campaign without guests:

    python3 -B benchmarks/results/2026-10-14-strict-parsing-comparison/review-raw.py \
      --campaign build/parsing-clean-8930aaa --output build/parsing-review-copy.json

[The evidence archive](artifacts.tar.xz) retains current frozen compiler/GC/host
sources, exact full inputs, source ledgers, current Wasm/native/LLVM and Chez
artifacts, scalar providers, Rust controls, all 56 raw samples, diagnostics,
synthetic captures, historical author evidence and its preserved failures, and
audit/coordination records. Its [manifest](manifest.json) records every member's
bytes, digest and mode. Immutable external tools/libraries/imports remain
identified in the plan; all audited local dependencies are retained explicitly.
Freeze/readiness/checkpoint files retain their original premeasurement stage.

Verify archive bytes and the full member inventory without extraction or
guest execution:

    python3 -B benchmarks/results/2026-10-14-strict-parsing-comparison/package.py
