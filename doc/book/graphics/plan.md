# WebGPU design

Applications draw through two layers written in `snail-scheme`: a `Gpu`
capability that is a thin wrapper around WebGPU, and `(snail shell graphics
...)` libraries of pipelines and packers on top of it. They replaced a
fixed JavaScript renderer, `host/browser/renderer.mjs`, and its picture
store. This chapter explains how the layers work and why they are shaped
as they are; the [library reference](../libraries/gpu.md) lists each
library and its entry points. Open work on them is tracked in
[the graphics issue](https://github.com/tsnl/snail-scheme/issues/463).

The game renderers now expose scene-level interfaces. Siegework and Hearsay share the forward color pass and presentation with the glTF renderer. The G-buffer and deferred-light timings below describe the earlier path and its lower-level GPU fixtures. [Current rendering architecture](rasterizer.md).

Device requests, decoding, pipeline creation and readbacks need only ordinary
functions and the runtime's waits. Those waits are suspensions,
scheduled in `snail-scheme` ([task operations](../runtimes/tasks.md)), so nothing
here depends on an engine extension.

## WebGPU through a capability

The `Gpu` of `(snail shell gpu)` mirrors WebGPU's own operations and
descriptors, each a field of the `Gpu`:

```scheme
(let* ((encoder ((● gpu create-command-encoder)))
       (frame ((● gpu current-texture)))
       (pass ((● gpu begin-render-pass)
              encoder
              (new RenderPassDescriptor
                (colors (list (new ColorAttachment
                                (view (view-of gpu (● frame texture) 1))
                                (load (Clear (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 1.0))))
                                (store #t))))
                (depth (None))))))
  ((● gpu set-pipeline) pass pipeline)
  ((● gpu set-bind-group) pass 0 group)
  ((● gpu draw) pass 3 1 0 0)
  ((● gpu end-pass) pass)
  ((● gpu submit) (list ((● gpu finish) encoder))))
```

Its operations make buffers, textures, views, samplers, shader modules,
render and compute pipelines, bind groups and query sets, write buffers and
textures, encode copies, render passes and compute passes, and submit
them. A pass begun timed (`begin-timed-render-pass`,
`begin-timed-compute-pass`) writes the device's time into two queries, as
it begins and as it ends; `submit-timed` resolves the queries after the
encoder's commands, submits it and reads the times, and `elapsed-seconds`
answers the time between two. `request-device`, `read-buffer` and
`decode-image` wait for the host by ticket, as does `work-done`, which
waits until the device has done what was submitted, so a loop whose
frames cost the device more than a display frame does not queue them
without bound. The calls are procedural;
the capability keeps them reasonable. A `Gpu` parameter says exactly which
functions touch the device, and a `Gpu` is a record of the operations, so
another one changes what the calls do without changing their callers.
`host-gpu`, in `(snail shell gpu)` itself, runs them on the host's device
through `host/browser/gpu.mjs`: the browser target provides it to a page's
main, and a program on Node makes it itself, where it uses Dawn
([WebGPU on Node](#webgpu-on-node)).
`with-recorded-gpu` (`(snail shell gpu record)`) records them instead, so a
library is tested without a device (`tests/programs/gpu-record.sld`).
`tests/browser/gpu.mjs` draws, reads back, decodes and dispatches a compute
shader on Chromium's software WebGPU, and `tests/gpu.mjs` runs the checks
that need no screen on Node's device.

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
- **Misuse is WebGPU's to report.** The host's `Gpu` checks nothing a device
  checks: a destroyed object reaches WebGPU's validation, which reports it
  on the page's console.
- **Descriptors are fields.** A descriptor is a list of words and texts in
  a fixed order per kind: an object it names is its id, an enum value
  WebGPU's name for it, a list its count and then its items. An object
  being made crosses to the host as those fields' staged bytes, which
  `host/browser/gpu.mjs` reads with a `DataView` into the dictionary WebGPU
  takes. A render pass and every other command crosses as calls with
  scalar arguments, an attachment's view and then its load and store, and
  a timed pass's query set and indices before the pass begins.
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
field's type, so a shape needs no value. Derived record and field names
use underscores in WGSL wherever their Scheme names have hyphens. For
example, shaders refer to the record `Paint-uniform` as `Paint_uniform`.

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
glow, color and whether it turns to face the camera. Its `material` is a
`Vec2f` holding metalness and roughness. Its `id` is an `I32` for picking.

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

The `Raster` and the `GBuffer` are made for the same `Planes`, which may
add two more. Motion, `rg16float`, is the screen motion in texture
coordinates from where the pixel's surface was in the last frame:
`write-raster` returns the raster with the frame's camera kept, so the
next frame's vertices are placed under both cameras. An upright sprite
faces each frame's viewing direction when computing its motion. The `r32uint` plane
holds all 32 bits of each instance's `id` field, with 0 where nothing
is drawn. `read-id` returns those bits as an `I32` for picking. A plane
left out has no target in the pipeline and no attachment in the pass,
WebGPU's null target, so the shader's output there costs nothing. Siegework draws with
`color-planes`, the four without motion or ids.
A second pass, `begin-lit`, clears the target to the background and holds
the G-buffer's depth read-only, so the pass can both sample it and test
against it. In it, `draw-sun` of `(snail shell graphics passes)`, through
its `Sunlight` (the pipeline, and a bind group over the G-buffer), lights
each surface by Cook-Torrance under the sun and the ambient light
(`lighting.wgsl.scm`). Translucent surfaces are then drawn over it, lit by
the same function, tested against the G-buffer's depth.

The lit pass draws into a light target of `light-format`, `rgba16float`,
so a highlight may be brighter than 1. `draw-post`, through a `Post` made
for the canvas's format and size, brings it to the screen in two
full-screen passes (`post.wgsl.scm`). The `Post`'s `Tone` chooses the
curve. `Neutral`, for light already in display terms, takes the shoulder
of Khronos's PBR Neutral curve without its toe: a color whose largest
channel is under 0.8 passes unchanged, so a scene keeps the colors it was
drawn in, and a brighter one is scaled toward 1, keeping its hue, and
desaturated a little. `Filmic`, for physical light, is John Hable's curve
from Uncharted 2 with a white point of 11.2, then encoded as sRGB, since
the canvas's 8-bit formats are not sRGB formats. FXAA, in the reduced form of Lottes's algorithm many
WebGL renderers use, then blends each pixel along the edge its diagonal
neighbors' brightness shows.

`(snail shell app)`'s `draw-frame` draws Siegework's `Frame` this way,
keeping each batch's surface until the batch's version changes, so a still
frame writes only the camera and the sun. Siegework's frames keep the old
renderer's shading below the tone curve's knee, with smoothed edges. On an
RTX 5090, through headless Chromium on Vulkan, the page's main thread
spends 0.28 to 0.35 ms a frame at 60 frames a second, against the old
renderer's 0.24. Per frame the program makes one object, the canvas's
view, writes the camera and the sun, and draws over four passes: the
G-buffer, the lit pass, tone mapping and FXAA. On Chromium's software
WebGPU, three passes and finding every
object by path each frame cost 31 to 33 ms a second of tasks, and 48 to 52
when descriptors crossed as JSON, against the old renderer's 20 to 21.
Textured meshes and sprites are gone from `Frame`; pictures are drawn as
quads from an atlas.

## Scans, sorts and gaussian splats

`(snail shell graphics scan)` computes an exclusive prefix sum of a storage
buffer's `u32` numbers in place, by Blelloch's work-efficient scan
(`scan.wgsl.scm`). A workgroup of 256 invocations scans a tile of 512
numbers in workgroup memory, an upsweep building a tree of partial sums and
a downsweep handing each node the sum to its left, and writes the tile's
total to a buffer of sums one level up. That level is scanned the same way
until one fits in a tile, and each level's scanned sums are then added back
to the tiles below it, top down. A `Scan` is made once for a buffer and a
count, keeping each level's sums, uniform and bind groups, and
`dispatch-scan` encodes it into a compute pass; dispatches in a pass see
the writes of those before them.

`(snail shell graphics radix-sort)` sorts `u32` keys and their `u32` values,
least-significant digit first, eight bits a pass (`radix-sort.wgsl.scm`).
A pass's workgroups share the blocks of 256 keys in runs, the first
workgroup taking the first run. A pass counts each run's keys by digit into
a table laid out digit-major, 256 words a workgroup, and scans the table
with a `Scan`, which gives where each run's keys of each digit start. It
then scatters each key and its value there, a block at a time, after the
keys of its digit earlier in the run. A key's rank in its block is a count
of the matching digits before it in workgroup memory, the simplest stable
ranking, so every pass is stable and the passes together sort. A table
laid out by block, as the sort's was at four bits a pass, would hold as many
words as there are keys at 256 digits; by workgroup it holds a million at
most. A `Sorter` sorts 8, 16, 24 or 32 bits from one pair of keys and
values into another. Its passes alternate between the second pair and a
spare pair of its own so that the last pass writes the second pair, so it
sorts a pair in place only when the passes are even: 16 or 32 bits. Both
libraries are building blocks with no knowledge of what they order.

`(snail shell graphics splat)` renders 3D Gaussian Splatting (Kerbl et
al., 2023) with them. A `Gaussian` is a `Pod` record: its center, the row
of the transforms table that places it, a unit quaternion, its standard
deviations and its opacity, already activated. Its quaternion and its
deviations with its opacity are f16s (`Vec4h`), so a record is 32 bytes
where floats took 48; its center stays a float, since f16s step by 0.004
six units from the origin, more than a tenth of the size of three in four
of bicycle's trained gaussians. Its 16 spherical-harmonic
colors, to degree 3, sit beside it in a buffer of f16s two to a 32-bit
word, 26 words a gaussian: 104 bytes where 48 floats took 192. Each degree
starts a word of its own, so a kernel reading one degree reads only its
words, and kernels unpack them with WGSL's own `unpack2x16float`, which
every device has, where `shader-f16` is missing from Dawn on NVIDIA's
Vulkan driver and from SwiftShader. A
program makes its `Splats` once with room for its gaussians and its
transforms, writes `Cloud`s of packed gaussians where it likes, and writes
the transforms table whenever things move, so clouds are posed and
composed without touching their gaussians. A frame is a compute pass and a
draw, each in a pass the caller begins:

- `sort-splats` projects every gaussian, an invocation each
  (`splat-project.wgsl.scm`): its transform carries its center and its
  covariance R S Sᵀ Rᵀ into the world, the view and the pinhole's Jacobian
  at its center carry the covariance to the screen (EWA splatting), 0.3
  pixels² of blur keeps it at least a pixel wide, and its inverse is the
  conic the fragment stage evaluates. Its color is its harmonics seen from
  the eye in its own frame, through the inverse of its transform. Its key
  is its depth's bits inverted, so a radix sort of the keys puts far before
  near; a culled gaussian keeps radius 0 and the largest key.
- `draw-splats` draws a square of each gaussian's radius per instance, in
  sorted order (`splat-draw.wgsl.scm`), whose fragments blend
  `exp(-dᵀ conic d / 2)` times its opacity over what is drawn.

This is the reference's math with a global sort and blended quads in place
of its tiled rasterizer, so it needs no per-tile lists. `(snail shell
graphics ply)` reads the binary PLY files 3DGS trains into a `Cloud`, its
header parsed into where each property sits, every gaussian activated and
given the same transform row. Its `write-ply` writes such a file from a
cloud as training keeps it, a `Trained`: the properties in the reference's
order, nothing activated, the rows that are no gaussian left out. `write-cloud` sends a cloud to the device
65,536 gaussians at a time, since a write's bytes are copied whole into the
runtime's memory on their way and a trained scene's run to a gigabyte.

`(snail shell graphics splat-view)` draws the same splats tile by tile, as
training renders them ([differentiable
splatting](tensors.md#differentiable-splatting)): `splat-train`'s graph,
rendered for viewing, lowered to a program that is given the splats' own
gaussians, coefficients and transforms with `bound`. Its params view each
`Gaussian` record as a row of floats, narrowed at the offsets its `Pod`
layout gives. Each activated scale and opacity goes back to the logarithm
and logit the renderer activates. Each transform row becomes a
`Placement`, gathered per gaussian. The program's steps go into the
caller's compute pass, and a triangle in the caller's render pass presents
the image. It blends front to back in floats, over black, and stops where a
pixel's transmittance would fall under 1e-4. The quads blend back to front
in the target's eight bits and never stop early. Both clamp alpha to 0.99,
skip what is under 1/255, and cull a gaussian under 1/255 opacity. Where
two gaussians stand at one depth, the quads draw the later one over the
earlier, and the tiles put the earlier in front.

`src/apps/splats/compare.scm` measures the two on Node, at the views a
scene was photographed from, each frame's passes timed on the device. On
bicycle as `src/apps/train` trains it (4,194,304 gaussians), at
1237x822, on an RTX 5090, over eight photographs' views:

| | Compute pass | Render pass | PSNR against the photograph |
| --- | --- | --- | --- |
| Quads | 1.37 ms | 2.98 ms | 25.23 dB |
| Tile by tile | 16.10 ms | 0.01 ms | 25.55 dB |

The tiles' image is closer to the photographs at every view, since
training fitted the cloud to this renderer. The PSNR between the two
renderers' images is 38.3 dB on average, and 31.4 at the least. The
tiles take 3.7 times as long. Their blend alone took 1.72 ms, less than
the quads' draw. Their two sorts took 1.92 and 0.85 ms. When this was
measured, before tensor graphs were fused
([#875](https://github.com/tsnl/snail-scheme/issues/875)), most of the rest
of their 273 steps were the projection's tensor kernels, a buffer each.

`src/apps/splats` opens on one procedural ring written three times on three
transform rows, which it turns each frame, and shows a trained scene in
their place: a `.ply` dropped on the page, picked, or named by
`?cloud=ADDRESS`. A reconstruction's frame has no up of its own, so the
viewer takes it from the cameras that photographed the scene, COLMAP's
`images.bin`, read by `(snail shell graphics colmap)`, whose `poses-up` is
the mean of their ups. It turns the cloud upright by its transform row,
where the harmonics turn with it, and starts at the first camera. `(snail
shell graphics fly)` flies the view, as it does the path tracer's, and its
`upright` is the turn. Mip-NeRF 360's bicycle as
`src/apps/train` trains it, a 1 GB file of 4,194,304 gaussians, took 22
seconds to read in Chrome and flew at the display's 60 frames a second on
an RTX 5090. T toggles drawing tile by tile. Every two seconds the console
has the frame rate and one frame's compute and render passes, timed on the
device where it has timestamps.

`tests/programs/graphics-splat.sld` reads a PLY file and records the
dispatches of a frame of 300,000 gaussians; `tests/browser/gpu.mjs` scans
300,000 numbers in three levels and checks each, sorts 5,000 keys and
checks the order is stable, and splats three gaussians, then turns one by
its transform, as quads and tile by tile; both agree to a step of a texel. On an RTX 5090, through headless Chromium on Vulkan, the
viewer keeps 60 frames a second with room for 60,000, 1,000,000 and
4,000,000 gaussians, the gaussians it does not write culled but sorted and
drawn; from submit to the queue's completion takes 3.9, 3.8 and 5.8 ms at
the median.

## Middleware, not a renderer

The graphics libraries are middleware: composable WebGPU pipelines and packers
whose interfaces are buffers and textures, in WebGPU's own terms. The
application decides what to pack, when to copy, and how to stitch passes
together. A higher-level operation such as drawing a sphere is a helper that
prepares the buffers a pipeline expects, not a call into a renderer.

**The ABI is not stable, on purpose.** A pipeline's interface is a `snail-scheme`
record deriving `Pod`, and it changes when the pipeline does. Nothing is hidden
behind a renderer object: every pass, buffer and layout is a value the
application can read, replace or extend.

- **No bindless.** Core WebGPU has no binding arrays, so material textures live
  in atlas arrays, and the quad pass draws runs of quads that share a
  texture. The path tracer puts every image in one texture array for the
  same reason ([scenes](tracer.md#scenes)).
- **No multi-draw.** The G-buffer pass issues one `drawIndexedIndirect` per
  geometry; the `indirect-first-instance` feature lets each start at its
  own instance.
- **A low-poly game** packs its geometry, material and instance tables,
  renders albedo, normal and depth, lights them with a sun pass of its own
  or the library's, and composites the result to the canvas with quads. A
  richer game builds its own passes from the same pieces.
- **Filtered textures** are **proposed**: the atlas would then carry gutters
  of repeated edge texels and mips, UVs would wrap in slot space (`fract`
  to repeat, `clamp` to clamp) with samples half a texel inside the slot,
  and a filtered sample would use `textureSampleGrad` with derivatives of
  the unwrapped UVs, so the wrap cannot spike the mip level. Pixel art
  samples nearest today, which needs none of this.

## WebGPU on Node

On Node the device is [Dawn](https://dawn.googlesource.com/dawn)'s, the
WebGPU implementation inside Chromium, through Dawn's own Node binding,
`dawn.node`, as npm's [`webgpu`](https://github.com/dawn-gpu/node-webgpu)
package publishes it prebuilt. The repository's `package.json` pins it and
`make fetch` installs it; a Node build of a program that may ask for a
device depends on the same version
([a Node package](../snail-scheme/projects.md#a-node-package)). On Linux,
Dawn reaches the GPU through Vulkan, opening the loader by name, and the
loader finds the system's driver. NixOS keeps no loader where the dynamic
linker looks, so `shell.nix` names nixpkgs' in `LD_LIBRARY_PATH`; outside
the shell, NixOS needs the same, or `vulkan-loader` among `nix-ld`'s
libraries. The shell also adds Mesa's lavapipe, Vulkan on the CPU, to the
system's drivers: Dawn prefers a GPU, and on a machine without one, as
CI is, the checks run on lavapipe. `host/native/gpu.mjs` hands Dawn to the same
`host/browser/gpu.mjs` the page uses, at the program's first
`request-device`, so a program that never asks for a device needs none. A
program on Node makes the `Gpu` itself, as `tests/gpu/node.scm` does:

```scheme
(define (main (host Host) (out OutputPort)) (→ Unit)
  (let* ((gpu (host-gpu host)) (info ((● gpu request-device))))
    (write-line out (string-append "format: " (texture-format-name (● info format))))
    (device-checks gpu out)
    ((● gpu work-done))))
```

Node has no screen: there `current-texture` fails, so a program draws into
textures of its own, which are `rgba8unorm`, and reads them back.

Dawn rounds timestamps to 65,536 ns unless told not to, as Chromium rounds
a page's to 100 μs, so that a page cannot time what it should not see.
`host/native/gpu.mjs` tells it not to: a program on Node is no page, and
can time a kernel of a few microseconds.

Node decodes no images of its own either, as a browser does, so
`decode-image` there is npm's
[`@napi-rs/canvas`](https://github.com/Brooooooklyn/canvas) package, a 2D
canvas over Skia, pinned and installed as `webgpu` is and loaded at a
program's first decode. It reads what a browser reads, JPEG, PNG, WebP, GIF
and AVIF among them, and gives the same texels: turned as the image's EXIF
orientation says, with straight alpha. An image is decoded off the
program's thread, then drawn on a canvas and read back on it. A canvas
keeps each color multiplied by its alpha, as a page's bitmap does, so both
hosts give a color exactly where the image is opaque and round it alike
where it is not: (200, 100, 50) under an alpha of 3 comes back
(170, 85, 85), and under an alpha of 0, black. A 4946 by 3286 JPEG took 127
to 171 ms, about 50 ms of it on the program's thread, and four at once 256
to 265 ms; a 1237 by 822 one took 10 to 16 ms. The package is MIT. The
binary it installs holds Skia, which is BSD-3-Clause, and its bill of
materials lists four MPL-2.0 crates among permissive ones.

Dawn runs in the program's process. Chromium's runs in a GPU process that
each call is sent to. On an RTX 5090, under Vulkan, a chain of 10,000
dependent one-workgroup dispatches, alternating among eight pipelines and
bind groups, measured:

| Per dispatch | Node | Chromium 152 |
| --- | --- | --- |
| Encoding, on the program's thread | 1.4 μs | 0.06 μs |
| Encoding and running | 2.3 μs | 1.9 μs |
| Submitting one and waiting for it | 19 μs | 500–600 μs |

The page only records each call for the GPU process, which encodes in
parallel, so a long batch runs about as fast on either. A program that
waits on the device often, as a training loop that reads its loss does,
waits a thirtieth as long on Node. Chromium coarsens the page's clock to
100 μs, which the last row's range shows.

Node keeps Dawn's guards, as a browser does: validation of every call,
bounds checks on shaders' memory, and zeroed workgroup memory and
resources. Turning the first three off, which Dawn's toggles allow, saved
0.1 μs of the 1.4 that encoding a dispatch takes on the 5090, and a shader
that gathers 268 million words at computed indices took the same 7.84 ms
without bounds checks. The zeroing cannot go: WebGPU promises zeroed
buffers, and a tensor program's params start at zeros, Adam's moments
among them. What Node gains is Dawn in its own process.

An indirect dispatch is the exception. Dawn checks its arguments on the
device with a dispatch it adds before it, and gives that dispatch a new
uniform buffer each time, written at creation through a staging buffer the
host can map. Dawn's Vulkan backend gives every mappable buffer memory of
its own (crbug.com/dawn/849), and making one took about 0.23 ms on the
5090. Submitted one at a time, a validated indirect dispatch took a median
of 0.26 ms of wall time through submission and 0.22 ms more waiting for
completion, against 9 and 11 μs for a direct one; with validation skipped
it took what a direct one does. The wait may be the release of the staging
buffer, but `onSubmittedWorkDone` waits for the device as well, and only a
trace would tell them apart. Chromium takes about the same for a page.

Nothing needs indirect dispatches. A kernel that a count the device
computes sizes runs a fixed number of workgroups, at most 4,096, which
read the count and loop over the work below it, so the work is the
count's (`radix-sort.sld`, `bvh.sld`). That costs the device less than
launching exactly the workgroups the count needs: eight dispatches of a
kernel storing each key took 0.026 ms over 1.65 million keys, and 0.034
ms dispatched indirectly with validation skipped; over 33.5 million keys,
0.637 and 0.821 ms. A few thousand long-lived workgroups beat a workgroup
for each block. So validation costs a training step nothing measurable:
bicycle's 30,000 steps took 857.5 s with it and 857.1 s without.

## Device baseline

Required features: `indirect-first-instance`, `float32-filterable` and
`rg11b10ufloat-renderable`. Used when present: `texture-compression-bc`,
which phones lack, `shader-f16`, which SwiftShader, the tests' adapter,
lacks, `timestamp-query`, for profiling, and `subgroups`, which splat
training's backward pass sums over; `request-device` answers which it got.
Raised limits, as far as the adapter allows: buffer and storage-binding
sizes of 1 GiB, 16384-texel textures, 64 bytes of color attachments per
sample, since a full G-buffer fills the default 32, and 32 KiB of
workgroup memory. Texture
heaps start uncompressed; a later `reset` may choose BC.

## Design choices

- Images are decoded by the host behind `decode-image`, a host operation
  that waits, rather than in `snail-scheme`. It answers nothing for bytes
  the host does not decode.
- `update` only computes: prefetching happens from `draw`.
- Shader sources are S-expression files printed by `generate-library`
  recipes, since a quoted form is a literal only. A shader's structs come
  from `Pod` at run time: `(string-append (declarations shape) shader)`.
