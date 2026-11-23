# Path tracing

glTF scenes path traced on the GPU, a frame at a time: first hits
rasterized into a G-buffer, the bounces after them traced through a BVH by
a wavefront of kernels, lit by an environment, and denoised. `src/apps/viewer`
flies through a scene this way. The [path tracing primer](../graphics/path-tracing.md)
explains the physics, and [the path tracer](../graphics/tracer.md) how the
pieces run and what they cost.

## `(snail shell graphics bvh)`

Ray queries, which WebGPU lacks: a bounding volume hierarchy over any
`Triangles`, and kernels that trace queues of rays through it. `build-bvh`
builds it once, in one compute pass: Morton codes of the triangles'
centroids, a bitonic sort of them, the tree from the sorted codes, and its
boxes refit from the leaves up, then packed so each node holds both its
children's boxes. `make-ray-kernels` makes the queries, `intersect` for the
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

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/trace/scene.sld)

## `(snail shell graphics svgf)`

A denoiser for one path a pixel: spatiotemporal variance-guided filtering
(Schied et al., 2017). `filter-svgf` reads a frame's noisy radiance and the
G-buffer planes it was traced from, keeps a history across frames, and
writes the filtered light, scaled by an exposure, into a plane the program
gives it, such as a `Post`'s. A frame is two compute passes: temporal
accumulation, variance and the first à-trous level, then four more levels;
`resize-svgf` follows the canvas.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/svgf.sld)

## `(snail shell graphics trace render)`

A scene path traced to the canvas, composed of the libraries above: the
first hits rasterized into a G-buffer, a wavefront of kernels for the
bounces, each bounce's rays traced by `bvh`'s queries and lit by an
`environment`, then `svgf` and `(snail shell graphics passes)`'s tone
mapping and FXAA. A scene with blended materials also gets a blended
layer: the nearest blended surface in front of the first hits, traced and
filtered on its own, then blended over them by its alpha
([the blended layer](../graphics/tracer.md#the-blended-layer)). `make-tracer` makes a `Tracer` once for a scene and the
canvas, `resize-tracer` follows the canvas, `retrace` gives it another
scene and environment with the same pipelines and targets, and
`draw-traced` draws a frame; `tracer-frames` counts the frames since the
camera last moved ([a frame](../graphics/tracer.md#a-frame)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/trace/render.sld)
