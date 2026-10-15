# Complete Ackermann timing readiness

Seven exact complete Ackermann configurations passed the
[timer diagnostics](timer-diagnostics/campaign.json): two repetitions of
`ack(3, 12)`, with the original expected result `32765`. The fixed runner is
ready for the parent's coordinated quiet window. **The clean 56-process
campaign has not launched.** These checks add no measured workload.

The [plan](timing-plan.json) selects production Scheme/V8, exact native-final
Scheme Wasm/V8, native64, original compiled Chez, recursive Rust native,
heap-frame Rust native, and heap-frame optimized Rust Wasm/V8. Rust's recursive
native row stays separate from its existing `--heap-frames` controls. Its raw
and optimized recursive Wasm failures at the default V8 stack remain in the
[original correctness preparation](../2026-10-14-strict-ack-preparation/README.md).
V8 stack, tiers and GC retain their defaults; the Rust WASI command suppresses
its existing experimental warning.

The schedule contains one predetermined discarded process per system, followed
by seven retained rounds. Each retained round rotates the seven systems by one
position, putting every system in each position exactly once. All 56 processes
are fresh and execute serially on CPU 5 with a 120-second deadline. Every
discard is validated. The first failure stops the campaign and remains recorded;
the runner supplies no replacement observations or continuation.

All new configurations explicitly select the prepared artifact directory as
their working directory. Chez and Rust read its complete original `input.txt`;
native64 receives the same values in its existing arguments. The older
heap/native timer records omitted working-directory, stdin and environment
metadata. [That provenance gap](diagnostic-provenance-gap.json) remains explicit.
The new diagnostics validate the new configurations; they do not reconstruct
the missing historical metadata.

The [runner](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-ack-measurement-preparation/measure.py) guards 250 identities, including all 225 original
archived preparation files, the executable/module inputs, original sources,
hosts and entry/provider interfaces, its own source, external tools, and the
unchanged Matrix supervisor's complete 18-module local import closure. The
[static inspection](static-inspection.json) compared every uncompressed original
file with its archive-manifest digest during the static-only hold. Identity
checks precede every launch and follow every outcome, including failures, and
also bracket the campaign. The plan records influential Node, native-GC, Chez,
loader, locale and timezone variables and rejects the named runtime overrides.

Workload clocks retain the prepared hosts' boundaries. Scheme V8 instantiates
the module and runs `main` before its clock; its final assertion includes
`result.toString()`. Native64 initializes before its clock, compares I64 values
inside it, then formats and cleans up. Chez retains the complete recurrence,
its original numeric predicate and its original success output frame; that
frame does not print the result value. Rust reads inputs before its clock,
retains argument selection, the full recurrence and its original assertion
inside it, then prints `32765`. Scalar opacity imports and Rust's `black_box`
retain their different optimization boundaries.

Every output must match the entire frozen system-specific frame, with exactly
one reported workload duration. Chez's two displays of its primary clock must
agree exactly. Workload and process clocks must be finite and positive.
Process time includes launch, capture, group cleanup, leader reap and handle
closure; its difference from workload time includes several kinds of overhead.
File hashing and output parsing lie outside that process interval.

The [focused verification](dry-checks/summary.json) rejected 70 malformed
variants of the seven actual outputs: altered result/unit, truncation, duplicate
clock, extra output, NaN, infinity, exponent overflow, negative time, zero time
and exponent underflow. It also rejected failed process records and changed
runner, schedule and command identities. Default verification started no
children, and reuse of the existing diagnostic directory preserved its records.
Four actual ownership fixtures exercised unsuccessful exit, a timed-out
descendant, SIGINT and SIGTERM. All diagnostic process groups and capture
handles are terminal. The reproducible check is
[tests/strict-ack-measurement/verify.py](../../../tests/strict-ack-measurement/verify.py).

Each attempt records its identity before launch. Pending, running and final JSON
records use temporary-file replacement; this is an atomic replacement guarantee.
The complete ownership operation keeps the group until actual cleanup, reap
and pipe closure. SIGINT and SIGTERM request a stop without interrupting that
operation; capture follows its deadline before the stop is recorded. Failed
attempts preserve raw output and both process and identity-check evidence.

The pinned simplify workflow used an independent explanation without code or
file access, followed by a focused lifecycle debate. Fixed command data, cyclic
scheduling, exact frame dispatch and whole ownership operations express the
model directly. Exhaustive command checks/output dispatch, CLI data, host data,
and the complete process/sample/campaign transactions exceed ten lines where
splitting would obscure their guarantees. The compiler and providers were read
without modification.

The seven diagnostics used 7.15 seconds of aggregate process wall time while
other work could occur. Eight fixed rounds imply about 57 seconds before
integrity/record overhead; reserve two quiet minutes. This is a launch estimate,
with no performance comparison. [Readiness](readiness.json) records the hashes,
terminal sessions and exact commands.

Default verification launches no guest:

```sh
python3 -I -B /tmp/snail-strict-ack-measurement-20261014/benchmarks/results/2026-10-14-strict-ack-measurement-preparation/measure.py
```

After the parent's separate quiet-window release:

```sh
python3 -I -B /tmp/snail-strict-ack-measurement-20261014/benchmarks/results/2026-10-14-strict-ack-measurement-preparation/measure.py --run --output /tmp/snail-strict-ack-measurement-clean-20261014
```
