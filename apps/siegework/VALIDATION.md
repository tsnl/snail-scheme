# Release validation — 2026-10-18

## Recording checkpoint — 2026-10-18

The recording follow-up preserves the deployed World11 save contract. Its
canonical default-O1 package is generation `d8a53467290cafd21cbee80b`, built
from integration code checkpoint `5c4e3e49` on landed main `812ffaad`. The
586,067-byte module has SHA-256
`001be8dbe734d4f10d1a13b391aa02aa3a79f38fe203c05a4d1fb3bb9ff0b558`.

The exact package passes 218 actual-Wasm application checks, eight recording
checks, and all 20 headed Chromium hosting/storage sections. The latter includes
recording import/export, actual IndexedDB aborts, camera input during read-only
playback, stale replay input during exit, and unchanged live World, Client,
revision and saved bytes. Formatting and the book build pass. Existing linked
counter/application fixtures were reused because their source and ABI did not
change; the game itself was rebuilt with current main's build recipe.

The informed Astra review of the recorder found one input-admission race.
The corrected host binds queued input to its admission runtime; a separate
Astra source review and red/green Chromium regression verify that exiting replay
cannot redirect an old command into the live colony. No other recorder blocker
was found. The optional native-pixel-alignment candidate remains unpublished:
its low-DPR border gaps are less regular than the current continuous projection.

Recording begins at the current page's saved checkpoint. Refresh can therefore
export an existing completed colony's final state, but cannot recover its earlier
history. The 64-MiB recorder is bounded and reports eviction: a synthetic ten-minute
100-KB fixture fits in 16.8 MiB; a sustained dense 6,000-active-tick fixture retains
only the final 6m48s. These are instrumented diagnostics, not phone-FPS results.
See [the recording guide](recording.md) for replay, binary dumps and analysis.

## Idle-clock retention correction

The recorder-only correction at `9e8a4137` was repackaged with the default-O1
build recipe. Generation, Wasm bytes and SHA-256 remain exactly the same as the
recording checkpoint above; the packaged JavaScript recorder matches the
corrected source. All eleven recording checks pass against this rebuilt
package. A fresh headed Chromium run of `recording-browser.mjs` also passes,
including failed IndexedDB publication, generation changes, dump playback and
import, stale input on replay exit, unchanged live saves, and checkpoint reload.
The previous complete 20-section browser run remains the broader baseline.

A paired actual-Wasm test with an eight-entry budget and 192 idle polls ends at
live revision 199 in both versions. Previously only revisions 198–199 remained;
the correction retains all eight meaningful entries, with honest revision gaps
and no eviction. User commands, effects, advancing ticks and all history
boundaries remain recorded. An informed Astra xhigh review found no blocker and
independently passed all eleven checks. No scheduler, save or game-state rule
changed.

## Published combined World11 package

The final default `-O1` build from source `aba9a809` combines fixed model
instancing, decoded-snapshot reuse, live tower transport, houses, compact mobile
controls, the 128×128 expedition and thin tile borders. Its generation is
`bba303dd013b64224fea8ad5`, with a 583,751-byte simulation and SHA-256
`0135a3505039dc2194fd02f67ea613daaf4b69c077044c760f079471579e3101`.
All 18 files served on port 4212 were fetched and compared byte-for-byte with the
tested package. The existing preview server was retained.

World11 uses `siegework-colony-v11`, so refreshing starts a fresh colony under the
new save identity. Old World10 records remain untouched. This deliberate reset
belongs to the compact map, not the border or rendering changes. Client remains
schema 8. An already running World10 page rejects the incompatible hot update and
keeps its committed code and save until a full refresh.

The exact published package passes 218 actual-Wasm application checks, 22 product
presentation groups and all 19 hosting groups, including both persistence and
product browser input suites. Its paid seed-one expedition repeats the isolated
balance result: nest discovery at 3:12, victory at 4:40.3, 1,240 ore spent and 44
remaining. This eager fixture establishes feasibility, not an ordinary player's
completion time. The unchanged library pipeline passes 12 actual-Wasm groups
and 14 headed GPU groups, including the copied-matrix boundary correction,
retained instances, motion/reveal clocks, native insets and exact resource cleanup.
Repository formatting and book-source checks also pass.

Thin borders use a one-percent inset of the existing terrain occurrences. They
add no mesh vertices, prototype buffers or draw pass. Native screenshots cover
1100×760 at DPR 2, 390×844 at DPR 3 and 568×320 at DPR 2, each at 0°, 45° and 90°,
plus water and a fresh fog reveal. A paid five-building colony retains 17 fixed
GPU meshes for 390–403 occurrences across these views. The product browser suite
also verifies three houses and three workers in shared indexed draws and no new
mesh uploads on the next tick. No MSAA, resolution reduction or pixel snapping
was introduced.

The independent informed Astra review found no remaining source or artifact
blocker after checking the numeric correction, combined source, exact package
hash, browser logs and native screenshots. Exact-head GitHub CI and landing are
tracked in [PR #338](https://github.com/tsnl/snail-scheme/pull/338).
The paired CPU report below remains a comparison of its named World10 packages;
it does not include the later numeric guard, compact map or border refinement.

The remaining sections preserve the evidence for earlier individual checkpoints.

## Earlier isolated compact expedition checkpoint

The default O1 build in `build/compact-final/solo` produced generation
`4f105c10d1e2aaa848b69bde`, a 563,731-byte simulation with SHA-256
`b53c04555e42ecfba644e6028e52559b839ee27028680a11baecb5970012e7da`.
The map is 128×128, with radius-eight hub jitter and nest displacement of
32–40 cells on its major axis and at most eight on the other. The nearest map
edge remains at least fifteen coordinate steps away. Nest clearings take
precedence over local rocks, including where the compact nest meets the starter
neighborhood. Nest tiles never contain ore. If the rich eastern deposit shares
the nest's exact position, it moves one clear cell west. All 65,535 seeds retain
their northern and eastern deposits; the eastern deposit is always buildable
ground.

Compiled terrain checks cover all 65,535 seed placements and 194 sampled actual
walking routes. The sampled nest routes are 32–53 cells, averaging 41.65. The
wave opening is 45 seconds, ordinary waves are thirty seconds apart, strength
steps are ninety seconds apart, raids replace waves starting at 2:15, and the
first boss arrives at nine minutes. Ordinary count growth remains slower at
4.5-minute steps. Survival at ten minutes remains an active run; destroying the
nest remains the only victory condition. Prices, ore production and weapon
damage are unchanged.

The final linked package passes all 208 application integration checks, including
the compiled terrain fixture, paid construction, combat, serialization and HUD
countdowns. Three invalid typed application fixtures fail compilation as expected.

The paid seed-one expedition fixture discovers the nest at 3:12, first damages
it at 3:30 and wins at 4:40.3. It produces 1,256 ore, spends 1,240, finishes with
44 spendable ore, loses five frontier buildings and kills 35 enemies. Its hub
retains 300 health. All orders use ordinary visible locations and paid model
operations; no snapshot edits, free resources or removed enemies support this
result. This northward, two-second decision fixture demonstrates an affordable
offensive expedition. It does not establish a normal player's ten-minute run
or a competent search policy for every seed. Human pacing remains to be playtested.

The separate three-minute-discovery, half-DPS capacity guardrail passes all
20 windows through 10.25 minutes and all 759 through 360.25 minutes. Its tightest
ten-minute window has 7.67 times the wave's required damage; the six-hour minimum
is 6.45 times. These idealized budgets exclude travel, construction and combat
losses. They do not establish survival or victory. Reports are generated by
`scripts/test-applications`; the focused pacing run is documented in
[`tests/applications/README.md`](../../tests/applications/README.md).

World11 uses `siegework-colony-v11`. A real World10 record is rejected explicitly
by the storage contract and snapshot-schema checks; neither check mutates the
current colony or the old record. Old browser saves remain under their existing
application identity. This is a deliberate prototype reset, not a migration.
Browser/GPU publication validation belongs to the combined renderer checkpoint.

The focused simplify pass used an independent explanation of map bounds, attack
timing and saved geography. Direct seed formulas and one model-owned pacing
contract express those rules without a second map generator or pacing state.
The test policy remains one explicit ordered decision operation so its spending
priorities can be read together; it is intentionally longer than the usual
ten-line function target.

## Fixed models, houses and live transport — combined World10 checkpoint

The combined package uses immutable colored model vertices and indices shared by
actual GPU instances. Tiles, composite buildings, workers, freight and enemies
reuse fixed meshes; changed batches upload occurrence transforms and current
normal matrices. Aimed guns remain separate instances. Native HiDPI rendering,
single-sample coverage, the 2:1 dimetric camera and smooth Q/E rotation remain.
Houses, contextual hub hiring, live tower transport, CSS upgrade indicators and
compact attack alerts are included. Product alerts no longer create inset scenes;
the library inset API is still exercised independently.

The canonical default `-O1` package is generation
`2ffe90d18d12b3cb9fb2dc6a`, with a 583,357-byte simulation and SHA-256
`809d28a60d8ebecaf832d6966de3ac39e23ba0a92518773bca1ace40eb62f3db`.
A second canonical build after Scheme formatting produced the same generation
and simulation hash. World remains schema 10 and Client is schema 8. The new
scene provider ABI needs the matching host package: an older host rejects the
new module before replacement and retains its committed instance, state and
presentation. Reloading the complete package preserves compatible World10 saves.

The implementation checkpoints are `7b15f216` (scene/model ABI and GPU resources),
`eebf4c9b` (stable physical Q/E order on narrow left-handed layouts), and
`2c1f0b1b` (fixed product models). Validation of this exact module passed:

- 218 actual-Wasm application integration checks, including shared tile, house
  and worker prototypes, retained geometry and tick-only instance replacement.
- 22 product presentation groups, including house roofs, shared plinths, all
  stacked artillery levels and the corrected level-three brass placement with
  no overlapping coplanar outward faces.
- 12 generic actual-Wasm draw3d groups and 13 headed Chromium/WebGPU groups.
  Pixel probes cover ordered A/B/A blending and opaque ties, nonuniform normals,
  motion endpoints and clocks, phased opacity, reveals and native-DPR insets.
  Every allocated buffer and texture is destroyed exactly once through resize,
  replacement, omitted models, pending readback and shutdown.
- All 19 static-hosting groups, including persistence and product browser input.
  The product GPU capture draws three houses and three workers as shared
  instances; one frame uses 11 mesh buffers for 271 occurrences. Its next tick
  adds no mesh uploads. Native DPR 1, 2 and 3 remain covered.
- 60 paired steps against the immutable expanded-renderer baseline, with exact
  owner snapshots and complete UI output. Current/prior endpoints and normals
  differ by at most 0.00001404; terrain retains its colored triangle multiset.

The focused simplify pass used an independent behavioral explanation before the
renderer rewrite. Default batches preserve node order; only explicit opaque
unordered terrain may regroup instances. Prototype caches retain the completed
frame's live references, not historical geometry. Generation ownership and failed
preparation keep candidate resources separate from committed rendering. The
final informed release review and publication are separate from this checkpoint.
A subsequent bridge-boundary correction (`3c9cb696`) rejects matrices made
singular by binary32 copying and nonzero subnormal normal coefficients. All
12 actual-Wasm groups and 14 GPU groups passed, including failed-current/prior
retention and a lit anisotropic triangle with a normal coefficient near 1e-36.
These follow-up checks are separate from the recorded package validation above.
Repository formatting and book-source checks also passed.

The [paired measurement report](../../doc/measurements/fixed-model-instances-2026-10-18.md)
records the exact baseline, candidate, raw results and limitations. On the shared
host, grown-colony tick/view medians fell from 18.94–19.29 ms to 2.57–2.71 ms;
96-enemy encounter medians fell from 21.37–21.99 ms to 7.19–7.65 ms. One warmed
encounter tick transfers 132,504 bytes instead of 1,803,192 bytes, with zero mesh
bytes; retained and camera-only views upload nothing. These are CPU and payload
diagnostics. Chromium used SwiftShader for GPU correctness, not physical GPU FPS.
The separate compact-map/World11 pacing change is outside this measurement.

Reproduction commands (the browser runners require a private static server and
Chromium CDP endpoint):

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
node tests/applications/runtime.mjs build/siegework/solo /path/to/application-async-tests build/siegework
node tests/draw3d/colony.mjs build/siegework/solo
node tests/draw3d/playtest.mjs build/siegework/solo
node tests/draw3d/onboarding.mjs build/siegework/solo /path/to/saved-fixtures
scripts/test-draw3d
node tests/draw3d/browser.mjs http://127.0.0.1:PORT/draw3d-tests/ http://127.0.0.1:CDP
node tests/draw3d/colony-browser.mjs http://127.0.0.1:PORT/ http://127.0.0.1:CDP
node tests/draw3d/instance-profile.mjs /path/to/baseline/solo build/siegework/solo /path/to/saved-fixtures /path/to/results.json
```

The checkpoints below are historical records. Their pending checks and rendering
policies describe their own source and artifacts, not the combined result above.

## Earlier live transport source checkpoint

This checkpoint replaces persistent track geometry with a fresh deterministic
rooted transport tree each tick, adds display-clock path phases and shared open
stone plinths, makes every completed tower a cart station, and doubles both cart
speeds at each tower level. The slower endpoint sets the link speed; the hub is
level three. Artillery levels show one, two or three stacked gun assemblies.
Kind-four buildings now have house geometry; house population rules and the
native-resolution host are separate integration changes.

The canonical debug build in `build/siegework/solo` produced generation
`36ce0edd407b8069deda2284`, a 560,887-byte simulation with SHA-256
`df383ddeb6c3f7c76fc4ef66064a4e2873bbe2e11dccd54816dfdce839f40c6c`.
It passes 199 actual-Wasm application checks, eight existing presentation groups,
and ten focused transport checks (the final cycle/missing-parent case was added
after the full 199-check run). The transport checks include a separate Kruskal
cost oracle, stable topology, newer parents, disconnection, source-owned cargo
refunds, destruction, saved alternative routes, graded movement across corners,
an eight-cell U-shaped ride, pause and legacy track geometry removal.

Nine generic scene/bridge groups pass using the existing linked primitive
fixtures with the current JavaScript hosts. Eleven private Chromium/SwiftShader
renderer groups pass, including a phase crest moving along eight retained
groups, pixel changes between simulation ticks and no additional geometry
uploads. These use the actual WebGPU API with a software adapter, not hardware
frame-rate measurements. Generic inset contracts remain tested independently of
the product's separate notification changes.

The new mesh regression passes house roofs, shared plinth clearance and all
three artillery stacks. It also detected a remaining coplanar overlap between
the level-three tower support and its brass decoration. The source moves that
decoration into the front bay; **this last geometry-only correction has not yet
been compiled**. The combined build must rerun `tests/draw3d/playtest.mjs`, check
the result at native resolution through all camera snaps, and complete the
fresh informed review before publishing this source checkpoint.

`tests/applications/transport-profile.mjs` is an instrumented CPU diagnostic on
the same module. It constructs checked 16/64/256-depot chains over seed one's
open home terrain with two idle workers and no enemies. Decode median/p95 times
were 0.55/1.07, 1.64/3.55 and 11.66/14.25 ms. Warm complete-tick medians were
2.01, 6.59 and 28.48 ms; the 256-depot p95 was 29.27 ms and its first tick took
31.89 ms. Complete ticks include both fresh tree computations, worker dispatch,
serialization and boundary validation. These shared-host observations are not
isolated MST benchmarks or a claim about a full combat colony.

The focused simplify pass used an independent behavioral explanation and
debated infeasible graph edges and cargo ownership before implementation.
Path-map and canonical-route caches reuse only exact passability inputs;
topology itself is recomputed. A restored legal directed route retains its
own progress instead of being replaced by a warm cached alternative. One
bounded movement operation spans several segments without processing another
job. The existing two-pose renderer still interpolates a chord across a corner
for up to 100 ms; authoritative movement follows every route segment.

Reproduction commands:

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
node tests/applications/runtime.mjs build/siegework/solo /path/to/application-tests build/siegework
node tests/applications/colony-transport.mjs build/siegework/solo
node tests/applications/transport-profile.mjs build/siegework/solo
node tests/draw3d/colony.mjs build/siegework/solo
node tests/draw3d/playtest.mjs build/siegework/solo
node tests/draw3d/run.mjs build/transport-draw3d
node tests/draw3d/browser.mjs http://127.0.0.1:4237/transport-draw3d/ http://127.0.0.1:9477
```

The historical checkpoints below describe their own rendering policies and
published packages, not the pending combined release.

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

## Earlier house and contextual feedback source checkpoint

The source now replaces walls with houses (12 base worker places, four per
completed house, maximum 64), keeps repeated hiring in the selected hub, retains
actual construction rejection reasons in the selected popup, shows CSS upgrade
waiting indicators, and removes product attack thumbnails. World remains schema
10; transient Client is schema 8. Old kind-four saves retain their eight-ore
ledger and become houses. The abandoned wall planner and contact-input extension
are absent from this checkpoint.

Scheme source parsing and JavaScript syntax checks passed. Actual Wasm, product
browser and hosting validation for the combined transport, housing, feedback and
native-resolution package are pending integration; the earlier unpublished wall
prototype build is not validation of this source and must not be published.

## Executed checks

The current viewport revision restores native HiDPI world rendering, with no
MSAA. The canvas backing dimensions follow the device-pixel ratio; DOM controls
and text also retain native HiDPI resolution. The orthographic camera keeps 30°
elevation and diagonal quarter-turn snaps for 2:1 dimetric ground diamonds.
Intermediate rotations remain smooth; picking, pan and camera-relative light
continue using the same camera basis.

The current published package is `build/siegework-cache/solo`, generation
`ae733e7b2bcc57d95974ba65`, built at `1a0f2403`. Its 546,626-byte simulation
has SHA-256
`64e4cbd2288679a9bf075f92c6857c26726c9948b6a9423807a2d735091bf9da`.
It preserves the native viewport and existing World10 colonies. Refresh once
for the added host snapshot-identity provider.

This exact package passes 199 actual-Wasm application checks, 21 presentation
groups and all 19 Chromium hosting/storage sections, including both product
browser suites, hot replacement, failed writes, restart and saved reopen.
All 18 published files on port 4212 were compared byte-for-byte against this
package. Formatting and the book build pass.

A bounded cache reuses three validated typed snapshots per owner and module
instance. Newly encoded candidates still undergo complete validation before
persistence. Sixty complete baseline/candidate output and snapshot comparisons
match. Shared-host encounter tick/view medians fell from 26.43–27.52 ms to
17.27–17.85 ms; these CPU diagnostics do not establish hardware frame rate.
See [the cache measurement report](../../doc/measurements/decoded-snapshots-2026-10-18.md)
for raw rounds, work counts and the required application purity contract.

The following native-host checkpoint predates the cache implementation.

The native host checkpoint is `build/siegework-native/solo`, generation
`97a05e81371239ddd43bad09`. It repackages the existing canonical debug Wasm with
the updated settings and browser host. Its 542,560-byte simulation has SHA-256
`2a3b5ea33b3801da5d8c90c84a2efafd108276237ee4f87cea4fba56777cb82d`.
No compiler, Scheme scene or shader source changed for this checkpoint.

That exact module passes 190 actual-Wasm application checks and 21 presentation
groups, including all four 2:1 camera snaps, projected picking, screen-aligned
drag and camera-relative lighting. Eight scene-fixture groups pass, including
native DPR 1, 1.25, 2, 3 and 4 at odd viewport dimensions, DPR-only resizing,
stale and accepted generation installation, rollback and one-pixel bounds.
Fixture Wasm is reused because its Scheme source and execution ABI are unchanged.

Private headed Chromium with Xvfb and Vulkan SwiftShader passes ten renderer
groups and nine product-browser groups. Renderer checks cover single-sample
coverage, inset cameras, shader replacement and rollback, queued readback,
resize, retained animation, and exactly-once texture destruction. Product checks
verify native world and DOM screenshot dimensions at DPR 1, 2 and 3 on an odd
1101×761 CSS viewport, unchanged logical input, accepted and rejected code
replacement, touch construction, menus and saved reopen. These software GPU
checks do not establish hardware frame rate or thermal behavior.

The native checkpoint replaced the earlier quarter-resolution package on port
4212, and the cache package above now supersedes it. World10 saves remain
compatible. The original invalid-transition and Firefox QueueId reports remain
unreproduced; this revision does not claim to fix them.

### Earlier checkpoints

The superseded quarter-resolution viewport package was generation
`76028643ef515259bfdc74bb`, with a 543,943-byte simulation and SHA-256
`2d2cc87e239d10965ee85dc2ac7eb7813c15b82ed83fbc0d630b7a463f9f2192`.
It passed 190 application, 21 presentation, 19 hosting, ten renderer and nine
product-browser groups. Its publication preserved World10 saves. That reduced
resolution policy has been removed in favor of the native dimetric view.

The earlier Pause-menu checkpoint was generation
`843e8f05dadb6b5f55434e6c`. It passed 182 application checks, 18 presentation
groups, seven product-browser groups and all 19 hosting sections. Its World10
save remains compatible with this prototype; the transient Client schema is now 7.

The earlier direct-construction package is `build/siegework-direct-build-settled/solo`,
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

Before the quarter-resolution viewport revision, private Chromium/SwiftShader
resource checks used native DPR 3, including a
1170×2532 backing canvas. Buffer/texture counts stayed bounded in the measured
windows, and close released the tracked resources. They do not establish phone
frame rate, thermal behavior or the absence of a long-session leak. Full snapshot
encoding/decoding, garbage collection and animated views remain
measured costs; the finalization change is not a complete mobile performance fix.

## Saves, replacement and diagnosis

The current application ID is `siegework-colony-v11`, with world schema 11 and client
schema 8. Compact geography deliberately starts a fresh identity and rejects
World10 imports. Saved colonies do not contain transient Client state. Additive
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
remains on port 4212, with private mobile HTTPS on port 8443. Publication details
for the current viewport revision are recorded above.
