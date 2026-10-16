# Complete Maze seven-system comparison

The complete original **10,000 constructions of a 20 × 7 maze** pass on all
seven systems. Production Snail on V8 takes a median **0.419037 seconds**, and
native64 takes **0.461827 seconds**. Native takes **10.4855% more time** than V8
executing the exact optimized Wasm consumed by native lowering. Original Chez
takes **0.332521 seconds**; the unchanged Rust native reference takes
**0.229181 seconds**.

| System | Median seconds | Minimum–maximum seconds | Median / original Chez |
| --- | ---: | ---: | ---: |
| Snail production linked Wasm on V8 | 0.419036819 | 0.415633793–0.423085429 | 1.260180 |
| Snail native64 | 0.461827422 | 0.459433069–0.465222026 | 1.388866 |
| Snail exact native-final Wasm on V8 | 0.417998163 | 0.417264752–0.419515307 | 1.257057 |
| Original Chez | 0.332521329 | 0.330862453–0.333273955 | 1.000000 |
| Exactly adapted Chez | 0.500966136 | 0.500254224–0.503299189 | 1.506568 |
| Rust native | 0.229180672 | 0.227546644–0.231139955 | 0.689221 |
| Rust Binaryen-optimized Wasm on V8 | 0.246174006 | 0.241920870–0.251513939 | 0.740325 |

Each row retains all seven observations. Ratios divide medians without
intermediate rounding. These descriptive comparisons cover this complete
workload on one host; seven cyclic rotations balance positions, without an
adjacency-balance or statistical-confidence claim.

This adds one complete benchmark to historical measured coverage: **46 of
57**, including **45 original-Chez-paired comparisons**. Those accumulated
results span successive compiler revisions. This campaign freshly measures
Maze at the source basis below; it does not remeasure the preceding coverage.

## Current source, native lowering and the original contract

Compiler/library/collector basis is
**da8519f83f54dabb9cbfef1297bb46a29d7683b7**, including the current growing
precise native collector and wrapping-word scalar library. The worktree was
isolated from that commit. Native64 mechanically lowers optimized Wasm to
LLVM; all production Scheme and Rust Wasm paths retain mandatory Binaryen.
The native opacity provider returns the same value without incrementing an
observation counter. Its clean frame verifies zero counted calls and input
resource markers `setup_closed=1`, `worker_closed=0`, `closed=1`.

The full canonical input has SHA-256
`90874004ae477b9a77164e83459454490a6da66a29cca6cb5d1f71e2b04bb1a9`.
Every successful sample checks the entire supplied **668-character list**,
including **42 newlines and both list endings**. The original recursive
bitwise-and, div/mod algorithms, RNG seed 20, operation order, aliasing,
callback behavior and immediate lexical escape remain. Detailed source
adaptation and ordered observations are documented in the separate
[correctness preparation](../2026-10-14-strict-maze-preparation/README.md).
Its clocks and operation counters supply no clean timing observations here.

Fresh source regeneration matches the reviewed author byte for byte for the
upstream source, upstream kernel, adapted kernel, strict program and original
Chez program. Adapted Chez contains the identical concrete Maze kernel and
exact current scalar prelude. Its complete source differs from the historical
author only by the twelve-line wrapping-word compatibility additions, retained
as a patch. It contains no extra Datum/read library bodies. Both Chez controls
were freshly compiled from these current sources.

Fresh current Wasm differs from the historical integration's executable bytes;
those older executable results were not substituted for current validation.
All seven current complete canonical frames pass. Thirty-two additional
current predicate controls pass on raw linked Wasm, optimized linked Wasm,
native64 and adapted Chez: once, twice, wrong Unicode character, missing/extra
tail, zero with false/list expectations and negative with false expectation.
These are diagnostics, separately preserved. The full historical preparation
and its parent-reviewed ordered traces retain their earlier source basis.

The exact native-final V8 module is copied from the actual optimized input
used by LLVM lowering. Relevant SHA-256 identities are:

| Artifact | SHA-256 |
| --- | --- |
| Current production linked optimized Wasm | `23bb977e541550baf721cb4030250304b3aa091a60d25f564cb91cfbf2d1cddf` |
| Actual native lowering input / identical V8 control | `7ffb7965d8f311837c7b7070ef16afc0ce7c491c67014a9ae3d4ffa61bab08fb` |
| Current native executable | `10e3b6a372e214fc9a6bd3373e88abf924507040a2698dee2d19a4b9005e5bd5` |
| Current precise collector source | `4bdf53cc0544c00b4b4d8018d44eafa2d063c672fa8cbac828a49f7d24459bfe` |

Rust uses the unchanged, previously validated author binaries and source.
Its indexed Vec cells/walls, native integer bit operations, temporary child
vectors, row-major allocation, owned Box character lists and iterative
destruction remain documented independent representation and lifetime choices.
Historical preparation also validates additional raw paths. The seven systems
in this table are the freshly executed clean comparison. The numbers do not
isolate a collector, allocation representation or arithmetic change.

## Fixed execution and independent review

The [frozen plan](timing-plan.json) has SHA-256
**09f16e4cded8ee975a7426dfca357d102bb45bea4beaecff5550f052501da7e9**.
It fixes 718 content identities, actual commands/tools/imports/libraries/Chez
heaps, full inputs, relevant environment, CPU 5, default runtime/GC settings,
120-second timeout, seven discarded warmups and seven cyclic rotations.
All 56 processes are fresh and execute serially. Setup and input parsing precede
each clock; the complete 10,000 runs and full final predicate are inside it.
Output serialization and final cleanup follow it. Ambient environment remains
in memory for child execution; retained evidence contains only explicit and
relevant fixed settings, without unrelated session or credential variables.

The parent released the quiet window after actual Parsing session 65131 and
the compiler representation retry had exited successfully. Other agents held
builds, tests, compression and workloads. [Coordination](coordination.json) was
saved before launch. The [actual clean tool transcript](clean-run-tool-transcript.json)
shows session **62668**, terminal chunk **39749a**, exit **0**, and all 56 rows.
No sample was replaced, trimmed or rerun. The parent released the window only
after that actual completion; compression followed the release.

[The runner](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-maze-comparison/measure-seven.py) owns each original process group through leader
reaping, descendant inspection and bounded cleanup. It captures stdout/stderr
as bytes in regular files, closes and syncs them, and preserves terminal
records before parsing. Unexpected executing descendants invalidate a sample
even if cleanup stops them. The frozen guests do not daemonize; original-group
inspection does not prove absence of arbitrary escaped descendants.

[The independent auditor](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-maze-comparison/review-raw.py) imports no runner and starts no guests.
It independently scans the canonical character tokens, checks schedule,
configuration, recorded terminal/cleanup outcomes, capture identities and full
frames, and recomputes all medians/ranges and ratio directions. Rust's entire
serialized list is additionally compared with the independently derived
expectation. Success integers and Chez's success frame rely on separately
reviewed full guest predicates and negative fixtures. Hashes and repeated raw
reviews establish byte identity and recorded consistency, rather than an
independent observation of every historical process event.

[Its review](independent-review.json) completed at actual chunk **61af53**,
exit **0**. The parent separately reparsed all 56 captures and reproduced every
median/range at actual chunk **e64b98**, exit **0**; its limited review is retained
separately. Protocol replay passes all seven complete frames and rejects 43
corrupt frames, including duplicate JSON keys, partial output, boolean/float
success values and nonpositive clocks. Actual synthetic byte/exit/timeout/
orphan/SIGTERM captures and statuses are retained. The
[focused simplify review](simplify-review.md) records behavioral explanation,
debate and the boundaries of these checks.

Two preparation assumptions failed safely and remain separate: full adapted
Chez source equality stopped on the current word prelude, and historical Wasm
equality stopped after fresh current builds produced different bytes. Both
actual terminal failures, retained artifact trees and the corrected current
validation are archived. The auditor's first attempt also rejected relative
capture-path spelling; its code and exit-one record are retained. The final
auditor resolves those paths against the actual launch directory. Sample bytes,
timing code and the frozen plan were unchanged.

## Replaying and retaining evidence

Verify the original frozen paths without starting a guest:

    python3 -B benchmarks/results/2026-10-14-strict-maze-comparison/measure-seven.py

Independently replay the completed raw campaign without guests:

    python3 -B benchmarks/results/2026-10-14-strict-maze-comparison/review-raw.py \
      --campaign build/maze-clean-da8519f --output build/maze-review-copy.json

The runner's `--run` action requires the exact plan hash, a fresh output
directory and an explicit coordinated-release label. Reproduction on another
host requires fresh artifacts, environment/import identities and a newly
reviewed plan. Recorded commands preserve their actual absolute locations;
raw capture paths preserve their actual spelling relative to the recorded
worktree launch directory.

[The archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-maze-comparison/artifacts.tar.xz) retains current frozen compiler/GC sources,
current and historical programs/artifacts/LLVM, original full inputs, source
ledgers, counter-free native provider/entry, Rust controls, all 56 raw samples,
diagnostics, synthetic captures, failed attempts and audit/coordination records.
The [manifest](manifest.json) records every member's exact bytes, hash and mode. Immutable
external tools/libraries/imports are identified in the plan; audited local
dependencies are retained explicitly. Frozen preparation/readiness flags
describe their premeasurement stage and remain unchanged as provenance.

Verify archive bytes and the complete member inventory without extraction or
guest execution:

    python3 -B benchmarks/results/2026-10-14-strict-maze-comparison/package.py
