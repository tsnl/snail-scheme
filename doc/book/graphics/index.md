# Graphics

The forward renderer shades glTF materials for Willowbank, the SF taxi game, the glTF viewer and offline renders. Siegework lights instanced geometry, and orthographic atlas sprites draw, into the same texture-first frame pipeline. The GPU capability under these scene APIs also supports compute workloads and Gaussian splatting. [Forward rendering](rasterizer.md) · [WebGPU capability](plan.md) · [Library reference](../libraries/gpu.md).

- Inspect lighting in the [white furnace](../play/furnace/) or drop a model into the [glTF viewer](../play/viewer/).
- The [previous renderer](tracer.md) explains the path-tracing work that preceded this renderer.
- [Tensors and training](tensors.md) covers differentiation and GPU training.
- [Open Splats](../play/splats/) to view a trained Gaussian scene.
