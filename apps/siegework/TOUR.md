# Reading Siegework

Siegework composes shared application, serialization and browser libraries with
an app-owned immutable colony simulation. The compiler remains hosted by Chibi;
Scheme owns the game rules and presentation executed in the browser.

## Follow the modules

| Module | Responsibility |
| --- | --- |
| [`terrain.sld`](src/siegework/terrain.sld) | Compact seeded terrain with bounded hub/three-nest placement and immutable deposit capacities, permanent surveys, weighted bounded walking/flight pathfinding and exact grid-crossing direct fire. |
| [`model.sld`](src/siegework/model.sld) | Immutable buildings, workers, enemies, freight, persistent deposits/nests and world; shared kits, paid hub capacity upgrades, worker assembly, separate upgrade trees, paid hub repairs, deliveries, excavation, enemy ranks, crowd separation, retaliation, captured worker flights, shared terrain/cable heights and the per-tick geometric minimum spanning transport tree. |
| [`guidance.sld`](src/siegework/guidance.sld) | First-extractor guidance derived from authoritative orders and permanent survey history, choosing a known, safely reachable deposit. |
| [`state.sld`](src/siegework/state.sld) | Derived world transport, checked restart envelope, scalar bounds, canonical site identities, captured flights, queued routes, ownership and exact underground/produced material conservation. |
| [`presentation.sld`](src/siegework/presentation.sld) | Pure difficulty readouts derived from the model's ninety-second interval, shared by the HUD and accessible status. No independent game clock. |
| [`status.sld`](src/siegework/status.sld) | Accessible text diagnostics for resources, orders, workers and threats. |
| [`recording.sld`](src/siegework/recording.sld) | Pure on-demand observations of a validated World for replay/dump analysis; no recording storage or game transitions. |
| [`observation.sld`](src/siegework/observation.sld) | Read-only player knowledge projection through bounded scalar rows; real visibility and purchase previews, with hidden hostile/reserve data withheld. |
| [`headless.mjs`](headless.mjs) | Node owner of the same compiled reducer, explicit simulation ticks, FIFO operations, episode horizons/reward, opaque checkpoints and optional privileged diagnostics. |
| [`environment-cli.mjs`](environment-cli.mjs) | Bounded JSONL and MCP stdio transports sharing the headless environment; MCP pages player observations. See the [environment contract](headless.md). |
| [`analyze-recording.mjs`](analyze-recording.mjs) | Node dump reader that invokes the actual Scheme decoder/projection and collects observed economy, individual nest clears, exhaustion counts, orders and frontier progress. |
| [`build.scm`](build.scm) | Explicit library roots, one game/shader compilation and static browser packaging. |
| [`view.sld`](src/siegework/view.sld) | Fixed colored models for buildings, workers, freight and enemies; per-occurrence poses and aimed gun instances; repeated terrain meshes; the overhead camera, screen-relative pan, animated Q/E rotation, scale-only zoom, fragment reveal, straight aerial transport pulses, cyan reveal-radius guides, camera-facing health/reserve instances and nearest-building/crystal/ground picking. |
| [`game.sld`](src/siegework/game.sld) | Typed owner entry point; client selection, one pending placement, camera commands, actual construction replies, local attack mutes, restart/pause handling and HUD composition. |
| [`hud.sld`](src/siegework/hud.sld) | Mirrored edge controls, circular readouts and tile-anchored contextual cards through the reusable top-down Scheme UI library. |

The [game guide](README.md) describes play and controls. Shared API contracts are
in the [application chapter](../../doc/book/lofi/applications.md).
The [recording guide](recording.md) follows the optional publication recorder in
`src/application/recording.mjs`, isolated snapshot player in
`src/application/playback.mjs`, and Pause controls in `src/browser/recording.mjs`.
The `solo/` package runs from static hosting and stores one game record in
IndexedDB under a stable application ID. A Web Lock gives one tab ownership.
A build with `SAVE_SERVICE_URL` also emits static `synced/` files with explicit
online save/load. The optional service stores opaque checkpoints; all simulation
runs in the browser. See the [save guide](../../doc/static-saves.md).

Headless execution instantiates that same static package in Node. Operation 12
reads one validated World and emits the player projection without invoking the
view. Its rows share the runtime's read-only scalar transaction and bounded
publication output. Privileged operation 11 remains the recording projection;
its global nest/enemy/reserve totals are not player observations. The host queues
whole policy operations, advances only explicit ticks, and owns the external
episode horizon. Neither transport owns another simulation or changes World12.

## Follow one accepted command

1. [`BrowserInput`](../../src/browser/input.mjs) translates pointer, keyboard,
   and form input into typed client command arguments.
2. [`ReducerRuntime`](../../src/application/runtime.mjs) queues a client
   transition. Scheme returns immutable presentation state and send descriptions.
3. [`solo.mjs`](../../src/browser/solo.mjs) forwards a game request through
   [`LocalState`](../../src/application/local.mjs). World/client commands, state
   import, code installation and shutdown share the runtime's FIFO.
4. Scheme decodes state, runs the handler and validates its replacement. The
   runtime materializes effects before asynchronous persistence begins.
5. IndexedDB atomically compares the old revision and saves `{revision, state}`.
   Queries see the old state until transaction completion, then the new state,
   revision and effects publish together. Failed saves preserve the old game.
6. The browser queues committed replies back to Client. One placement keeps its
   pending slot until the authored completion message runs, including when
   persistence fails. An accepted reply closes selection and remembers the next
   ordinary building type; a failure keeps the intended choice available to retry.

The selected tile and remembered ordinary building type are Client presentation
state. A construction button captures both its kind and absolute cell, so a stale
button cannot order a new selection. The second tap on the same empty tile emits
that same typed `build-cell(kind, cell)` request. Deposits offer only extractors;
existing-building taps inspect, with separate explicit upgrade and cancel actions.
The model's normal placement operation validates and pays for each order.
Before the first accepted extractor, placement and the other purchase rules
reject every alternative use of ore. Only accepting that paid extractor sets
the saved `started` flag; selection, failed requests and camera input do not.
Contextual disabled actions explain the same restriction without enforcing it
only in the interface.

One local placement slot remains occupied through reply and completion. Imports
clear selection and supersede the older result without releasing that slot early.
A queued activation after a failed write can retry the still-unpaid intended order;
an accepted site becomes inspect-only. This uses the existing ordered local
messages, without a batch protocol or a second game world. Code replacement and
shutdown drain admitted commands and replies.

Pause presentation covers the current selection without replacing it.
Client distinguishes the closed menu, Pause and restart confirmation; committed
World pause also supplies the Pause menu after a saved colony reloads. Resume
unpauses explicitly, while canceling restart returns to Pause. Covered gameplay
actions are ignored, but pending build replies and display updates still run.
One menu operation remains pending through its ordered settlement. A committed
reply records success without releasing that slot; a failed save returns to the
appropriate retry state. Startup and checkpoint imports call the existing
`resetPresentation` hook after installing the durable World. An import
supersedes an older operation's result while retaining its pending slot until
settlement. These boundaries keep camera guards local to Client rather than
decoding the full colony on every drag, pan or zoom event.

## Follow the serialization boundary

Persisted records explicitly derive `Serialize` and `Deserialize` from
[`(lofi serialization)`](../../src/lofi/serialization.sld). The derived instances
own every record field's transport: nominal type, constructor, field names and
typed scalar or list values use the shared compact S-expression binary format.
No process address or WasmGC reference crosses the boundary.

The client uses the generic [`application serialization`](../../src/application/serialization.sld)
envelope: schema, binary byte count and four packed bytes per `I32` word. The
world inserts its run marker after the schema, before that binary count and
payload. The host reads only this documented header. The Scheme decoder proves
that the header marker equals the marker in the deserialized `World`.

The game declares world schema 12 and client schema 8 under application ID
`siegework-colony-v12`, which starts a fresh save identity for explicit hub capacity
removal of house buildings, finite deposits and three persistent nests. Earlier worlds are rejected rather than reinterpreted. Record sizes grow and
shrink within the runtime's 1,048,576-word limit. Earlier world schemas have different
layouts or geography and are rejected. The browser retains
an incompatible record and explains how to reopen a compatible package; changing
the static mount path leaves its origin/application save identity unchanged.

Within that envelope, payload revision 1 adds a final `payload-version = 1`
World field, `Enemy.max-hp`, and `Bot.flight` (empty or one committed `Flight`).
The app-local decoder recognizes only the original 33-field World with the
original 11-field Bot and 9-field Enemy, or the complete revision-1 shape.
It extends the original shape before ordinary typed decoding and validation;
the first accepted transition serializes the canonical revision. Legacy flights
start empty. Legacy maximum HP freezes `max(current HP, spawn health at saved
tick)` because the original spawn tick is unavailable. New spawns store the exact
maximum once, so wounds and later difficulty never change their denominator.
This compatibility is forward only; old packages reject the extended records.

Typed construction establishes field shape. The app then checks scalar/count
bounds, distinct IDs, legal bounded routes, construction carriers and
reservations, worker job/cargo relationships, mining occupancy, rail endpoints
and cargo, enemy ranks, bounded legacy track cells, and the ore ledger. Bounded
parent-chain checks prove that every freight route reaches the hub; newer tower
IDs may be parents. These checks remain in Scheme for every host.

Transport derives a fresh dense Prim tree every tick. Squared Euclidean cell
distance ranks eligible straight links, then endpoint IDs break ties. Eligibility
uses the larger endpoint reveal radius and a conservative terrain-column sight
test; no map-sized transport flood or route cache is needed.

`CartEdge` carries two exact endpoints and their service cost. The bounded route
search visits walking neighbors and boarding connections. Walking costs 1600
work units per cell; a flight costs 320 times its tick duration, including two
lift ticks and two landing ticks. The slower endpoint chooses speed 80, 160 or
320 world units per tick, with the hub at level three. Adjacent station cells
remain walking steps because boarding cannot improve their travel time. Arrival
jobs run on the following tick after movement finishes.

Freight belongs to its source until unloading. Reroutes return it to the living
source exactly once; source destruction accounts for it as lost. The reserved
track field is checked on input and cleared on the next simulation tick. Views
ignore it: the retained energy rail represents the current undirected paths,
so its uniform display-clock pulse needs no geometry rebuild.

Construction reserves one entire kit from one source. The source's loose stock
excludes the reservation, while extractor capacity includes it. `local-spent`
records locally consumed construction ore, including paid kits later lost. The
bank is `160 + delivered + local-spent - spent`; produced ore equals deliveries,
local spending, raw losses and all remaining loose stock/cargo/freight. Returning
a local paid kit to the hub transfers its cost from local spending to delivered
ore before refunding or retaining the project's hub-backed reservation.

Every deposit retains its own remaining reserve after extractor loss or depletion.
The view draws compact unlit green health bars and optional purple reserve bars
with no text or warning animation. Fixed colored frames and fill meshes are
instanced in opaque unordered batches. Reserve denominators come from the seed;
health uses the unit's maximum, including each enemy's saved spawn maximum.
Known terrain gates deposits/nests, current sight gates enemies, and swept
viewport culling preserves moving bars until both endpoints leave the view.

Bar endpoints derive from the actual body poses (including worker flight height)
and static model tops. Their camera-facing matrices share the World owner's
motion epoch with body batches. Camera-only changes rebuild bar instances while
retaining body geometry and the same interpolation fraction. Display animation
requires no new Scheme queries; an exhausted reserve retains its purple frame.

Canonical order identifies the three home sites followed by the regional candidates.
The parser compares that list and all three nest identities/coordinates with one
trusted seed-derived layout, retained only for the current seed in each Wasm
instance. Building the layout visits nineteen candidates, never 16,384 map cells.
A restore cannot populate the cache or replenish a reserve. Exact total original
capacity minus remaining underground ore must equal `produced`; the existing
physical stock, cargo, freight, spending and loss equation proves where it went.
Production clips each withdrawal before increasing the mine buffer. Exhaustion
releases miners and the loose cache, but leaves paid kits with their owners and
hauls the final partial load. Upgrades change slots without changing geology.

Three immutable nest records retain seed-owned IDs/coordinates and individual
health. Every scheduled wave assigns its global enemy positions to rotating
front shares before skipping dead nests; clearing a front removes its share
rather than reallocating it. Raids select the nearest exposed operation closer
to their own source than the hub. Spawn precedes combat, so a nest killed on a
spawn tick emits its last share. Clearing all three wins even if enemies remain;
that outcome retains the existing precedence over same-tick hub destruction.
The fixed nest model is instanced three times, and dead sites retain their seeded
terrain clearing. Depletion changes retained terrain only on its final unit.

Accepted restarts increment a bounded run marker, including replaying the same
seed; the maximum wraps to zero. Rejected seed input retains it. The saved world
retains this marker as an application invariant; the browser
does not create a network epoch or request receipt.

## Follow replacement and checks

Candidate code is prepared in a fresh Wasm instance and checked against current
snapshots. Installation queues behind pending saves and revalidates the latest
committed state. A failed candidate leaves installed code intact. Reducer traps
can recover the previous compatible generation; save failures retain code and
state. Shutdown drains admitted messages before closing durable storage.

[`tests/applications`](../../tests/applications/README.md) executes real compiled
Scheme/Wasm transitions, including cancellation, preemption, depot freight,
endpoint loss, invalid ownership and persistence failures. Fixture helpers edit
typed wire records to establish boundary scenarios; they contain no alternate
game simulation. Browser checks exercise shared input, WebGPU presentation,
online checkpoint transfers and compatible or rejected reloads. Current evidence
is recorded in [`VALIDATION.md`](VALIDATION.md).
The shared model-only probe also supports the
[`starter economy experiment`](../../tests/applications/starter-economy-test.md).
Its instantaneous, validated fixtures price paid survey orders against the finite
starter reserve; separate geometric and visible-only results distinguish budget
opportunity from reliable scouting, defense and elapsed time.
The [actual-tick starter sprint](../../tests/applications/starter-sprint.mjs)
replays one measured seed-one route through ordinary game commands, requiring
the second mine to operate before the starter runs dry.

## Follow visibility and rail ownership

Permanent surveys remember explored terrain. Worker sight is derived from current
positions and does not append survey history on every step. Both contribute to
current knowledge; construction checks current visibility before assigning a new
worker or picking up a kit. A carrier already traveling on a proved route can
complete it. The HUD and world marker share the same hidden-construction rule.

Each simulation tick rebuilds a deterministic hub-rooted minimum spanning tree.
A candidate straight cable must have clear terrain sight and fit within the
larger actual reveal radius of its two endpoints; the hub contributes radius
nine. Remembered surveys do not extend link reach. Squared Euclidean distance
and endpoint IDs determine the tree independently of list order or tower age.
The shared terrain-height rule bounds today's rock peaks at 850 thousandths of
a cell. The cable plane is 900, so current mountains never obstruct it; the
conservative grid-column sight test also checks both cells at diagonal corners.

The cable endpoints supply two retained layers: a steady opaque dark backing
and a narrower bright core that pulses uniformly on the display clock. Each
undirected pair instances one straight rectangle, sorted and packed with its
fast-cyan or ordinary-gold tint. The padded camera window culls whole spans;
reserved legacy track bitmasks never produce geometry. Towers and artillery
use compact ground-level models. Cyan outlines show the union of the hub's
and ready towers' actual reveal radii.

Unchanged directed links preserve freight progress. Changed links return the
load once to its surviving source; a destroyed source loses its own cargo.
Freight shuttles lift, cross the cable and lower before unloading. Every ready
tower offers worker flights; the slower endpoint determines speed, each level
doubles it, and the hub counts as level three. Walking and flight costs include
the same movement time used by assignment estimates and execution.

A worker boards only at a current link endpoint. Its captured origin,
destination, progress and speed then determine lift, cruise and landing without
consulting the towers again. Destruction cannot interrupt that committed flight
or duplicate its job, cargo or source reservation. The next queued leg is
checked again before boarding and replanned if the tree changed. Saves validate
captured coordinates and safe ground endpoints; no live tower is needed to
resume an active flight. Legacy routed freight is accepted at the boundary and
settled once when the next tick replaces its route with a current straight link.

A rejected transition never becomes the saved colony. The runtime captures the
command, committed snapshots and any staged candidate; the browser retains one
latest reproduction beside the save. Inspect it with
`await snailApp.session.store.failure()` in developer tools. Capturing a failure
does not advance the game revision or replace its last committed state.

The construction command returns its decision with the tentative World, so the
selected-site popup retains a precise rejection even after a later notice.
One placement still owns its pending slot through reply and authored settlement;
a failed durable save releases the slot without reporting success. Client 8
stores that rejection and removes the former worker-menu state.

World12 saves `hub-capacity-level` from zero through six. Capacity is derived as
12 plus twice that tier; prices are 100 times two to the tier. The tier is
independent of the hub's fixed transport grade three. An accepted expansion
charges hub ore and assigns one worker: job 14 returns, job 15 assembles for
30 simulation ticks, and fleeing timer 14 retains the same paid order. Its target
stores the reserved price; cargo remains ordinary mined ore. Completion advances
the tier and clears the job atomically. Death before completion refunds exactly
the stored price. There is no separate pending queue or automatic recruit.

The decoder proves the tier bounds, at most one expansion owner, the matching
price, phase/location constraints, and enough investment for completed and pending
upgrades. Hiring counts both living workers and paid recruits against completed
capacity. Existing exact bank and produced-ore conservation equations remain.

Attack alerts are ordinary location/dismiss controls and create no scene insets.
Upgrade waiting labels project above their buildings through the shared camera;
CSS animates their rings without requesting additional Scheme or scene frames.
