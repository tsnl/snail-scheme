# Historical Siegework validation

Archived evidence for the retired renderer and hosting architecture. Paths and
commands refer to their original revisions and are not current instructions.

> Historical prototype evidence follows. Current Siegework uses static browser
> execution and optional explicit checkpoint save/load; see the
> [current validation](../../apps/siegework/VALIDATION.md) and [save guide](../../doc/static-saves.md).

# Siegework validation

## Optional colony direction, physical supply and harder attacks

The 2026-10-17 schema-7 playtest uses generation `043f83cfb8e5b3e3dbb6e578`.
Solo and cloud package the identical newly compiled game Wasm, SHA-256
`94712804d2678e50cca9e7c55b872b7222ac3c1f6bffd2c58aceba033a41959a`.
All app Scheme source hashes were captured before compilation and checked again
before serving. Existing schema-4, schema-6 and earlier schema-7 playtests and
saves remain separate. Cloud uses port 4187 and solo uses 4188 for this checkpoint.

All 52 focused compiled-Wasm gameplay checks pass: 30 prior colony, encounter
and logistics cases plus 22 direction/supply/movement/schedule cases. They cover
joint worker/source completion estimates, prompt retry, local-only payment,
whole-kit exclusivity against hauling/trains, reserved mine capacity, cancellation,
source and carrier destruction, both carried and uncollected retreat, destroyed
hauler destinations, and bank/raw-material conservation. A naturally filled
construction cache supplies a local project without hub payment and releases its
ore when the bank is low. Sole-worker recovery remains covered. Loaded chains of
three moving towers drain in either request order across pause/restore, preserving
identity and parents; a parent can move while its child still has stock. Invalid
moves, cancellation refunds, destination conflicts and outside-map input are checked.

Actual Chromium 152 pointer and keyboard input builds a mine and tower, observes
a loaded rail shuttle, reads real WebGPU pixels, queues a move, pauses and reopens
the durable save, resumes the move and switches Auto/Manual on both hosts. The
screenshots show a visible rail to the moved tower. The browser helper scrolls
real targets into view and waits for accepted cloud state to finish restoring;
these are executable UI checks, not simulated clicks on hidden DOM controls.
SwiftShader Vulkan supplies the adapter; this is not hardware performance evidence.

A changed-code replacement from the earlier schema-7 artifact
`a3e8f35c98ab89884ba60cae` retains a paused world with loaded freight, a queued move,
and an overscrolled client camera/tool, then resumes with conservation intact.
The separately compiled terrain fixture still checks eight map fingerprints and
970 routes, adding blocked direct fire, diagonal rock corners, same-position
shots and observed-versus-unknown planning rays. A 50-enemy boundary fixture
survives save/reload and presentation; 51 is rejected. The ceiling is derived
from the finite schedule, and rendering grows its buffer from actual quad count.

`make test`, `make check`, changed JavaScript syntax and whitespace checks pass.
This iteration did not repeat all generic runtime adversarial wrappers or the
full hosting regression runner; the shared host/compiler implementation is unchanged.
The focused gameplay, changed-code reload and both real browser ownership paths
were executed against newly compiled gameplay code.

### Same-seed strategy observations

`colony-strategies.mjs` compares fixed Manual orders with Explore and Defend,
checking conservation on every tick. The softer comparison artifact is
`78ac39a9fd615c1fa3313b9a`; the harder artifact is the checkpoint above. Both include
the same cache and colony policy. The harder finite schedule spawns 50 attackers
versus 26: the opening remains at 1:00, ordinary follow-ups use 45-second spacing,
raids replace the nearby ordinary slots, and the unchanged 1,800-health finale
gets six ordinary escorts. Warnings identify spawn time, size and kind; these are
not arrival-time promises.

| Seed / policy | Outcome / finish before → after | Hub HP | Buildings lost | First actual damage | Peak live threats | Local kits after |
| --- | --- | --- | --- | --- | --- | --- |
| 1 manual-baseline | win 7:28.8 → win 7:39.4 | 300 → 279 | 0 → 2 | 7:26.0 → 7:21.0 | 5 → 7 | 1 |
| 1 explore | win 7:33.8 → loss 7:42.0 | 300 → 0 | 5 → 8 | 1:08.0 → 1:08.0 | 8 → 11 | 8 |
| 1 defend | win 7:27.2 → win 7:31.1 | 300 → 300 | 1 → 2 | 7:23.0 → 6:39.0 | 5 → 7 | 15 |
| 7 manual-baseline | win 7:28.8 → win 7:39.2 | 300 → 272 | 0 → 2 | 7:26.0 → 6:37.0 | 5 → 7 | 1 |
| 7 explore | loss 4:53.0 → win 7:48.4 | 0 → 181 | 5 → 10 | 2:04.0 → 1:24.0 | 8 → 10 | 13 |
| 7 defend | win 7:25.6 → win 7:29.6 | 300 → 300 | 0 → 2 | 6:22.0 → 1:24.0 | 5 → 7 | 15 |
| 43 manual-baseline | win 7:28.8 → win 7:39.4 | 300 → 279 | 0 → 2 | 7:26.0 → 7:21.0 | 5 → 7 | 1 |
| 43 explore | win 7:30.4 → loss 3:21.0 | 300 → 0 | 6 → 2 | 2:04.0 → 1:33.0 | 5 → 6 | 4 |
| 43 defend | win 7:25.6 → win 7:28.4 | 300 → 300 | 0 → 1 | 7:24.0 → 7:24.0 | 5 → 7 | 15 |

Minimum hub reserve stayed at 1 for the fixed Manual orders, 40 for Explore and
42 for Defend; Auto never spent its 40-ore reserve. The Manual opening is identical
across these three maps and gives limited balance coverage. It still survives
all three harder runs, now losing two buildings and some hub health; its final
bank remains comfortable (439–441 ore). Defend also survives all three with full
hub health, while Explore is unstable and loses two. These measurements show
additional pressure and policy tradeoffs, not calibrated difficulty, player skill
or evidence that automation is more enjoyable. Human playtesting should guide
further tuning instead of forcing a scripted layout to lose.

Before the bounded cache, the same whole-kit rule produced zero local pickups
in nine seeded runs because small hauling batches emptied the buffers. The cache
makes them occur in routine play: one local kit per fixed Manual run and 4–15 per
harder Auto run. It retains at most 50 loose ore at one extractor, with no extra
ledger or control, and releases it below 40 hub ore or three workers. This trades
some bank delivery latency for nearby construction supply; it is not multi-source
planning or a globally optimal online schedule.

Two fresh source-free Astra Max explanation/debate passes covered the new model
and supply/relocation rules. They supported derived reservation ownership, explicit
local-to-hub accounting, final-route cancellation/refund, and parent-before-child
drain liveness. The resulting codec separates source ownership from relocation
checks. Existing atomic purchase/ETA transitions, exhaustive rule dispatch and
whole-world invariant checks remain deliberate exceptions to the ten-line target.
No generic planning framework or compiler cleanup was introduced.

## Derived colony and hosting integration

The final 2026-10-17 integration combines asynchronous execution, outpost
logistics and separate solo/cloud packages with derived world/client schema 6.
Both packages use generation `66be352c533caec8b1bfdf14` and the exact same game
Wasm (SHA-256 `bca27ee9c78e1e1cf54462728f2648e5a2be952b69a4d3f80682b35760fd0390`).
The game compiled from the final Scheme sources; the two hosts package those
artifacts without a second game compilation.

All 66 application integration checks pass on the cloud package. These include
33 colony/encounter/logistics scenarios, malformed derived records and marker
headers, rejection of schemas 4 and 5, code replacement and rollback, durable
restart receipts, persistence failures and the ten tiny-Wasm async boundary
checks. The game-wrapper fixtures were rebuilt against the schema-6 sources;
three invalid application declarations also fail compilation as expected.

All 13 generic browser input/form/layout checks and the complete two-client
WebGPU/reload runner pass on the final cloud package. The latter reaches combat
with ore in transit, freezes both through shared pause and visibility changes,
and activates changed Wasm while preserving the paused colony, overscrolled
camera, selection and pending command. Incompatible schemas, marker offsets and
WGSL candidates retain the running package.

All 14 hosting checks pass in actual Chromium: separate packages share exact
Wasm; real IndexedDB transactions retain state, epochs and receipts through
abort/retry and competing commits; one tab owns a solo save; slow persistence
admits one pending tick; visibility resumes without catch-up; compatible reload
retains both owners; incompatible startup/update retains the save; browser
restart and a moved static subpath reopen it without application-server
requests; leaving during open closes GPU/lock resources; cloud server restart
and independent clients resume the saved SQLite match. The private browser
runner waits for a real WebGPU adapter before opening the application.

`make check`, JavaScript syntax and whitespace checks pass. All packages,
profiles, ports and databases used here are isolated test outputs. Chromium 152
uses the SwiftShader Vulkan adapter; this is correctness evidence, not hardware
coverage or a timing measurement. Older saves are rejected, not migrated.
Upstream profiling code, measurement JSON and the earlier checkpoint evidence
below retain their original scope. Unified GitHub CI is tracked separately.

## Earlier schema-5 outpost candidate

The 2026-10-17 outpost candidate uses generation `d1105da2b285bc57b308159b`,
world/client schema 5 and a 10,240-word world snapshot. It is tested in a separate
package on port 4181; the live schema-4 checkpoint on 4175 is unchanged.

All 33 game scenarios pass against the compiled Scheme/Wasm: the previous 20
colony and encounter scenarios plus 13 logistics cases. The new cases exercise
uncollected and carried cancellation refunds, pause/restore during a return,
nearest-worker preemption including a miner, loaded hauler and repairer, usable
route distance across a wall, cancellation without losing unrelated cargo,
reservation release on worker death, actual depot unloading, two-hop freight,
empty returns without duplicate income, tower arming with zero kill income,
endpoint-loss accounting/reconnection, and rejected malformed ownership.
A separate compiled defended run exterminates the siege at tick 4488 with the
hub at 300 health and 26 kills. Resource conservation is checked through the run;
this is a possible winning layout, not a difficulty or balance claim.

After rebasing the outpost commits onto asynchronous runtime `67ad1ca2`, all 33
game scenarios and the ten tiny-Wasm async boundary checks pass together. The
merge retains awaited mutations and schema-5 assertions. Game Scheme sources and
compiler dependencies are unchanged, so this run reuses the verified game and
async fixture artifacts without recompilation. Evidence is in
`build/playtest/logistics-async-rebase.log`; this does not claim that the older
schema-4 failure wrappers were rerun against the schema-5 game.

Actual Chromium 152 keyboard and pointer input on isolated DevTools port 9345
placed a paused build, cancelled it with C and observed the refund in two clients.
T armed a completed tower without replacing its identity, depot or rail service.
Workers then unloaded ore nearby and rail freight reached the hub. Real WebGPU
readback and `build/siegework-logistics/logistics.png` show the resulting colony,
with exact status and scene provenance in `logistics-browser.json`. This scene
was built through controls, not loaded from a simulation fixture. The adapter
is isolated SwiftShader Vulkan; it is not hardware or Firefox stability evidence.

The full two-client browser suite also passes on this package. It reaches combat
with ore in transit, preserves the shared manual pause through visibility changes,
and activates changed compatible Wasm while preserving the entire colony,
overscrolled camera and pending request. Incompatible run-marker offsets, shaders
and schemas are rejected; a valid package recovers. GPU boundary pixels, rejected
margin placement and resumed simulation are checked. The freight scenario
separately pauses and restores a loaded shuttle and verifies its frozen frame.

`make test`, `make check`, `scripts/test-build`, app Scheme formatting, JavaScript
syntax and whitespace checks pass. The main candidate compiled in 15 minutes
13.82 seconds, using 913.12 seconds of user CPU; the separate compatible-game
fixture took 15 minutes 46.34 seconds and 946.03 seconds of user CPU. These are
measured development costs, not compiler profiling. The checkpoint's full hosted
CI passed, with its serial application job taking 49 minutes 55 seconds; the
outpost follow-up has not yet run hosted CI.

A read-only upgrade preflight validated the latest checkpoint save with both
codecs. It retained revision 63842, epoch, seed 2, tick 4620, 644 ore, 13 buildings
and 12 workers. The candidate changes the schema word, clears the obsolete source
mine IDs on seven ore-returning workers, and appends zero-initialized new storage.
No live state was written and no package was switched. Evidence is recorded in
`build/playtest/outpost-upgrade-preflight.json`; this is not an automatic migration.

Fresh source-free Astra Max explanation/debate passes covered logistics ownership
and presentation. One current cargo and one next-build reservation per worker
represent preemption directly; there is no separate courier/builder protocol.
Fixed links to older connected towers make the network acyclic, with one bounded
shuttle per link. Casualties settle before broken links lose cargo and reconnect.
Removing the reservation or empty return leg would lose the required ownership
or throughput behavior. Codec rows and exhaustive job/cargo transitions remain
cohesive exceptions to the ten-line function target.

## Earlier derived staffed-colony integration

The cleanup integration preserves the landed colony behavior while replacing the
fixed-layout schema-4 codec with derived schema-6 snapshots. The world retains a
host-visible restart counter; decoding checks it against the typed record before
applying the original bounds, path, ownership and conservation checks. Prior save
formats are rejected rather than converted implicitly.

Local integration checks pass for the compiled colony startup, `make test`,
`make check`, real Chromium input contracts and the two-client WebGPU/reload
runner. The browser checks include seed restarts, shared purchases, pause,
overscrolled camera retention, pending command preservation, incompatible marker
offsets, invalid shaders and schema rejection. This uses Chromium 152 with the
SwiftShader Vulkan adapter and is correctness evidence, not a clean timing run.
The application fixture suite and required GitHub correctness run are tracked
separately in the pull request.

## Earlier schema-4 colony

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
