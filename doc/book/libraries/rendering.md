# Rasterized graphics

Games and tools use `(snail shell graphics renderer)` to manage models, scenes, environments and frame output. Supplying an output port in `RendererConfig` records commands that another renderer can replay. The same renderer supports glTF meshes, Siegework's lit instances and Hearsay's orthographic sprites. Its component libraries below expose vertex formats, passes, atlas composition and presentation. [Forward rendering and API tracing](../graphics/rasterizer.md).

## `(snail shell graphics atlas)`

Pictures composed on the GPU into padded slots of texture-array pages. A
`Picture` is `Layer`s of regions of encoded images, each with its colors
swapped as listed, so art drawn in one palette is recolored, as LPC's skin
ramps are. `make-atlas` makes the `Atlas`, a value the application keeps
with the rest of its state; `atlas-pictures` composes the pictures it lacks
in a render pass of the caller's encoder, and `atlas-slot` and
`slot-region` say where each is. `atlas-url` reads a region back as a PNG
data URL, so a HUD's `img` shows a composed portrait.

The host decodes each source image once, and the atlas keeps it. Slots are
placed on shelves; when a picture no longer fits, every page is cleared and
the pictures asked for are placed again. A slot keeps a transparent texel
around its picture, so nearest sampling at its edge never reads a
neighbour; gutters of repeated texels would be needed only for filtered
textures, with mips, which the atlas does not have
([atlas and quads](../graphics/plan.md#atlas-and-quads)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/atlas.sld)

## `(snail shell graphics quad)`

2D quads in world units under a 2D camera (`View2D`), each a rectangle
turned by its angle, showing a region of one page of a texture array,
tinted, over what is drawn before it. `make-quads` makes a `Quads` once for
a texture and a target; `draw-quads` draws a run of `Quad`s as one instanced
draw. Corners snap to the target's pixels in the vertex shader. A `Quads`
draws one run a frame, since its buffers are written before the frame's
commands run, and its instance buffer grows in powers of two.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/quad.sld)

## `(snail shell graphics mesh)`

The geometry table holds eight shapes (`Box`, `Pyramid`, `Prism`, `Sphere`, `Tile`, `Tetrahedron`, `Octahedron` and `Upright`). Each stands on y = 0 in the unit cell. `make-geometry` uploads the shared vertex and index buffers once. `upload-batch` groups instances by shape and uploads the instance buffer. The draw ranges stay on the CPU. `draw-meshes` issues one direct indexed draw per populated shape with its first instance and count. `release-batch` frees the instance buffer.

An instance carries where it is and where it was, for motion, its yaw,
scale, glow, color, metalness and roughness, whether it turns to face the
camera, and an id for picking.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/mesh.sld)

## `(snail shell graphics raster)`

Mesh instances rasterized into a G-buffer, and translucent ones lit at once
over it. A program makes its `Raster` once (`make-raster`: pipelines,
geometry, and the camera's and sun's uniforms), a `GBuffer` for the
canvas's size, and a `Surface` for each batch, remade when the batch
changes. A frame writes the camera and the sun (`write-raster`), draws the
G-buffer (`begin-gbuffer`, `draw-surface`), then opens the lit pass
(`begin-lit`), where `(snail shell graphics passes)` lights it and
translucent surfaces are drawn over it.

The G-buffer holds each pixel's albedo, normal, material (metalness,
roughness and glow) and depth, and, when its `Planes` ask, the screen
motion since the last frame and the id of the instance drawn there, which
`read-id` reads back to pick what a tap is on. A plane left out has no
target and costs nothing. A `Camera3D` carries its view-projection and its
inverse, in closed form for a `Pinhole` or `Parallel` lens, so the lighting
recovers each pixel's position from its depth
([meshes, the G-buffer and the sun](../graphics/plan.md#meshes-the-g-buffer-and-the-sun)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/raster.sld)

## `(snail shell graphics passes)`

Full-screen passes over a G-buffer. `draw-sun`, through a `Sunlight` made
once and relit when the G-buffer is remade, lights each pixel by
Cook-Torrance under the frame's sun, with the same lighting translucent
surfaces get. The lit pass draws into a `light-format` target, `rgba16float`,
so a highlight can be brighter than 1, and `draw-post`, through a `Post`
made for the canvas's format and size, brings it to the screen: tone mapping
by a `Tone`, then FXAA. `Neutral` leaves a color whose largest channel is
under 0.8 as it is, for scenes already in display terms; `Filmic` is John
Hable's curve, for physical light.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/passes.sld)

## `(snail shell graphics fly)`

A camera that flies, +y up. `steered` takes drags, W, A, S, D, Q, E, the
wheel and the exposure keys `[` and `]`; `flown` moves it by the time
elapsed. It starts back from a scene's box with `fly-over`, or where it is
put with `fly-at` and `fly-toward`; `fly-eye`, `fly-target`, `fly-fov` and
`fly-exposure` say where it is and how it sees, and `fly-camera` is the
rasterizer's camera. `upright` stands a scene whose up is another way. The
glTF viewer and the splats viewer share it.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/fly.sld)
