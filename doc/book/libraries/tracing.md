# Rendering glTF scenes

The forward renderer accepts glTF meshes, materials and skins. Its scene loader expands glTF accessors into vertex and index buffers, uploads images with mipmaps and keeps material draw ranges. `skin-scene` accepts rigid and joint-weighted bindings. `deform-scene!` uploads the pose for the moving suffix of a scene.

The shared forward color pass also supports lit instanced geometry and orthographic atlas sprites. The games choose the appropriate passes and the compositor presents their finished textures. [Frame sequence and material rules](../graphics/rasterizer.md) · [Retired tracer library reference](https://github.com/tsnl/snail-scheme/blob/07e831337bcedfad9e6763d77a80e3d1abb44ed0/doc/book/libraries/tracing.md).

## `(snail shell graphics gltf)`

A glTF 2.0 scene, a `.gltf` file's JSON or a `.glb` file, read by `read-gltf`
into what drawing and tracing it need: its buffers and images, each
primitive's accessors as byte offsets into the buffers laid end to end, its
materials, and each primitive `Placed` by the default scene's node
hierarchy. The buffers' bytes are not read here: they go to the device
whole, and a compute pass unpacks each accessor. `gltf-bounds` is the
scene's box.

It reads triangle primitives with positions, normals, a first set of texture coordinates and tangents, indices of any width, metallic-roughness materials with their textures and alpha modes, and `KHR_materials_emissive_strength`. `gltf-transformed` composes a column-major instance transform with each placed primitive. Unsupported sparse accessors and Draco or meshopt compression are reported through `attempt-reading`. [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/gltf.sld)

## Skinned animation

`(snail shell graphics gltf animation)` reads the hierarchy, skins, vertex influences and animation clips. `(snail shell graphics animation)` samples and blends the local transforms. `posed-nodes` evaluates the hierarchy once for an instance. A rigid prop follows the world transform of its named node. `skin-palette` applies inverse binds to those same world transforms for mesh deformation. [Skinning and the tracer](../graphics/tracer.md#skinned-animation) · [Animation](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/animation.sld) · [glTF animation reader](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/gltf/animation.sld)
