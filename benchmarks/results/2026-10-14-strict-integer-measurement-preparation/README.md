# Independent exact-integer measurement readiness

The complete pi and Chudnovsky controls are ready for a coordinated timing
window. No clean campaign has launched. This review starts from `7479b2f` and
uses the unchanged [prepared controls](../2026-10-14-strict-integer-controls/README.md).
All evidence here is diagnostic; measured suite coverage is unchanged.

The independent audit compares every file in all four original archives with
the actual frozen artifacts, validates all 152 original full/negative/probe
records, restores the source ledgers, and regenerates the strict and three
compiled-Chez sources byte-for-byte. The shared corpus is clean at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`; it was read without modification.
The [audit](independent-audit.json) retains each archived file and record hash.

The final [timer diagnostics](timer-diagnostics-final/campaign.json) execute
all sixteen exact commands at the complete original counts: pi count 100,
all three algorithms and all ten precision rows; Chudnovsky count 1,000,
complete binary splitting and all ten results. Every process passes the full
result predicate and emits the entire expected numerical output followed by
exactly one finite, nonnegative duration. Setup and expected conversion precede
the workload clock; its final numerical predicate remains inside; decimal
rendering follows. The Scheme hosts additionally check exactly three opacity
calls per iteration. Their cost remains inside the clock.

I checked the archived production/native-final WAT, V8 code captures and native
repetition disassembly against their module/program identities. Pi retains
three returned scalar arguments feeding the full precision traversal and its
three recurrences; Chudnovsky retains the returned arguments, precision traversal
and recursive numerical path. Both native bodies decrement the repetition count
before the three opacity calls and return to the guard after the numerical work.
The final complete comparison follows the loop. The observed V8 outer bodies
are Liftoff; the existing captures include inner tier transitions. These are
observed configurations, without a claim that subsequent tiers are fixed.

The [fixed plan](timing-plan.json) guards 107 identities and preserves all sixteen
original command configurations. It freezes 144 fresh processes on CPU 5:
eight systems, two workloads, one predetermined discard and eight retained
observations per pair. Workloads run in the order pi, then Chudnovsky. The eight
retained rounds rotate the system order so each system occupies every position
once within each workload. Every discard is validated. A failure stops the
campaign and remains recorded; there are no replacement samples or later
exclusions. V8 tiers and GC settings remain at their defaults.

The deadline is fixed at 300 seconds per process. Under ongoing activity, the
final diagnostic pass used 66.78 seconds of aggregate process wall time; its
slowest complete process was checked limb-body Chez pi at 44.66 seconds. Those
observations support a 12–15 minute quiet reservation and the deadline only.
They provide no performance comparison. Original/adapted native-bigint Chez,
checked limb-body Chez and Rust retain the arithmetic, scalar, layout, opacity,
allocation and ownership differences described in the original report.

The [runner](measure.py) reuses the unchanged Matrix process supervisor, with
its complete 18-module local import closure in `supervisor/`. Default verification
checks the closure, actual module origins, helper contracts, exact commands,
environment guards and artifact identities before launching a guest. Each row
owns one process group through capture, bounded cleanup, leader reap and pipe
closure. Pending and final JSON records use atomic replacement. SIGINT/SIGTERM
request a stop without interrupting the launch/cleanup ownership transition;
the current capture obeys its fixed deadline before the stop is recorded.

[Dry verification](dry-verification.json) passed actual nonzero-exit, descendant
timeout, SIGINT and SIGTERM cases, plus seven malformed-output cases for each
of the sixteen real timer outputs. It rejects a mutated final numerical component,
truncation, duplicate clock, extra output, NaN, infinity and a negative clock.
All original and new diagnostic process groups and capture handles are terminal.
The default runner invocation also completed with no guest started.

Preparation failures remain reviewable. `failed-preparation-import.json`
records a cached import crossing frozen directories; isolated source regeneration
corrected it. `failed-source-regeneration-root-corpus.json` retains the failed
query against the uninitialized root corpus; the verified initialized shared
corpus supplies the read-only source. `failed-preparation-inventory.json` retains
the incorrect location of a retention summary. Finally,
`timer-diagnostics-attempt1/` contains fourteen valid diagnostic guests and the
identity-guard stop caused by editing the runner during that pass. The later
sixteen-command pass used one unchanged final runner identity. Neither pass
contributes retained samples.

The pinned simplify workflow used a fresh Sol 6.1/max explainer with no history,
files or tools, followed by a focused lifecycle debate. It supported direct
command data, the visible cyclic schedule, exact result framing and the existing
supervisor. The resulting changes add atomic records and handled stop requests.
Exhaustive identity/source audits, output dispatch and complete process/campaign
transactions remain longer than the ten-line target to keep their contracts
visible. No compiler, provider or previously accepted harness module was edited.

After the parent's quiet-window release, launch from the reviewed worktree:

```sh
python3 -I -B /tmp/snail-strict-integer-measurement-20261014/benchmarks/results/2026-10-14-strict-integer-measurement-preparation/measure.py --run --output /tmp/snail-strict-integer-measurement-clean-20261014
```

[Readiness](readiness.json) contains the exact launch command, terminal session
records and scheduling estimate. [Artifact identities](artifact-identities.json)
lists each system's executable/module and the native provider object. The plan
SHA-256 is `d0946c397d52f674abb5d9019afcd28f68d6e44d358a90c3e9aba89e2ad319c3`;
the runner SHA-256 is
`1607e9f88521fe88ee707ffceaf8e1554a3cd4154251c28bcb0b5811a20df4ea`.
