# The path tracer

`(snail shell graphics trace render)` path traces a glTF scene into the
canvas a frame at a time. SVGF filters the light before tone mapping.
It is composed of graphics middleware, each a library usable
on its own: a BVH and its ray queries, an environment light, a denoiser.
The [primer](path-tracing.md) gives the physics; this chapter gives the
program. `src/apps/viewer` flies through the user's own scenes with it, or
through Khronos's glTF sample models: **[open the viewer](../play/viewer/)**.

## A frame

| Stage | Library | What it does |
| --- | --- | --- |
| Surfaces | `trace/surface.wgsl.scm` | Rasterizes the first hits into a G-buffer: shading normal, albedo, material, motion, the triangle drawn, and depth. A scene with blended materials also gets the nearest blended surface in front of them, in a second G-buffer, the blended layer. |
| Direct light | `restir`, `trace/restir.wgsl.scm` | Resamples sky directions and points on emissive triangles at each first hit, with candidates from this pixel, the previous frame and a neighbor. |
| Paths | `trace/path.wgsl.scm`, `bvh` | A wavefront of compute kernels, each bounce's rays traced by the BVH's queries, for each layer. |
| Filter | `svgf` | Temporal accumulation, variance, five à-trous levels, then remodulation by albedo and exposure, for each layer. |
| Compose | `trace/compose.wgsl.scm` | Blends the blended layer's light over the first hits', by its alpha. |
| Display | `upscale`, `passes` | Reconstruct on the stable display grid, then tone map, encode sRGB and apply FXAA. |

`resize-tracer` sets the internal render grid. Every draw traces every internal
pixel. Pass the dimensions of the output view and the number of paths per
pixel to the same entry point at every render scale.

```scheme
(draw-traced gpu tracer canvas camera spread exposure bounces moved
  (new TraceSettings (display-width width) (display-height height) (samples 1)))
```

Choose one or two paths per pixel and one to eight bounces. Report geometry
or lighting motion with `moved`. The tracer compares the unjittered cameras
to detect camera motion. `tracer-frames` counts still frames since the
last movement or history reset.

A `Tracer` holds a record for each lifetime: a `Kit` of what is made once,
the pipelines and uniforms; a `World` of the scene, its BVH and the
environment; `Targets` of what the canvas's size sets; and `Bindings`,
every bind group over the three, which `bind` alone makes. `resize-tracer`
and `retrace` each replace one record and bind again, so no bind group
names a target or a scene that is gone. The libraries share the few steps
every set of compute kernels repeats, in `(snail shell graphics kernel)`.

### Temporal reconstruction

Each frame offsets the camera by the next point of a Halton sequence in
bases 2 and 3. The sequence starts at index one, with half a pixel
subtracted from each coordinate. The first two offsets are (0, −1/6) and
(−1/4, 1/6) in internal pixels. Both paths at two spp share that first
hit, trace separate light and BSDF draws, and contribute to a mean before
SVGF. Both update visibility. Only the first carries a reservoir into
the next frame. [Halton sampling in *Physically Based Rendering*](https://pbr-book.org/4ed/Sampling_and_Reconstruction/Halton_Sampler)

The per-layer radiance buffer holds summed RGB with the observation count
in alpha. `read-traced-radiance` returns these accumulator bytes. `gather`
divides RGB by the requested path count when writing the noisy texture for SVGF.

SVGF uses the motion between the two jittered G-buffers to find past
observations of the same surface. The display resolve runs at native
size as well as at larger output sizes. In a stationary view it averages
linear HDR at each display pixel. Its history grows to 16 frames, after
which each new observation has weight 1/16. At a silhouette, samples can
legitimately see different surfaces within that pixel. During motion,
the resolve removes the change in jitter from the G-buffer motion vector.
Each of its four display-history taps must match the triangle and previous
projected depth. Moving sky and blended surfaces use current samples.
Tone mapping and FXAA run at the output size.

Camera or reported scene motion limits temporal ReSTIR to two batches of
old candidates, or one above 1.5 pixels of motion. Moving SVGF keeps up
to four observations and gives the current one at least 40% weight.
Use `discard-trace-history` for a camera cut. A changed sky, scene, bounce
depth or render grid starts fresh history. Changing only the display
size or exposure starts a new display history and preserves render-grid
history.

## The wavefront

A path is not one long kernel but a sequence of small ones, each its own
pipeline, so each stays simple and keeps its registers few:

```
temporal_reservoirs → primary → [occlude → connect → intersect → shade] × bounces → gather
```

- `temporal_reservoirs` draws fresh light candidates and merges reprojected history.
- `primary` places the [first hit](#first-hits) on its triangle, merges a neighbor's reservoir, emits the selected shadow ray and scatters the BSDF ray.
- `shade` samples the surface's BSDF for the next bounce and direct
  lighting for a shadow ray, appending each to its queue.
- `occlude` and `intersect` are the BVH's queries over a queue.
- `connect` adds the selected light's weighted contribution when the
  shadow segment is clear. It records the outcome of the first hit's shadow
  test in the owning layer's history.
- `gather` writes each pixel's radiance for SVGF.

Two ray queues alternate between bounces, with one shadow queue. Each holds
80-byte `Ray` records (origin and limit, direction and random seed, the hit,
the throughput and the scatter density), one record so the kernels stay
under WebGPU's default eight storage buffers a stage. Rays append with an
atomic count kept per bounce, 256 bytes apart. Russian roulette may end a
path after its third bounce.

A queue kernel is dispatched over the maximum number of paths for this draw.
Each layer dispatches one lane per internal pixel. Threads past the actual
queue count return at once. Chromium validates each indirect dispatch,
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

Each path draws four fresh candidates at its first hit. When both the sky and mesh emit, each candidate has
equal odds of coming from either family. A single emitting family gets all
the draws. The sky sampler chooses a direction from its importance table
and solar disc. The mesh sampler chooses a triangle in proportion to its
initial world-space area times its emitted luminance, then a uniform point
on it. Opaque triangles with constant emission are eligible. Textured,
masked and blended emitters still contribute when a path hits them.

Consider a patch of area `dA` on a triangle of current area `A`. If the
sampler chooses that triangle with probability `p` including the family
choice, the chance of landing in the patch is `p × dA / A`. The area
density is therefore `q = p / A`. In the shader the sampling domain is the
triangle with unit mass, so `q = p` and the RGB integrand contains
`J = A × abs(cos at the light) / distance²`. This puts it in the same
units as the proposal and preserves the point when the light moves or
changes area. The sky uses solid angle directly.

The scalar target `t` is the luminance of the unshadowed RGB contribution
times the receiver's estimate of visibility. The RGB includes emitted
radiance, the receiver's BSDF and cosine, the change of measure above, and
the power-heuristic weight for light sampling. A BSDF ray that hits the
emitter or escapes to the sky supplies
the complementary weight. A camera looking directly at the sign sees its
full emitted radiance.

A reservoir holds the selected direction and its target, a weight sum `S`,
a count `M`, and the identity and coordinates of a selected emitter. A
fresh draw with proposal density `q` contributes `t / q`
to the sum. Zero-weight draws still count. A draw of weight `w` replaces
the selection with probability `w / S` after the addition. The selected
sample's multiplier is `W = (S / M) / t`, or zero for an empty selection.

The proposal and the replacement draw answer different questions. A light
arrives at rate `q`, so giving each arrival weight `t / q` makes its expected
weight proportional to `t`. After seeing the stream, candidate `i` has
selection probability `w_i / S`. Every later replacement multiplied its
survival odds by the old sum divided by the new sum. Those factors telescope.
With equal weights the next candidate replaces the previous selection with
probability `1 / M`, the ordinary unknown-length reservoir rule.

The motion vector locates one previous pixel. Its normal must agree with
the current normal (dot product at least 0.9), and the two depths must
agree within 2% in the previous camera's projection. The surface pass projects the previous pose of the same triangle and carries its clip-space depth in the emission target’s alpha channel. Both ReSTIR and SVGF check the temporal donor’s triangle identity and compare against that depth when geometry moves. The donor represents
up to 20 times the number of fresh candidates at the receiver. The spatial
step chooses one of the four axial neighbors. Each donor belongs to the
completed temporal pass and uses the same surface test in the current
projection. Each accepted donor contributes its represented count `m` and
weight `target_here × W_donor × m`. The biased estimator
divides by the total represented count even when a sample could have
contributed at only some of those surfaces. This can lose energy at surface
boundaries. [Bitterli et al., 2020](https://research.nvidia.com/publication/2020-07_spatiotemporal-reservoir-resampling-real-time-ray-tracing-dynamic-direct)

Only the final direction needs a visibility test. Its shadow ray carries
the receiving surface's RGB contribution with its sampling correction into
the BVH query. Each layer owns its final history and both take turns using one
temporal scratch buffer. A sky or uncovered pixel writes empty history.
A sky bake increments the environment revision. The next draw starts every pixel with fresh proposals. A direction on last minute’s dim sky can now fall inside the bright solar disc, so its old selection weight belongs to a different proposal distribution. Resizing or replacing the scene or environment also starts a new history.

`upload-lit-scene` takes finite-range punctual lights and capacity for moving ones. A ground-plane grid lists static lights whose influence overlaps each cell. Vehicles update a short list of moving lights with `update-moving-lights!`. The punctual lights compete with the weighted sky or mesh estimate for one shadow ray. A finite ray runs from the offset receiver to the selected light. Later bounces use one fresh sky or mesh candidate and the same visibility step. Last Mile's storefront strips illuminate the shop and pavement from their actual triangles.

The GPU regression lights a white wall with a two-triangle rectangle against
a black sky. Numerical integration at its center gives 0.3000 linear
radiance. Across its 9×9 near-constant wall patch, direct sampling measured
0.2981 over 12 frames and BSDF-only sampling measured 0.2980 over 24.
Raw sample variances were 0.0369 and 0.2151 respectively. Moving the blocker
behind the sign preserves the light. Moving it between the wall and sign
extinguishes it. A separate pose test moves the sign across a stationary
receiver while reusing its reservoir.

### Learning which lights reach a surface

Each first hit remembers the two distinct sources its shadow rays most
recently tested. A new source starts with a visibility estimate of ½. A
shadow observation moves the estimate toward one for a clear ray or zero
for a blocked ray. A source can be one emissive triangle, a punctual
light, the analytic solar disc, or one of six sky regions. Points on a
partly covered triangle can give different answers.

The estimate scales the target for fresh candidates, reused candidates at
the receiver, and the final choice among punctual lights and the ReSTIR
sample. Each selection divides out its own priority when weighting the RGB.
An interior surface can therefore spend more rays on a dim lamp it can see.
A fresh shadow test on the winning direction determines its contribution.

A fraction of shaded first hits scores its candidates by unshadowed energy
to explore. Both kinds of selection update the receiver from the ray they
actually traced. A surface
that fails reprojection starts with empty visibility history. A spatial
neighbor can suggest a light sample, while visibility estimates always
belong to the receiver. Independent reference samples use neutral priorities.

Set the minimum exploration fraction and the recovery target in displayed
frames on the tracer. This example asks for at least one exploratory path
in eight and a 12-frame response (0.4 seconds at 30 fps).

```scheme
(Tracer-guiding-set tracer
  (new LightGuiding (exploration-floor 0.125) (recovery-frames 12)))
```

Recovery means closing 90% of the expected gap from the old visibility to
the new one for a retained light that wins every probe. Let `N` be the
number of shadow opportunities per receiver in the requested frames.
With `T` displayed frames and `s` paths per pixel, `N = T × s`.
The per-opportunity response is `r = 1 − 0.1^(1/N)`. The actual probe
probability is `p = max(exploration-floor, r)`, and each observation
uses gain `a = r/p`. With probes alone the expected remaining gap after
`N` opportunities is `(1 − p a)^N = 0.1`. A higher exploration floor
buys more frequent probes with smaller updates. A shorter target can raise
exploration so that one clear observation suffices.

For a fully uncovered light that wins a fraction `s` of probes, the chance
of at least one rediscovery is `1 − (1 − p s)^N` under constant independent
odds. Its expected residual visibility error from probes alone scales as
`(1 − p s a)^N`. Guided wins also teach the receiver. Actual reservoir
selection depends on the light's energy relative to the other candidates.
Rare proposals, partial occlusion and eviction can extend the wait.

The same response rate sets a positive visibility floor `min(½, r)` for
candidate weighting. Temporal donor count is capped at `(1 − r)/r` times
the fresh count, using one **reservoir write per frame** at either sample count. Thus fresh proposals account for at least `r` of
the represented temporal stream. The existing caps of 20, or less while
driving, can shorten this memory. The default is a ⅛ exploration floor
and a 48-frame recovery target.

In the 9×9 indoor regression a screen blocks a bright patch of sky and a
weaker lamp lights the wall. Each receiver casts one shadow ray per frame.
Energy-only selection with reservoir reuse sends 75% of those rays toward
the blocked sky and gives raw red-channel variance of 0.0156. With a ⅛
exploration floor, shortening the recovery target spends more rays on the
blocked sky and finds the opening sooner.

| Recovery target | Sky rays while blocked¹ | Raw variance while blocked | Sky rays in first 4 open frames | Sky rays in next 12 | Mean radiance in those 12 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 48 frames | 38% | 0.00460 | 47% | 75% | 0.2856 |
| 12 frames | 46% | 0.00580 | 60% | 77% | 0.2876 |

¹ Measured over 12 frames after 20 warm-up frames. The open-room reference
averaged 32 independent samples per pixel and gave 0.2886.

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

`(snail shell graphics bvh)` builds a two-level hierarchy on the device,
as hardware ray tracing has one. A bottom level is a tree over one span of
a scene's triangles: the still triangles in one, and each moving object's
in one of its own. The top level is a tree over the bottom levels' roots.
It takes any triangles: a positions buffer read as 32-bit words at a
stride and an offset, an index buffer, and the spans that move, which a
`MovingScene` sets from its skin bindings, one span a binding.

Every tree is built top down by the surface area heuristic, as a CPU
builder splits a node. The node's primitives' centroids fall into 16 bins
along each axis. Each of the 45 boundaries between bins is priced by the
area of the box on either side times the count there. The node splits at
the cheapest, or stays a leaf of up to four triangles when no split pays
for the step a walk takes into it. The device builds a level a dispatch.
A level's nodes are its tasks, each a contiguous span of primitives. One
workgroup takes a task: it bins the span, chooses, and rewrites the span
stably into its two children's spans for the next level. The tree is the
same however the device schedules the work. A workgroup takes every
`num_workgroups`-th task, so no dispatch is sized by a count only the
device knows, and none is indirect. A bottom level may take 40 levels.
A span that could not otherwise reach leaves of four by then is halved
instead of binned, so every span ends in a leaf.

Near the root a level has few nodes, and one workgroup a node would
leave the device idle. A wide node, of more than 4,096 primitives, is
split by every workgroup in blocks of 1,024. Each workgroup bins its
blocks into the node's bins in memory, then one workgroup chooses and
makes the node. The blocks count their left primitives, scan the
counts, and scatter stably as a workgroup's partition does. The tree is
the one a workgroup would have built. On an RTX 5090, building Sponza's
262,267 triangles took 14.3 ms a workgroup a node and takes 5.0 ms this
way. The linear BVH built them in 2.0 ms.

A slot is a child as a walk reads it: a box, a pointer and a count. A
count of 0 points at a node, two slots side by side; a count above 0 is a
leaf of that many triangles, each stored as a corner and two edges in the
leaves' order, so a test reads one 48-byte record. Slot 0 is the top
level's root. A top level's leaf is a copy of a bottom level's root slot,
so a walk crosses from the top level into a bottom level as into any node.
It visits the nearer child first, with a 64-entry stack and a cap of 8192
steps.

`refit-bvh!` follows moving triangles after their vertices change. Their
leaves read the vertices again, and each triangle's box merges into its
leaf's slot and every slot above it with atomic minimum and maximum, on
floats laid out as words that sort as the floats do. The top level is then
built again over the roots. The still triangles' tree is never touched
again. A scene with nothing moving has nothing to refit.

Before this, one linear BVH covered every triangle: Morton codes of the
triangles' centroids on a 1024-cell grid over the scene's box, a bitonic
sort, Karras's tree, and a refit of every node. Its grid followed the
whole scene's box. In Last Mile, an 80 km horizon put the 90,197 nearby
triangles of the busiest street window into only 3,981 codes. Equal codes
leave the tree no way to separate triangles. On an RTX 5090 through Dawn,
at the Hyde Street stand with 146,667 triangles traced at 1280 by 720:

| Median GPU time a frame | Linear BVH | Two levels, SAH |
| --- | ---: | ---: |
| Wavefront, two bounces | 9.07 ms | 2.06 ms |
| Wavefront, one bounce | 4.11 ms | 1.49 ms |
| Refit after a pose | 1.02 ms | 0.18 ms |
| Building the still triangles' tree, once | 1.34 ms | 2.43 ms |

The old refit made 50 passes over every node, whatever moved. The new one
merges only the 44 moving objects' boxes and rebuilds the top level over
45 roots.

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
displacement for motion vectors and the expected previous depth. SVGF stores the current clip-space depth and octahedral normal for validation on the next frame. During motion each new observation receives at least 40% of the accumulated illumination weight. Both primary visibility and secondary rays
consume the same world-space triangles. Mesh topology and materials stay fixed.

Each skin binding of a `MovingScene` is one object, with a bottom level of
its own. After a simulation tick, `refit-tracer!` refits those trees and
rebuilds the top level over them ([the BVH](#the-bvh-and-ray-queries)).
Bindings survive a refit. `make-tracer` takes the tone curve. Last Mile uses
`Photographic` for a hue-preserving shoulder followed by sRGB encoding. Last
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

## Render a still

The Node host can render a PNG directly from a local glTF or GLB with the same WebGPU tracer. Run from the repository root.

```sh
./snail-scheme run --target node tools/render.scm scene=scene.glb output=preview.png width=1280 height=720 samples=64 bounces=4
./snail-scheme run --target node tools/render.scm scene=sf stand=0 minute=1040 output=hyde.png
./snail-scheme run --target node tools/render.scm scene=taxi brake=1 eye=2.7,1.35,-3.8 target=0,0.65,0 output=braking.png
```

`sf` builds the actual street neighbourhood, vehicles, people, lamps and sky at one of the 16 taxi stands. `taxi` and `sedan` show the vehicle on a flat surface. An external model resolves buffers and images relative to its file and is framed from its bounds. Supply both `eye` and `target` to choose a camera in scene coordinates. `minute` is local solar time in minutes after midnight. `layers` sets the square texture-layer size for external models and vehicle previews.

`(snail shell graphics still)` renders a fixed camera into an offscreen texture and returns the updated tracer and tightly packed RGBA bytes. It traces every pixel on every sample, with up to 4,096 observations and eight bounces. Image dimensions must fit the device’s ray-buffer limit. Offline frames use the stationary SVGF history. Last Mile caps its own frame rate and reports movement while driving.

### Capture reconstruction inputs and a reference

This view faces Busacca Gallery near the Hyde Street stand. The command writes
a cold, full-resolution 1 spp training input and a 128 spp reference at the
same camera and scene time.

```sh
./snail-scheme run --target node tools/render.scm scene=sf stand=0 minute=1380 \
  eye=-142.32,84.50,271.08 target=-138.32,83.45,278.08 \
  width=240 height=135 bounces=2 samples=128 capture=gallery
```

`gallery.noisy.rgba32f` and `gallery.reference.rgba32f` contain row-major,
little-endian float32 RGB radiance and a coverage marker. The reference
averages fresh observations on the GPU using a disjoint seed range with
temporal and spatial reuse disabled. Both images precede SVGF, exposure and
tone mapping. Each file holds all opaque pixels first, followed by the
blended layer when present. The blended layer's albedo alpha gives its
compositing weight. The JSON file records dimensions, layer order, seeds,
sample count and bounce depth.

The matching `.opaque.*` and `.blended.*` files contain the native,
tightly packed G-buffer planes. Their names give the channel formats.
They carry octahedral normals, emission and previous clip depth, sRGB
albedo with linear alpha, material factors, UV motion, triangle IDs
and hardware depth. The `.camera` file contains the actual jittered `Camera3D` Pod bytes. The reference uses that same subpixel position for every independent lighting observation.

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
`&eye=x,y,z,yaw,pitch` for the camera. The viewer starts with one path per internal pixel.
Use `?spp=2`, or append `&spp=2` to an existing query, for two paths.

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
frames in each of three runs, before visibility guiding. The current
`SurfaceReservoir` occupies 64 bytes, including 16 for visibility history.

### Fewer path samples

The following historical comparison includes the retired checkerboard schedule.

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

A second comparison kept learned visibility enabled on both schedules,
immediately before adding native-resolution jitter. At two accumulated
paths per pixel, full coverage in two frames took **0.633 ms** with
filtered RMSE **0.01462**. Alternating coverage needed three frames and
**0.888 ms**, with filtered RMSE **0.01526**. A single warm frame on the
alternating schedule took 0.286 ms versus 0.318 ms at full coverage.
This used the same 384×256 scene and 54,781 surface pixels, a fresh
4,096-spp reference, 32 cold starts for error, and the median GPU time
over 124 cold starts on the RTX 5090.

### Subpixel jitter

At 192×128, the same two-box scene was rendered with four bounces and
one path per pixel per frame. Both runs used the same seeds, SVGF and
display resolve. Only the camera offsets changed. The reference averages
128 independent paths at each of 16 regularly spaced subpixel positions
(2,048 spp). Error covers the entire resolved linear-HDR image over 16
cold starts, before tone mapping and FXAA.

| Frames | Fixed pixel centers, RMSE | Halton jitter, RMSE |
| ---: | ---: | ---: |
| 8 | 0.02268 | 0.01489 |
| 16 | 0.02233 | 0.01403 |

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
