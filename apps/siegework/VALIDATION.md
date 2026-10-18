# Release validation — 2026-10-18

## Scope and checkpoints

The static 3D game is the only Siegework implementation. Parent PR
[#334](https://github.com/tsnl/snail-scheme/pull/334) landed as `266134fe` after
its complete GitHub CI passed. Earlier validation and prototype history remain
in Git and that PR. This follow-up refines colony rules, presentation boundaries,
brush planning, mobile controls and scene finalization.

The canonical build is `apps/siegework/build.scm`. It defaults to debug Wasm
optimization; `--release` selects the full optimization pipeline. Both profiles
include the final runtime link. A measured public Fibonacci CLI pair took
5.677 seconds in debug and 155.941 seconds in release, producing the same output.
Those are not Siegework build timings. Full game compilation still takes much
longer; per-build wall observations on this shared host are not controlled
compiler benchmarks.

## Executed checks

The compact edge-strip checkpoint passed all 175 actual-Wasm application
integration checks. These cover the full 3×3 hub, paid worker repairs, separate
observation/logistics and artillery upgrade trees, retained rails and compatible
World10 saves, gentler escalation, retaliation and brush-order settlement.
The latest rotation/dismissal package is checked separately before publication.

Six browser-effect groups execute real Wasm through `BrowserApplication` and
`LocalState`: reply-before-completion ordering, first/middle/last/all save
failures, a trapped World dispatch, compatible replacement with pending orders,
close during UI and clock saves, and error text after clock recovery. Failed
saves preserve committed state and leave unpaid planned cells retryable.

The scene fixture runner passes all eight groups, including exact dependency
reuse, motion endpoints, independent insets, malformed-frame rollback, immutable
numeric arrays, native DPR and sharp reveal contours. A pure difficulty fixture
checks normal and doubled model intervals, cap and bounds. Product checks execute
the game Wasm to inspect hub actions, combined artillery coverage, joined walls,
rail clearance, camera-relative lighting and presentation-only commands.

`make test`, `make check`, CI coverage-planner tests and the book build pass.
The applications CI job builds Siegework and executes its application, UI and
3D suites; backend correctness remains partitioned across the other jobs.

The source-derived `max-dps-test` passes 379 waves over its default finite
horizon at three-minute deposit discovery and 0.5 utilization. Its tightest
capacity/health ratio is 12.95× under an optimistic investment heuristic. This
assumes free exploration, construction, hauling and relocation, perfect gun
coverage and no losses. It is a damage-capacity guardrail, not proof of an
optimal strategy or of survivable gameplay. See
[the test assumptions](../../tests/applications/max-dps-test.md).

## Performance and resources

The numeric scene-finalization change avoids recursively copying already checked
geometry. On the bounded three-inset fixture it removes `Object.values` traversal
of 26 arrays containing 333,334 numeric entries per changing frame. Alternating
shared-host measurements and complete output/snapshot comparisons are recorded
in [the measurement notes](../../doc/measurements/scene-finalization-2026-10-18.md)
and their raw JSON. Geometry stays frozen; wrappers and reveal metadata retain
recursive finalization. Resolution and animation scheduling are unchanged.

Private Chromium/SwiftShader resource checks used native DPR 3, including a
1170×2532 backing canvas. Buffer/texture counts stayed bounded in the measured
windows, and close released the tracked resources. They do not establish phone
frame rate, thermal behavior or the absence of a long-session leak. Full snapshot
encoding/decoding, garbage collection and animated high-resolution views remain
measured costs; the finalization change is not a complete mobile performance fix.

## Saves, replacement and diagnosis

The application ID remains `siegework-colony-v10`, with world schema 10 and client
schema 5. The new host code and client layout require a page refresh. Saved
colonies do not contain transient Client state. A real earlier published World10
record is reopened through the actual IndexedDB reader and `LocalState`; additive
game endpoints are allowed only when previous endpoint, state, effect, run-marker
and reset contracts remain identical. Live protocol replacement stays strict.
Incompatible saves are retained and explained, never silently reset.

Brush plans are local presentation state. Done submits independent paid orders;
there is no batch-wide atomicity. Committed replies precede authored completion
messages, so rejected and unsaved cells remain available for retry. Replacement
and close drain admitted orders and their replies.

The original reported invalid-transition crash and Firefox QueueId crash remain
unreproduced. A rejected transition retains the exact committed colony and one
separate command/snapshot reproduction. Inspect it with
`await snailApp.session.store.failure()` in developer tools.

Destructive browser tests use private profiles, hosts and saves. The user preview
remains on port 4212, with private mobile HTTPS on port 8443; publication replaces
the complete package with its manifest last and preserves the user's save.
