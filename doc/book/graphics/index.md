# Graphics

Applications draw today through `(snail-core app)`: `view` returns a frame
of mesh batches, sprites and pictures, and a fixed WebGPU renderer in
`host/browser/renderer.mjs` draws it with one metallic-roughness shader.

- The [WebGPU design](plan.md) proposes a `gpu` effect and
  `(snail-core graphics ...)` libraries of composable pipelines and packers,
  replacing the JavaScript renderer.
- The [path tracing primer](path-tracing.md) explains the physics of the
  lighting that plan leaves for after rasterization.
