# A game that reloads while you play

**Planned integration tutorial.** The game actor owns world state and retained
graphics resources. The [native GUI runtime](../../book/platforms/native-gui.md) invokes
its input, lifecycle, and redraw handlers. A temporary frame actor computes the
next world and drabing commands from a snapshot.

Aim for `build.scm`, `game.sld`, and `frame.sld`. Start with a pure frame rule and
one headless frame. For the first interactive example, allow one frame computation
at a time:

1. Give the frame actor a copy of the world and queued input.
2. Keep collecting new input in a separate queue while the frame runs.
3. Accept the returned world and commands; use the new input in the next frame.

The event thread keeps running, and a result cannot overwrite newly queued
input. A slow frame still delays that input's visible effect. More concurrent
simulation would need an explicit rule for accepting or merging results.
Stopping a frame releases its temporary state; the game retains meshes and
textures until the GPU has finished using them.

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
- **G06 — Failure and budgets:** failures of spawned actors stay contained, connections
  clean up pending work, and queues remain bounded. `no-gc` forbids collection;
  `expect-no-gc` traps in debug and permits release recovery only when requested.
  WasmGC instances currently do not provide these collection controls.
- **G07 — Allocation bounds:** a later restricted frame rule has a stated input
  bound and verifiable allocation formula. Measurements are not a static proof.

Run pure host, headless lifecycle, and actual graphics profiles separately. Record
artifact versions, peak heap use, live actors/connections, and retained native/GPU
resources. The first implementation must choose the graphics backend and measure
its baseline before claiming frame-time or GC guarantees.
