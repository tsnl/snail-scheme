# Reading Siegework

Siegework composes shared application, serialization and browser libraries with
an app-owned immutable colony simulation. The compiler remains hosted by Chibi;
Scheme owns the game rules and presentation executed in the browser.

## Follow the modules

| Module | Responsibility |
| --- | --- |
| [`terrain.sld`](src/siegework/terrain.sld) | Compact seeded terrain with bounded hub/nest placement, permanent surveys, weighted bounded pathfinding and exact grid-crossing direct fire. |
| [`model.sld`](src/siegework/model.sld) | Immutable buildings, workers, enemies, freight and world; shared kits, house capacity, worker assembly, separate upgrade trees, paid hub repairs, deliveries, excavation, enemy ranks, crowd separation, retaliation, graded cart travel and the per-tick geometric minimum spanning transport tree. |
| [`guidance.sld`](src/siegework/guidance.sld) | First-extractor guidance derived from authoritative orders and permanent survey history, choosing a known, safely reachable deposit. |
| [`state.sld`](src/siegework/state.sld) | Derived world transport, checked restart envelope, scalar bounds, routes, ownership and material conservation. |
| [`presentation.sld`](src/siegework/presentation.sld) | Pure difficulty readouts derived from the model's ninety-second interval, shared by the HUD and accessible status. No independent game clock. |
| [`status.sld`](src/siegework/status.sld) | Accessible text diagnostics for resources, orders, workers and threats. |
| [`recording.sld`](src/siegework/recording.sld) | Pure on-demand observations of a validated World for replay/dump analysis; no recording storage or game transitions. |
| [`analyze-recording.mjs`](analyze-recording.mjs) | Node dump reader that invokes the actual Scheme decoder/projection and collects observed economy, combat totals, orders and frontier progress. |
| [`build.scm`](build.scm) | Explicit library roots, one game/shader compilation and static browser packaging. |
| [`view.sld`](src/siegework/view.sld) | Fixed colored models for buildings, workers, freight and enemies; per-occurrence poses and aimed gun instances; repeated terrain meshes; the overhead camera, screen-relative pan, animated Q/E rotation, scale-only zoom, fragment reveal, transport pulses and nearest-building/crystal/ground picking. |
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

The game declares world schema 11 and client schema 8 under application ID
`siegework-colony-v11`, which starts a fresh save identity for compact geography.
World10 coordinates and paths are deliberately rejected rather than reinterpreted
under the same seed. Record sizes grow and
shrink within the runtime's 1,048,576-word limit. Earlier world schemas have different
layouts or geography and are rejected; derivation does not migrate existing saves. The browser retains
an incompatible record and explains how to reopen a compatible package; changing
the static mount path leaves its origin/application save identity unchanged.

Typed construction establishes field shape. The app then checks scalar/count
bounds, distinct IDs, legal bounded routes, construction carriers and
reservations, worker job/cargo relationships, mining occupancy, rail endpoints
and cargo, enemy ranks, bounded legacy track cells, and the ore ledger. Bounded
parent-chain checks prove that every freight route reaches the hub; newer tower
IDs may be parents. These checks remain in Scheme for every host.

Transport derives a fresh dense Prim tree every tick. Squared Euclidean cell
distance ranks eligible edges, then endpoint IDs break ties. The graph admits
only routes within the serialized 1024-step bound: a cached surveyed-ground
flood rejects disconnected nodes, and exact bounded BFS tests candidate edges
lazily. Rejected candidates are replaced by the cheapest remaining parent;
later joined nodes may still connect a previously blocked candidate. Navigation
scratch is keyed by seed, breaches, surveys and blocking building footprints.
Saved legal paths take priority over canonical cached paths. The cache cannot
supply topology or override a restored shuttle's valid route.

`CartEdge` carries a physical adjacent edge and its traversal cost. Walking
costs forty units; level-one, level-two and level-three links cost four, two and
one. Both route search and the worker's bounded movement budget use those
costs. The slower endpoint selects a link's service level, with the hub at
level three. A worker can cross up to eight adjacent cells per tick, but its
arrival job still runs on the next tick.

Freight belongs to its source until unloading. Reroutes return it to the living
source exactly once; source destruction accounts for it as lost. The reserved
track field is checked on input and cleared on the next simulation tick. Views
ignore it: eight retained dot groups encode the current directed paths and
phase offsets, so display-clock opacity animation needs no geometry rebuild.

Construction reserves one entire kit from one source. The source's loose stock
excludes the reservation, while extractor capacity includes it. `local-spent`
records locally consumed construction ore, including paid kits later lost. The
bank is `160 + delivered + local-spent - spent`; produced ore equals deliveries,
local spending, raw losses and all remaining loose stock/cargo/freight. Returning
a local paid kit to the hub transfers its cost from local spending to delivered
ore before refunding or retaining the project's hub-backed reservation.

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

## Follow visibility and rail ownership

Permanent surveys remember explored terrain. Worker sight is derived from current
positions and does not append survey history on every step. Both contribute to
current knowledge; construction checks current visibility before assigning a new
worker or picking up a kit. A carrier already traveling on a proved route can
complete it. The HUD and world marker share the same hidden-construction rule.

Each simulation tick rebuilds the rooted depot tree. Its current paths supply
eight retained groups of glowing dots whose phases travel toward the hub on the
display clock. Reserved track bitmasks never produce geometry. Both towers and
artillery reuse one stone plinth mesh, with
four corner pillars and an open arch on each face. Houses use ordinary solid
building geometry; they have no connecting shield panels. Buildings can occupy
transport paths and intersections without removing their connections.

Unchanged directed routes preserve freight progress. Changed routes return the
load once to its surviving source; a destroyed source loses its own cargo.
Every completed tower offers worker carts. The slower endpoint determines the
link's speed; each tower level doubles it, and the hub counts as level three.
Weighted route costs and assignment estimates use those same travel speeds.

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

Completed kind-four houses add four worker places to the hub's base 12, capped
at 64. Hiring counts both living workers and paid queued recruits. The decoder
enforces the hard bound, allowing housing destruction to leave a valid
over-capacity colony. Houses use the ordinary eight-ore construction ledger,
health and worker jobs.

Attack alerts are ordinary location/dismiss controls and create no scene insets.
Upgrade waiting labels project above their buildings through the shared camera;
CSS animates their rings without requesting additional Scheme or scene frames.
