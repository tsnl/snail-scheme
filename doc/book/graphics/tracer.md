# The path tracer

`(snail shell graphics trace render)` path traces a glTF scene into the
canvas a frame at a time, with one path a pixel, filtered by SVGF and
tone-mapped. It is composed of graphics middleware, each a library usable
on its own: a BVH and its ray queries, an environment light, a denoiser.
The [primer](path-tracing.md) gives the physics; this chapter gives the
program. `src/apps/viewer` flies through the user's own scenes with it, or
through Khronos's glTF sample models: **[open the viewer](../play/viewer/)**.

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

`(snail shell graphics gltf)` reads a scene's file, a `.gltf` file's JSON
or a `.glb` file, into the meshes, materials, images and buffers it names.
Each buffer and image has a `Source`: a file named by a URI relative to
the scene's, bytes the scene holds (a base64 `data:` URI or a `.glb`
file's binary chunk), or for an image a range of a buffer. A buffer also
has the length the scene reads of it and where it starts once the buffers
are laid end to end, which is where the device gets it.
`load-scene` of `(snail shell graphics trace scene)` takes a function that
reads several paths at once, so a page fetches every buffer and image
together (`fetch-all-bytes`).
Only the files the sources name are read; the rest come with the scene's
file. It unpacks the buffers on the device into one vertex and one index buffer,
draws each image into a layer of one array texture with its mipmaps, and
scales a scene less than a unit across up to one.

## The viewer

```sh
./snail-scheme build --target browser src/apps/viewer/main.scm
```

The viewer ships no scene. It shows the files its user chooses: a `.glb`,
or a `.gltf` with the files it names, and an `.hdr` file to light it;
without one, a drawn sky and sun light it. Files come dropped on the page,
a folder at a time or several files, or through the browser's pickers, O
for files and Shift+O for a folder, which the File System Access API's
`showDirectoryPicker` opens where the browser has it. `(snail shell files)`
is that effect: `open-picker` asks the user and returns, a `FilesEvent`
says files were dropped or picked, and each file the user chose is its
path within the choice and an address that `fetch` reads, a `blob:` one
for a file of theirs. `retrace` keeps the tracer's pipelines for the new
scene, and the old scene and light are destroyed. Drag to look, WASD to
fly, Q and E down and up, the wheel for speed, `[` and `]` for exposure.

A link dropped on the page is a file too, one whose path is its address,
and a scene chosen by address names its files relative to it, so the
browser fetches them from where the scene is published
(`fetch-all-bytes`, every file of a scene together). The page's samples
are such links: Khronos's sample models, at a pinned commit of
[glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets),
and four of [Poly Haven](https://polyhaven.com/hdris)'s environments.
Clicking one drops it on the page. So the site publishes none of them,
and a model's license is its publisher's to state. The page's query
chooses the same way: `?model=ADDRESS&env=ADDRESS`, each an address
`fetch` reads, such as a path on the page's server, and
`&eye=x,y,z,yaw,pitch` for the camera.

Files that cannot be shown leave the view as it was, and the page says why:
a `.gltf` chosen without the files it names, an address that answers 404, a
file shorter than the scene says, an image the browser does not decode, a
scene whose geometry is compressed by Draco or meshopt, an HDR file that
is not one. Reading a
scene performs `reading`, of `(snail shell graphics gltf)`: `unreadable`
stops it with a reason, anywhere from the JSON to the last image, and
`attempt-reading` turns the reading into a `Result`. Nothing refused is
left on the device, by the order of the work rather than by cleaning up:
the viewer reads the HDR file (`read-hdr`) before it loads the scene, and
`load-scene` loads the layers, the one step on the device that can refuse,
before anything else of the scene.

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

All 151 of Khronos's sample models with a glTF variant load and render.
Fetched from GitHub by the page's sample links, FlightHelmet was drawn 3.9
s after its link was clicked and Sponza 7.3 s.
