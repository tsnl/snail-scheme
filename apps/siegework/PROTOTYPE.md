# Siegework prototype contract

Build a fast colony expedition targeting about ten minutes on a seeded 80×80 map. Keep the
art simple so discovery, logistics and defensive choices can be playtested.
The [player guide](README.md) describes the implemented controls and costs.

## Playable loop

- A hub, three pooled workers, one visible starter deposit and two hidden expansion
  choices. The starter holds 600 ore; north offers 900 and east offers 1,800 beyond a
  ridge crossing. Routes follow traversable surveyed ground.
- The first construction order must be a 25-ore extractor. Until it is accepted, time
  stays stopped and all other ore purchases are rejected. Selecting a deposit
  does not start the run; cancellation after acceptance does not stop it again.
- Completed observation towers extend active sight. Remembered geography survives
  lost coverage; current enemies require active sight. Placement requires visible,
  reachable ground. A worker assembles every site; all structures need delivered
  materials. Extractors and towers need one 25-ore kit; artillery needs two.
  Towers also accept worker deliveries and send freight upstream through automatic
  rail links determined by placement. Arming a tower retains its observation and
  depot roles; rail cargo becomes spendable only on arrival at the hub.
- Occupied mining slots produce into bounded buffers; upgrades add slots, not
  free production or underground reserves. Deposits persist after extractor loss;
  exhaustion stops output, releases miners and flushes the last partial stock.
  Workers mine, collect ore, deliver it to a connected depot or
  the hub, build projects from hub or local reserved kits. No individual
  orders are needed. Additional workers, extraction upgrades and observation
  upgrades compete with artillery for delivered ore. Idle drones can take construction orders; the last useful economic
  assignment is protected when another worker is available. No implicit ore cache
  is withheld from the bank. Kills award no resources.
- Single-rotor drones choose nearby reachable tasks and carry ore or kits.
  New orders reserve the lowest estimated complete worker/source trip, preempting mining or hauling
  while retaining any carried supplies. Uncollected kits return to their source;
  carried kits refund only after a physical hub return. Existing builders retain
  their kit ownership and completed buildings cannot be cancelled.
  Enemies attack buildings, never drones; actual hits produce bounded
  location alerts. Lost cargo is not refunded. A sole worker alternates mining
  and hauling; a surviving hub can assemble one emergency replacement.
  Three 900-health nests emit fixed shares of one wave budget. Clearing a nest
  removes its share; raids target exposed operations nearer their own source
  than the hub. The first eight-enemy wave spawns at 0:45, ordinary waves are thirty
  seconds apart, ranks increase every ninety seconds, and the first boss spawns
  at 9:00. Lose the hub or destroy all three nests; time grants no victory.
- Placement remains manual. Completed towers/guns can queue a two-cell,
  five-ore correction that drains supplies and preserves damage and identity.
- Rocks block direct artillery fire. There is no automatic repair.
- Explicit Pause/Resume freezes simulation while allowing inspection and
  paid planning. It survives durable restart and compatible reload.
- Resign asks for confirmation and reveals the frozen map without destroying
  the hub or advancing the simulation.
- Overhead 3D, continuous WASD camera pan with a three-cell exterior margin,
  pointer/arrow cursor and snapped
  construction. Guns visibly aim automatically at eligible visible enemies; bounded shot traces
  show each actual firing without changing immediate damage.
  The compact status shows the current plan, economy and rejected orders;
  selected structures expose their staffing, materials and freight. A numeric seed form starts
  a reproducible new run only when explicitly submitted.

The world uses **real WebGPU**, low-poly meshes and shaders compiled from Scheme
expressions. The grid governs movement and combat; mesh height is presentation.
There is no JavaScript copy of the simulation rules. The browser loads Snail-generated Wasm
and runs client reducers, pure presentation and all world transitions, saving them locally.

## Public application model

Application code is Scheme, using the current typed subset. A library-level
`application` declaration bundles the common state type, initial value, schema
version and named handlers. It generates typed lexical command constructors and
private reducers; the programmer does not maintain a message enum or registry.
Dispatch refers to those bindings. Each handler gets an explicit stable state
value plus typed payload, and returns replacement state plus effect descriptions.
No ambient mutable state map is part of the application API.

There is one committed transition at a time per owner. Effects run after commit;
completion is a later message. Different owners may run independently. State
reachable from a prior snapshot remains unchanged. The compiler checks common
state/results and handler argument types; purity is a programming contract, not
currently a whole-program effect proof.

Wire commands carry a stable versioned endpoint identity and structured payload,
never an arbitrary closure or Wasm pointer. A generated manifest preserves owner,
state schema, handler binding and payload metadata for validation, replay and
future analysis. The initial payload codec may be deliberately small.

The [application chapter](../../doc/book/lofi/applications.md) documents the shared
API and its limits. Reusable state, transport, browser and GPU libraries live in
top-level `src/`; game rules, schemas, settings, assets and build composition live
under this application. A small app does not mean the supporting libraries are
hidden or compressed into it.

## Reload and durability are part of the first slice

The stable runtime owns state while Scheme Wasm modules are replaceable. Candidate
initialization and validation are isolated. A compatible replacement attaches to
the current state at a message boundary; it does not rerun game initialization.
A bad candidate, trap, invalid shader or incompatible schema must not corrupt the
last accepted state. GPU pipeline creation completes before replacement.

Keep state lifetimes explicit:

1. The browser-owned game survives compatible code reload and completed local saves.
2. IndexedDB checkpoints survive browser restart; optional explicit online copies
   can be loaded on another device. No game process runs on the save service.
3. Camera, cursor and input survive code replacement but reset with a full page load.

A local transition writes state and a monotonically increasing revision before
publication. A failed write preserves the previous state. Online checkpoint ETags
version remote replacement separately and reject stale writes. External effects
still need their own delivery contract.

The colony uses world schema 15 and client schema 8 with variable-size derived snapshots.
Its world envelope exposes a checked run marker before the generic binary payload.
The application ID `siegework-colony-v15` starts a fresh save identity for the
sparser resource placement on the compact map. Old browser records remain untouched under their
previous identity and old imports reject.
Schema versions cover field meaning as well as shape. Reject incompatible schemas
until a deliberate migration exists. Portable snapshots contain values, not GPU
handles or WasmGC references. Copying a bounded record into a fresh module heap is
acceptable initially; document its cost and keep it behind the typed state API.

## Acceptance checks

| Check | Required evidence |
| --- | --- |
| Real browser path | Reproducible app-local `build.scm`; generated simulation Wasm executes; Scheme shader AST compiles to inspectable WGSL; real WebGPU submits indexed meshes. |
| Colony game | Multiple mine deliveries; hub/local construction conservation; cancellation and preemption ownership; depot/rail delivery and endpoint loss; discovery and known-route rules; calm drones; deterministic loss, resign, raid and surviving layout; zero kill income, staffed slots, sole-worker recovery, loss accounting and seeded replay. |
| Static solo | Local-only package makes no gameplay-server requests; IndexedDB commits precede publication; optional online checkpoint transfer leaves local play independent of service availability. |
| Immutable transitions | Retained prior snapshots stay unchanged; concurrent submissions have no lost updates; trap and failed durability commit publish no partial state/effects. |
| Compatible reload | Reload during hauling and combat, with a selected tool/cell, overscrolled camera, manual pause and pending input; preserve state and consume no simulation tick. |
| Failure isolation | Invalid candidate, incompatible schema and invalid WGSL leave the old application/pipeline usable. |
| Durable restart | Reopen the browser after a completed commit and recover the accepted colony and pause state. |
| Typed API | Compile-negative wrong handler payload, wrong state result and wrong application owner. Scheme and Lofi both import the same shader/application libraries. |

Record browser/version, actual GPU adapter, origin, build revision, providers and
limitations with the checks. Compilation alone does not pass a runtime gate.

## Explicit future work

Walls with deliberate breach behavior, randomized/fairly telegraphed finales, a
larger tech tree, terrain elevation, unbounded terrain generation and
additional resources remain deferred. The map uses a bounded seeded family.
Ordinary enemies retain their hub route and raiders their outpost route while
attacking structures. Observation is circular rather than
line-of-sight occlusion. Buildings do not block walking routes. Drones continue
working near enemies. These are experiment limits, not claims of a general
strategy-game simulation.
Current towers and the hub form a deterministic minimum spanning tree of
eligible straight ziplines. Clear cable sight and either endpoint's reveal
radius bound each link. Worker flights are bidirectional; freight moves toward
the hub. One bounded shuttle per link models throughput; there is no
manual track placement, rail collision or intermediate track damage.
Richer payload codecs, migrations, broader shader syntax, browser device recovery
and structural sharing are library milestones. Explicit opaque checkpoint
save/load is available as an optional build.
GPU tensors/PyTorch integration is a possible future motivating use case, not a
required dependency.

Model checking is also future work. Preserve inspectable typed protocol metadata
now; later add optional invariants and bounded trace exploration. Siegework examples
include nonnegative resources, no duplicate purchases, and unchanged state after
failed reload. Liveness depends on fair ticks, delivery assumptions and explicit
bounds. Deliberate tick cycles must remain distinguishable from runaway causal
message chains. Nothing here proves arbitrary Scheme termination or distributed
fairness, ordering or crash semantics.
