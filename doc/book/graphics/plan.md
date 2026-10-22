# Runtime and graphics plan

**Status:** milestones 1 (tools) and 2 (the application runtime) are
implemented. The `ctl`, GPU and graphics-library work below remains
proposed. Applications run their own loop on JavaScript Promise Integration
(JSPI), while `src/app/renderer.mjs` still draws their `Frame` values. The
later milestones replace that renderer with a WebGPU effect and `graphics`
libraries of pipelines and packers.

## The application runs its own loop

An application's messages are pure functions over immutable state:

```scheme
(define-application Game
  (reset: default-reset) ; returns the binder the runtime runs inside
  (init: new-game)       ; seed width height -> Game
  (update: step)         ; Game Input -> Game
  (view: draw)           ; Game -> Frame
  (hud: panels)          ; Game -> (List Panel)
  (save: save-game)      ; Game -> Save
  (restore: restore-game)) ; Save -> Game
```

Only the loop calls the messages. `reset` returns a binder that surrounds
startup and the entire run with handlers. Its result and effect row are
quantified on the factory, rather than on the returned binder, so the
binder is monomorphic. `default-reset` just calls its argument. A later GPU
binder will install WebGPU handlers at this same boundary.

The generated loop exports `app_main : (Option Any) -> (Option Any)` with
`mut`, `screen`, `events` and `storage` effects. It first adopts a compatible
handover by structural TypeId, restores saved bytes if the type changed, or
initializes a cold start without a save. A live migration refuses an absent
or incompatible save; it never silently initializes fresh state. Only cold
startup may retry without an incompatible saved value.

`next-event` drains the queue through a plain `poll-event` import and
suspends through `wait-event` when it is empty:

- `FrameEvent` updates elapsed time, constructs a `Frame`, and renders it.
  HUD values are computed at most every 100 milliseconds; saves are made
  every five seconds.
- `InputEvent` updates state and the HTML HUD.
- `Hidden` saves and continues.
- `Reload` saves and returns the state as an opaque `Any`.

The state is a loop variable. One cell records the last state whose entire
event succeeded, after presentation and any save. A trap cannot commit its
partially processed candidate. States must be immutable; the message types
reject ordinary mutation, and explicit unsafe operations remain the caller's
responsibility. `app_state` returns the committed checkpoint as `Any` after
a trap. The `Frame` name remains drawing data, so the tick is named
`FrameEvent`.

### The host

The host starts one entry through JSPI:

```js
const main = WebAssembly.promising(instance.exports.app_main);
const handover = await main(previous); // null or an opaque managed value
```

`src/app/runtime.mjs` owns that invocation, its event queue and storage
imports. `host.mjs` owns the page's canvas, renderer, pictures and HUD across
invocations. DOM listeners enqueue events; they never call back into Wasm.
Consecutive moves for the same pointer and consecutive resizes coalesce
without crossing other input. Only consuming the pending frame requests
another animation frame, so slow work cannot accumulate ticks.

Event waits and whole storage operations use `WebAssembly.Suspending`.
Save imports copy a borrowed byte record before awaiting IndexedDB; even
failed persistence retains an owned snapshot for migration. GPU calls still
use the existing synchronous `screen` binding. Suspending device requests,
readbacks, image decoding and pipeline creation belong to the proposed GPU
milestone.

Reload fences the old queue with `Reload`. Its accepted prefix finishes,
the loop saves and returns, and the host waits for the entry to settle
before relinking any modules. New input waits for the next invocation. The
candidate starts with Resize and Frame(0); only successful initial
presentation accepts it and delivers the waiting input. Until then the old
program and its handover remain available for rollback. Cold startup,
including a retry, finishes before a relink may stop it.

After a trap the host reads `app_state`. When it needs to serialize that
checkpoint, it runs the old entry with `Reload` as its first event, avoiding
the failing update or view. A rejected candidate restarts the old program;
a cold first-frame failure also retains its owner so a source fix can resume
it. The consumed failing event is dropped; unread actions survive.

The invariants beside the runtime code are:

1. One entry per application is active at a time. The host calls only
   `app_main`, and `app_state` after a trap; all other work arrives as events.
2. Handler globals stay installed across suspension and return to their
   entry values after normal settlement or a trap. Entries never overlap
   within one runtime instance, so restoration cannot alter another run.
3. Only Lofi calls suspending imports. Rust scalar services keep a stack in
   linear memory that JSPI does not switch.
4. Host imports are leaves. No Wasm function is handed to a JavaScript
   callback API; an intervening JavaScript frame would prevent suspension.

The pinned Node 26 runs static and independently linked Wasm in headless
tests. Browser tests cover queued input, migration refusal, traps and cold
startup recovery. The [application model](../lofi/applications.md) and
[toolchain](../lofi/toolchain.md) describe the implemented API and reload
contract.

## Effects: `fun` and `ctl`

**Proposed, from milestone 3 onward.**

An operation declared `fun`, the default, always returns to its caller at
once; it compiles to a direct call, as every operation does today. An
operation declared `ctl` hands its handler the caller's continuation as
`resume`, which the handler may call once, later, or never.

`ctl` handlers run on JSPI. A `handle` with `ctl` operations runs its body
on a stack of its own, through a host trampoline. Performing a `ctl`
operation is a suspending import that sets the body's stack aside and
returns control to the handler; `resume` settles the body's promise, then
suspends the handler until the body performs again or returns, so `resume`
returns what the rest of the handled computation produces. An operation the
innermost handler does not handle is forwarded from that handler's stack.
A second `resume` traps. Handler stacks are global variables today, so each
switch saves and restores them with the stack it belongs to.

Measured in Chrome 156 with trivial work per call:

| Operation | Time |
| --- | --- |
| Wasm-to-Wasm call (a `fun` operation) | 4.5 ns |
| Plain JavaScript import | 9–11 ns |
| JSPI import that suspends | 84–88 ns |
| JSPI entry call, allocating a stack | 600–640 ns |
| `ctl` perform and resume on JSPI | 290–325 ns |
| `ctl` perform and resume on native stack switching | 45 ns |

`ctl` suits coarse operations, such as events, readbacks, asynchronous GPU
work and a few coroutines, and not per-element iteration; `fun` stays the
default. Native stack switching, implemented in Chrome behind
`--wasm-wasmfx`, later replaces the JSPI backend without changing programs.

## WebGPU through an effect

The `gpu` effect mirrors WebGPU's own operations and descriptors, so code
using it reads like WebGPU:

```scheme
(effect gpu
  ((create-buffer (-> BufferDescriptor GpuBuffer))
   (write-buffer (-> GpuBuffer I64 Bytes Unit))
   (create-texture (-> TextureDescriptor GpuTexture))
   (write-texture (-> TextureCopy Bytes Unit))
   (create-shader-module (-> ShaderSource GpuShaderModule))
   (create-render-pipeline (-> RenderPipelineDescriptor GpuRenderPipeline))
   (create-bind-group (-> BindGroupDescriptor GpuBindGroup))
   (create-command-encoder (-> GpuCommandEncoder))
   (begin-render-pass (-> GpuCommandEncoder RenderPassDescriptor GpuRenderPass))
   (set-pipeline (-> GpuRenderPass GpuRenderPipeline Unit))
   (set-bind-group (-> GpuRenderPass I32 GpuBindGroup Unit))
   (draw-indexed-indirect (-> GpuRenderPass GpuBuffer I64 Unit))
   (end-pass (-> GpuRenderPass Unit))
   (finish (-> GpuCommandEncoder GpuCommandBuffer))
   (submit (-> (List GpuCommandBuffer) Unit))
   (current-texture (-> GpuTexture))
   (destroy (-> GpuObject Unit))))
```

The calls are procedural; effects keep them reasonable. A `! gpu` row says
exactly which functions touch the device, and handlers customize what the
calls do without changing their callers: tracing, recording for tests,
validating handles, capturing a frame, or decoding compressed textures for a
device that lacks them.

- **Paths.** Long-lived objects are created by resource path, as in
  `(create-buffer (BufferDescriptor (path "siegework" "materials") size usage))`.
  The same path and descriptor return the existing object, which is how a
  reloaded module reattaches to what the last one created.
- **Lifetimes follow scope.** Objects created under `reset` live for the run;
  objects created during a frame, such as encoders and transient buffers,
  are destroyed when it ends; `destroy` stays available.
- **Eviction.** Each frame marks the objects it uses. Unmarked objects move to
  an LRU pool and are evicted only when an allocation would exceed the
  memory budget. If the marked objects alone exceed it, the runtime panics
  with a report of the largest. An evicted object is created afresh when
  next requested.
- **Handles carry generations**, so using an evicted handle is a clear error
  rather than a WebGPU validation message.
- **The boundary marshals.** Descriptors cross as staged bytes, and pass
  commands as small scalar calls that the default handler may batch until
  `submit`.

## The `graphics` library

`graphics` is middleware: composable WebGPU pipelines and packers whose
interfaces are buffers and textures. The application decides what to pack,
when to copy, and how to stitch passes together.

| Library | Provides |
| --- | --- |
| `(graphics pod)` | `(deriving Pod)` on a struct gives its WGSL layout and alignment, a packer from a list to `Bytes`, and its WGSL declaration, one source of truth for each shader interface. |
| `(graphics wgsl)` | Shaders as S-expressions: one-to-one with WGSL, read from source files by build-time recipes and printed to WGSL text, with struct declarations from `Pod`. |
| `(graphics mesh)` | The flat glTF-shaped model as records and packers: geometry, material, instance, transform and indirect-draw tables, and lights. |
| `(graphics atlas)` | Texture-array pages with padded slots, slot tables, mips, and texture encoders, uncompressed first. |
| `(graphics raster)` | A deferred G-buffer pipeline with configurable targets: depth, normal, albedo, metal-roughness, emissive, ids and motion. |
| `(graphics passes)` | Full-screen passes: a fixed sun, tone mapping, FXAA, copies. |
| `(graphics quad)` | 2D quads in world units under a 2D camera, pixel-snapped in the vertex shader, sampling any texture view, including earlier passes' targets. |
| later | `(graphics bvh)`, compute ray tracing and `(graphics svgf)`, for path-traced lighting over the rasterized G-buffer. |

- **Sampling an atlas.** Slots carry gutters of repeated edge texels; UVs wrap
  in slot space, `fract` for repeat and `clamp` for clamp; samples stay half
  a texel inside the slot; filtered textures use `textureSampleGrad` with
  derivatives of the unwrapped UVs, so the wrap cannot spike the mip level;
  pixel art samples nearest, without mips.
- **No bindless.** Core WebGPU has no binding arrays, so material textures live
  in atlas arrays, and the quad pass draws runs of quads that share a
  texture.
- **No multi-draw.** The G-buffer pass issues one `drawIndexedIndirect` per
  geometry; the `indirect-first-instance` feature lets each start at its
  own instance.
- **A low-poly game** packs its geometry, material and instance tables,
  renders albedo, normal and depth, lights them with a sun pass of its own
  or the library's, and composites the result to the canvas with quads. A
  richer game builds its own passes from the same pieces.

## Device baseline

Required features: `texture-compression-bc`, `shader-f16`,
`indirect-first-instance`, `float32-filterable` and
`rg11b10ufloat-renderable`; `timestamp-query` when present, for profiling.
Raised limits: buffer and storage-binding sizes near 1 GiB, 16384-texel
textures, and 64 bytes of color attachments per sample, since a full
G-buffer fills the default 32. Texture heaps start uncompressed; a later
`reset` may choose BC.

## Milestones

Each milestone is a focused series of pull requests:

1. **Tools.** *Done.* `shell.nix` takes nixpkgs from an npins pin, Node is
   at 26, and a podman devcontainer that CI builds packages the same tools.
2. **Runtime.** *Done.* The JSPI main loop, `reset`, the `events` and storage effects,
   and the HTML HUD driven from the loop, still drawing with today's
   renderer.
3. **`ctl`.** `ctl` operations and their handlers on JSPI.
4. **GPU.** The `gpu` effect, the host executor with paths, marking and
   eviction, the device baseline, and a recording handler.
5. **2D.** `(graphics pod)`, `(graphics wgsl)`, `(graphics atlas)` and
   `(graphics quad)`; Hearsay ported.
6. **3D.** `(graphics mesh)`, `(graphics raster)` and `(graphics passes)`;
   Siegework ported and the old renderer removed.

## Choices made, and open questions

- The rewrite is a new series of pull requests; the textured-sprite renderer
  in #380 remains the baseline it replaces.
- Images are decoded by the browser behind `decode-image`, a suspending
  import, rather than in Lofi.
- `update` stays total: prefetching happens from `view`.
- Open: shader sources as S-expression files compiled by recipes, the
  default here, or as S-expressions built in Lofi code.
