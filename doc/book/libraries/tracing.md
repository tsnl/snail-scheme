# Path tracing

glTF scenes path traced on the GPU, a frame at a time: first hits
rasterized into a G-buffer, the bounces after them traced through a BVH by
a wavefront of kernels, lit by an environment, and denoised. `src/apps/viewer`
flies through a scene this way. The [path tracing primer](../graphics/path-tracing.md)
explains the physics, and [the path tracer](../graphics/tracer.md) how the
pieces run and what they cost.

## `(snail shell graphics bvh)`

Ray queries, which WebGPU lacks: a two-level bounding volume hierarchy over
any `Triangles`, and kernels that trace queues of rays through it. A bottom
level is a tree over the still triangles or one moving object's span, and
the top level a tree over their roots. `make-bvh-builder` makes the
builder's kernels once. `build-bvh` builds every tree on the device, top
down by the surface area heuristic, a level a dispatch. `refit-bvh!`
refits the moving objects' trees after their vertices change and rebuilds
the top level. `make-ray-kernels` makes the queries, `intersect` for the
nearest hit and `occlude` for any, with the program's `cutout` test, and
`trace-rays` runs one over a queue.

A queue is a buffer of 80-byte rays and its count, so a kernel appends to it
with atomics. A query is dispatched over the queue's capacity, and the
invocations past the count return: an indirect dispatch would launch only
what the count needs, but with Dawn's validation each takes about half a
millisecond of wall time, more than the idle workgroups cost
([the BVH and ray queries](../graphics/tracer.md#the-bvh-and-ray-queries)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/bvh.sld)

## `(snail shell graphics environment)`

Light from all around a scene: an equirectangular `Environment`, made on the
device from a Radiance HDR file (`read-hdr`, `hdr-environment`), the format
of Khronos's glTF sample environments, or drawn from a `Sky` with a sun
(`sky-environment`), with the table that samples it by its light. A path
tracer binds `environment-group` to look it up and to sample it.

`read-hdr` reads a file's header and the start of each row, which is all
that can be wrong with one, so a program checks its file before it puts
anything on the device; `hdr-environment` then decodes the pixels there, a
row a thread, and averages them down to the width asked for.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/environment.sld)

## `(snail shell graphics restir)`

`reservoir-shader` supplies the WGSL types and operations for weighted
reservoir sampling. `LightSample` holds a direction and its scalar target.
`Reservoir` exposes the sample, weight sum, represented proposal count,
one-based emitter slot (zero for a sky direction), and two packed 16-bit
square coordinates. Reflecting the square across its diagonal yields the
uniform barycentric point on that triangle. `reservoir_draw` adds a draw
with its proposal density and returns whether it was selected.
`reservoir_merge` takes a donor, its target at the receiver and
the count it contributes. Each accepts a uniform random draw for selection.
`reservoir_weight` derives the final shading multiplier.

`reservoir-buffer` allocates one 64-byte `SurfaceReservoir` per pixel.
The 32-byte reservoir is followed by the octahedral normal, triangle ID,
clip depth and a 16-byte `VisibilityHistory`. Its `recent` and `previous`
entries each hold an i32 source key and f32 visibility estimate. Key zero is
empty. Positive keys name mesh emitter slots. Sky regions use −1 through −6
and the analytic solar disc uses −7. Punctual keys are −7 minus the one-based
lamp ID. Moving slots come first, followed by static lights in scene order.
All grid copies of a static fixture share its ID. Directly uploaded grid
entries with zero in `intensity.w` use their texel address. An application that
reorders moving lights gives the new occupant that slot's recent estimate.
`observe_visibility` takes a history, a nonzero key, a shadow test result
and an update gain, and returns the updated history.

`(light-guiding-rates settings paths-per-pixel)` exposes the four
f32 fields uploaded with each wave. They are the exploration probability,
visibility update gain, minimum visibility used in selection, and maximum
temporal donor count in multiples of the fresh count. The settings are a
`LightGuiding` with `exploration-floor` in [0, 1] and positive integer
`recovery-frames`. Pass them to `Tracer-guiding-set` on an existing tracer
and use the returned tracer for subsequent draws. [Learning which lights reach a surface](../graphics/tracer.md#learning-which-lights-reach-a-surface)

## `(snail shell graphics gltf)`

A glTF 2.0 scene, a `.gltf` file's JSON or a `.glb` file, read by `read-gltf`
into what drawing and tracing it need: its buffers and images, each
primitive's accessors as byte offsets into the buffers laid end to end, its
materials, and each primitive `Placed` by the default scene's node
hierarchy. The buffers' bytes are not read here: they go to the device
whole, and a compute pass unpacks each accessor. `gltf-bounds` is the
scene's box.

It reads triangle primitives with positions, normals, a first set of texture coordinates and tangents, indices of any width, metallic-roughness materials with their textures and alpha modes, and `KHR_materials_emissive_strength`. `gltf-transformed` composes a column-major instance transform with each placed primitive. Unsupported sparse accessors and Draco or meshopt compression are reported through `attempt-reading`. [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/gltf.sld)

## Skinned animation

`(snail shell graphics gltf animation)` reads the hierarchy, skins, vertex influences and animation clips. `(snail shell graphics animation)` samples and blends the local transforms. `posed-nodes` evaluates the hierarchy once for an instance. A rigid prop follows the world transform of its named node. `skin-palette` applies inverse binds to those same world transforms for mesh deformation. [Skinning and the tracer](../graphics/tracer.md#skinned-animation) · [Animation](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/animation.sld) · [glTF animation reader](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/gltf/animation.sld)

## `(snail shell graphics trace scene)`

A glTF scene on the device, loaded once by `load-scene`: every triangle in
the world in one vertex and one index buffer, unpacked from the scene's
buffers by a compute pass; the materials in one storage buffer; and every
image in one layer of one texture array with its mips, since WebGPU binds
no unbounded table of textures. A layer is the same size whatever the
image's, and a material names its textures by layer. Rasterizing and
tracing read the same buffers, so what is drawn is what rays hit. A
scene's `blended` says whether any material is blended, so that the
tracer makes its blended layer only for a scene that has one.

`Scene.emitters` holds an `EmitterTable` built during upload. Its
`triangles` plane contains sorted scene triangle IDs as `r32uint`,
padded with 0xffffffff. Its `distribution` plane holds emitted RGB and
inclusive row weights as `rgba32float`. An extra column holds the cumulative
weight of the rows. The tracing shaders read these planes at scene bindings
6 and 7. Both planes support texture readback. Sampling weights use the upload pose. A reused point reads the
current vertex buffer. `make-emitter-table` takes sorted, distinct triangle
IDs and the unpacked vertex, index and material buffers. A scene made with
`Scene-emitters-set` borrows the original geometry, images and sampler.
Release the owning scene once and release a separately allocated replacement
table with `release-emitter-table`.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/trace/scene.sld)

## `(snail shell graphics svgf)`

A denoiser for one path a pixel: spatiotemporal variance-guided filtering
(Schied et al., 2017). `filter-svgf` reads a frame's noisy radiance and the
G-buffer planes it was traced from, keeps a history across frames, and
writes the filtered light, scaled by an exposure, into a plane the program
gives it, such as a `Post`'s. A frame is two compute passes: temporal
accumulation, variance and the first à-trous level, then four more levels;
`resize-svgf` follows the canvas. Its planes are 32-bit floats: a still
camera's history is a running average, which a frame moves by as little as
1/4096, a step half floats round away.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/svgf.sld)

## `(snail shell graphics trace render)`

A scene path traced to the canvas, composed of the libraries above: the
first hits rasterized into a G-buffer, a wavefront of kernels for the
bounces, each bounce's rays traced by `bvh`'s queries and lit by an
`environment`, then `svgf` and `(snail shell graphics passes)`'s tone
mapping and FXAA. A scene with blended materials also gets a blended
layer: the nearest blended surface in front of the first hits, traced and
filtered on its own, then blended over them by its alpha
([the blended layer](../graphics/tracer.md#the-blended-layer)). `make-tracer` makes a `Tracer` once for a scene, the
canvas and a tone curve, `resize-tracer` follows the canvas,
`refit-tracer!` follows a moving scene's objects, `build-scene-bvh` builds
a scene's BVH ahead of the frame that changes to it, for `retrace-built`, `retrace` gives it another
scene and environment with the same pipelines and targets, and
`draw-traced` draws a frame, its paths bouncing as many times as it asks,
up to `most-bounces`. Its final argument is a `TraceSettings` record with
`display-width` and `display-height`, a path a pixel. Both sizes use
Halton-jittered first hits, SVGF and the stable display resolve.
`encode-trace-observation` takes a caller-owned command encoder, tracer,
camera, pixel spread, bounce depth and random seed. It writes the G-buffer,
per-layer radiance and noisy targets for one fresh full-resolution sample.
The caller can encode reconstruction or a readback next, then submit.
Submit before writing the next observation into the same kit. The caller
supplies the observation camera, including any chosen subpixel offset.
Independent observations leave the interactive history intact. `(snail shell graphics still)` provides
`read-traced-radiance` and `trace-reference` for the [capture format](../graphics/tracer.md#capture-reconstruction-inputs-and-a-reference).
`tracer-frames` counts the frames since the camera last moved or the bounces
changed. [A frame](../graphics/tracer.md#a-frame)

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/trace/render.sld)
