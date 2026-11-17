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

Its operations make buffers, textures, samplers, shader modules, render
pipelines and bind groups, write buffers and textures, encode copies and
render passes, and submit them; `request-device`, `read-buffer` and
`decode-image` wait for the host by ticket. The calls are procedural;
effects keep them reasonable. A `! gpu` row says exactly which functions
touch the device, and handlers customize what the calls do without
changing their callers. The browser target installs `provide-gpu`
(`(snail shell gpu page)`), which runs them on the page's device through
`host/browser/gpu.mjs`; `with-recorded-gpu` (`(snail shell gpu record)`)
records them instead, so a library is tested on Node without a device
(`tests/programs/gpu-record.sld`). `tests/browser/gpu.mjs` draws, reads back
and decodes on Chromium's software WebGPU.

Both handlers keep the same books, in `(snail shell gpu)`, and the host
keeps only a table from id to object:

- **Paths.** Long-lived objects are created by resource path, as in
  `(create-buffer (new BufferDescriptor (path (Some (list "siegework" "materials"))) ...))`.
  The same path and descriptor return the existing object, which is how a
  module that starts again finds what the last one created. A path names
  one object of each kind, so a pipeline and its bind group may share one.
  A handle says whether its object is `fresh`, so its contents are still to
  be written; a changed descriptor replaces the object, and the bind
  groups that named it.
- **Lifetimes follow the frame.** An object made without a path, such as
  an encoder, a pass or a transient buffer, is destroyed when the frame
  ends, at `submit`; `destroy` stays available.
- **Eviction.** Each frame marks the objects it uses. When an allocation
  would exceed the memory budget `request-device` was given, the least
  recently used unmarked objects that hold memory are evicted, with the
  bind groups that name them. If the marked objects alone exceed it, the
  program panics with a report of the largest. An evicted object is
  created afresh when its path is next asked for.
- **Handles carry generations**, the count of objects made by their path,
  and the books check every handle before the host sees it, so using a
  replaced, evicted or ended object panics with what it was rather than
  leaving WebGPU to report an invalid object.
- **Descriptors are fields.** A descriptor is a list of words and texts in
  a fixed order per kind: an object it names is its id, an enum value
  WebGPU's name for it, a list its count and then its items. The books
  compare those lists to find an object by its path, so a lookup encodes
  nothing. Only an object being made crosses to the host, as staged bytes
  that `host/browser/gpu.mjs` reads with a `DataView` into the dictionary
  WebGPU takes. A render pass and every other command crosses as calls
  with scalar arguments, an attachment's view and then its load and store.
  Buffer and texture contents cross as `Bytes`, which the host hands to
  WebGPU as a view of the program's memory, without a copy. A pipeline's
  layout is WebGPU's `"auto"`, so a bind group is made against a pipeline
  and a group index.

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

An `Atlas` is a value the application keeps: its pages' size and count,
the packer's cursor, and a table of slots, each a picture's page, corner
and version. Its pages are one `rgba8unorm` texture array made by path.
`atlas-pictures` places each picture whose version the atlas lacks on the
next shelf, a texel of transparency around it, and composes it in a render
pass of the caller's encoder: each layer is a piece that copies a source
region texel for texel, its colors swapped by a run of a storage-buffer
table, over the layers before it (`atlas.wgsl.scm`). A picture that no
longer fits clears every page, and the pictures asked for are placed
again; a texture made afresh, after a reload, empties the atlas. Images are
decoded by the host, once by their source's key. `atlas-url` copies a
region back and encodes it as a PNG data URL (`(snail shell png)`), so an
`img` in the HUD can show a composed portrait.

A `Quad` is a `Pod` record: center and size in world units, an angle, a
page, a texel region and a tint. `draw-quads` writes a run's instances and
a `View2D` camera to buffers named by the run and draws them instanced as
a triangle strip; the vertex shader snaps each corner to the target's
pixels (`quad.wgsl.scm`). Both shaders are printed by the recipe
`(snail shell graphics shaders)`.

Hearsay draws this way (`src/apps/hearsay/drawing.sld`). Its shapes are
pictures too, white texels and a hexagon drawn by the program as PNGs, so
each frame is one run of quads in the old renderer's order: ties, markers
and rings, bases, figures from far to near, then pips. Its frames match
the old renderer's within a pixel along edges. On headless Chromium's
software WebGPU, both keep 60 frames a second, and the page's main thread
spends 53 to 70 ms a second in tasks against the old renderer's 47 to 55:
the quads are rebuilt and packed every frame, where the old renderer kept
batches by version. An atlas composes one picture a call, since an LPC
sheet decodes to 4.4 MB and a character has six; composing eighteen
characters in one frame exceeded the budget, which the books reported.

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

`(snail shell graphics raster)` makes a frame's `Raster` once: the
pipelines found by path and the camera and sun written to uniforms. A
`Camera3D` carries its view-projection and its inverse, computed in closed
form for a pinhole or parallel lens, so the sun pass recovers each pixel's
position from its depth. `raster-meshes` writes albedo, normal, material
(metalness, roughness, glow) and depth; a revealed batch discards outside
its disc. `sun-pass` of `(snail shell graphics passes)` clears the target
to the background and lights each surface by Cook-Torrance under the sun
and the ambient light (`lighting.wgsl.scm`). `raster-translucent` then
draws translucent batches over it, lit by the same function, testing the
G-buffer's depth without writing it.

`(snail shell app)`'s `draw-frame` draws Siegework's `Frame` this way,
keeping each batch's packed instances in its `Frames` until the batch's
version changes, so a still frame writes only its uniforms. Siegework's
frames match the old renderer's shading. On headless Chromium's software
WebGPU, the page's main thread spends 31 to 33 ms a second in tasks
against the old renderer's 20 to 21; the GPU's own calls cost both about
10. Per frame the program creates no object, writes 11 buffers and draws 8
times, and what remains is spread across finding objects by path, the
three passes' calls and packing each batch's indirect arguments. Its
descriptors once crossed as JSON, and the books compared that text on
every lookup, which cost 51 ms a second. Textured meshes and sprites are gone from
`Frame`; pictures are drawn as quads from an atlas.

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
