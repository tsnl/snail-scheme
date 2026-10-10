# A game that reloads while you play

**Planned integration tutorial.** Build a small game whose Scheme library exports
window handlers. The runtime creates the root actor and invokes resume, input,
resize, redraw, and close handlers. Scheme authoring starts with ordinary pure
rules; the platform owns the event loop and IO.

Aim for `build.scm`, `game.sld`, and `frame.sld`. A frame actor receives an owned
snapshot and computes the next world and drawing commands in a temporary heap.
It returns independently owned results and retires. The renderer retains meshes
and textures behind explicit resource references. Input must continue while a
frame call is suspended; no actor-wide waiting lock is implied.

## Observable checkpoints

- **G01 — Entry and IO:** a real window dispatches handlers; snapshot save/load
  exercises Rust runtime IO and repeated startup/shutdown cleans up correctly.
- **G02 — Pure rules:** a fixed input trace produces equivalent results under
  Chibi and compiled Scheme, without requiring a renderer.
- **G03 — Frame lifetimes:** 10,000 bounded headless jobs drain back to baseline
  actor/resource counts. Temporary heaps are isolated; the proposed 32-bit heap
  model and independent collection controls need explicit runtime support.
- **G04 — Retained graphics:** delayed GPU completion and resize do not free live
  buffers. Messages carry small commands, not textures or rendered frames.
- **G05 — Reload:** new frames use a validated replacement artifact; in-flight
  work pins the old version. Invalid builds preserve the running version; world
  schema changes require an explicit migration or reset.
- **G06 — Failure and budgets:** subordinate failures stay contained, connections
  clean up pending work, and queues remain bounded. `no-gc` forbids collection;
  `expect-no-gc` traps in debug and permits release recovery only when requested.
  WasmGC instances currently do not provide these collection controls.
- **G07 — Allocation bounds:** a later restricted frame rule has a stated input
  bound and verifiable allocation formula. Measurements are not a static proof.

Run pure host, headless lifecycle, and actual graphics profiles separately. Record
artifact versions, peak heap use, live actors/connections, and retained native/GPU
resources. The first implementation must choose the graphics backend and measure
its baseline before claiming frame-time or GC guarantees.
