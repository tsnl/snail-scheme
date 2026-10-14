# Complete Puzzle comparison

| Variant | Median seconds | Range |
| --- | ---: | ---: |
| Strict Snail on V8 | 1.108720 | 1.105937–1.112014 |
| Original Chez | 0.957874 | 0.951007–0.960494 |
| Adapted-source Chez | 0.949335 | 0.941587–0.957843 |
| Rust/Wasm | 0.455568 | 0.455117–0.456255 |

Strict Snail takes 1.157× the original Chez time and 2.434× the Rust/Wasm
time on this full workload. All 20 executions pass, including one discarded round
and four retained cyclic rotations. Each implementation appears once in each
ordinal position. Original inputs remain 1,000 searches, size 511 and expected
trial counter 2,005. Strict returns the original predicate's acceptance flag.
The implementations share one coordinated CPU 5 window with agent-controlled
builds, tests, profiles and compression paused. Unrelated activity is not excluded.

## Source and representation

The [preparation](../2026-10-14-strict-puzzle/README.md) preserves both untimed setup
regions, every complete search/reset, recursive trial before the zero-sentinel
check, successful placements and failed-branch restoration. Its bounded local
escape becomes Boolean search control; this does not implement general continuations.
Mutable scalars use explicit Refs and the false/count result is a closed variant.
Typed Bool/I64 storage replaces generic vectors. The adapted Chez control uses
the same source adaptations; the original Chez program is unchanged.

The preparation retains 132 behavior checks, complete board/mask/row-identity
comparisons and an independent board oracle. The canonical 79,550-event search
trace matches original Chez. Separate completed-operation diagnostics and exact
optimized/default-tier disassembly establish retained reset stores, fitting,
placement/removal, search recursion and counters. These diagnostics are not
timing artifacts. In particular, the search retains its 13 orientation-index
Ref allocations per repetition; the strict compiler is unchanged in this port.

The frozen Rust reference uses unpacked byte Bool vectors and Wasm32 usize
classes/maxima/counters. Its owned Puzzle is reused across searches; recursive
calls borrow it directly. It retains the original reset, fitting, backtracking,
recursive-before-sentinel order and final counter predicate. Native Rust tests
also check the complete filled board and repeat reset/search; no complete-board
dump from the actual timed Rust Wasm is claimed. Rust asserts search success
where original Scheme can return false; the comparison is scoped to the checked
canonical fixed geometry. The parent inspected its actual source before timing.

## Timing, validation and artifacts

Each workload timer includes all repetitions and its final predicate. Compilation,
process startup, input parsing and initial owned/module setup are outside timing.
Per-repetition resets remain inside. Node 24.19 uses default tiering, with no
NODE_OPTIONS, profiler or validation counters. `clean.json` retains commands,
stdin, stdout/stderr, individual samples, process elapsed times and unchanged
source/artifact/tool identities. The strict source is the exact frozen preparation
already reviewed in PR106; Rust reuses its validated frozen executable without
a rebuild or a benchmark rewrite. Its original build workflow and a separate
reconstruction-command clarification are preserved in the handoff supplement.

`artifacts.tar.xz` contains the exact programs, source, specifications, compiled
Chez modules, Rust source/build handoff and measurement driver with a path map.
`manifest.json` checks every member; external Nix tools remain identified by hash
and path. The clean driver uses one discarded round plus four cyclic rotations.
Replaying on another path or machine requires remapping paths and freezing a new
observation set, while retaining all original non-diagnostic workload settings.

This adds one measured workload to the strict coverage inventory: 28 of 57 at
their recorded compiler checkpoints, with 27 paired Chez comparisons. It does not
establish whole-suite coverage or whole-suite performance.
