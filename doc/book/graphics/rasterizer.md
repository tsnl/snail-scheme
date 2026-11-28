# The forward renderer

Willowbank, The Last Mile, the glTF viewer, offline stills and the white furnace use the same forward material renderer. Siegework and 2D sprite scenes use its color pass, full-resolution output texture and compositor with pipelines suited to their geometry. All application drawing is written in Snail Scheme.

## A frame

The renderer draws into its own textures. A browser compositor samples the finished RGBA8 texture through a fullscreen triangle in the canvas format. The offline renderer can read that texture directly or export the linear RGBA16F lighting attachment. Changing the presentation format only changes the compositor. This follows the texture-first design of the earlier Python renderer. [Resin compositor](https://github.com/tsnl/resin/blob/966e3a6d4bb5a3b93a4df3d0a2ec0b6f36f9304d/src/zfw/compositor.py#L121-L146).

1. Draw three 1024² directional shadow cascades and the camera depth prepass. Each has a different view-projection. They share the vertex transform, alpha coverage, draw loop and single-sample pipelines. A 4× MSAA camera uses the same shaders compiled for four samples. The GPU clips the submitted triangles for each view.
2. Shade opaque draws into HDR with depth equality. The depth prepass allows grouping draw calls by material. Each glTF primitive has a vertex and index range and its material has one bind group.
3. Sort translucent primitives by distance from the eye and blend them back to front with depth writes disabled. For moving shells, the CPU updates each sort center from the same joint palette as the vertices. A rigid mesh costs one matrix product. Double-sided convex shells draw their back faces first.
4. Resolve MSAA, tone-map in compute and run FXAA. Both games with a sky render at the canvas’s physical pixel dimensions. The pause menu selects 1× or 4× MSAA. The glTF viewer uses the 1 and 4 keys.

| glTF material | Depth and shadow maps | Forward color |
| --- | --- | --- |
| OPAQUE | Vertex-only for single-sided or two-sided geometry | Material group |
| MASK | The cutoff tests base texture alpha times material alpha, with the same UVs and sidedness as color | Material group |
| BLEND | No depth writes or shadow casting | Global painter order |

The debug glTF loader welds seam vertices and checks convexity, winding and connectivity for blended primitives when it creates the mesh. Release builds omit the construction check. Intersecting translucent primitives remain an ordering limitation. Meshes use ordinary indexed draws. [Broccoli reference](https://github.com/tsnl/broccoli).

## Lights and materials

The visible sky, nine diffuse spherical harmonic coefficients and a six-level prefiltered GGX cubemap come from the same environment. A generated library bakes the four times of day and the split-sum BRDF lookup. The directional sun or moon supplies direct light and filtered shadows. Shadow filtering compares neighboring depth texels and blends across cascade boundaries. The viewer can also prefilter a dropped Radiance HDR panorama. Press V to see each cascade’s actual depth texture.

Base color and emissive textures are decoded to linear light. Metallic and roughness use the blue and green channels. glTF occlusion uses red and its strength scales the indirect illumination. A packed ORM texture can supply all three. The city stores stationary point lights by ground cell and updates a separate list of moving headlights and taillights. Each source has a range, intensity and, for spotlights, a direction and cone. The village adds an evolving ground material and animated water normals. Texture compression and local irradiance probes are future work.

Siegework lights solid instanced meshes in the color pass and then blends its reveal, link and placement overlays. Its depth buffer is enough for these passes. Sprites draw from an atlas in order through an orthographic camera with nearest filtering and pixel-snapped corners. It renders to RGBA8 and presents directly so pixel art keeps its colors. Both paths skip shadow maps and environment baking.

## Measure and inspect

The white furnace measures glTF materials under a uniform environment using the same shaders as the games. Its central pixel reports the scene-linear material response and a background reference. A smooth white metal should return close to one. A rough white metal in this single-scattering GGX model returns about 0.307 at normal incidence. [Open the white furnace](../play/furnace/).

Render an asset locally with `./snail-scheme run --target node tools/render.scm scene=model.glb output=preview.png width=960 height=540`. Use `linear=film.rgba32f` for linear values, `cascade=0` through `cascade=2` for the shadow views, or `brdf=blinn-phong` for direct Blinn–Phong shading. The Blender comparison in `benches/render/compare.mjs` reads linear values from the same scene and camera. [Ride benchmark](../games/iygtw.md).

## Record and replay a scene

In `(snail shell graphics scene)`, a `ModelNode` references a glTF and a `GroupNode` places its children under a local transform. Each model brings its own geometry and materials. Repeated references share the source buffers and material images. `scene-geometry` produces the authored world coordinates. The viewer and offline tool enlarge a scene smaller than one unit as a whole when loading it for inspection. For example, a village scene can place two instances of the same tree beside a house.

```scheme
(GroupNode unit-matrix
  (list (ModelNode "house.glb")
        (GroupNode tree-by-gate (list (ModelNode "oak.glb")))
        (GroupNode tree-by-road (list (ModelNode "oak.glb")))))
```

The public `Renderer` owns the render context, resident models and environments. `create-scene-node!` returns a model handle. Select it with `use-model!`, supply the environment with `set-sky!`, then call `render!` with a `SceneFrame`. Each frame supplies the camera, viewport, lighting, shading, exposure, shadow selection and MSAA. The result is a texture. `present-render!` can also composite that texture to a surface in the same submission. This arrangement follows the resource and scene managers in [tsnl/graphics](https://github.com/tsnl/graphics/blob/a7ab5c8862c492aac37ce4953d154091d1fbe886/src/lib.rs#L42-L49).

For a world with many static pieces, `create-static-geometry!` uploads the glTF placements in one byte buffer and returns a handle. Each primitive names an opaque or alpha-tested material slot on the model that draws it. `select-static-geometry!` sets that model’s visible handles. The camera depth, shadow and color passes draw the selected buffers alongside the model. Changing the selection reuses those buffers and material bindings. Geometry handles live until the renderer is released. A renderer trace records the placement data and source bytes once and references the handles on later selections.

A renderer accepts an optional ordinary `OutputPort` at construction. A file, an in-memory writer and the browser download adapter all use the port interface from `(snail core io)`. A new renderer can replay the stream from any `InputPort`. Each call returns the number of commands it ran and leaves the port at the next command.

```scheme
(define (recording-renderer (gpu Gpu) (out OutputPort)) (→ Renderer)
  (make-renderer gpu (new RendererConfig (trace (Some out)))))

;; Advance three commands, inspect the renderer, then finish the stream.
((● renderer replay) input (Some 3))
((● renderer replay) input (None))
```

Open the viewer, Willowbank, The Last Mile, Siegework or the furnace with `?trace=1`. Click **Download renderer.jsonl** to take a snapshot of all renderer operations so far. Capture uses extra memory and may stall a frame while reading back newly painted mud tiles or composed sprites. Recording stays disabled on the usual URL. The same API works offline.

```sh
./snail-scheme run --target node tools/render.scm scene=model.glb record=ride.jsonl output=original.png
./snail-scheme run --target node tools/render.scm replay=ride.jsonl output=replay.png
```

Each logical command begins with a versioned JSON object containing an operation, arguments and binary block lengths. The following JSON string lines carry the blocks in base64 chunks of up to 24 KiB of source data. A model creation embeds geometry, material definitions, texture bytes and any skin bindings. Later commands carry poses, lighting changes, updated material tiles and camera frames. Instanced batches contribute data when their version changes. Sprite atlas updates carry the changed rectangle, and sprite draws preserve painter order. The stream can replay offline after the original assets and game have gone away. `commands=N` stops the offline tool after N commands and writes the most recent completed frame if there is one.

## Why the path tracer was retired

A working wavefront tracer supported ReSTIR, SVGF, emissive triangles, and reference renders compared to Blender Cycles. In the Lantern Row benchmark at 1600×900, two paths per pixel and two bounces, the RTX 5090 spent 10.76 ms of its 15.80 ms median GPU frame traversing rays. The first-hit raster pass took 0.21 ms. Frame time and motion quality on laptop GPUs led us to replace the tracer. A future renderer may revisit it. The pull request and pinned source preserve the implementation and its measurements. [PR #947, replace path-tracer with simpler rasterizer](https://github.com/tsnl/snail-scheme/pull/947) · [Archived tracer](https://github.com/tsnl/snail-scheme/tree/07e831337bcedfad9e6763d77a80e3d1abb44ed0/src/snail/shell/graphics/trace) · [Archived validation and Blender comparisons](https://github.com/tsnl/snail-scheme/blob/07e831337bcedfad9e6763d77a80e3d1abb44ed0/doc/book/graphics/tracer.md).
