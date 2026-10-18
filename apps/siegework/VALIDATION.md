# Release validation — 2026-10-18

## Scope and checkpoints

The static 3D game is the only Siegework implementation. Parent PR
[#334](https://github.com/tsnl/snail-scheme/pull/334) landed as `266134fe` after
its complete GitHub CI passed. Earlier validation and prototype history remain
in Git and that PR. This follow-up refines colony rules, presentation boundaries,
direct tile construction, mobile controls and scene finalization. The latest
prototype removes brush planning, keeps the consolidated Pause menu and points
persistent first-extractor guidance toward the highlighted deposit.

The canonical build is `apps/siegework/build.scm`. It defaults to debug Wasm
optimization; `--release` selects the full optimization pipeline. Both profiles
include the final runtime link. A measured public Fibonacci CLI pair took
5.677 seconds in debug and 155.941 seconds in release, producing the same output.
Those are not Siegework build timings. Full game compilation still takes much
longer; per-build wall observations on this shared host are not controlled
compiler benchmarks.

## Executed checks

The previous published checkpoint is the Pause-menu package, generation
`843e8f05dadb6b5f55434e6c`. It passed 182 application checks, 18 presentation
groups, seven product-browser groups and all 19 hosting sections. Its World10
save remains compatible with this prototype; the transient Client schema is now 7.

The final direct-construction package is `build/siegework-direct-build-settled/solo`,
generation `b5c163ca67346083fc50b78b`. Its 543,980-byte simulation has SHA-256
`3305cb1b213ea0e6c517c27d1f9406034836f7899d015e4f1b3cd272c8e88a11`.
The canonical build took 139.257 seconds on the shared host; this is an
observation, not a controlled compiler comparison. The package includes the
final visual CSS and four-sample main-scene and inset rendering.

That exact final module passes all 190 actual-Wasm application integration
checks, 20 presentation groups and eight product-browser groups. The integration
total includes eight direct-placement and seven async-menu groups. The suite
covers the full 3×3 hub, paid repairs, separate artillery and
observation/logistics upgrades, retained rails, compatible World10 saves,
escalation and retaliation.

The preceding combined package, generation `dba79bfda3579e94d16f2e4f`, passed
all 19 hosting sections with the same final CSS and four-sample renderer.
The final module adds only two presentation corrections: free Close actions
on occupied-site and nest popups, and notification avoidance around victory
and defeat cards. Focused actual-Wasm and browser checks cover both corrections;
the unchanged generic hosting sections were not repeated for this final module.

The new construction checks exercise free selection, second-tap building,
success-only remembered types, deposits retaining the ordinary preference,
slow/failed/rejected orders, stale typed buttons, imports superseding older
replies, and Pause while an order settles. A queued activation after a failed
write may retry the still-unpaid order; it cannot duplicate a paid structure.
Seven async-menu groups cover delayed and failed Pause/Resume/Restart, repeated
confirmation producing one new run, selection preservation, authoritative
imports and pending placement replies. Camera handlers on an established
128-enemy colony perform no World reads.

Product checks cover 56px controls, hub actions, exact artillery coverage,
joined walls, rail clearance, camera-relative light, local attack dismissal,
selected-site popup placement and notification avoidance. The browser runner
uses real single clicks, rapid double clicks, post-render repeated taps, touch,
IndexedDB delays/failures and reload. It checks portrait widths 320, 360 and 390,
landscape 568×320 and 640×360, both handedness settings and native DPR 3.
Painted readouts and guidance consume taps instead of ordering behind the HUD.
Popup and alert layout leaves the selected tile tappable; failure diagnostics
leave retry controls reachable. Victory and defeat cards keep Restart reachable
on both control sides. The same runner retains Pause lifecycle,
rotation, pan/pinch, worker hiring, GPU readback and disposal checks.

The hosting fixture now selects a tile and uses the explicit Tower or Extractor
button. It verifies free selection, exact payment, worker kit delivery,
completion and active saved-colony reload. The full hosting runner additionally
covers transaction aborts, writer ownership, visibility suspension, hot
replacement, moved mount paths and optional checkpoint transfers through outage.

Six browser-effect groups execute real Wasm through `BrowserApplication` and
`LocalState`: reply-before-completion ordering, first/middle/last/all save
failures, a trapped World dispatch, compatible replacement with pending orders,
close during UI and clock saves, and error text after clock recovery. Failed
saves preserve committed state and leave unpaid selected sites retryable.

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
schema 7. The changed client layout requires a page refresh. Saved
colonies do not contain transient Client state. A real earlier published World10
record is reopened through the actual IndexedDB reader and `LocalState`; additive
game endpoints are allowed only when previous endpoint, state, effect, run-marker
and reset contracts remain identical. Live protocol replacement stays strict.
Incompatible saves are retained and explained, never silently reset.

Selection, the remembered ordinary kind and one pending placement are local
presentation state. Buttons capture both kind and cell. Committed replies
precede authored completion messages; only accepted orders update memory.
Rejected and unsaved selections remain available to retry. An authoritative
import supersedes the older result while retaining its occupied slot until
completion. Replacement and close drain admitted orders and replies.

The original reported invalid-transition crash and Firefox QueueId crash remain
unreproduced. A rejected transition retains the exact committed colony and one
separate command/snapshot reproduction. Inspect it with
`await snailApp.session.store.failure()` in developer tools.

Destructive browser tests use private profiles, hosts and saves. The user preview
remains on port 4212, with private mobile HTTPS on port 8443. The final package
above was published as 18 files with its manifest last. HTTP checks matched the
served manifest, simulation, CSS, renderer and browser hosts to that package;
the user's saved colony was preserved.
