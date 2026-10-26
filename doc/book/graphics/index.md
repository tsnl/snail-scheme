# Graphics

Applications draw today through `(lofi app)`: `view` returns a frame of mesh
batches, sprites and pictures, and a fixed WebGPU renderer in
`host/browser/renderer.mjs` draws it with one metallic-roughness shader.

- The [WebGPU design](plan.md) proposes an effect and `graphics` libraries of
  composable pipelines and packers. The application-owned JSPI loop already
  runs; the renderer replacement remains proposed.
- The [path tracing primer](path-tracing.md) explains the physics of the
  lighting that plan leaves for after rasterization.
