# Reading Siegework

Siegework composes shared application, serialization and browser libraries with
an app-owned immutable colony simulation. The compiler remains hosted by Chibi;
Scheme owns the game rules and presentation executed in the browser.

## Follow the modules

| Module | Responsibility |
| --- | --- |
| [`terrain.sld`](src/siegework/terrain.sld) | Seeded terrain, remembered surveys and bounded adjacent-cell pathfinding and exact grid-crossing direct fire. |
| [`model.sld`](src/siegework/model.sld) | Immutable buildings, workers, enemies, freight and world; worker/source completion estimates, exclusive kits, queued relocations, deliveries and combat. |
| [`planning.sld`](src/siegework/planning.sld) | Optional Manual/Auto Explore/Defend investment policy using observed opportunities and a bounded reserve. |
| [`guidance.sld`](src/siegework/guidance.sld) | First-extractor guidance derived from authoritative orders and permanent survey history, sharing the planner’s preferred known deposit. |
| [`state.sld`](src/siegework/state.sld) | Derived world transport, checked restart envelope, scalar bounds, routes, ownership and material conservation. |
| [`status.sld`](src/siegework/status.sld) | Accessible text diagnostics for resources, orders, workers and threats. |
| [`build.scm`](build.scm) | Explicit library roots, one game/shader compilation and static browser packaging. |
| [`view.sld`](src/siegework/view.sld) | Low-poly scene composition, the overhead camera, screen-relative pan and nearest-building/crystal/ground picking over the existing grid. |
| [`game.sld`](src/siegework/game.sld) | Typed game and presentation commands, contextual placement, HUD composition and the scalar entry point. |
| [`hud.sld`](src/siegework/hud.sld) | Compact contextual controls and status through the reusable top-down Scheme UI library. |

The [game guide](README.md) describes play and controls. Shared API contracts are
in the [application chapter](../../doc/book/lofi/applications.md).
The `solo/` package runs from static hosting and stores one game record in
IndexedDB under a stable application ID. A Web Lock gives one tab ownership.
A build with `SAVE_SERVICE_URL` also emits static `synced/` files with explicit
online save/load. The optional service stores opaque checkpoints; all simulation
runs in the browser. See the [save guide](../../doc/static-saves.md).

## Follow one accepted command

1. [`BrowserInput`](../../src/browser/input.mjs) translates pointer, keyboard,
   controller and form input into typed client command arguments.
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

The game declares world schema 7 and client schema 1 under application ID
`siegework-colony`, which starts a fresh save identity. Record sizes grow and
shrink within the runtime's 65,536-word limit. Schemas 4, 5 and 6 have different
layouts and are rejected; derivation does not migrate existing saves. The browser retains
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
