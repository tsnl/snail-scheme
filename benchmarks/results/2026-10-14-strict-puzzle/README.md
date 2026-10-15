# Full puzzle preparation

All 1,000 original puzzle searches pass in raw Wasm, optimized Wasm, untouched
Chez and the adapted-source Chez control. The original size is 511 and the
original predicate checks counter 2,005. This archive contains 132 behavior
checks and separate retained-work evidence, with no clean timing observations.
Source port `5a93622c749a317fa3ac4aa364723b55ecfd8a04` adds no compiler changes;
all 52 compiler/build sources match native String basis
`2def9941eb85f211e116e6955799fdc9ef561da8`.

Puzzle uses existing Bool/I64 vectors, homogeneous lists, explicit Ref cells and
a closed false/count result. Its local escape continuation is never stored,
passed or re-entered. It becomes Boolean control: test nonzero class count before
fit, scan masks in the original increasing order, place before recursive trial,
run trial before testing the zero sentinel, retain successful placements, and
remove an unsuccessful placement before advancing the candidate. Every normal
trial return increments the search counter once. This source adaptation does
not implement general continuations. The inclusive offset scans, orientation
loops, board resets, mask resets and all original stores remain.

Both setup regions matter. Global vectors allocate before the harness definition;
the original generated list and traversal allocate thirteen fresh piece rows
after that definition and before timing. Those rows remain distinct and retain
their identities across searches. The typed outer vector receives one additional
shared empty row sentinel, replaced before timing. Omitted fills are unspecified
by Scheme; pinned Chez fills with numeric zero, which is truthy. Explicit Bool
true preserves all board/mask truth tests. Canonical resets overwrite every cell
before use; partial/initial state comparisons explicitly project through
truthiness and do not equate raw numeric zero with Boolean true.

Two global mutable scalars and two local assigned bindings use explicit Refs.
The trial's initial local zero is never read before placement replaces it, so
that result is an immutable local. A shared failure variant and one count
constructor per successful source call preserve false versus integer zero.
The adapted Chez control shares both kernel regions and these representations.
Three harness edits unwrap its result at the original equality predicate and
failure printer. Reversing all changes recovers the complete original source
byte for byte, including trailing setup. Original Chez is untouched. Physical
allocation equivalence is not claimed; optimized Wasm already removes one local
Ref while retaining thirteen orientation-index Ref constructors per repetition.

The strict harness accepts decimal I64 counts/sizes and Boolean-or-I64 expected
values, transporting large integers as decimal strings before BigInt conversion.
It returns the original predicate's acceptance flag; the native failure wrapper
reports that flag, whereas Chez prints the original value. Nonpositive repeats
perform no search or hiding calls and retain false. The actual returned hidden
size drives each positive iteration. A separate control passes requested size
512 but returns known-valid 511 from hide, and succeeds in all four forms.
Ordinary size-512 probes still fail at the original first out-of-bounds access.

[Correctness evidence](correctness-summary.json) records twelve canonical runs
at counts 1, 2 and 1,000; fifteen complete-state/effect cases across four forms;
fourteen harness boundary cases across four forms; and four returned-size checks.
Every probe step compares 7,202 observations: cursor/counter, all 512 board cells,
all 13 × 512 mask cells, class counts, classes, maxima, retained row identities
and row independence. The canonical search has an exactly matching 79,550-event
trace against both original Chez and an independent Python board model.

Probes cover place/remove round trips, recursive trial zero before its parent
succeeds, failed-branch restoration before the next candidate, exhausted classes,
negative nonzero class counts, masks suppressing invalid board reads, valid-edge
fit rejection, partial writes before bounds failures, initial/partial/repeated
resets and the initial-placement error branch. That branch emits the original
newline and `Error.` and continues searching from zero. Expected false, true,
integer zero, minimum I64 counts/sizes and wrong expected counters remain distinct.
These extra observations exist only in separate modules.

The [retention audit](retention-audit.json) inspects the canonical optimized
module, whose only exports are `bench` and `main`. Its identity import result
feeds the reset loops. Mask scans, board reads, conditional placement/removal,
class counts, recursive search and counter updates remain. Separate completed-
operation diagnostics at counts 1, 2 and 1,000 subtract all setup activity. At
1,000 they report 30,835,000 Bool stores and 4,022,000 I64 stores, exactly matching
the independent source oracle. They also complete 835,240,000 Bool array reads,
766,720,000 row-reference reads, 83,141,000 I64 array reads, 2,096,000 Ref stores,
13,000 Ref constructors and 1,000 count constructors. No arrays allocate during
the search phase; all board/mask arrays were allocated in setup.

Those counters describe instrumented Wasm instruction completions, not physical
memory accesses, allocator events or performance. Erasing the observers recovers
all 22 original function forms exactly. In default-tier code from the unchanged
canonical binary, hot TurboFan routines retain the row/mask/board loads, true
placement stores, false removal/reset stores and search recursion before the
zero-sentinel comparison. The orientation routine retains a 24-byte Ref bump
allocation path. The outer repetition routine remains Liftoff in this capture;
no claim of universal TurboFan tiering is made. Original final-counter correctness
alone would not prove retention, and legal removal of unobserved work would not
be a semantic bug.

`make test` and `make check` pass in this worktree. All 27 prior specifications
and generated strict sources remain byte-identical. The unchanged compiler's
283 strict and 20 extern contracts are inherited from the frozen native String
layer, not rerun by this source-only port. The fresh no-history/no-file Sol 6.1
maximum-reasoning explanation and informed debate are recorded in
[simplify-review.md](simplify-review.md); implementation inspection and checks
belong to the port agent. Independent source-code and observer-code audits are
not claimed. Three preparation stages are retained: canonical-only r1, complete
r2, and all 132 checks on the exact committed source in r3.

Restore and hash-verify the archive without executing a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-puzzle-replay \
  --report benchmarks/results/2026-10-14-strict-puzzle
```

The replay check records actual restored raw/optimized Wasm and both Chez
controls at count 2. No timing measurements or cross-system ratios are included.
