# WebGPU and graphics libraries

**Proposed.** Applications send `Frame` values to
`host/browser/renderer.mjs`, a fixed JavaScript renderer. This design replaces
it with two layers written in Snail-Core: a `gpu` effect that is a thin wrapper
around WebGPU, and `(snail-core graphics ...)` libraries of pipelines and
packers on top of it. Delivery is tracked in
[the graphics issue](https://github.com/tsnl/snail-scheme/issues/463).

Device requests, decoding, pipeline creation and readbacks need only ordinary
handlers and the runtime's waits. Those waits suspend through JSPI today and
become ordinary effects once handlers have one-shot continuations
([issue 511](https://github.com/tsnl/snail-scheme/issues/511)), so nothing here
depends on an engine extension.

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

## The `graphics` libraries

The graphics libraries are middleware: composable WebGPU pipelines and packers
whose interfaces are buffers and textures, in WebGPU's own terms. The
application decides what to pack, when to copy, and how to stitch passes
together. A higher-level operation such as drawing a sphere is a helper that
prepares the buffers a pipeline expects, not a call into a renderer.

**The ABI is not stable, on purpose.** A pipeline's interface is a Snail-Core
struct deriving `Pod`, and it changes when the pipeline does. Nothing is hidden
behind a renderer object: every pass, buffer and layout is a value the
application can read, replace or extend.

Each row is `(snail-core graphics NAME)`:

| Library | Provides |
| --- | --- |
| `pod` | `(deriving Pod)` on a struct gives its WGSL layout and alignment, a packer from a list to `Bytes`, and its WGSL declaration, one source of truth for each shader interface. |
| `wgsl` | Shaders as S-expressions: one-to-one with WGSL, read from source files by build-time recipes and printed to WGSL text, with struct declarations from `Pod`. |
| `mesh` | The flat glTF-shaped model as records and packers: geometry, material, instance, transform and indirect-draw tables, and lights. |
| `atlas` | Texture-array pages with padded slots, slot tables, mips, and texture encoders, uncompressed first. |
| `raster` | A deferred G-buffer pipeline with configurable targets: depth, normal, albedo, metal-roughness, emissive, ids and motion. |
| `passes` | Full-screen passes: a fixed sun, tone mapping, FXAA, copies. |
| `quad` | 2D quads in world units under a 2D camera, pixel-snapped in the vertex shader, sampling any texture view, including earlier passes' targets. |
| later | `bvh`, compute ray tracing and `svgf`, for path-traced lighting over the rasterized G-buffer. |

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

## Design choices

- Images are decoded by the host behind `decode-image`, a host operation
  that waits, rather than in Snail-Core.
- `update` stays total: prefetching happens from `view`.
- Open: shader sources as S-expression files compiled by `generate-library`
  recipes, the default here, or as S-expressions built in Snail-Core code.
