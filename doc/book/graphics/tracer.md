# The retired path tracer

The glTF viewer, offline tool and games now use the forward renderer. We retired the shared wavefront tracer because its ray traversal and temporal reconstruction struggled to meet the game’s performance and motion-quality targets. The GPU code and its book chapter remain available together at the last tracer revision. [Forward renderer and measurements](rasterizer.md) · [Replacement PR](https://github.com/tsnl/snail-scheme/pull/947).

The archived chapter describes traversal, emissive triangle sampling, ReSTIR reservoirs, SVGF, the linear reference integrator and comparisons with Blender Cycles. It also includes the exact commands and scenes used to reproduce those comparisons. [Read the archived chapter](https://github.com/tsnl/snail-scheme/blob/07e831337bcedfad9e6763d77a80e3d1abb44ed0/doc/book/graphics/tracer.md).

## White furnace

The furnace remains a standalone app and evaluates the forward renderer’s material model under a constant white environment. [Run the furnace](../play/furnace/) · [Interpret the measurement](rasterizer.md#measure-and-inspect).
