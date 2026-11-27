# Replacing the path tracer

The proposed shared renderer uses WebGPU rasterization for Willowbank, the
glTF viewer, headless renders and the white furnace. We built a working
wavefront path tracer with ReSTIR, SVGF and a scene-linear reference mode
that we compared against Blender Cycles. The transition PR is titled
**replace path-tracer with simpler rasterizer**. We are retiring the tracer
because of the cost of rendering a moving game on the GPUs we want to
support. A future renderer can revisit that work. The last working revision
includes the code, comparison scenes and commands to reproduce the results.
[Archived renderer](https://github.com/tsnl/snail-scheme/tree/07e831337bcedfad9e6763d77a80e3d1abb44ed0/src/snail/shell/graphics/trace) · [Reference renders and furnace measurements](https://github.com/tsnl/snail-scheme/blob/07e831337bcedfad9e6763d77a80e3d1abb44ed0/doc/book/graphics/tracer.md#compare-with-blender-cycles)

The published measurements explain the decision. At 1600×900, two paths
per pixel and two bounces, the median Lantern Row frame on an RTX 5090
spent 10.76 ms on ray traversal out of 15.80 ms of measured GPU work.
Rasterizing the first hits took 0.21 ms. Better importance sampling can
reduce noise per ray. Shadow rays and continuation rays still traverse
the scene. The cost of drawing multiple shadow maps and shading foliage
on an integrated GPU needs its own measurement. [Riding benchmarks](../games/iygtw.md)

## What to match in Broccoli

Broccoli submits indexed mesh instances grouped by material, renders
directional shadow maps, then shades the meshes forward. This is a good
fit for the village's short light list. It also makes 4× multisampling
possible with a single HDR color target and depth. Use a single forward
renderer first. A deferred lighting pass would become worth measuring if
overlapping lights come to dominate the frame. [Frame and draws](https://github.com/tsnl/broccoli/blob/55ca4c6ce97940ae4aa4da236189bf13c8ac04cd/src/broccoli/engine/render.cc#L2450-L2461) · [GPU limits and defaults](https://github.com/tsnl/broccoli/blob/55ca4c6ce97940ae4aa4da236189bf13c8ac04cd/src/broccoli/engine/render.cc#L28-L87)

| Feature | Broccoli at the reference revision | First Snail implementation |
| --- | --- | --- |
| Materials | Blinn–Phong and metallic-roughness PBR with base color, tangent-space normals, metalness and roughness textures. [Shader](https://github.com/tsnl/broccoli/blob/55ca4c6ce97940ae4aa4da236189bf13c8ac04cd/res/shader/3d/ubershader.wgsl#L219-L411) | Match both on a calibration mesh. Use PBR for glTF and honor texture mips, color space, emissive factors, alpha mode and sidedness. |
| Lights | Up to four directional lights and sixteen point lights. PBR point lights have inverse-square falloff. Ambient is a scalar. | Use explicit lights. Begin with a key directional light and local point lights. The environment bake below supplies ambient illumination. |
| Shadows | The PBR path compares one depth sample. The directional cascade array is configured for one 2048² map reaching 400 m. Point lights cast no shadows. [Shadow lookup](https://github.com/tsnl/broccoli/blob/55ca4c6ce97940ae4aa4da236189bf13c8ac04cd/res/shader/3d/ubershader.wgsl#L468-L513) | First reproduce one hard directional shadow. Then split the viewing distance into filtered cascades for the sun or moon. |
| Output | Filmic mapping on the PBR path, 4× MSAA, a bitmap overlay and a shadow-map inspector | Keep exposure, tone mapping and FXAA. Add selectable 1×/4× raster samples and a cascade inspector. The existing DOM supplies the game overlay. |

## Order of work

1. **Draw one frame through the real asset path.** Move glTF geometry,
   material uploads, texture mips and skinning out of `graphics/trace/scene`.
   The new draw path should allocate only its vertex, index, material and
   texture data. Keep one concrete `Renderer`. Its draw function calls the
   skin, shadow, color and post passes in order. Feed the same deformed
   positions and alpha cutoffs to shadow and color draws. Start with the
   courier, Moss, a leaf card and wet road. Inspect unlit albedo before
   judging the lighting. Our Cycles comparison already found a large
   canopy albedo difference.
2. **Add direct light and stable shadows.** Draw opaque and masked meshes
   into linear HDR, then blend transparent surfaces back to front against
   the same depth buffer. Tone map once. Start with one depth map, then
   try three fixed frustum splits. Fit each to the unjittered camera, snap
   its light-space center to a texel and include casters outside the
   camera view that can shadow the split. Blend across overlaps. Start
   with 3×3 percentage-closer filtering (PCF), averaging depth comparisons.
   Tune bias against tire contact and distant fences. This gives a soft
   edge of fixed filter width. Keep only the dominant sky light shadowed
   in the village's first preset. [Cascaded shadow maps and filtering](https://learn.microsoft.com/en-us/windows/win32/dxtecharts/cascaded-shadow-maps)
3. **Bake image-based lighting.** Have a `generate-library` producer read a
   scene-linear HDR sky, run a pinned filter, and return a library linking
   the baked resources. Key the bake by its source, filter version and
   settings so an unrelated Scheme edit can reuse it. For each sky, bake
   nine RGB diffuse irradiance coefficients and six cubemap faces at each
   GGX roughness level. Bake
   one shared 2D BRDF integration lookup for the chosen visibility and
   Fresnel model. Use the normal for diffuse and the reflected view
   direction plus roughness for specular. Keep the visible sun or moon
   disc in the background and omit its direct energy from the lighting
   bake so the directional light supplies it once. Test cubemap
   orientation with a single bright patch, roughness with a row of
   spheres, and diffuse normalization with the white furnace. Acquire
   the bytes through the existing resource cache. The game only uploads
   and samples them. For a raw HDR dropped into the viewer, prefilter
   once on import and cache the result against the same inputs. Local
   Blender irradiance probes and baked AO can follow when a global sky
   leaves sheltered areas too bright.
   [Generated libraries](../snail-scheme/macros.md#generated-libraries) · [Filament's environment filter](https://github.com/google/filament/tree/main/tools/cmgen)
4. **Move every caller, then delete the tracer.** The viewer should still
   open a user's glTF and sky. Keep headless PNG and linear HDR readback
   through the same renderer. Preserve the furnace's numerical readout and
   use Blender Cycles for path-traced references. Port Willowbank's animated
   characters, cutout foliage, puddles, tire tracks and four sky settings.
   Remove path counts and bounce depth from the controls and benchmarks.
   Load older saves with their ride and resolution intact. Remove the
   shared path renderer, its ray queues and BVH refits, ReSTIR, SVGF,
   temporal path reconstruction, volumetric fog and god rays. Audit their
   imports, GPU fixtures, CLI flags and book links in the same change.
   Keep depth of field off for the first image comparison.

The WebGPU surface already has per-layer depth views. PCF can start with
explicit depth loads. Expose cube views for environment mip sampling and
sample counts and resolve targets for MSAA in the browser and headless
hosts. Run both hosts on the same small scene to catch descriptor or face
orientation differences.

## When to switch the default

A capture of the Willowbank build on port 4193 in Chromium at device
pixel ratio 2 drew the 900p preset at 1440×900 on a 2880×1800 canvas.
Its active pipelines included SVGF, mist, depth of field, temporal
reconstruction and FXAA. There was no scene-outline pass. The cause of
the reported MacBook silhouette artifact is still open.

Capture Lantern Row, Mill Bridge and the orchard with the same camera,
sky, resolution and exposure before and after the switch. Include a ride
past cutout leaves and a slow pan across a cascade boundary. Inspect a
native-resolution crop of Moss, the rider and the spokes, with FXAA
toggled in a diagnostic capture. Record internal pixels, canvas pixels
and device pixel ratio so a Retina presentation can be reproduced.

Update `benches/iygtw/ride.mjs` to recognize the new target and report
skinning, shadow draws, material shading and post separately. Measure
median and p95 GPU times, CPU submission and uninstrumented frame
intervals. Keep the player's chosen resolution fixed. The initial target
is 30 fps with p95 GPU work under 25 ms, leaving room inside a 33.3 ms
frame. Try 900p on the MacBook Pro and RTX 5090 and 720p on the Radeon
840M. These are acceptance targets. Only the tracer has timings here.
