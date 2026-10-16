# Rejected native sweep bitmap experiment

Publishing each retained allocation-start bitmap word once did **not establish
a GCbench gain**. The candidate median is **0.97% higher** than its matched
control, and their observed ranges overlap. It fails the decision rule recorded
before measurement and remains unlanded.

All **18 scheduled attempts passed**: one warmup and five fresh-process samples
for each of the control, candidate and V8 routes. There were no retries or
replacement samples. This is a separate campaign from the
[CPU and allocation comparisons](../2026-10-16-native-cpu-gc/README.md), with no
new full57 ranking or Chez/Rust comparison.

| GCbench route | Median guest seconds | Observed minimum–maximum |
| --- | ---: | ---: |
| Matched native control | 2.328281 | 2.308967–2.341231 |
| Sweep bitmap candidate | 2.350928 | 2.338800–2.357007 |
| V8 | 1.230659 | 1.229514–1.231846 |

The pre-run rule required both **at least 2% lower median time** and a candidate
maximum below the control minimum. Neither condition passes. Observed ranges
are descriptive minima and maxima, not confidence intervals; the rejection
does not establish a general performance regression. The rule also prohibited
replacement samples or repeating the campaign to obtain acceptance.

The exact rule is retained as `sweep-probe-decision.txt` in the archive, with
SHA-256 `0d8e113f1d6807725bbe3ceeca185ae1c72b172575a01f04816cb9c84d94c357`.
All five samples and the warmup for each route remain in
[comparison.json](comparison.json).

## The isolated change

Both native arms start from `e66484f733860f4d806ea1f1f7930cd84051056e`
with the same retained allocation-inlining patch: a documented LLVM allocation
call-site attribute and a private Rust allocation hint. Its benefit is not
attributed to this experiment. Both arms use the portable CPU default and
default GC budget. These frozen binaries are identified independently of the
later production allocation commit.

The control clears each dead object's allocation-start bit directly in memory.
The candidate keeps the word in a local variable, clears dead bits there, and
publishes the retained word after examining all of its objects. Header zeroing,
live-object mark clearing, live statistics, finalizer order, region/block policy
and root handling remain unchanged. Finalizer callbacks run before sweep and
only queue scalar IDs; sweep itself has no callbacks or allocation. Exact
membership is published before allocation resumes.

Retained assembly shows a register bit-clear and one word store replacing
per-dead-object memory updates. The candidate also writes unchanged words when
they contain no dead objects, including empty words. This is a static code-shape
observation, not a measured dynamic store count or a performance explanation.

The two guest LLVM files are byte-identical. Both builds consume the unchanged
raw guest through mandatory Binaryen optimization, producing the same optimized
Wasm that V8 executes. The raw Wasm, inputs, providers, timing entry, repetition
count of one, depth of 20 and complete final predicate (`result = 1`) remain the
frozen production inputs. Actual executed ELF hashes are:

| Arm | SHA-256 |
| --- | --- |
| Control | `c0f13b35dec0f163b07ece61aa7335e57b8ff8810a31ae784fc3caf994ccbd8d` |
| Candidate | `d23b6bb3b48abb9904fa3445b6aa13292881412a00b25f621771ed46c24d9ef6` |

## Correctness and separate diagnostics

The retained preparation passes 61 Rust tests, formatting, the canonical native
and V8 predicates, and the native semantic fixture with forced collection.
That fixture covers dynamic arrays, zero-filled reuse, live roots, cycles,
subtype/identity checks and tail calls. These checks do not constitute a new
full-suite correctness run.

Separate instrumented control and candidate runs both record 79 collections,
226,122,905 allocation requests and 4,328,130,064 requested bytes. Their live,
occupied and peak-live counters also match, as do object, root, field, reused-hole
and large-allocation counts. Recorded sweep-phase totals, including finalizer
queueing, are 0.326030 s and 0.328760 s. Those runs were uncontrolled diagnostics;
neither their total elapsed times nor their phase times enter the clean timing
table. No new pause distribution or memory-use improvement is established.

Preparation command outputs and process records remain intact, including the
recorded pre-capture setup failures. The original `review.json` retains its
premeasurement status wording; it is a historical preparation snapshot, not the
final disposition of this rejected experiment.

## Protocol, audit and retained evidence

The fixed schedule rotates the three arms, with one warmup and five samples
per route. Every fresh process is pinned to CPU 2 on the recorded Core Ultra 7
270K Plus host. The guest timer includes the workload and complete final
predicate; input/setup, startup, result formatting and final cleanup are
excluded. V8 tiering during the workload remains within that interval.

Task-owned builds, correctness checks, profiling, archive and Git work were
idle during the measurement window. Independent review counted 23 process-name
snapshots at a five-second cadence and found no named competing compiler or
profiler. Ordinary desktop activity remained. CPU percentages are process-lifetime
averages, and there is no external-session quiet attestation or exhaustive
machine-idleness claim. The driver, observer and audit processes were reaped.

The independent audit reconstructs the schedule, checks all 18 attempts and
their actual commands, hashes source/input/output and executable dependencies,
checks successful exits and descendant cleanup, verifies final predicates and
guest timers, and recomputes the five-sample statistics. It also binds the
decision rule and verifies native CPU, optimized-Wasm and guest-LLVM parity.
Inherited production-row validation metadata is kept separate from the actual
executed ELF identities in `arm_dependencies`.

[evidence.tar.gz](evidence.tar.gz) retains the frozen source and patches,
executables, Wasm, LLVM and assembly; exact preparation and measurement commands,
outputs and process records; diagnostic counters; the decision rule; observer
evidence; and Scheme configuration, driver, audit and archive scripts.
`archive-paths.json` maps retained files to their original paths. Caches,
installed toolchains and duplicate run trees are omitted; manifest identities
remain. All 149 retained measurement files, the coordinator records and the
decision rule are byte-identical to their originals. Safe execution records
retain their original bytes. Any preparation
environment filtering is listed with original hashes in
`environment-filtering.json`. Internal file hashes and
[SHA256SUMS](SHA256SUMS) bind the evidence.

To inspect or reproduce the artifacts, use the recorded base revision and
common patch for both arms, then apply `experiment.patch` only to the candidate.
Use fresh output paths and the retained frozen raw guest, provider, entry and
configuration. `configure-sweep-probe.scm` names the exact arms, and
`measurement/driver.scm` retains the original schedule. The recorded result
remains rejected; a reproduction must not replace these samples or be combined
with earlier campaigns.
