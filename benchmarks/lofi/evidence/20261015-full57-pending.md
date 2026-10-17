# Pending draft: checked full57 evidence

**Local reporting draft; not for landing or citation as a final campaign result.**
Preparation is still running under the parent's session 64221. This document and
its [data capture](20261015-full57-pending.json) read the campaign without changing
its files or executing workloads. Performance claims remain withheld until the
parent announces measurement completion.

## Scope and current capture

The campaign is `/tmp/sfir-checked-full57-20261015-v1`, frozen at compiler revision
`8e547bfb353fa5c5aa7c17bc805db13af0d2bca1`. The reporting worktree starts at
`2b6e45880b411e4b12f09b43621f76f7ecca5ac0`; that revision does not change which
compiler produced the frozen artifacts. Later library, service and I/O changes
belong to separate evidence. Historical six-case measurements, Ack experiments
and paired input-buffer comparisons do not supply missing results here.

At the JSON capture on 15 October 2026, 17:25:34 UTC, all 57 selected static SFIR
sources existed and matched their frozen hashes. Forty-four cases had completed
validation records; thirteen had no saved case-status record. Initial compilation
can already be running before that record is created. File reads are not one
atomic snapshot while preparation runs. Per-case status files can advance ahead
of the completed prefix in `validation.json`.

| Route | Passed | Failed | Unavailable control | Not recorded |
| --- | ---: | ---: | ---: | ---: |
| SFIR Wasm | 43 | 1 | 0 | 13 |
| SFIR native | 44 | 0 | 0 | 13 |
| Chez original | 44 | 0 | 0 | 13 |
| Chez adapted | 32 | 0 | 12 | 13 |
| Rust Wasm | 43 | 1 | 0 | 13 |
| Rust native | 44 | 0 | 0 | 13 |

The failed routes are Ack's original SFIR and Rust Wasm executions. The
[Ack diagnostic](20261015-ack-stack.md) records their stack failures separately;
its private-worker and altered-tier probes cannot replace them. Absence of an
adapted Chez control means unavailable, not a successful validation or a missing
required attempt.

Neither `timing/plan.json` nor `timing/measurement.json` existed at capture.
This draft contains no execution durations, medians, ratios or timing samples.
Incidental clocks in validation logs establish none of those results.

The preparation-manifest hash identifies its captured bytes. Active preparation
can legitimately add `timing_plan_sha256` later. A changed manifest hash alone
does not imply changed frozen sources, artifacts or original validation files;
their independent identities remain authoritative. Inherited outcome fields in
`corpus.json` or manifest cases are historical metadata, never the authority for
this campaign's validation or measurement status.

## Final report structure, after completion

1. State the frozen compiler revision, source/input/tool identities, canonical
   counts and complete predicates, terminal campaign outcome and measurement
   interval. Keep source presence distinct from validation and measurement.
2. Preserve all 57 cases and six routes in the validation matrix. Record failures,
   timeouts, unsupported configurations, absent adapted controls and incomplete
   attempts explicitly, with links to their original command records.
3. Present separate clean-artifact eligibility and native optimized-guest parity.
   A validation pass or a parity-file path alone does not establish a complete
   clean measurement route.
4. Present clean medians and ratios only after the parent confirms completion.
   Reuse the frozen `timing.route_statistics` and `timing.comparison_ratios`
   contracts: complete schedule, one successful warmup, five successful samples,
   complete result/output predicates and retained quiet-window attestation. Use
   same-campaign comparisons; show original/adapted Chez separately and match
   SFIR Wasm/native to the corresponding Rust target. Withhold numbers for failed
   or incomplete routes.
5. Report build/process costs and artifact sizes separately from execution
   samples. Retain failed compilation and timeout outcomes alongside durations.
6. Archive exact final manifest, plan, measurements, terminal commands, native
   build/parity records and relevant output checks. Record each archive's hash
   and the parent's completed frozen-file verification evidence.

## Compile-cost boundaries

The final report can extract one-attempt process costs from `sfir-build`,
`native-build`, `chez-original-build`, `chez-adapted-build`, `rust-wasm-build`
and `rust-native-build` records. These are preparation observations under
contention, not a quiet compilation benchmark or guest execution samples.

`sfir-build` includes the frontend and mandatory Binaryen optimization. The native
helper consumes retained raw Wasm, performs mandatory optimization and then LLVM
lowering/linking; adding its duration to `sfir-build` repeats that optimization
cost. Rust's per-binary Cargo builds share the frozen target cache, so they are
not independent compilation from empty caches. Separate clean-entry builds and
checks also retain their own costs. Any aggregate needs an explicit scope and
must keep failed/time-limited attempts visible.

No new reporting framework or campaign command is needed for this draft. The
existing runner/timing records and helpers supply the final data once the parent
declares the campaign terminal. This pending capture must be replaced or clearly
retained as an earlier snapshot when final evidence is prepared.
