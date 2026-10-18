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
  1 (unlit). Surfaces are opaque and double-sided; lighting follows the supplied
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
all five geometry batches. No managed reference or GPU handle enters the cache:
retained data consists of copied vertices and indices, scoped to one Wasm instance.
Replacing the module starts fresh geometry caches while preserving typed state.

`present-scene!` transforms positions and normals only for changed batches.
The host validates finite scalars, complete uniforms and bounded indices. The
shaders apply the camera matrix and Lambert lighting. `src/webgpu/scene.mjs`
uploads only changed batch objects and draws current batches in one render pass.
It owns one high-performance adapter/device, one growable buffer pair per batch,
one uniform buffer and one single-sample depth target. Resize releases the old
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

## Checks

Run `scripts/test-draw3d` to compile and execute the math/geometry/shader checks
and a real colony frame in Wasm. It produces a browser fixture in
`build/draw3d-tests/`. The product surface does not currently support
`cond-expand`; test entry points follow the existing Lofi library convention,
with private helpers in final `Tests` sections.
