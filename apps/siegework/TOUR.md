# Reading Siegework

Siegework composes shared application, serialization and browser libraries with
an app-owned immutable colony simulation. The compiler remains hosted by Chibi;
Scheme owns the game rules and presentation executed by both browser and server.

## Follow the modules

| Module | Responsibility |
| --- | --- |
| [`terrain.sld`](src/siegework/terrain.sld) | Seeded terrain, remembered surveys and bounded adjacent-cell pathfinding and exact grid-crossing direct fire. |
| [`model.sld`](src/siegework/model.sld) | Immutable buildings, workers, enemies, freight and world; worker/source completion estimates, exclusive kits, queued relocations, deliveries and combat. |
| [`planning.sld`](src/siegework/planning.sld) | Optional Manual/Auto Explore/Defend investment policy using observed opportunities and a bounded reserve. |
| [`guidance.sld`](src/siegework/guidance.sld) | First-extractor guidance derived from authoritative orders and permanent survey history, sharing the planner’s preferred known deposit. |
| [`state.sld`](src/siegework/state.sld) | Derived world transport, checked restart envelope, scalar bounds, routes, ownership and material conservation. |
| [`view.sld`](src/siegework/view.sld) | Pure quads and status text for the colony, camera, minimap, reservations and freight. |
| [`game.sld`](src/siegework/game.sld) | Typed match/client commands, per-browser camera and selection, derived client transport and the scalar entry point. |
| [`shaders.sld`](src/siegework/shaders.sld) | Scheme-authored shader generation for the shared WebGPU quad adapter. |
| [`build.scm`](build.scm) | Explicit library roots, one game/shader compilation and separate solo/cloud packages. |
| [`three-view.sld`](src/siegework/three-view.sld) | Low-poly scene composition, the overhead camera, screen-relative pan and nearest-building/crystal/ground picking over the existing grid. |
| [`three-game.sld`](src/siegework/three-game.sld) | Separate 3D client state, contextual placement, typed HUD actions and the unchanged match reducer endpoints. |
| [`hud.sld`](src/siegework/hud.sld) | Compact contextual controls and status through the reusable top-down Scheme UI library. |
| [`three/build.scm`](three/build.scm) | Separate 3D solo/cloud packages using the shared Scheme scene shader. |

The [game guide](README.md) describes play and controls. Shared API contracts are
in the [application chapter](../../doc/book/lofi/applications.md).
The [3D prototype guide](three/README.md) describes its separate build, save
identity, contextual controls and currently implemented drawing API.

The `solo/` package runs from static hosting and stores one authority record in
IndexedDB under a stable application ID. A Web Lock gives one tab ownership of
that save. The `cloud/` package runs its authority on Node and stores the match
in SQLite; independent browsers can resume or cooperate in that same match.
Both packages use the exact same compiled game and shared browser presentation.

## Follow one accepted command

1. [`BrowserInput`](../../src/browser/input.mjs) translates pointer, keyboard,
   controller and integer-form input into typed client command arguments.
2. The browser's [`ReducerRuntime`](../../src/application/runtime.mjs) queues a
   client transition. Scheme returns an immutable client replacement and explicit
   send descriptions. The client model includes its own camera and selection.
3. [`cloud.mjs`](../../src/browser/cloud.mjs) sends a match envelope with stable
   handler identity, sequence and epoch. Local prediction uses the same Scheme
   match reducer and is replaced by the authority's accepted snapshot.
   [`solo.mjs`](../../src/browser/solo.mjs) submits directly to the local durable
   authority. Both use [`application.mjs`](../../src/browser/application.mjs) for
   input, client transitions, presentation and code replacement.
4. [`Authority`](../../src/application/authority.mjs) admits that envelope in the
   runtime's shared FIFO. Retry receipts are checked before stale epochs, so an
   accepted restart can be retried with its preceding epoch.
5. The bridge decodes typed state, executes one Scheme reducer, validates its
   replacement and materializes effects before persistence starts. World and
   client commands, restore, code installation and shutdown share this lane.
6. The durable adapter saves state, revision, epoch and consumed retry metadata
   atomically. Queries see the prior committed state while the save is pending.
   Only a successful save publishes the replacement and notifications. An
   observer failure retains the committed receipt and never reruns the reducer.

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

The original 2D owners declare schema 7. The 3D prototype shares world schema 7
and has a separate client schema 1 and application ID. Record sizes grow and shrink,
within the runtime's 65,536-word limit. Schemas 4, 5 and 6 have different layouts and
are rejected; neither derivation nor this integration migrates existing saves.
Existing packages and databases are left intact. Cloud packages need a separate
database unless an explicit migration is implemented and validated. Solo retains
an incompatible record and explains how to reopen a compatible package; changing
the static mount path leaves its origin/application save identity unchanged.

Typed construction establishes field shape. The app then checks scalar/count
bounds, distinct IDs, legal bounded routes, construction carriers and
reservations, worker job/cargo relationships, mining occupancy, rail endpoints
and cargo, and the ore ledger. Rails point to older tower IDs or the hub, keeping
the upstream graph acyclic. These checks remain in Scheme for every host.

Construction reserves one entire kit from one source. The source's loose stock
excludes the reservation, while extractor capacity includes it. `local-spent`
records locally consumed construction ore, including paid kits later lost. The
bank is `160 + delivered + local-spent - spent`; produced ore equals deliveries,
local spending, raw losses and all remaining loose stock/cargo/freight. Returning
a local paid kit to the hub transfers its cost from local spending to delivered
ore before refunding or retaining the project's hub-backed reservation.

Accepted restarts increment a bounded run marker, including replaying the same
seed; the maximum wraps to zero. Rejected seed input retains it. The authority
compares committed and staged header markers, then rotates the epoch in the same
durable commit as the world and retry receipt.

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
session renewal and compatible or rejected reloads. Historical evidence remains
in [`VALIDATION.md`](VALIDATION.md).
