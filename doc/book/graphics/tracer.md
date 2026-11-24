# The path tracer

`(snail shell graphics trace render)` path traces a glTF scene into the
canvas a frame at a time, with one path a pixel by default, filtered by SVGF and
tone-mapped. It is composed of graphics middleware, each a library usable
on its own: a BVH and its ray queries, an environment light, a denoiser.
The [primer](path-tracing.md) gives the physics; this chapter gives the
program. `src/apps/viewer` flies through the user's own scenes with it, or
through Khronos's glTF sample models: **[open the viewer](../play/viewer/)**.

## A frame

| Stage | Library | What it does |
| --- | --- | --- |
| Surfaces | `trace/surface.wgsl.scm` | Rasterizes the first hits into a G-buffer: shading normal, albedo, material, motion, the triangle drawn, and depth. A scene with blended materials also gets the nearest blended surface in front of them, in a second G-buffer, the blended layer. |
| Direct light | `restir`, `trace/restir.wgsl.scm` | Resamples environment directions at each first hit, using its light, the previous frame and a neighboring pixel. |
| Paths | `trace/path.wgsl.scm`, `bvh` | A wavefront of compute kernels, each bounce's rays traced by the BVH's queries, for each layer. |
| Filter | `svgf` | Temporal accumulation, variance, five à-trous levels, then remodulation by albedo and exposure, for each layer. |
| Compose | `trace/compose.wgsl.scm` | Blends the blended layer's light over the first hits', by its alpha. |
| Post | `passes` | Hable's filmic curve, sRGB encoding, and FXAA. |

`make-tracer` takes a `Scene`, an `Environment`, the canvas format and size,
and builds every pipeline and target once; `resize-tracer` remakes the
targets for a new size, and `draw-traced` draws a frame for a camera, its
paths scattering at most as many times as the frame asks, one to
`most-bounces` (eight). A tracer smaller than the canvas still draws into
all of it, since the last pass samples the picture by screen coordinates.
A camera that holds still keeps accumulating: `tracer-frames` counts the
frames since it last moved or the bounces last changed, either of which
starts the history again.

For half a path sample per pixel (spp) per still frame, call
`(draw-sampled-traced gpu tracer canvas camera spread exposure bounces moved (Checkerboard))`.
The first frame, a resize, a replacement scene or environment, a change in
camera or bounce count, and a reported geometry change (`moved`) each trace
every pixel. Successive
still frames alternate the two halves of the checkerboard on both layers.
Three frames from a cold start therefore give each surface pixel two new paths.
`(EveryPixel)` traces the full image on each draw.

A `Tracer` holds a record for each lifetime: a `Kit` of what is made once,
the pipelines and uniforms; a `World` of the scene, its BVH and the
environment; `Targets` of what the canvas's size sets; and `Bindings`,
every bind group over the three, which `bind` alone makes. `resize-tracer`
and `retrace` each replace one record and bind again, so no bind group
names a target or a scene that is gone. The libraries share the few steps
every set of compute kernels repeats, in `(snail shell graphics kernel)`.

## The wavefront

A path is not one long kernel but a sequence of small ones, each its own
pipeline, so each stays simple and keeps its registers few:

```
temporal_reservoirs → primary → [occlude → connect → intersect → shade] × bounces → gather
```

- `temporal_reservoirs` draws fresh light candidates and merges reprojected history.
- `primary` places the [first hit](#first-hits) on its triangle, merges a neighbor's reservoir, emits the selected shadow ray and scatters the BSDF ray.
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

A queue kernel is dispatched over the maximum number of paths for this draw.
On a checkerboard, each row dispatches half its columns, rounded up, and a
lane's column and row parity locate its pixel. Threads past the queue's
actual count return at once. Chromium validates each indirect dispatch,
which takes about half a millisecond of wall time, more than the wasted
threads cost.

The counts and each bounce's bind groups are made for `most-bounces`, and
the wave's uniform is written each frame, so a frame of fewer bounces marks
an earlier one the last and runs only that many.

## First hits

A ray leaves a surface lifted off it by 1/10,000 of its coordinates' size,
toward the side it goes, so it does not meet the surface again. Depth alone
places a first hit less well than that far from the eye: the projection's
near plane is 0.1 units away, and 30 units out Sponza's outer wall came back
a millimetre in front of or behind itself. Rays from behind it met the wall
and darkened it in bands that moved with the camera. So the surface pass
draws three corners a triangle, reading each corner's vertex through the
scene's indices, and writes the triangle it drew; `primary` moves the
depth's point onto that triangle's plane and takes the triangle's normal,
facing the eye, as the geometric one. The G-buffer keeps only the shading
normal, so it is no larger for the triangle.

## Biased ReSTIR direct lighting

A sampled first hit draws four candidate directions on a full frame and two
on a checkerboard frame, all from the environment's importance table. The
RGB contribution of a direction is its radiance times the BSDF, cosine and
the environment's power-heuristic weight. The BSDF ray
that escapes to the environment still supplies the complementary weight.
The scalar target `t` is the luminance of that unshadowed RGB contribution.

A reservoir holds the selected direction and its target, a weight sum `S`
and a count `M`. A fresh draw with proposal density `q` contributes `t / q`
to the sum. Zero-weight draws still count. A draw of weight `w` replaces
the selection with probability `w / S` after the addition. The selected
sample's multiplier is `W = (S / M) / t`, or zero for an empty selection.

The motion vector locates one previous pixel. Its normal must agree with
the current normal (dot product at least 0.9), and the two depths must
agree within 2% in the previous camera's projection. The donor represents
up to 20 times the number of fresh candidates at the receiver. The spatial
step chooses one of the four axial neighbors on a full frame or one of the
four diagonal neighbors on a checkerboard. Each donor belongs to the
completed temporal pass and uses the same surface test in the current
projection. Each accepted donor contributes its represented count `m` and
weight `target_here × W_donor × m`. The biased estimator
divides by the total represented count even when a sample could have
contributed at only some of those surfaces. This can lose energy at surface
boundaries. [Bitterli et al., 2020](https://research.nvidia.com/publication/2020-07_spatiotemporal-reservoir-resampling-real-time-ray-tracing-dynamic-direct)

Only the final direction needs a visibility test. Its shadow ray carries
the receiving surface's RGB contribution times `W` into the usual BVH
query. Each layer owns its final history and both take turns using one
temporal scratch buffer. A sky or uncovered pixel writes empty history.
Resizing or replacing the scene or environment starts a new history.
A pixel skipped by the checkerboard keeps its reservoir and the last radiance
in its layer's slot. `gather` marks that radiance with a negative alpha in the
noisy texture. SVGF carries forward the pixel's illumination, moments and
observation count, and runs its spatial filters at full resolution.

## The blended layer

A glTF material is opaque, masked or blended. The first hits' G-buffer
holds only opaque and masked surfaces, and a masked one is discarded below
its cutoff. A scene with a blended material, whose `Scene` says
`blended`, gets a second G-buffer of the same targets, the blended layer.
Every triangle is drawn again over a copy of the first hits' depth, so
the depth test keeps the nearest blended surface in front of them, with
its alpha in the albedo's. A texel whose alpha is under 1/255 is no
surface and hides nothing.

The layer is lit as the first hits are:

- **Paths.** Its paths run as a second wavefront after theirs, over the
  same queues once the counts are cleared. Its radiance comes after theirs
  in the same buffer, so the bounces need no change, and a pixel the layer
  does not cover makes no path.
- **Filtering.** It is gathered into its own noisy plane and filtered by
  its own SVGF, with its own normals, depth and motion. So each layer's
  history follows its own surface, where a stipple of the two would mix
  them.
- **Composing.** A triangle over the screen then blends the layer's light
  over the first hits', in the light target, through the target's blend
  state: α·T + (1 − α)·O, before tone mapping.

Only the nearest blended surface is in the layer: a blended surface behind
another one is not seen through it. Rays treat blended surfaces as
cutouts, passing through with the odds of their alpha, so shadows and
reflections see them in part.

A scene without a blended material makes none of the layer's targets,
bind groups or filters. `retrace` remakes the targets when a new scene
changes that. On an RTX 5090 at 1280 by 657, AlphaBlendModeTest took 3.3
to 5.4 ms a frame, the same as before the layer within the timing's noise.

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

For an art-directed sky, `make-sky-light` and `update-sky!` take a `Sky`. For outdoor light, `make-atmosphere-light` and `update-atmosphere!` take an `Atmosphere` with a sun direction, horizontal wind displacement in kilometres, and cloud cover from zero to one. Each update refreshes the same GPU resources and their sampling distribution. Release them with `release-sky-light`.

The outdoor sky integrates molecular and aerosol scattering along a ray through a spherical atmosphere. Slant paths through the air and ozone change the colour of the setting sun. A diffuse term approximates higher orders of scattering. A second ray march integrates extinction and in-scattering through a marine cloud layer from 650 to 1,850 metres. Short marches toward the sun give the banks self-shadowing. Overhead density governs how much skylight reaches their undersides. The directional environment represents the view from street level. Buildings share the cloud cover above that reference point. [Atmospheric transport and spherical geometry](https://ebruneton.github.io/precomputed_atmospheric_scattering/atmosphere/functions.glsl.html) · [Real-time volumetric clouds](https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn)

The sky texture contains scattered radiance. Two additional texels hold the solar disc's direction, angular radius and cloud-attenuated irradiance. The sampler chooses between the sky and the disc by their integrated luminance, then samples solid angle inside the chosen region. This keeps the sun round at its apparent diameter of 0.53° even in a small environment map. Camera rays, water reflections and shadow rays see the same light. The outdoor environment also adds distance haze to long camera sightlines. A `PinholeRange` lens takes the vertical field of view in radians and the near and far clip distances in world units. Last Mile sets them to 0.35 metres and 32 kilometres so the Pacific horizon is visible from a bluff.

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

## Moving geometry

Last Mile uses the same surface, path, SVGF and post passes for a moving cast.
A `MovingScene` owns a static prefix of world vertices and one contiguous range
of local vertices per moving object or skinned mesh. `pose-scene!` writes the posed vertices
and their displacement from the previous draw. The surface pass uses that
displacement for motion vectors. Both primary visibility and secondary rays
consume the same world-space triangles. Mesh topology and materials stay fixed.

`make-moving-tracer` keeps the leaf order and binary tree for those triangles.
After a simulation tick, `refit-tracer!` refreshes the leaf boxes, propagates
their bounds and packs them into the original query buffer. Bindings survive
a refit. An application can choose a tone curve at construction with `make-graded-moving-tracer`.
Last Mile uses `Photographic` for a hue-preserving shoulder followed by sRGB encoding.
The viewer can discard this build scratch for static scenes. Last
Mile asks each frame for two bounces, and the final FXAA pass samples
normalized screen coordinates so a small traced image fills a larger browser
canvas. [Last Mile](../games/last-mile.md)

## Skinned animation

Start with a mesh and one joint. A vertex fully weighted to that joint follows its matrix, just as the sedan follows its rigid pose. Add a hinge and let a vertex share two joints. Its position becomes a weighted sum of the two transformed bind positions. A character uses the same operation with up to four influences per vertex.

1. Call `read-rigged-gltf` in `(snail shell graphics gltf animation)`. It reads the buffers once and returns the mesh, its per-vertex influences, a parent-first hierarchy, inverse binds and named clips. A primitive with a skin starts in mesh coordinates. A rigid attachment gets a slot for its own node. Multiple skins can order their joints differently.
2. Use `sample-pose` in `(snail shell graphics animation)` at the desired clip time. Untargeted local transforms keep their authored values. STEP holds a key until the next key. LINEAR interpolates translations and scales and takes the shortest quaternion arc for rotations. `clip-time` wraps or clamps a clock. `blend-poses` crossfades local poses and `blend-branch` restricts a blend to chosen nodes.
3. Call `joint-palette` with the pose and the instance placement. It walks the hierarchy, including non-joint ancestors, and multiplies each joint’s world matrix by its inverse bind. For a prop attached to a hand, resolve its index with `named-node`, call `posed-nodes` once, and compose the prop with that node’s world matrix. Pass the same array to `skin-palette` for deforming the mesh. A joint’s inverse bind belongs only in the skin palette. Instances share the rig and clips and sample their own poses.
4. Give `skin-scene` the fixed topology and vertex influences once. At each draw, `deform-scene!` blends the palette matrices on the GPU, transforms positions, normals and tangents, and records the displacement back to the preceding draw. Refit the BVH after a pose changes. Camera visibility and Monte Carlo shadow queries then use the same triangles. SVGF receives their motion vectors and FXAA runs after tone mapping.

The reader supports floating-point transform keys, unsigned byte or unsigned short joint indices, and floating-point or normalized unsigned integer weights. It reports unsupported cubic samplers, morph-weight channels, sparse accessors and additional vertex influence sets. The mechanical hinge fixture in `tests/programs/data/hinge.gltf` has a non-joint ancestor, reversed node order and mixed weights. [glTF skins and animations](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#skins)

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
is that capability, `FilePicker`: `open-picker` asks the user and returns, a `FilesEvent`
says files were dropped or picked, and each file the user chose is its
path within the choice and an address that `fetch` reads, a `blob:` one
for a file of theirs. `retrace` keeps the tracer's pipelines for the new
scene, and the old scene and light are destroyed. Drag to look, WASD to
fly, Q and E down and up, the wheel for speed, `[` and `]` for exposure.

Keys also set what a frame costs: 1 to 8 how many times its paths bounce,
four at first, and `-` and `=` halve and double the pixels traced, each
side by the square root of two, down to an eighth of each side. The page
says the settings as they change and keeps them in its save for the next
visit. Inside Sponza on an RTX 5090 at 2000 by 1217, four bounces at full
resolution took 18.9 ms a frame, and two at 50% resolution 5.3 ms.

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
`&eye=x,y,z,yaw,pitch` for the camera. Add `?spp=0.5` to the viewer URL
to enable checkerboard sampling while the view is still. If the URL already
has a query, append `&spp=0.5`.

Files that cannot be shown leave the view as it was, and the page says why:
a `.gltf` chosen without the files it names, an address that answers 404, a
file shorter than the scene says, an image the browser does not decode, a
scene whose geometry is compressed by Draco or meshopt, an HDR file that
is not one. Reading a
scene stops through a prompt of `(snail shell graphics gltf)`: `unreadable`
stops it with a reason, anywhere from the JSON to the last image, and
`attempt-reading` turns the reading into a `Result`. Nothing refused is
left on the device, by the order of the work rather than by cleaning up:
the viewer reads the HDR file (`read-hdr`) before it loads the scene, and
`load-scene` loads the layers, the one step on the device that can refuse,
before anything else of the scene.

## Water surfaces

A glTF material can opt into the tracer’s water shading with `"extras": { "snailWater": true }`. Use a nonmetallic material and a dark linear base colour for light returned by the water body. The dielectric interface reflects about 2% of the light at normal incidence and approaches full reflection at grazing angles. A ray can reflect geometry as well as the sky.

Set `Camera3D.scene-time` in seconds to move wave trains in world metres. Rasterized first hits and traced secondary hits share their normals. Each wave is filtered along its direction across the pixel footprint. Unresolved waves contribute their slope variance to the material roughness. The mapped surface supplies depth, visibility and ray origins. The model represents deep water with a fixed shoreline and a bulk colour.

## Performance

On a matte white wall under a uniform environment, first-hit ReSTIR
reduced the variance of unfiltered radiance from 0.0864 to 0.0491. Mean
radiance was 0.984 before and 0.983 after. This measured 256 one-bounce
frames after 16 warm-up frames, over the center 32 by 32 pixels of a
96 by 96 image.

On an RTX 5090 through Dawn, a 768 by 512 scene with two boxes on a ground
plane took 0.264 ms for the four-bounce wavefront before ReSTIR, 0.390 ms
with full-rate ReSTIR and 0.263 ms with the still-frame checkerboard.
These are median GPU pass times over 405 frames per mode, after 15 warm-up
frames in each of three runs. Each reservoir entry occupies 48 bytes,
including the depth and normal used for reuse.

### Fewer path samples

The two boxes on a ground plane were lit by a sky with a sun and rendered
at 384 by 256 from empty history, with four bounces. The reference averaged
4,096 unfiltered samples from the original tracer using a separate range of
random seeds. Error is linear RGB root-mean-square error (RMSE) on the 54,781 surface pixels
across 32 cold starts. Each unfiltered average counts newly traced paths.
The SVGF column measures the filtered light before tone mapping.

| Tracer | Frames | Path spp | Raw RMSE | SVGF RMSE | GPU time to image |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original | 8 | 8 | 0.1811 | 0.02085 | 2.312 ms |
| ReSTIR, full rate | 2 | 2 | 0.1601 | 0.01580 | 0.846 ms |
| ReSTIR, checkerboard | 3 | 2 | 0.1620 | 0.01629 | 1.094 ms |
| ReSTIR, checkerboard | 8 | 4.5 average | 0.1138 | 0.01662 | 2.401 ms |

GPU time sums the six pass durations from the G-buffer through FXAA
over the indicated frames. The table gives the median of 93 cold starts
on the RTX 5090 through Dawn, excluding scene setup. At 768 by 512, the
median GPU pass time per still frame was 0.420 ms for the original tracer,
0.547 ms for full-rate ReSTIR and 0.422 ms for the checkerboard across
405 frames per mode.

On the uniform white wall at 384 by 256 with one
bounce, the same two-spp checkerboard budget gave 0.00646 filtered RMSE.
The original tracer at eight spp reached 0.00541.

### Browser scenes

Before first-hit ReSTIR, the following frame times were measured on an
RTX 5090 through Chromium on Vulkan at 1280 by 657.

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
