# Drawing 3D scenes in Scheme

`(draw3d)` is an initial reusable scene drawing library. Geometry, materials,
transforms, camera projection, ray picking, and scene composition are Scheme
values and operations. `(webgpu shader)` checks the Scheme shader expressions
and generates WGSL. The browser host owns GPU buffers and submits indexed draws.

```scheme
(import
 (scheme base)
 (scheme immutable)
 (draw3d))

(define camera
  (orthographic-camera (vec3 4.0 -6.0 5.0) (vec3 0.0 0.0 0.0)
                       (vec3 0.0 0.0 1.0) 8.0 1.5 0.1 100.0))
(define picture
  (scene camera
         (list (mesh box-geometry (material 12298387 0.0)
                     (compose (translation (vec3 0.0 0.0 0.5))
                              (scaling 1.0 1.0 1.0))))
         (directional-light (vec3 -1.0 -1.0 2.0) 0.7)
         (vec3 0.35 0.4 0.45) 790042))
;; Inside a browser application's presentation query:
(present-scene! picture)
```

The API follows the explicit scene/camera/mesh data and renderer ownership in
[Resin's archived 3D API](https://github.com/tsnl/resin/blob/archive/main-v3/src/resin/draw_3d.py).
The initial feature set is also comparable to the scene, indexed geometry and
camera concepts in [Three.js](https://threejs.org/docs/pages/Object3D.html).
It is a Scheme library, not a Three.js import or a compatible implementation of
the complete Three.js API. Resin's path tracer is an API reference, not the
rendering algorithm used here.

## Values and coordinate conventions

- `vec3` contains binary64 components. X is right, Y forward, Z up. Conversion
  to GPU binary32 happens at the copied scalar boundary.
- `transform` contains three basis vectors and an origin. Construction rejects
  singular or nonfinite transforms. `compose parent local` applies local first.
  `group` applies a transform to all its children; `mesh` combines geometry,
  material and a local transform. Normals use the inverse transpose, including
  nonuniform scales and reflections.
  Its arguments are `(transform x-basis y-basis z-basis origin)`, all `Vec3`.
  `group` takes a local transform and a list of child nodes; `mesh` takes
  geometry, material, then a local transform.
- `indexed-geometry` copies vertex and triangle-index vectors. It normalizes
  normals and rejects invalid indices. Accessors return individual immutable
  vertices and indices, so callers cannot mutate the checked backing arrays.
  Unit box, plane and square pyramid geometry are provided.
  Construct custom vertices with `(vertex position normal)` and pass a vertex
  vector plus an `I32` triangle-index vector to `indexed-geometry`.
  Normals are supplied explicitly; degenerate triangles are allowed and produce
  no covered area. No normal-generation or asset-cache policy is implicit.
- `material` takes packed RGB and an emission blend from 0 (Lambert shaded) to
  1 (unlit). Surfaces are opaque by default and double-sided; lighting follows the supplied
  normal on both sides. One directional light and RGB ambient light belong to
  each scene. Display RGB values are lit directly without a color-space workflow.
  `directional-light` takes a vector pointing **toward** the light and a
  nonnegative scalar intensity; the constructor normalizes its direction.
- `orthographic-camera` takes eye, target, up, vertical height, aspect, near and
  far. `perspective-camera` uses vertical focal length instead of height:
  `1.7320508` corresponds to a 60-degree vertical field of view. Camera vectors
  and clip ranges are checked. WebGPU depth ranges from zero to one.
- `camera-ray` takes normalized device coordinates, X left-to-right and Y
  bottom-to-top. `ray-ground` returns an empty list for a parallel or backward
  intersection, otherwise one world-space point at the requested Z height.
  `bounds` checks an axis-aligned box from minimum/maximum corners; `ray-box`
  returns the first forward intersection, or an empty list. Parallel axes and
  rays starting inside a box are handled explicitly. Siegework selects the
  nearest building box before falling back to the ground cell.
  Rays are unbounded forward rays; these intersection functions do not apply
  camera clipping. The prototype's camera interval contains its selectable grid.

## Rendering and ownership

`scene` eagerly describes one uncached batch. For a retained scene, use
`batched-scene` with the same camera/light/ambient/background arguments and a list
of lazy batches:

```scheme
(retained-batch 3 1 (empty-list) (lambda () (world-nodes world)))
```

The arguments are a stable nonnegative key, an owner dependency mask, a list of
`I32` dependencies and a zero-argument node builder. Mask 1 depends on game state,
2 on presentation state, 3 on both, and 0 on neither. The bridge compares exact
immutable owner identities and scalar dependency sequences before invoking the
builder. Dependencies must cover every input that changes geometry. The compiler
does not prove that declaration complete. Use a fixed, small key set, unique
within each frame; changing a key deliberately starts a different retained batch.

A mask-zero batch can depend on selected scalar fields instead of a whole owner.
Siegework does this for terrain visibility and rail paths, while workers, enemies
and shuttles depend on game state. Camera movement changes uniforms and reuses
geometry batches. No managed reference or GPU handle enters the cache:
retained data consists of copied vertices and indices, scoped to one Wasm instance.
Replacing the module starts fresh geometry caches while preserving typed state.

Completed numeric arrays are frozen at the bridge's construction boundary, so
the presentation finalizer can preserve them without recursively copying every
number. Wrappers and reveal metadata still receive recursive freezing. See the
[measured finalization cost](../../doc/measurements/scene-finalization-2026-10-18.md)
for avoided work, output-equivalence checks and remaining mobile costs.

`present-scene!` transforms positions and normals only for changed batches.
The host validates finite scalars, complete uniforms and bounded indices. The
shaders apply the camera matrix and Lambert lighting. `src/webgpu/scene.mjs`
uploads only changed batch geometry and draws each view in its own render pass.
It owns one high-performance adapter/device, growable vertex/index buffers per
batch, a shared uniform buffer and one single-sample depth target. Motion batches
also own previous positions and a uniform buffer; translucent batches own a
uniform buffer for their opacity. Resize releases the old
depth target; shader replacement preserves buffers and retains the prior pipeline
for rollback.

Close stops admission, drains preparation/readback and submitted work,
unconfigures the canvas and destroys all owned resources. An embedding host uses
`await createSceneRenderer(canvas, onError)` and `await renderer.close()`; the
shared browser session includes cleanup. Scheme scene values require no GPU
resource disposal. See the [WebGPU specification](https://www.w3.org/TR/webgpu/).

Instanced GPU transforms, textures, glTF import, transparent sorting, shadow maps,
richer materials, animation assets and path tracing remain future features.
Picking currently intersects ground planes and axis-aligned boxes.

## Additional camera views

After the main scene, present up to three independently keyed inset scenes:

```scheme
(present-scene! overview)
(present-scene-inset! 7 detail-camera-scene 20 30 96 72)
```

The arguments are a nonnegative `I32` view key, a complete scene, then logical
canvas X, Y, width and height as `I32` values. Coordinates must be nonnegative;
dimensions must be positive. An inset has its own camera, background and depth.
Later insets cover earlier ones where their rectangles overlap. Rendering the
complete inset before copying its visible rectangle preserves its projection
when the right or bottom edge extends beyond the canvas.

All views share one adapter, device and submission. Each inset owns a camera
uniform and color/depth targets; batch keys are scoped to their view, so two
cameras may both use batch key 3. The bridge validates every view before
publishing any retained batch changes. Resize replaces targets while preserving
geometry, and omitted or fully clipped insets release their GPU resources.
Explicit previous/current motion remains authoritative when a view reappears.
Animation in an inset redraws the complete frame without rerunning Scheme.

The browser uses the full native device-pixel ratio for the main canvas and
insets. Requested physical sizes exceeding the device's texture limit fail
before target allocation. Insets use GPU texture copies, with no per-frame
readback or additional device requests. Close drains pending readbacks and
releases every view's resources.

## Motion between committed states

`moving-group` takes a previous local transform, a current local transform and a
list of child nodes. Put it inside a `motion-batch` to interpolate its positions:

```scheme
(motion-batch 3 1 (empty-list) 100
  (lambda ()
    (list (moving-group previous-transform current-transform
            (list (mesh box-geometry surface identity-transform))))))
```

The batch arguments are key, owner dependency mask, scalar dependencies, positive
`I32` duration in milliseconds and a zero-argument node builder. Keys and
dependencies follow the retained-batch contract above. Motion batches are opaque.
An ordinary `group` or mesh transform applies at both endpoints; nested
`moving-group` nodes supply both complete transform hierarchies. Outside a motion
batch, a moving group draws its current transform directly.

Scheme transforms corresponding previous and current vertex positions when a
changed batch is built. The browser uploads them once, then advances a per-batch
fraction from 0 to 1 using elapsed display time from its first draw. The vertex
shader mixes those positions before camera projection. The browser's animation
frame loop redraws active motion without running the Scheme view, reducers or UI
layout again. After drawing the final fraction once, motion stops redrawing.
Existing pulse animation can continue independently.

Reusing the same immutable batch preserves its clock and GPU buffers, including
during camera changes or shader replacement. A new batch value starts a new
transition. Static batches allocate no previous-position buffer: both vertex
bindings reuse the current buffer. A motion batch owns a separate previous
buffer and uniform so concurrent batches can use different durations.

For a simulation committing every 100 ms, a duration of 100 ms displays the
transition from the prior committed state to the current one over the following
tick interval. This adds approximately one simulation tick of visual latency;
there is no extrapolation. Delayed commits hold the last endpoint, and a new
batch replaces an unfinished transition rather than blending from the last
displayed fraction. The application chooses suitable prior transforms, matching
entities by identity and using current transforms for new entities or a new run.
The application bridge supplies [prior committed snapshots](../../doc/book/lofi/applications.md#previous-snapshots-for-presentation).

Both endpoints use the **current** geometry, child hierarchy, materials and
normals. Only transformed positions interpolate; this does not morph between two
meshes, interpolate lighting normals, preserve removed entities or animate
topology changes. Rotations and scales interpolate vertex positions linearly,
not through a rigid-transform interpolation.

## Fragment-level radial reveals

Wrap any retained, motion or translucent batch with a radial reveal:

```scheme
(reveal-batch
  (retained-batch 8 0 dependencies (lambda () newly-visible-nodes))
  transition-id center-x center-y enclosing-radius 0.7 elapsed-ms 3000)
```

The wrapper takes the batch, a nonnegative `I32` transition identity, world XY
center, enclosing radius, nonnegative edge width, nonnegative initial elapsed
milliseconds and positive duration milliseconds. Center, radius and feather are
`F64`; times are `I32`. An edge width of zero requests a sharp continuous contour;
a positive width feathers it. The radius must enclose **all** supplied geometry in XY,
including tile corners and both endpoints of moving geometry. Stage the complete
geometry at the start. Previously revealed geometry belongs in ordinary batches.

The fragment shader measures distance from each interpolated world position to
the center. The continuous contour advances with a quintic easing curve: slow
start, fast middle, slow finish. The host updates a small uniform and redraws
existing buffers at display rate; Scheme, reducers and UI layout do not run on
that path. Exactly invisible fragments discard, and the endpoint exposes the
entire supplied batch. After that endpoint is drawn once, reveal-driven redraw
stops. Completed geometry can remain in its reveal wrapper indefinitely.

One identity names one transition across all batches and cameras on the device.
Those wrappers must agree on center, radius, feather and duration. Elapsed time
seeds the clock only when the identity first appears; later age values do not
reset or advance it. Camera changes, geometry updates, shader replacement and
resize preserve the clock. Updating only reveal metadata reuses existing vertex
and index buffers. A wrapper's presence anywhere in the complete frame retains
its clock, including empty or clipped views. Omitting the identity from the whole
frame releases it; a later appearance starts from the supplied elapsed value.
Use a fresh identity for each event, including a new run. Multiple concurrent
identities are supported; replacing an unfinished event with ordinary geometry
would immediately expose its remaining area.

Revealing opaque geometry blends color while writing depth, preserving its
opaque endpoint and normal self-occlusion. This is a bounded approximation to
transparent overlap: a nearer feather drawn first can hide a surface submitted
behind it later. The renderer does not sort transparent triangles. Existing
translucent batches keep blending without depth writes, including when wrapped.

## Checks

Run `scripts/test-draw3d` to compile and execute the math/geometry/shader checks
and real colony and nested-motion frames in Wasm. It produces a browser fixture
in `build/draw3d-tests/`. Serve that directory, then run
`node tests/draw3d/browser.mjs FIXTURE_URL DEVTOOLS_URL` against an isolated
Chromium instance. GPU checks cover intermediate and final motion pixels,
independent durations, shared reveal clocks, fragment opacity, inset cameras,
native DPR, shader replacement, buffer reuse and resource cleanup.
The product surface does not currently support
`cond-expand`; test entry points follow the existing Lofi library convention,
with private helpers in final `Tests` sections.
