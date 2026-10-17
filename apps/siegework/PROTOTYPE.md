# Siegework prototype contract

Build one tiny, complete logistics-and-siege game. Keep the map fixed and the art
raw so language, compiler, state and browser problems become visible early. The
broader [game vision](README.md#the-run) is not a feature checklist for this demo.

## Minimum playable loop

- One fixed overhead grid, one hub, two candidate deposits, one extractor and one
  automatic hauler. Distance changes delivery time; the far deposit can justify
  the extra travel with a larger load.
- A small starting stock. Extractors, artillery, one economy upgrade and repairs
  compete for it. The authority checks affordability, bounds and occupancy.
- Timed, escalating attackers, followed by a warned siege beast. Defenses fire
  automatically. Lose when the hub falls, repel by surviving the deadline, or
  exterminate by killing the final attackers. An attempt lasts about two minutes.
- Snapped placement using pointer or controller/keyboard. Workers need no repeated
  orders. A single action starts a fresh run. Full radial menus, 3D art,
  pathfinding, procedural maps and randomized final events can wait.

The world must use **real WebGPU** and shaders compiled from Scheme expressions.
Colored quads and DOM status text are sufficient. No Canvas2D substitute and no
JavaScript copy of the simulation rules. The browser loads Snail-generated Wasm
and runs client reducers, pure presentation and speculative command transitions;
one server runs the same artifact for accepted world transitions.

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

Keep three lifetimes distinct:

1. The authoritative match survives code reload in its stable host.
2. A durable snapshot survives an authority process restart. The first SQLite
   adapter has one authority; it is not a distributed shared-writer solution.
3. Browser selection/cursor/pending input survives code reload independently of
   incoming world snapshots. A full page reset is not hot reload.

A durable transition includes state, revision, consumed retry sequence and match
epoch before acknowledgment/publication. Repeating a request cannot spend twice.
A stale-run command cannot affect a new run. External effects still need explicit
idempotency; do not claim universal exactly-once execution.

Schema versions cover field meaning as well as shape. Reject incompatible schemas
until a deliberate migration exists. Portable snapshots contain values, not GPU
handles or WasmGC references. Copying a bounded record into a fresh module heap is
acceptable initially; document its cost and keep it behind the typed state API.

## Acceptance checks

| Check | Required evidence |
| --- | --- |
| Real browser path | Reproducible app-local `build.scm`; generated simulation Wasm executes; Scheme shader AST compiles to inspectable WGSL; real WebGPU submits quads. |
| Small game | Automatic cargo deliveries, resource/placement validation, a deterministic losing run and a surviving layout; clock independent of render rate. |
| Two clients early | Distinct identified players act on one authoritative world; concurrent purchases serialize; both converge to the same accepted revision. |
| Immutable transitions | Retained prior snapshots stay unchanged; concurrent submissions have no lost updates; trap and failed durability commit publish no partial state/effects. |
| Compatible reload | Reload during hauling and combat, with a selected tool/cell and pending input; preserve state and consume no simulation tick. |
| Failure isolation | Invalid candidate, incompatible schema and invalid WGSL leave the old application/pipeline usable. |
| Durable restart | Restart after a commit before acknowledgment, retry it, recover the accepted state and avoid a second purchase. |
| Typed API | Compile-negative wrong handler payload, wrong state result and wrong application owner. Scheme and Lofi both import the same shader/application libraries. |

Record browser/version, actual GPU adapter, origin, build revision, providers and
limitations with the checks. Compilation alone does not pass a runtime gate.

## Explicit future work

Random/fairly telegraphed finales, richer routes, radial menus, 3D art, matchmaking,
large worlds and additional resources are game questions after this loop works.
Richer payload codecs, migrations, broader shader syntax, browser device recovery,
structural sharing and a server database with fencing are library milestones.
GPU tensors/PyTorch integration is a possible future motivating use case, not a
required dependency.

Model checking is also future work. Preserve inspectable typed protocol metadata
now; later add optional invariants and bounded trace exploration. Siegework examples
include nonnegative resources, no duplicate purchases, and unchanged state after
failed reload. Liveness depends on fair ticks, delivery assumptions and explicit
bounds. Deliberate tick cycles must remain distinguishable from runaway causal
message chains. Nothing here proves arbitrary Scheme termination or distributed
fairness, ordering or crash semantics.
