# The path tracer

`(snail shell graphics trace render)` path traces a glTF scene into the
canvas a frame at a time, with one path a pixel, filtered by SVGF and
tone-mapped. It is composed of graphics middleware, each a library usable
on its own: a BVH and its ray queries, an environment light, a denoiser.
The [primer](path-tracing.md) gives the physics; this chapter gives the
program. `src/apps/viewer` flies through Khronos's glTF sample models
with it, or through the user's own: **[open the viewer](../play/viewer/)**.

## A frame

| Stage | Library | What it does |
| --- | --- | --- |
| Surfaces | `trace/surface.wgsl.scm` | Rasterizes the first hits into a G-buffer: normal, albedo, material, motion and depth. |
| Paths | `trace/path.wgsl.scm`, `bvh` | A wavefront of compute kernels, each bounce's rays traced by the BVH's queries. |
| Filter | `svgf` | Temporal accumulation, variance, five à-trous levels, then remodulation by albedo and exposure. |
| Post | `passes` | Hable's filmic curve, sRGB encoding, and FXAA. |

`make-tracer` takes a `Scene`, an `Environment`, the canvas format and size,
and builds every pipeline and target once; `resize-tracer` remakes the
targets for a new canvas size, and `draw-traced` draws a frame for a camera.
A camera that holds still keeps accumulating: `tracer-frames` counts the
frames since it last moved.

## The wavefront

A path is not one long kernel but a sequence of small ones, each its own
pipeline, so each stays simple and keeps its registers few:

```
primary → [occlude → connect → intersect → shade] × 4 bounces → gather
```

- `primary` turns each pixel's G-buffer surface into a ray.
- `shade` samples the surface's BSDF for the next bounce and the
  environment for a shadow ray, appending each to its queue.
- `occlude` and `intersect` are the BVH's queries over a queue.
- `connect` adds the light of each shadow ray that reached the sky,
  weighted by multiple importance sampling against the BSDF ray that
  might have found it.
- `gather` writes each pixel's radiance for SVGF.

Two ray queues alternate between bounces, with one shadow queue. Each holds
80-byte `Ray` records (origin and limit, direction and random seed, the hit,
the throughput and the scatter density), one record so the kernels stay
under WebGPU's default eight storage buffers a stage. Rays append with an
atomic count kept per bounce, 256 bytes apart. Russian roulette may end a
path after its third bounce.

Every queue kernel is dispatched over the queue's capacity, and threads
past its count return at once. Chromium validates each indirect dispatch at
about half a millisecond, which made indirect dispatch slower than the
wasted threads.

## The BVH and ray queries

`(snail shell graphics bvh)` builds a linear BVH on the device in one
compute pass: Morton codes of the triangles' centroids, a bitonic sort of
them, Karras's tree over the sorted codes, and boxes refit from the leaves
up. It takes any triangles: a positions buffer read
as 32-bit words at a stride and an offset, and an index buffer. Each node
holds both its children's boxes, and a child pointer with the high bit set
names a triangle. Traversal visits the nearer child first, with a 64-entry
stack and a cap of 8192 steps.

`make-ray-kernels` builds `intersect` (the nearest hit) and `occlude` (any
hit) for a caller's `cutout(triangle, barycentric, seed)`, the WGSL that
says whether a hit counts; the tracer's discards alpha-masked texels.
`trace-rays` runs a query over a queue.

## Environment light

`(snail shell graphics environment)` makes an `Environment` from a Radiance
HDR file, decoded on the device a row a thread and averaged down to at most
4096 texels wide, or from a drawn `Sky` with a sun. Either way it then
builds a table that samples directions in proportion to their light: each
row's cumulative distribution, weighted by sin θ for the solid angle it
spans, and the rows' distribution in the last column.
`environment-light.wgsl.scm` gives kernels the radiance of a direction, the
density it is sampled with, and a sampled direction.

## Scenes

`(snail shell graphics gltf)` reads a glTF file's JSON into the meshes,
materials, images and buffers it names. Each buffer and image has a
`Source`: a file named by a URI relative to the scene's, a base64 `data:`
URI, the binary chunk of a `.glb` file, whose JSON `glb-chunks` finds, or
for an image a range of a buffer.
`load-scene` of `(snail shell graphics trace scene)` takes a function that
reads several paths at once, so a page fetches every buffer and image
together (`read-resources`, [linked files](../snail-scheme/types.md#linked-files)).
Only the files the sources name are read; the rest come with the scene's
file. It unpacks the buffers on the device into one vertex and one index buffer,
draws each image into a layer of one array texture with its mipmaps, and
scales a scene less than a unit across up to one.

## The viewer and the samples

```sh
scripts/fetch-khronos-samples            # every sample model and environment
./snail-scheme build --target browser src/apps/viewer/main.scm
```

`(khronos samples)` is a generated library that links each fetched file:
`(sample-model "Sponza")` gives a model's files as `Resource`s and
`(sample-environment "helipad")` an HDR file. A build links all 1.4 GB, and
a page fetches only what it shows: Sponza reads 67 of 999 objects. The
files themselves stay outside version control, under `build/`, as
`src/khronos/ATTRIBUTION.md` explains; without them the library lists none.

The page's query chooses the scene: `?model=Sponza&env=helipad`, with
`env=sky` or none for the drawn sky, and `&eye=x,y,z,yaw,pitch` for the
camera. `models.html` links every model and credits its authors. Drag to
look, WASD to fly, Q and E down and up, the wheel for speed, `[` and `]`
for exposure.

The user's own files replace the scene: a `.glb`, or a `.gltf` with the
files it names, and an `.hdr` file to light it. They come dropped on the
page, a folder at a time or several files, or through the browser's
pickers, O for files and Shift+O for a folder, which the File System
Access API's `showDirectoryPicker` opens where the browser has it.
`(snail shell files)` is that effect: `open-picker` asks the user and
returns, a `FilesEvent` says files were dropped or picked, and each file
the user chose is its path within the choice and a `blob:` address that
`fetch` reads. `retrace` keeps the tracer's pipelines for the new scene, and the
old scene and light are destroyed.

The site's viewer links seven CC0 and CC-BY models (`make viewer-samples`)
and no sample environments, whose licenses mostly forbid publishing them;
it opens on FlightHelmet in the drawn sky.

## Performance

On an RTX 5090 through Chromium on Vulkan, at 1280 by 657, a frame takes:

| Scene | Frame |
| --- | --- |
| Sponza, inside, sky | 8.7 ms |
| Sponza, inside, footprint_court | 8.9 ms |
| Sponza, from outside | 6.3 ms |
| DamagedHelmet, helipad | 3.7 ms |
| FlightHelmet, footprint_court | 3.7 ms |
| SciFiHelmet, sky | 3.2 ms |

All 151 sample models with a glTF variant load and render. Over a network
40 ms away, Sponza's page is ready in 1.9 s.
