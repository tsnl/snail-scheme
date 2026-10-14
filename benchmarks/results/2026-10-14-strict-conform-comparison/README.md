# Complete Conform: native64 takes 13.73% more time than identical-Wasm V8

The complete canonical Conform comparison passes all 56 scheduled fresh
processes: seven predetermined discarded warmups and 49 retained observations.
The original input invokes the complete kernel 500 times with names
`(a b "c" "d")`, then checks all 31 expected strings in their original order,
including the list ending. The root independently checked every complete
capture, command, predicate, cleanup and all 453 frozen identities before
recomputing the medians and ranges.

These are complete workload-clock seconds, including the final predicate and
excluding setup. Every system has seven retained observations; all variation
remains in the ranges. The separate process medians include launch through
capture, reap and owned-group cleanup. Their complete ranges are retained in
the [independent review](independent-review.json).

| System | Workload median | Workload range | Process median |
| --- | ---: | ---: | ---: |
| Production Scheme Wasm on V8 | 1.599662733 | 1.594527930–1.610720732 | 1.631300544 |
| Mechanical native64 | 1.825969003 | 1.821331055–1.841988903 | 1.829923904 |
| Exact native-final Scheme Wasm on V8 | 1.605583018 | 1.599421711–1.618279808 | 1.638020288 |
| Original Chez | 0.891038255 | 0.887997459–0.893596485 | 0.924037906 |
| Adapted Scheme body on Chez | 2.571686675 | 2.568153127–2.586856199 | 2.605042334 |
| Rust native | 0.502839416 | 0.500542465–0.505763234 | 0.505964584 |
| Optimized Rust Wasm on V8 | 0.712783650 | 0.708547917–0.717859172 | 0.738049068 |

Production V8 takes **1.795× original Chez time**, **0.622× adapted Chez time**
and **2.244× this Rust/Wasm reference's time**. Native64 takes **13.73% more
time** than V8 on the exact same final Scheme Wasm and **3.631× Rust native
time**. Adapted Chez takes 2.886× original Chez time. The adapted source/storage
changes act together, while Rust has its own algorithms and reclamation. These
controls do not isolate a code-generation, collector or individual helper cost.

Conform adds one measured workload, bringing historical strict coverage to
**45 of 57**, **44 with paired Chez controls**. These accumulated reports use
different compiler revisions and do not constitute a whole-suite rerun.

The isolated measurement worktree is `/tmp/snail-conform-measurement-20261014`,
created from preparation commit `2b47be48bf7fabd3ce4e226fbcf5a1e7a48a6940`.
Compiler and original build-driver basis remain
`43322a25b23e7c1d110378793247f984d2043d21`. The later ledger correction
`7bd327f` is recorded separately and changes no generated source or executable.
This work changes only the measurement report and runner; compiler, runtime,
benchmark algorithms and Rust reference source are unchanged.

The actual root-owned timing tool session `65477` was drained to exit zero
before other heavy work resumed. Its [completion record](coordination-after.json)
and [quiet-window coordination](coordination-before.json) distinguish actual
tool completion from namespace-local child/group records. The independent
capture audit also reached exit zero. No clean invocation was retried or replaced.

## Verified preparation and exact artifacts

The [preparation report](../2026-10-14-strict-conform-preparation/README.md)
archives the complete source, compiler snapshots, adaptations, actual linked
Wasm/native artifacts, complete correctness observations and development
failures. Its 33,165,056-byte archive has SHA-256
`1a5c38a6eb1e4ef82ef36389105b59ed3602e4a57a0d880d7becd3ef3e38a2d0`.
All 1,111 unique regular members were restored and verified under
`build/conform-evidence-2b47be4`; the author worktree and artifacts are untouched.
All 96 compiler snapshot files and 673 prepared Conform members match their
recorded identities. The 119 preparation command records are terminal, with
20 expected fatal-use failures and 12 expected negative Rust assertions, no
timeouts and no executing descendants.

| Input or control | SHA-256 |
| --- | --- |
| Complete upstream `src/conform.scm` | `5b544ec3ea2416df03ef935d45ad96b7204c35ecaf7344118d3d34bbb3dc9de5` |
| Original `inputs/conform.input` | `9c0f8f0e5a9e61836442b9b85a6f5b844b31f05f14ed3586a9280f4edf138794` |
| Production optimized linked Wasm | `3e773a4c0b720036a2f79f60c584deabc545faaafa83d3d2206fceb3add24aa4` |
| Exact native-final Scheme Wasm | `9426f2994388c65ca60ff5fc10850116fd0f616a0aba088980ad18643a3e47fc` |
| Mechanical native64 executable | `90945ab28604cea76134ed559e37497c98d7d698ad7412ef3f5f4c88e96803ce` |
| Optimized Rust Wasm | `f6dee4c7c1f4c3217bb554065ca79d0289c5271d76ac445c6c3e0b900fc9501f` |
| Rust native executable | `a101bffa82ad8ffed59b76f52a187114df2901777a6f282652bae691d5bad6ea` |

The upstream corpus revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
Production artifacts retain mandatory Binaryen optimization. The native64 arm
mechanically lowers the archived final Scheme Wasm; its V8 control uses those
exact same module bytes with a separately pruned scalar Wasm provider. Provider
target, ABI linkage and optimization opportunities still differ. Original Chez,
adapted Chez and the unchanged Rust reference retain their distinct layouts,
allocation and reclamation strategies described in the preparation report.

Typed records and Refs preserve the original functional sets, alternating
unstable split/merge sort, copied node list, shared mutable memo tables,
insertion before recursive blue-edge construction and temporary red assumptions.
The exact list-copy expression remains, although physical immutable-list spine
identity is not directly observable in strict List. Strict `symbol->string`
returns a fresh string where original Chez may reuse one. Ignored setup/setter
status values become Unit, membership becomes Boolean at condition-only uses,
and the unreachable missing-class error omits generic node rendering.

Rust uses arena indices, Vec nodes/edges/tables/sets, VecDeque sorting and Rc
names, retaining removed noncanonical nodes until each invocation ends. It
compares UTF-8 byte lengths where Scheme compares Unicode scalar lengths; the
canonical ASCII and uniform Greek-renaming fixture preserve ordering, but
arbitrary mixed-width Unicode names are outside the Rust equivalence claim.
The separate detailed streams, 38 identity/alias/order/state assertions and all
500 per-invocation 30-counter deltas agree across five Scheme paths. A separate
64 KiB-minimum/64 MiB-arena stress run survives 19,005 exact native collections.
Those observations and GC settings enter neither clean artifacts nor timings;
the stress run is not an allocation census.

The [path mapping](path-mapping.json) replaces only the archived author worktree
prefix with the verified restored tree. It preserves every other command,
working-directory and stdin byte. The actual measurement commands consume the
restored artifacts and inputs. Original absolute paths inside build metadata and
debug/source maps remain historical evidence. External tool binaries, Python
imports, dynamic libraries and Chez boot files remain pinned by observed hashes;
the report does not claim those external installations are portable.

## Fixed timing protocol and complete frames

The [timing plan](timing-plan.json) fixes these seven systems in this initial
serial order:

1. Production optimized linked Scheme Wasm on V8.
2. Mechanical native64.
3. V8 on the exact native-final Scheme Wasm.
4. Original Chez.
5. Adapted Scheme body on Chez.
6. Rust native.
7. Optimized Rust Wasm on V8.

Exactly one first round is discarded in advance: seven fresh processes, one per
system. Seven further cyclic rotations retain all 49 observations. Every system
occupies each serial position once. There is no adaptive stopping, trimming,
retry or sample replacement. Any status, timeout, output, identity, environment
or cleanup failure stops the campaign and preserves every started record.
The rotations balance positions, not all predecessor or adjacency pairs.

Each process is pinned to CPU 5. Node/V8 and the native collector use their
defaults. Warning suppression is the only Node flag. Inherited instrumentation,
heap/collector overrides, Python import overrides, loader injection and Chez
library/boot overrides are rejected. Relevant inherited settings are frozen and
checked; CPU availability and all 453 identities are checked before each sample.
The actual runner import closure contains 173 files, including the unchanged
archived `matrix_port.py`/`data_ports.py` supervision dependencies and their
loaded Python dependencies. Source, tool, input, artifact, host, dynamic-library
and boot-file hashes are explicit in the plan. Host CPU, frequency policy,
affinity and load observations bracket the clean campaign.

Setup and input parsing precede every guest workload clock. That clock includes
all 500 original invocations and the complete final result predicate. Output
formatting and final cleanup follow the guest clock. The separate whole-process
clock starts immediately before `Popen` and ends after output capture, leader
reap, capture-handle closure and bounded owned-group cleanup. No inequality is
imposed between the independent clocks. Fresh processes do not establish cold
caches or exclude unrelated host activity.

Strict V8 requires one JSON line with the integer predicate result `1` and a
finite positive duration. Native64 additionally requires exact integer lifecycle
values: `barriers=0`, `setup_closed=1`, `worker_closed=0`, `closed=1`. Boolean
substitutes and duplicate JSON fields fail. Chez requires the complete three-line
`conform:500` frame and numerically equal primary/CSV durations. Its independent
rounded parenthesized interval must be finite and nonnegative. Rust requires
every one of the 31 strings in order, the list terminator, and the complete
`rust-wasm,conform:500` CSV frame. Nonzero exits, stderr, timeouts and nonpositive
or nonfinite workload/process durations fail on every host.

## Actual diagnostics and owned cleanup

All seven restored hosts executed the complete original workload once as
setup diagnostics, with `clean_sample=false` and `retained=false`. Their incidental
clocks are not comparison samples. All complete frames passed. Both the seven
archived frames and seven restored frames rejected 170 corruption cases each.
The [readiness audit](readiness-audit.json), [protocol record paths](protocol-records.json)
and [setup log](freeze-plan-attempt1.stdout.txt) preserve the checks.

The runner owns each actual returned `Popen` handle and launches it in a new
session. Signal handlers remember a stop request instead of unwinding while
`Popen` returns. Capture polls provide interruption checkpoints. The archived
supervisor stops the saved process group; bounded final operations reap the
leader, preserve cumulative partial capture and close actual pipe handles.
Cleanup verifies the absence of live group members before any next sample.
Descendants must retain the inherited session/group, be visible through `/proc`
and remain signalable/killable. Process-group scanning is not a kernel ownership
lease against later group-ID reuse.

Separate synthetic diagnostics pass stop requests during `Popen` assignment and
capture, timeout with partial stdout/stderr, a vanished leader, a descendant
closing capture pipes, and timeout with descendants. An additional diagnostic
passes an exited leader whose descendant retains capture pipes: the timeout
preserves the leader's output, reaps the leader and stops the remaining group.
Actual captured leaders are reaped, actual capture handles are closed and all
live-group inventories are empty.

The supplementary harness's first direct invocation omitted its helper's
`ORIGINAL_POPEN` initialization. Its raw started record and explicit terminal
failure acknowledgement remain under `supervision-held-pipe-attempt1`; the
corrected diagnostic is in `supervision-held-pipe-attempt2`. Frozen runner and
plan bytes are unchanged. The main setup/freeze tool session `54943` was drained
to terminal exit zero. [Execution handles](execution-handles.json) distinguish
tool-session completion from the namespace-local child/group records.

The pinned simplify pass used a fresh explainer with no history or file access.
The refined model keeps one literal frozen plan and one serial owned operation.
It motivated checking survivors, bounded final capture/reap, explicit handle
closure, cumulative partial-output preservation and the held-pipe edge case.
The existing process-group helper remains unchanged. Cohesive inventories,
literal policy definitions, process lifetime transitions, dispatch and tests
exceed the ten-line target where splitting would hide their contracts. The
review rejected a separate supervisor framework and a workload/process-clock
ordering assertion. Python syntax checks and actual linked target diagnostics
pass; no compiler/runtime behavior changed.

## Release and exact runner invocation

The plan SHA-256 is
`90b8a3ba32e6da8e25819c89dc797bd3c52b7d257bf7db717f8293ac094c6819`.
Runner SHA-256 is
`c551410d4cecdd402b36709b67149fc07c3d290f548f45c1bb74dff8a9245867`.
Freeze-script SHA-256 is
`7fdf291501ad0c7d45c5a13e37daddda459500b12858700572d04fb0f6e8f32e`.

Default invocation verifies identities and starts no benchmark. The root used
the exact command below after its explicit quiet-window release. It executes
the frozen 56-job schedule and requires a new output directory. The working directory is
`/tmp/snail-conform-measurement-20261014`.

```sh
/run/current-system/sw/bin/python3 /tmp/snail-conform-measurement-20261014/benchmarks/results/2026-10-14-strict-conform-comparison/measure-seven.py --run --output /tmp/snail-conform-measurement-20261014/benchmarks/results/2026-10-14-strict-conform-comparison/measurements-attempt1
```

`package.py --prepare` copies selected evidence once, requires every captured
parent-audited byte to match the review, and hashes, compresses and fully
decompresses that same snapshot. The original complete preparation archive is
included, preserving all 1,111 original members and source-basis distinctions;
selected restored sources/artifacts and all raw clean/diagnostic records remain
directly inspectable. Regenerable restored Cargo targets and Python caches are
excluded from the expanded selection, with the original archive and frozen
identities retaining their history. External tool installations remain outside
the archive.

Normal `package.py` invocation only verifies compressed-byte identity and every
safe unique regular member's hash, size, mode and complete inventory. It starts
no guest and does not replay semantic behavior. Publication uses exclusive
creation and rejects complete or partial existing bundles; failure removes only
files created by that invocation. This is not a simultaneous filesystem snapshot,
atomic multi-file publication or crash-durability claim. Root review and actual
process captures supply the semantic evidence. Separate synthetic checks pass
snapshot mutation, audited-byte mismatch, missing final sample, safe member
inventory, read-only verification, changed archive bytes, symlink rejection and
partial-publication cleanup. All 279 parent-audited local file hashes and the
historical coverage name sets remain verified. No push or merge occurs here.
