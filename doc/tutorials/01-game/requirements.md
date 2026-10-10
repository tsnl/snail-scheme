# Game acceptance criteria

All criteria are **planned**. The [tutorial](README.md) is the reading sequence;
this file states observable evidence for the future integration test.

| ID | Exercise | Required evidence |
| --- | --- | --- |
| G01 | Build the actor definition and start the native window runtime. Dispatch resume, input, resize, suspend/resume, redraw, and close. | The runtime spawns the root and invokes exported Scheme handlers. No Scheme polling loop. Window/surface cleanup handles repeated lifecycle events and partial initialization. |
| G02 | Replay a fixed input trace through the pure rule under Chibi and compiled code; save/reload a snapshot through IO. | Equivalent world/drawing results, separate app and reusable libraries, and errors returned through the file-service contract. No renderer needed for this checkpoint. |
| G03 | Run 10,000 bounded headless frame jobs with one simulation frame in flight. | A distinct isolated heap per job using the planned 32-bit Scheme object ABI, independent of native pointer width; actor count and temporary heap usage return to baseline after draining. Input remains responsive during a suspended frame call. Every output is independently owned before retirement. |
| G04 | Render with retained meshes/textures while delaying GPU completion and resizing. | No per-frame texture/framebuffer S-expression transfer; encoded command-size counters and independent device-memory counters. Resources stay alive until fences permit release; stale handles fail. Real window/device execution is required in the graphics profile. |
| G05 | Reload a compatible rule while a frame is running; then try invalid code and an incompatible world schema. | New spawns use the accepted artifact, old work pins its version, bad builds leave the last valid version usable, schema changes require explicit migration/reset. Closing retires all old artifacts and resources after their last use. |
| G06 | Exhaust each GC policy's budget in debug and release; kill a child and cancel pending frames. | `no-gc` never collects; `expect-no-gc` traps in debug and only recovers in release when requested; recovery observes rooted safepoints. Supervision contains failure, connection endpoints settle or terminate pending work, stale results cannot commit, and queue/actor limits hold. |
| G07 | Analyze a restricted bounded frame rule, then exceed an input bound. | A stated allocation formula with assumptions and accounting for runtime overhead; an eventual checker verifies it or reports unsupported analysis. Dynamic measurements are a separate result. This is a research extension, not a prerequisite for the first playable game. |

## Test profiles

The **host profile** runs pure rules with Chibi. The **headless profile** runs
actual actor isolation, codec, reload, and failure behavior using small native
test providers. The **graphics profile** runs a real window and renderer. A
headless pass or successful compilation cannot stand in for graphics execution.

Record artifact hashes, frame numbers, entity/input bounds, heap reservations,
peak live bytes, collection counts, outstanding actors/connections, queue sizes,
and native/GPU resource counts. Record timing on an identified machine; do not
invent a universal frame-time guarantee from the heap budget.

The 10,000-frame soak count is a proposed regression workload, not a performance
claim. Repeat reload/failure cycles within it and compare post-drain ownership
counters, not an assumption that an allocator immediately returns memory to the OS.

## Dependencies and remaining choices

Required platform work includes reusable root-actor loading, per-instance globals,
typed S-expression codecs, spawn/connect, futures and suspension, bounded heaps,
native window/renderer/file providers, and candidate-artifact publication. Full
`call/cc`, automatic allocation proofs, and arbitrary thread migration are not
requirements for the first runnable checkpoint.

Choose the initial graphics backend and frame reservation from a measured baseline.
Define the failure boundary of a debug trap and the world-store commit/version
policy before implementing G06. The tutorial must state these choices explicitly.
