# WebGPU and graphics libraries

Applications draw through two layers written in `snail-scheme`: a `gpu`
effect that is a thin wrapper around WebGPU, and `(snail shell graphics
...)` libraries of pipelines and packers on top of it. They replaced a
fixed JavaScript renderer, `host/browser/renderer.mjs`, and its picture
store. The effect, `pod`, `wgsl`, `atlas`, `quad`, `mesh`, `raster` and
`passes` are **implemented**; the rest is **proposed**. Delivery is tracked
in [the graphics issue](https://github.com/tsnl/snail-scheme/issues/463).

Device requests, decoding, pipeline creation and readbacks need only ordinary
handlers and the runtime's waits. Those waits are an ordinary effect,
scheduled in `snail-scheme` ([task operations](../runtimes/tasks.md)), so nothing
here depends on an engine extension.

## WebGPU through an effect

The `gpu` effect of `(snail shell gpu)` mirrors WebGPU's own operations and
descriptors, so code using it reads like WebGPU:

```scheme
(let* ((encoder (create-command-encoder))
       (pass (begin-render-pass encoder
               (new RenderPassDescriptor
                 (colors (list (new ColorAttachment
                                 (view (view-of (● (current-texture) texture) 1))
                                 (load (Clear (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 1.0))))
                                 (store #t))))
                 (depth (None))))))
  (set-pipeline pass pipeline)
  (set-bind-group pass 0 group)
  (draw pass 3 1 0 0)
  (end-pass pass)
  (submit (list (finish encoder))))
```

Its operations make buffers, textures, views, samplers, shader modules,
render and compute pipelines and bind groups, write buffers and textures,
encode copies, render passes and compute passes, and submit them; `request-device`, `read-buffer` and
`decode-image` wait for the host by ticket. The calls are procedural;
effects keep them reasonable. A `! gpu` row says exactly which functions
touch the device, and handlers customize what the calls do without
changing their callers. The browser target installs `provide-gpu`
(`(snail shell gpu page)`), which runs them on the page's device through
`host/browser/gpu.mjs`; `with-recorded-gpu` (`(snail shell gpu record)`)
records them instead, so a library is tested on Node without a device
(`tests/programs/gpu-record.sld`). `tests/browser/gpu.mjs` draws, reads back,
decodes and dispatches a compute shader on Chromium's software WebGPU.

It is WebGPU itself, without bookkeeping:

- **Objects are kept by the program.** Each `create-...` call makes an
  object and answers a handle, the id the host gave it. A program makes its
  pipelines, bind groups, buffers and textures once, keeps them in its
  state across frames, and makes them again only when what they depend on
  changes, as a WebGPU program in JavaScript keeps its objects. `destroy`
  lets an object go at the next `submit`, after the commands that use it:
  a buffer's or texture's memory is freed, as WebGPU's `destroy` does, and
  the host forgets any other kind, as JavaScript's collector would. So a
  library destroys what it replaces as soon as it replaces it.
- **A frame's objects go once used.** An encoder goes at `finish`, a pass
  at `end-pass`, a command buffer at `submit`, and the canvas's texture and
  its views at the next `current-texture`.
- **Misuse is WebGPU's to report.** The handlers check nothing a device
  checks: a destroyed object reaches WebGPU's validation, which reports it
  on the page's console.
- **Descriptors are fields.** A descriptor is a list of words and texts in
  a fixed order per kind: an object it names is its id, an enum value
  WebGPU's name for it, a list its count and then its items. An object
  being made crosses to the host as those fields' staged bytes, which
  `host/browser/gpu.mjs` reads with a `DataView` into the dictionary WebGPU
  takes. A render pass and every other command crosses as calls with
  scalar arguments, an attachment's view and then its load and store.
  Buffer and texture contents cross as `Bytes`, which the host hands to
  WebGPU as a view of the program's memory, without a copy. A pipeline's
  layout is WebGPU's `"auto"`, so a bind group is made against a pipeline,
  render or compute (`GpuPipeline`), and a group index.

An earlier version kept books on the program's behalf: objects found by a
resource path each frame, ended at `submit`, evicted under a memory budget
and checked by generation. Finding every object again each frame cost
Siegework more than the old JavaScript renderer spent drawing, so the books
are gone and the program keeps what it makes.

## Pod and WGSL

A record of `F32`, `I32`, WGSL's vectors (`Vec2f`, `Vec3f`, `Vec4f`,
`Vec2i`, `Vec4i`), `Mat4x4f` and other such records derives `Pod`. Its
`Shape`, found by type with `(shape)`, holds its WGSL layout: offsets by
WGSL's rules, so a `vec3f` aligns to 16 and an `f32` may follow it in the
same 16 bytes; the struct declarations it needs; and, for a vertex buffer,
`vertex-layout`'s attributes. `pack` writes a list of values at the
shape's stride, and `pod-bytes` one value. `derive-pod` is a macro beside
the class, as the other derivations are; a deriving macro receives each
field's type, so a shape needs no value.

A shader is a file of forms, one per WGSL construct, which
`shader-library` prints when its recipe runs; its header in
`src/snail/shell/graphics/wgsl.sld` tabulates the forms. A form the
printer does not know fails the build at its line. The device test
(`tests/gpu/`) draws with a shader from `src/gpu-test/paint.wgsl.scm` and a
uniform from a `Pod` record, so the browser's WGSL compiler checks what the
printer writes; `tests/programs/graphics-wgsl.sld` and `graphics-pod.sld`
check the printing and the layouts.

## Atlas and quads

An `Atlas` is a value the application keeps, made with `make-atlas` once
the device answers: its pages, one `rgba8unorm` texture array; the
pipeline that composes into them; each source image decoded, by its key;
the packer's cursor; and a table of slots, each a picture's page, corner
and version.
`atlas-pictures` places each picture whose version the atlas lacks on the
next shelf, a texel of transparency around it, and composes it in a render
pass of the caller's encoder: each layer is a piece that copies a source
region texel for texel, its colors swapped by a run of a storage-buffer
table, over the layers before it (`atlas.wgsl.scm`). A picture that no
longer fits clears every page, and the pictures asked for are placed
again. The host decodes each source image once, and the atlas keeps it.
A composing's buffers go at its submit. `atlas-url` copies a
region back and encodes it as a PNG data URL (`(snail shell png)`), so an
`img` in the HUD can show a composed portrait.

A `Quad` is a `Pod` record: center and size in world units, an angle, a
page, a texel region and a tint. A `Quads`, made once for a target's
format and a texture array, holds the pipeline, the camera's uniform, the
instance buffer and their bind group; `draw-quads` writes a run's
instances and its `View2D` camera and draws them instanced as a triangle
strip, one run a frame. The vertex shader snaps each corner to the
target's pixels (`quad.wgsl.scm`). Both shaders are printed by the recipe
`(snail shell graphics shaders)`.

Hearsay draws this way (`src/apps/hearsay/drawing.sld`). Its shapes are
pictures too, white texels and a hexagon drawn by the program as PNGs, so
each frame is one run of quads in the old renderer's order: ties, markers
and rings, bases, figures from far to near, then pips. Its frames match
the old renderer's within a pixel along edges. On headless Chromium's
software WebGPU, both keep 60 frames a second, and the page's main thread
spends 58 to 60 ms a second in tasks against the old renderer's 47 to 48:
Hearsay rebuilds and packs its quads every frame, where the old renderer
kept batches by version. An atlas composes one picture a call, so a frame
decodes one character's sheets, each 4.4 MB once decoded.

Slots have transparent gutters, not repeated edge texels: pixel art
samples nearest, which never reads past a slot's edge, so gutters of
repeated texels wait for filtered textures, with mips.

## Meshes, the G-buffer and the sun

`(snail shell graphics mesh)` holds eight shapes, each standing on y = 0
within the unit cell, in one geometry table written once. `meshes` packs a
batch's `Instance` records grouped by shape, with one `DrawArgs` per
shape, so a batch is one `drawIndexedIndirect` per shape from its own first
instance. An instance carries where it is and where it was, its yaw, scale,
glow, color and material, and whether it turns to face the camera.

`(snail shell graphics raster)` keeps what a scene draws with. A program
makes its `Raster` once: the G-buffer's and the translucent pipelines, the
geometry, and the camera's and sun's uniforms with their bind groups; a
`GBuffer` for the canvas's size, made again when it changes; and a
`Surface` for each batch, its style's uniform and bind group and its
instances and indirect draws, made again when the batch changes. A frame
writes the camera and the sun, and draws. A `Camera3D` carries its
view-projection and its inverse, computed in closed form for a pinhole or
parallel lens, so the sun pass recovers each pixel's position from its
depth. A solid surface writes albedo, normal, material (metalness,
roughness, glow) and depth; a revealed batch discards outside its disc.
A second pass, `begin-lit`, clears the target to the background and holds
the G-buffer's depth read-only, so the pass can both sample it and test
against it. In it, `draw-sun` of `(snail shell graphics passes)`, through
its `Sunlight` (the pipeline, and a bind group over the G-buffer), lights
each surface by Cook-Torrance under the sun and the ambient light
(`lighting.wgsl.scm`). Translucent surfaces are then drawn over it, lit by
the same function, tested against the G-buffer's depth.

`(snail shell app)`'s `draw-frame` draws Siegework's `Frame` this way,
keeping each batch's surface until the batch's version changes, so a still
frame writes only the camera and the sun. Siegework's frames match the old
renderer's shading. On an RTX 5090, through headless Chromium on Vulkan,
the page's main thread spends 0.28 ms a frame at 60 frames a second,
against the old renderer's 0.24. Per frame the program makes one object,
the canvas's view, writes the camera and the sun, and draws 8 times over
two passes. On Chromium's software WebGPU, three passes and finding every
object by path each frame cost 31 to 33 ms a second of tasks, and 48 to 52
when descriptors crossed as JSON, against the old renderer's 20 to 21.
Textured meshes and sprites are gone from `Frame`; pictures are drawn as
quads from an atlas.

## The `graphics` libraries

The graphics libraries are middleware: composable WebGPU pipelines and packers
whose interfaces are buffers and textures, in WebGPU's own terms. The
application decides what to pack, when to copy, and how to stitch passes
together. A higher-level operation such as drawing a sphere is a helper that
prepares the buffers a pipeline expects, not a call into a renderer.

**The ABI is not stable, on purpose.** A pipeline's interface is a `snail-scheme`
record deriving `Pod`, and it changes when the pipeline does. Nothing is hidden
behind a renderer object: every pass, buffer and layout is a value the
application can read, replace or extend.

Each row is `(snail shell graphics NAME)`:

| Library | Provides |
| --- | --- |
| `pod` | `(deriving Pod)` on a record gives its WGSL layout and alignment, a packer from a list to `Bytes`, its vertex attributes and its WGSL declaration, one source of truth for each shader interface. **Implemented.** |
| `wgsl` | Shaders as S-expressions: one-to-one with WGSL, read from source files by build-time recipes and printed to WGSL text, with struct declarations from `Pod`. **Implemented.** |
| `mesh` | The flat glTF-shaped model as records and packers: geometry, material, instance, transform and indirect-draw tables, and lights. **Implemented** as a geometry table of eight shapes, instances and indirect draws. |
| `atlas` | Texture-array pages with padded slots and slot tables, uncompressed. Pictures are composed into them on the GPU. **Implemented**, without mips. |
| `raster` | A deferred G-buffer pipeline with configurable targets: depth, normal, albedo, metal-roughness, emissive, ids and motion. **Implemented** with fixed albedo, normal, material and depth targets, and a forward pipeline for translucent surfaces. |
| `passes` | Full-screen passes: a fixed sun, tone mapping, FXAA, copies. **Implemented**: the sun. |
| `quad` | 2D quads in world units under a 2D camera, pixel-snapped in the vertex shader, sampling a texture array, including earlier passes' targets. **Implemented.** |
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

Required features: `indirect-first-instance`, `float32-filterable` and
`rg11b10ufloat-renderable`. Used when present: `texture-compression-bc`,
which phones lack, `shader-f16`, which SwiftShader, the tests' adapter,
lacks, and `timestamp-query`, for profiling; `request-device` answers which
it got. Raised limits, as far as the adapter allows: buffer and
storage-binding sizes of 1 GiB, 16384-texel textures, and 64 bytes of color
attachments per sample, since a full G-buffer fills the default 32. Texture
heaps start uncompressed; a later `reset` may choose BC.

## Design choices

- Images are decoded by the host behind `decode-image`, a host operation
  that waits, rather than in `snail-scheme`.
- `update` stays total: prefetching happens from `draw`.
- Shader sources are S-expression files printed by `generate-library`
  recipes, since a quoted form is a literal only. A shader's structs come
  from `Pod` at run time: `(string-append (declarations shape) shader)`.
