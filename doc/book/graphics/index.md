# Graphics

Applications draw through the `gpu` effect, a thin wrapper around WebGPU,
and the `(snail shell graphics ...)` libraries of composable pipelines and
packers built on it, all written in `snail-scheme`. Hearsay draws 2D quads
from an atlas; Siegework draws a 3D `Frame` of mesh batches, which
`(snail shell app)`'s `draw-frame` rasterizes into a G-buffer and lights;
Splats draws gaussians, sorted on the GPU by a radix sort built on a scan.

- The [WebGPU design](plan.md) describes the effect and the libraries.
- The [path tracing primer](path-tracing.md) explains the physics of the
  lighting that plan leaves for after rasterization.
