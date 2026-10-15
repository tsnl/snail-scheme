# Complete Equal: native improves on V8, but structural equality remains expensive

The original full-size Equal aggregate passes on raw linked Wasm, optimized
linked Wasm, actual native64, original Chez and the exact adapted Scheme body
on Chez. Current-source preparation uses compiler and driver
`6fd5ca453cc58903cdb64f13abc3cdc656b06226`, including reader staging and
cycle-safe Datum equality. The prior author's preparation on `610d6e9` remains
prior evidence and is never relabeled as this integrated source.

The isolated worktree is `/tmp/snail-equal-measurement-20261014`, above
`6fd5ca4`; main and the integration worktree are untouched. The upstream corpus
is pinned to `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Original input is
`100 100 8 1000 2000 5000 #t`, with SHA-256
`fd6624c8c04b324af8fc851d2cf5509543785b41a6a76c53232ac025245cae03`.
The original final Boolean is read but unused.

All 56 scheduled fresh processes completed successfully: seven predetermined
warmups and 49 retained observations. The parent independently parsed every
complete result frame, checked the schedule and process cleanup, recomputed
medians and ranges, and rehashed all 451 frozen identities. The actual runner
tool handle `92331` was drained to exit zero before other agents' build and
validation jobs were released.

## Clean comparison

These are complete workload-clock seconds, including the original aggregate
predicate and excluding startup/setup. Each system has seven retained samples;
all observed variation remains in the ranges.

| System | Median seconds | Retained range |
| --- | ---: | ---: |
| Snail production Wasm on V8 | 2.395007397 | 2.382166640–2.419409613 |
| Native-final Scheme Wasm on V8 | 2.408984969 | 2.392353448–2.411209887 |
| Snail native64 | 2.133532650 | 2.130816319–2.137788460 |
| Original Chez | 0.258255367 | 0.252048244–0.261719213 |
| Adapted Scheme body on Chez | 4.687177296 | 4.686080535–4.697449006 |
| Rust Wasm on V8 | 0.933199088 | 0.925408795–0.936876007 |
| Rust native | 0.813260313 | 0.806908107–0.844802374 |

Snail/V8 takes **9.274 times original Chez time**, **0.511 times adapted Chez
time**, and **2.566 times this Rust/Wasm reference's time**. Native takes
**11.434% less time** than V8 on the exact same final Scheme Wasm. Adapted Chez
takes 18.149 times original Chez time. The adapted control changes Datum
representation, explicit mutation helpers and the equality algorithm together;
it does not isolate any one cost. These results motivate profiling those
operations, without attributing the original-Chez gap solely to code generation,
GC or Wasm. Rust likewise uses its own representation and reclamation strategy.

The independently recomputed [review](independent-review.json) also records
whole-process medians/ranges and host observations. The original
[readiness audit](readiness-audit.json) remains the historical preparation
checkpoint. This is one additional measured workload, bringing historical
strict coverage to **44 of 57**, **43 with paired Chez results**; the accumulated
reports span different compiler revisions and are not a whole-suite rerun.

## Complete behavior and separate diagnostics

The source edits retain every original constructor algorithm, hidden operand,
enabled phase, count and exact-`#t` aggregate predicate. The 11 edits have
counted occurrences, exact reversal and a retained full-source patch. The
original cyclic phase remains commented out in the clean aggregate. The five
enabled constructors create a shared spine tree, an unshared tree, flat
vectors, lists sharing subtree elements, and deep car chains.

All five Scheme executors pass canonical input, a smaller positive input,
an unused `#f` output datum, and five zero-phase negatives. Complete output
frames and the original predicate are checked. Three Rust executors pass
the same eight fixtures; false aggregates cause the expected Rust assertion.
Rust source is unchanged and is an immutable Rc/pointer-pair-HashSet algorithm
and allocation-layout control, with an explicit work vector and iterative
destruction.

Separate observations check 5,050 shared pair occurrences, 109,600 unshared
pair occurrences at height eight, 1,000-element vectors, 2,000-element lists
whose subtree elements share, and a 5,000-deep car chain. Equality-call counts
are `[0, 100, 8, 1000, 2000, 5000]`; leading zero is the disabled clean phase.
All five enabled phases execute actual false equality in separate probes, with
checked short-circuit prefix counts. A separate cyclic case executes 17 calls.
The unshared occurrence count and adjacent-child distinction supplement the
unchanged recursive constructor and fresh-two-Ref semantics; they do not alone
prove global unsharing.

Current Datum module tests execute on raw and optimized linked Wasm and native.
`make test`, `make check`, `cargo test --offline` and `cargo fmt --all -- --check`
pass. The current full reader regression passes 95 cases on all three target
paths: 32 complete streams, 60 syntax-error cases and three UTF-8 failures.
All owned preparation/check tool handles were taken to terminal exit zero.
The 105 Equal subprocess records include 15 expected negative Rust exits.

The clean native executable omits the observational opacity counter. Its V8
control executes exactly the same final Scheme Wasm bytes with a scalar Wasm
provider. Separate counted executions establish 11 opacity calls per canonical
invocation. These counts and the file-lifetime observations are diagnostics;
clean samples use the counter-free hosts.

## Collector lifetime observations

Separate native processes force collection before and after the benchmark.
Setup-only performs two collections; full canonical work performs 3,180.
Both finish with 1,144 live bytes and 132 objects on this integrated source.
This supports no additional aggregate post-return live footprint relative
to setup. It does not identify each surviving object or equate allocation and
peak usage. The full diagnostic allocates 4,289,302,600 bytes in 32,587,903
allocations, and its peak live bytes are 19,978,248. The heap/statistics settings
belong only to this separate diagnostic.

The prior `610d6e9` setup/full observation finished with 1,136 live bytes and
131 objects. These are distinct preparations; no attribution is made about
the identity of the additional current-source object.

## Frozen measurement protocol

The intended seven systems are production optimized linked Wasm on default V8,
native-final Scheme Wasm on default V8, native64, original Chez, adapted Chez,
optimized Rust Wasm on default V8 and Rust native. Native and its common V8
module control share exact final Scheme Wasm bytes; their scalar services and
ABI linkage differ. The Rust and Chez controls use their own original layouts
and algorithms.

The plan fixes CPU 5, one fresh process per invocation, one predetermined
discarded round followed by seven balanced retained rotations, and no sample
replacement. Every retained system occupies each serial position once. The
Chez frame must name `equal:100:100:8:1000:2000:5000`; Rust retains its own
`equal:1` naming. Complete result frames, stderr, finite positive timer values and
owned-process cleanup are checked for every sample.

The runner enforces the concrete 56-job schedule, seven systems, CPU 5 and
120-second timeout, independently of the plan's contents. Signal handlers set
a stop flag; safe checkpoints obtain the actual Popen handle before honoring a
stop, and capture polls allow interruption during a running child. Cleanup
drains stdout/stderr, reaps the actual leader, closes its actual capture handles,
and records the stopped process group. Separate synthetic-process diagnostics
pass interruption before Popen assigns the returned handle, interruption after
partial stdout/stderr, and timeout after partial output. These diagnostics are
outside the clean workload. Zero and nonfinite workload/process durations are
rejected; the secondary rounded Chez duration must also be finite and
nonnegative.

The workload clock follows setup and includes the final predicate. The process
clock includes launch, startup/setup, workload, output capture, reap and bounded
process-group cleanup. Default V8 and native collector settings are retained;
inherited instrumentation, special heap settings, and GC flags are rejected.
Warning suppression is the only Node flag. Source, tool, input, artifact,
actual imported supervision dependencies and dynamic libraries are hashed
before timing. Host CPU/policy/affinity/load snapshots bracket the campaign.
Fresh processes do not establish cold caches or remove unrelated host activity.

The runner defaults to identity verification. `--run` requires the parent's
quiet-window release and a new output directory. Timing-host framing and
failure cases passed before the plan was frozen. The plan contains 56 jobs
and 451 identities; its SHA-256 is
`75bb0e97e47560a4447b3927fc46d88284b4d085e828788527b277af5e92a455`.

## Preserving the audited evidence

The parent reviews the captured clean records and records hashes of the exact
bytes it parsed. `package.py --prepare` copies the selected evidence once,
requires that snapshot to match the audited plan and all 56 raw samples, then
hashes, compresses and fully decompresses that same snapshot. Later edits to
live preparation files cannot change the captured collection. This does not
claim a simultaneous filesystem snapshot.

Normal `package.py` invocation checks the compressed archive identity, every
safe regular member, file sizes, modes and complete inventory. It performs
byte-integrity verification only. The parent audit and original control records
provide the semantic evidence; verification does not replay benchmark guests.
External tool binaries and regenerable Cargo/bytecode caches are excluded,
with their observed identities retained in the frozen plan.

Archive, manifest and verification record are created exclusively. Existing
complete or partial publications block preparation. Failure removes only files
newly created by that invocation; a missing companion record makes verification
fail. Publication is not claimed to be atomic across the three files or durable
against a crash. Separate synthetic checks cover snapshot mutation, audit-byte
mismatch, read-only verification, unsafe members, changed archive bytes and
partial publication cleanup.
