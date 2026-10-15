# Frozen Rust lattice handoff

This bounded handoff reuses the validated historical Rust/WASIp1 lattice
artifact. The original input is count10, problem44, expected120549. No Rust
source changed, no binary was rebuilt, and no clean timing was run for this
handoff. Work started in an isolated worktree above
`17b0ace5b5cf2f98856ccc09b2b5bf90bb7cfdd9`; earlier String-control and full-suite
sources/artifacts remain intact.

[handoff.json](handoff.json) records the exact artifact, 11-file historical
source bundle, input, Node/WASI host, commands, working directory, predicate and
timer boundaries. [build-provenance.json](build-provenance.json) preserves the
recorded release build command/profile and Rust/Node/Chez tool identities.
Historical records lack a verbose rustc log and a complete inherited
environment; the recorded empty environment object does not establish absence
of unrecorded overrides.

The Wasm SHA256 is
`68a65476693da208b3bddd712999b6214ce35460fb7fa422783c68bd23abf0b2`
(107,659 bytes). Its lattice module SHA256,
`2e0cb4c00460675e53924ef1bde4263a5bb35981d1843a56544a479a36e37f03`,
matches the current integrated source. The historical reader is frozen with the
artifact. A later reader-expanded checkpoint has a different binary and is
reported separately.

Unchanged historical full-count observations establish the canonical predicate.
[Supplemental checks](supplemental-correctness.json) execute this exact frozen
Wasm and original Chez artifact: both pass count1/problem33/result10 and
count1/problem44/result120549, and reject wrong11 and120548. These eight bounded
executions are correctness evidence; their raw CSV durations are not clean
performance samples.

The [source comparison](source-review.md) traces componentwise partial ordering,
candidate constraints, persistent assignment tails, reversed assignment-result
order, recursive enumeration/counting and the four discarded counting calls.
Rust shares target elements and assignment tails through Rc, but contiguous
vectors replace linked lists and last-tail result-spine sharing. One Rc
assignment node replaces two Scheme cons cells, direct enum comparison replaces
per-lattice comparator closures, and prompt reference-counted destruction
replaces GC. Count summation and integer domains also differ. These changes
preserve the canonical search and asymptotic structure while changing allocation
and call costs.

[Retained-work evidence](retained-work.json) points into exact optimized Wasm:
every timed invocation materializes lower lattices, executes all four discarded
counts and performs the complete selected search. The ten-repeat loop, recursive
comparison/constraint/enumeration/count functions and final supplied equality
remain. Rust explicitly applies black_box to the problem input, returned count
and four discarded counts. No additional full-structure validation or per-node
opacity is inside timing.

This source/artifact audit is independent of the historical port author. A new
no-file behavioral explainer/debate and a complete l3/l4 payload or comparison
matrix oracle are not claimed. The historical pending-review status remains
visible. Unsupported sequence shapes, malformed inputs, nonpositive counts and
unbounded integer results outside canonical inputs are also not claimed
equivalent. Older full-suite review cohorts and the portable suite timing
driver remain separate pending tasks.

`artifacts.tar.xz` preserves all29 frozen handoff files through27 verified blobs;
its SHA256 is
`502245a1bee31deb4e529ec0a693580648dae50b6bb5c5e76f4ddc6032afcbe2`
(154,924 bytes). [manifest.json](manifest.json) maps portable relative paths to
content hashes while the reports preserve original absolute provenance.
[archive-verification.json](archive-verification.json) records every blob's
successful post-pack hash check and matching historical Rust/Chez artifact
identities. Restore beneath a scratch directory and substitute relocated file
paths while preserving input, tool identities, CLI, working-directory policy
and validation contract.
