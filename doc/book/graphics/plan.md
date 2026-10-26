# WebGPU and graphics libraries

**Proposed.** The [application loop](../lofi/applications.md) and
[task runtime](../runtimes/index.md) already execute on JSPI. Applications still
send `Frame` values to `host/browser/renderer.mjs`; this design replaces that renderer
with a concrete GPU effect and libraries of pipelines and packers. Delivery is
tracked in [the graphics issue](https://github.com/tsnl/snail-scheme/issues/463).

Ordinary reusable handlers and runtime-provided waits are sufficient for device
requests, decoding, pipeline creation and readbacks. Public `ctl` is not required.
JSPI does not expose typed delimited continuation values; the
[continuation research](../runtimes/future.md) and
[explicit-lowering draft](../runtimes/memory-and-continuations.md) explain future
options without making GPU work depend on an engine extension.

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

## Design choices


- Images are decoded by the browser behind `decode-image`, a suspending
  import, rather than in Lofi.
- `update` stays total: prefetching happens from `view`.
- Open: shader sources as S-expression files compiled by recipes, the
  default here, or as S-expressions built in Lofi code.
