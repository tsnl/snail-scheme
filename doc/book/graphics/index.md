# Graphics

Applications draw through a `Gpu`, a capability that is a thin wrapper around WebGPU,
and the `(snail shell graphics ...)` libraries of composable pipelines and
packers built on it, all written in `snail-scheme`. Hearsay draws 2D quads
from an atlas; Siegework draws a 3D `Frame` of mesh batches, which
`(snail shell app)`'s `draw-frame` rasterizes into a G-buffer and lights;
Splats draws gaussians, sorted on the GPU by a radix sort built on a scan.

- The [WebGPU design](plan.md) explains the capability and how the
  libraries are built on it; the [library reference](../libraries/gpu.md)
  lists them.
- [Tensors and training](tensors.md) describes the tensor library, its
  gradients, Adam, and the compiler that runs them on the device.
- The [path tracing primer](path-tracing.md) explains the physics of the
  light a path tracer computes.
- [The path tracer](tracer.md) traces glTF scenes with that physics: a
  BVH, a wavefront of kernels, environment light and SVGF, flown through
  by `src/apps/viewer`.
- Measure the light returned by a white metal or dielectric under uniform illumination in the [white furnace](../play/furnace/).
- **[Open Splats](../play/splats/)** in a browser with WebGPU: rings of
  gaussians, or a trained scene's `.ply` dropped on the page with its
  COLMAP `images.bin`.
