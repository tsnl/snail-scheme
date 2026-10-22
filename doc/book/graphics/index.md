# Graphics

Applications draw today through `(lofi app)`: `view` returns a frame of mesh
batches, sprites and pictures, and a fixed WebGPU renderer in
`src/app/renderer.mjs` draws it with one metallic-roughness shader.

- The [runtime and graphics plan](plan.md) proposes the replacement: an
  application that runs its own main loop under JavaScript Promise
  Integration, WebGPU exposed through an effect, and a `graphics` library of
  composable pipelines and packers.
- The [path tracing primer](path-tracing.md) explains the physics of the
  lighting that plan leaves for after rasterization.
