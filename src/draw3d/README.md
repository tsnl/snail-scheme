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

`present-scene!` walks the hierarchy, transforms positions and normals, and
copies a single indexed frame through `snail.scene`. It never transfers a
managed reference or stores GPU handles in a game snapshot. The bridge parses
finite scalar values, complete uniforms and bounded indices before exposing a
frame. The shaders use the camera matrix and Lambert lighting on the GPU.

`src/webgpu/scene.mjs` owns one device, a growable vertex/index buffer pair, a
uniform buffer, and multisampled color/depth targets. Normal draws reuse them.
Resize releases replaced targets; shader reload preserves the buffers and
retains the preceding pipeline for rollback. Close stops new work, drains
preparation/readback and submitted work, unconfigures the canvas, then destroys
the owned resources. Scene values do not need individual GPU disposal.
An embedding host creates this owner with `await createSceneRenderer(canvas,
onError)` and must call `await renderer.close()` when it ends the session.
The shared browser application's `close()` includes this step; Scheme code
only calls `present-scene!` and does not acquire that host resource.
This follows the explicit resource model and depth attachment contract in the
[WebGPU specification](https://www.w3.org/TR/webgpu/).

The current renderer uploads transformed geometry per frame. Instanced GPU
transforms, textures, glTF import, transparent sorting, shadow maps, richer
materials, animation assets, and path tracing are future features. They are not
required for the initial Siegework scene. Picking intersects ground planes and
axis-aligned boxes; it does not perform arbitrary mesh ray intersection.

## Checks

Run `scripts/test-draw3d` to compile and execute the math/geometry/shader checks
and a real colony frame in Wasm. It produces a browser fixture in
`build/draw3d-tests/`. The product surface does not currently support
`cond-expand`; test entry points follow the existing Lofi library convention,
with private helpers in final `Tests` sections.
