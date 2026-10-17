# Staffed colony validation

The 2026-10-17 staffed-colony package uses generation
`e11ebb903197e057398944d0`, world/client schema 4, Node 24.19.0 and Chromium
152 with real WebGPU on the isolated SwiftShader software Vulkan adapter.
These are correctness and playability checks, not hardware performance or
Firefox stability evidence.

All 42 application integration checks pass against the compiled Scheme/Wasm.
They cover physically occupied mining slots, capacity upgrades, zero output
from empty/incoming slots, a sole worker mining and delivering, immediate nearby
task chaining, escape when the home route is dangerous, return to work, casualty
and raw-ore conservation, construction/repair kit loss exactly once, one persisted
emergency worker assembly, encountered-infrastructure damage, bounded copied-location
alerts, pause, same-seed replay, invalid seed rejection and seed/marker wrapping.
The original immutability, tower discovery, physical construction, multiple-mine
delivery, raid recovery, camera, shot and durable multiplayer checks also pass.
An undefended healthy hub can lose to the finale; a defended seed-1 colony wins.
Kills produce no ore. This demonstrates a possible win, not balanced difficulty.

The final two-client Chromium run on disposable port 4178 passed native seed-form
submission, shared restart and invalid-range rejection, actual keyboard/pointer
construction, WebGPU readback, live combat with cargo in transit, shared pause,
and changed compatible Wasm with the complete paused colony, overscrolled camera
and pending request preserved. It also rejected an incompatible run-marker offset,
invalid shader and incompatible schema, recovered to a valid package, checked
map/minimap boundary pixels, rejected margin placement and resumed the simulation.
The final generic input/form browser suite also passed on the same isolated browser.

Screenshots `build/playtest/colony-staffed.png` and `colony-sheltering.png` render
compiled-model checkpoints through the real browser/GPU. The danger checkpoint
deliberately positions attackers to expose the boundary; it is not a natural-play
claim. Their exact status text is in `colony-ui-status.json`. A fresh Astra low
reader correctly identified two miners and two haulers, occupied-slot production,
mine stock versus delivered ore, and four living workers sheltering because of
danger. It distinguished lost ore from worker deaths and understood both seed
restart controls. No further presentation fix was required.

The terrain fixture executes as Wasm and checks the original seed-1 geography,
eight golden map fingerprints and 970 routes across 194 sampled seeds, including
survey and hazard boundaries. Several seeded colonies also produce and physically
deliver ore in the compiled game tests. The generator is a bounded layout family,
not an unconstrained procedural terrain system.

The optional run-marker authority boundary is exercised with same-seed accepted
restarts, rejected seeds, duplicate receipts, stale queued commands, commit failure
and reload configuration mismatch. A hostile compiled transition returning an
invalid Unicode label verifies that output conversion fails before persistence,
state installation or epoch publication. Cold-start configuration must match the
saved package; there is no durable policy migration framework.

The live 4175 authority was stopped before backing up its latest package and
SQLite database in `build/siegework-backup-world3-20261017`. The explicit schema-3
to schema-4 upgrade passed both old and new codecs and retained revision 33814,
epoch/receipts, tick 1160, 105 ore, four structures and nine workers. Only the schema
word, seed 1 and nine newly defined worker-health words changed; the previous
geography and all existing colony values were preserved. The user then started a
new seed-2 run on the new package. Evidence is in `build/playtest/schema4-upgrade.json`.
This is a deliberate local upgrade, not automatic schema migration. Port 4173 and
the previous packages/databases remain intact.

Focused no-history Astra Max explanation/debate passes covered the staffed-worker
ownership model, seeded terrain, worker/alert presentation, generic smooth input,
integer forms and the authority restart boundary. They retained direct immutable
records, checked assignments and explicit cargo ownership. Completion now assigns
nearby work before a later worker can reserve it; output is materialized before
durable commit. A separate death queue, general job framework, stored terrain grid
and general schema migration system would add machinery without resolving a
current requirement. Cohesive record/codec rows, exhaustive job transitions,
input-event boundaries and view composition remain exceptions to the ten-line
target.

Fresh Astra low public-interface reviews identified misleading seed restart
labels, ambiguous selection and worker-state wording. The interface now distinguishes
the pending seed from the active map, states the shared restart consequence,
labels blocked workers as sheltering at the living hub, and shows occupied and
incoming mining slots separately. It does not imply that idle or game-over workers
are fleeing.

`make test`, `make check`, `scripts/test-build`, the mdBook build and whitespace
checks passed. Generic browser input tests cover actual keyboard/pointer/native
form input and injected gamepad samples; no physical controller was used.

Compilation remains a development cost. The first successful staffed-colony build
spent about 7 minutes 32 seconds between shader and simulation output. The final
game build, concurrent with seven game-linked fixtures, took about 10 minutes
7 seconds; fixtures completed over about 8 minutes 47 seconds to 9 minutes
33 seconds. Each compiler process used approximately one CPU at the last sample.
These are wall-clock observations, not profiling evidence. Several generic runtime
failure fixtures currently import the whole game and repeat its compilation.
A follow-up can use a small application for generic contract failures while
retaining a smaller real-game integration set; this change does not restructure
the tests while validating the deployment.

## Previous smooth-camera checkpoint

Smooth camera follow-up: compiled colony scenarios verify frame-time partitioning,
negative fractional camera flooring, all four overscroll bounds and margin rejection.
Actual Chromium 152 input on isolated port 4177 recorded subcell movement while
holding D, stopped on release, and placed the starter extractor at (12,20) after a
fractional negative pan. GPU readback and a screenshot passed. The generic input
suite separately covered variable frames, capped stalls, axis magnitudes, focus,
visibility, reconnect and legacy controls; no physical gamepad was used.
The 4175 update retained every authoritative world word, revision and receipt;
only the local client schema changed from 3 to 4, requiring a page refresh.

# Earlier colony checkpoint

The 2026-10-17 colony checkpoint uses generation `c0e0045c96df267e73aef205`,
world/client schema 3, Node 24.19.0 and Chromium 152.0.7977.82 with real WebGPU
on the isolated SwiftShader software Vulkan adapter. This is correctness and
playability evidence, not hardware performance or Firefox stability evidence.

The compiled colony scenarios cover two mine deliveries, completed-tower discovery,
radius upgrades, surveyed-route rejection, remembered geography after destruction,
interrupted kit ownership, bounded repairs, actual raid targeting and rebuilding,
malformed claims/routes, an undefended healthy-hub finale, all four camera margins,
manual pause/planning and fixed shot endpoints. A defended fixed layout exterminates
the final threat at tick 4504 (7:30.4), with ore balance checked across kills. Kills
produce no resources. This establishes a possible win, not balanced difficulty.

Actual keyboard and pointer play on disposable port 4176 verified worker-built
construction, shared Pause/Resume semantics, queued work while paused, camera
overscroll, rejected margin placement and GPU-rendered map/minimap boundaries.
A compiled firing checkpoint rendered its traveling shot in the same browser.
The complete two-client browser runner also passed shared purchases, active hauling
and combat, pause across visibility changes, identical paused colony/camera/pending
requests through changed compatible Wasm, invalid-WGSL/schema rejection, continued
GPU rendering and resumed simulation. `make test`, `make check`, `scripts/test-build`,
the mdBook build and whitespace checks passed for this checkpoint.
The generic input runner also passed focus/native controls, held repeats,
injected controller axes/reconnect, scaled pointer and responsive-layout checks.
No physical controller was used. Screenshots are local evidence under
`build/playtest/boundary-pause.png` and `build/playtest/shot.png`.

The live 4175 colony was stopped and backed up before an explicit schema-2 to
schema-3 conversion. The new codec validated the saved colony; only its schema
word changed. Revision 9059, tick 4568, epoch/retry receipts, 1679 ore, 20 structures
and 12 workers were retained. The old package and SQLite database remain together
in `build/siegework-backup-schema2-20261017`; 4173's earlier prototype was untouched.
This was a deliberate local upgrade, not automatic/general schema migration.

A fresh no-history Astra Max explained the colony ownership and route contract
without source access. The focused simplify debate replaced split assignment
checks with one prepared assignment that owns its checked path before reserving
materials, replaced a hardcoded worker reservation with a dynamic hauling reserve,
removed unused enemy cooldown state, and strengthened the snapshot decoder's
cross-record kit/path checks. Record/codec rows, exhaustive transitions and view
composition retain cohesive exceptions to the ten-line target. A separate input
explanation pass established per-trigger deadlines, no catch-up, and release
latches after focus/device/settings changes.

A fresh Astra low newcomer read only the public interface, screenshot and then
player guide. It correctly understood tower discovery, physical delivery, pooled
labor, upgrades and zero kill income. Its confusion led to a visible legend and
first-action cue, hover/cursor selection instructions, explicit range hints,
installed-upgrade labels, and a separately labeled last-order result. The guide
now explicitly distinguishes mine stock from spendable delivered ore.

The older two-minute prototype's validation remains below as historical evidence.

## Earlier two-minute prototype

The browser checkpoint on 2026-10-16 used compiler base `4525dda7` and packaged
artifact generation `8c6d44d9733225ec5c8b9da4`. Later library checks are recorded
below.
These are correctness checks, with no performance or hardware-GPU claims.

| Environment | Observed |
| --- | --- |
| Compiler host | Chibi 0.12.0, Binaryen 132 |
| Authority/runtime | Node 24.19.0, generated WasmGC, private `snail.reducer` scalar provider |
| Browser | Chromium 152.0.7977.82, `http://127.0.0.1:4173`, two independent sessions |
| GPU | Real WebGPU using Google's SwiftShader software Vulkan adapter |

`scripts/test-applications` builds the real game and small fixtures. The runtime
checks cover shared Scheme/Lofi APIs, retained immutable snapshots, automatic
hauling, pure view, declarative client effects, compatible reload with changed
behavior, hostile candidates and views, rejection of invalid encoded states,
startup checks before publication, rollback after staged writes/effects,
ordered submissions, contested purchases, durable failure, SQLite restart/retry,
and deterministic losing and winning runs. Compile-negative fixtures reject a
wrong state result, wrong payload and command from the wrong application owner.

The suite has 19 runtime checks and three compile-negative cases. The
[browser runner](../../tests/applications/README.md) verifies actual GPU
pixels, independent shader candidate validation, two-client purchases and
convergence, stale snapshot rejection, combat and cargo in transit, changed Wasm
behavior after reload, exact pending-request preservation, and continued
rendering after invalid WGSL or an
incompatible schema. A Chromium window on an isolated Xvfb display was also
visually inspected. The headless compositor's screenshot is not used as evidence
of GPU rendering; GPU texture readback is.

Formatting, changed Markdown links, `git diff --check`, and the mdBook build pass.
The parent PR owns compiler/backend validation; this app does not repeat the
performance suite or change the compiler implementation.

Two independent Luna builders started from public libraries, documentation and
the game contract at `228076e5`, without reading the reference implementation.
Their experimental apps remain on local branches rather than becoming extra
reference games in this PR:

| Experiment | Local commit | Observed result |
| --- | --- | --- |
| `experiment/siegework-newcomer-a-20261016` | `0ce891a3` | App-local build, Scheme victory/loss/reset and upgrade income, two clients, real WebGPU pixels, changed module replacement with identical world/client snapshots. |
| `experiment/siegework-newcomer-b-20261016` | `c375d62d` | App-local build, Scheme extractor income/artillery/victory/reset, two clients, real WebGPU pixels and reconnect to the retained match. |

Each experiment records commands and failures in its app's `NEWCOMER.md`. The
feedback exposed missing import guidance, `I64` vector indices versus `I32`
snapshot words, the limited arithmetic surface, constructor-name collisions,
owner/handler settings wiring and unlinked browser flags. The chapter now covers
those boundaries and includes a runnable immutable-state codec. A mismatched
codec length also motivated the executable packaging preflight and a regression
that rejects invalid encoded replacements before durability. These small
experiments test usability; they do not establish full Scheme conformance or
replace the reference game's integration checks. One builder used the shared
replacement API manually after a server restart; automatic polling during live
combat is covered by the reference browser runner.

A fresh, no-history **gpt-6-astra at low effort** understanding check started from
`3e9e1435`. It ran the documented counter and its own immutable stock/typed send
test as actual Wasm; both returned `42`. It found no functional reducer defect.
Its need to inspect source for initializers and effect tags led to the runnable
`testing.sld` example and named `effect-send?`/`effect-notice?` predicates. Its
missing-parenthesis typo also exposed an opaque parse diagnostic. Parent commit
`4525dda7` now reports its filename, line/column and expected closing delimiter.
This check did not exercise the browser, durability or reload.

A separate fresh, no-history **gpt-6-astra at max effort** explained the state
commit, reload and packaging contract without repository access, then debated
the implementation observations. The focused simplify pass fixed abandoned
first-candidate buffers reserving a state shape: preparation now validates with
temporary buffers and installation rebuilds from current snapshots. Regression
checks cover discarded/out-of-order candidates, state advancing before
installation, and an observer throwing after a committed receipt. The pass kept
synchronous transitions and trusted immutable application discipline; fresh Wasm
instances per message, an async lock and an outbox would add unrelated machinery.
Atomic commit/validation and publication operations remain cohesive even where
they exceed the ten-line target. No broader refactoring was needed once those
boundaries and their failure cases were explicit.

A second fresh, no-history **gpt-6-astra at max effort** explained only the
application declaration/dispatch and shader construction/emission contracts,
without repository access. Debate established that the private one-field
`Handler` record added no invariant beyond its function type. Applications now
hold the annotated reducer functions directly; nominal owner types, arity
adapters, delayed initialization and slot bounds checks remain. The shader's
successful stage/width checks already dominate emission of the same immutable
trees, so a second checked AST or combined width/text result would add machinery
without strengthening the boundary. The two passes remain, with that invariant
beside emission. Ordinary functions fit the ten-line target. The 13-line arity
macro and 11-line declaration expansion remain cohesive exhaustive cases.

This pass rebuilt generation `f66f0e7aae927dd5d58f580b` and passed all 19 runtime
checks, three compile-negative cases, `make check` and `git diff --check`.
Strengthened fixtures cover zero/one/two arguments, payload order, request reuse
with different states, an unforced trapping initializer, nested shader widths,
fragment-stage rejection even beneath multiplication by zero, and matching
macro/constructor output. Handler identities, effect schema, settings and WGSL
text match the published build. A direct reload from the browser checkpoint's
Wasm into this generation retained both active-combat and client snapshots
exactly and executed the next tick. Browser checks were not repeated for this
library-only pass. It stops here because the remaining representation and checks
serve explicit contracts; no public API, runtime or compiler change was needed.

The scope remains one local authority, bounded scalar snapshot copying, a small
shader vocabulary and the current typed Scheme subset. There is no automatic
schema migration, durable external-effect outbox, distributed writer protocol,
GPU device recovery or model checker. Host JavaScript/HTML/CSS changes require a
restart; Scheme modules and shader pipelines have the state-preserving path.
