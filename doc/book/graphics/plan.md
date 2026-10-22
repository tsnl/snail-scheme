# Runtime and graphics plan

**Status: proposed.** Nothing on this page is implemented yet. Today an
application is a `(lofi app)` program whose host calls into it for every
input and frame, and whose frames are drawn by a fixed WebGPU renderer in
`src/app/renderer.mjs`. This plan replaces both: the application runs its
own main loop, suspended between events by JavaScript Promise Integration
(JSPI), and draws through an effect that exposes WebGPU itself, with a
`graphics` library of pipelines and packers on top.

## The application runs its own loop

An application is a set of messages, each with the effects it may perform:

```scheme
(define-application Game
  (reset reset)       ; returns the binder the runtime runs inside
  (init  new-game)    ; seed width height -> Game                 total
  (update step)       ; Game Input -> Game                        total
  (view  draw)        ; Game -> Unit ! gpu                        one frame
  (hud   panels)      ; Game -> (List Panel)                      the HTML HUD
  (save save) (restore restore))

;; The binder installs handlers around whatever the runtime runs inside it.
(: reset (All (e) (-> (-> (-> Unit ! gpu e) Unit ! e webgpu))))
(define (reset)
  (lambda (run) (with-webgpu config (lambda () (with-gpu-trace run)))))
```

Message handlers never call one another; only the runtime does. `reset`
returns a binder rather than running the loop itself, so it stays a leaf
like `update` and `view`, and the runtime decides what runs inside the
handlers: the main loop, a test, or the next run after a reload. Its effect
row is quantified on `reset` itself, so the binder needs no higher-rank
type: the runtime instantiates it once, at the loop's own row.

The game's state is a loop variable, never a GPU object, and `update` stays
total so simulation stays deterministic and saves stay trivial.
`define-application` generates the loop, exported as `app_main`:

```scheme
(: app-main (-> (Option Any) (Option Any) ! events storage webgpu))
(define (app-main handover)
  ((reset) (lambda () (run (boot handover)))))

;; A state handed over by a reload is adopted when its type is unchanged;
;; otherwise the last save is restored, or a new game begins. The host is
;; told which, so a reload can say whether the game survived it.
(define (boot handover)
  (match (adopt handover)
    ((Some state) (report-boot (Adopted)) state)
    ((None) (match (load-save)                         ; suspends on IndexedDB
              ((Some bytes) (report-boot (Restored)) (restore-or-init bytes))
              ((None) (report-boot (Fresh)) (init (random-seed) (canvas-size)))))))

;; The loop keeps its latest state in a cell, and returns the state a reload
;; hands to the next run.
(define (run state)
  (remember! state)
  (match (next-event)
    ((Frame elapsed) (let ((next (update state (Elapsed elapsed)))) (view next) (run next)))
    ((Input input) (run (update state input)))
    ((Hidden) (store-save (save state)) (run state))
    ((Reload) (store-save (save state)) (Some (type-convert state Any)))))
```

`app_main` takes and returns an `(Option Any)`. `adopt` is a type test, not a
cast: it returns None when the `Any` holds another type, comparing TypeIds
that hash each type's fields and cases, so a reordered enum is a different
type. `app_state`, a plain export, returns the state cell as an `Any`.

`next-event` drains queued events through `poll-event`, a plain import, and
suspends through `wait-event` only when the queue is empty.

### The host

The host stops calling the application; the application calls the host.
The host calls one export, `app_main`, and reads the module's memory:

```js
const main = WebAssembly.promising(instance.exports.app_main);
const handover = await main(previous);   // the state a reload hands on, or null when the application quits
```

- DOM listeners push events into a queue that coalesces pointer moves and
  resizes, holds at most one pending frame, and requests the next animation
  frame only after the loop takes the last one.
- Asynchronous browser APIs are imports wrapped in `WebAssembly.Suspending`:
  `wait-event`, `load-save`, `store-save`, `request-device`, `map-read`,
  `create-render-pipeline-async`, `on-submitted-work-done` and
  `decode-image`. Synchronous WebGPU calls stay plain imports.
- Hot reload: the host pushes `Reload`; the loop saves and returns its state
  as an `Any`; with no frames left on the stack, the host relinks the changed
  modules, as #377's `relinkModules` does between events today, and calls
  the new `app_main` with that state. Its `boot` adopts the state when the
  `Any`'s type is unchanged, so an edit to a function body keeps the game
  exactly as it was, and falls back to the save otherwise. Its `reset`
  rebinds the handlers around the new run. No suspended stack is abandoned.
  GPU objects and their path index live in the host, so they survive the
  swap.
- A trap rejects `app_main`'s promise, and the host shows the error. The
  instance survives a trap, so the host reads the state from before the
  event that trapped through `app_state`, and hands it to the program the
  fix builds.

The invariants the runtime keeps beside its code:

1. The host calls only `app_main`, and `app_state` once `app_main` has
   trapped; while `app_main` is suspended, everything else arrives as an
   event.
2. Only Lofi code calls suspending imports, never a Rust service: the Rust
   runtime keeps a stack in linear memory that JSPI does not switch.
3. Host imports are leaves. No Wasm function is handed to a JavaScript API
   that calls back, since a JavaScript frame between the entry and a
   suspending import makes suspension fail.

Headless runs use Node 26 or later, whose V8 enables JSPI, or handle the
`events` and `gpu` effects in Lofi with scripted events and a recording
GPU handler.

## Effects: `fun` and `ctl`

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

Each is its own pull request:

1. **Tools.** Pin nixpkgs in `shell.nix` with `npins`, move to Node 26, and add
   a podman devcontainer.
2. **Runtime.** The JSPI main loop, `reset`, the `events` and storage effects,
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
