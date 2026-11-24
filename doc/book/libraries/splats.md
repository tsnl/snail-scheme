# Gaussian splats

3D Gaussian Splatting (Kerbl et al., 2023), drawn two ways and trained on
photographs. `splat` draws gaussians as sorted quads, the fast way to view
a cloud; `splat-train` is the differentiable renderer, drawing tile by tile,
that training descends through, and `splat-view` draws a cloud with it, as
training saw it. `src/apps/splats` views clouds and `src/apps/train` trains
them ([scans, sorts and gaussian splats](../graphics/plan.md#scans-sorts-and-gaussian-splats),
[tensors and training](../graphics/tensors.md)).

## `(snail shell graphics splat)`

Gaussians as middleware: a storage buffer of `Gaussian` `Pod` records, each
placed by its row of a transforms table, projected to screen-space ellipses
by a compute pass (EWA splatting, with spherical harmonics to degree 3),
sorted far to near by `(snail shell graphics radix-sort)`, and blended in one
instanced draw. A program makes its `Splats` once (`make-splats`) with room
for its gaussians and transforms, writes `Cloud`s where it likes
(`write-cloud`, `pack-cloud`) and writes the transforms whenever they move
(`write-transforms`), so clouds are posed and composed without touching
their gaussians. A frame is `sort-splats` in a compute pass and
`draw-splats` in a render pass, both the caller's.

A `Gaussian` keeps its center as floats and its rotation and its scale
with its opacity as f16s (`Vec4h`), 32 bytes a record; `cloud-gaussian`
reads one back. Each gaussian's 16 colors of coefficients are f16s two to
a 32-bit word
(`harmonic-words`, 26 a gaussian), each degree from a word of its own,
so that color k's three start at the word's half 3k plus its degree
(`harmonic-half`). `write-harmonics!` rounds a gaussian's floats into
them, and `cloud-coefficient` reads one back.

Gaussians a program has not written are zero, so transparent and culled.
`write-cloud` sends a cloud 65,536 gaussians at a time, since a write's
bytes are copied whole into the runtime's memory on their way and a trained
scene's run to a gigabyte.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/splat.sld)

## `(snail shell graphics ply)`

The PLY files 3D Gaussian Splatting trains: `read-ply` reads one into a
`Cloud` for `splat`, its header parsed into where each property sits and
each gaussian activated (scales through `exp`, opacity through the
sigmoid, the quaternion normalized), every gaussian on one row of the
transforms table, so a file is one posable cloud. `write-ply` writes a
`Trained` cloud as the reference implementation would, properties in its
order and nothing activated, so what reads the reference's files reads
these.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/ply.sld)

## `(snail shell graphics colmap)`

COLMAP's sparse reconstructions, `cameras.bin`, `images.bin` and
`points3D.bin`: each camera's intrinsics (`read-cameras`), each image's pose
and file name (`read-images`), and each point's position and color
(`read-points`). A pose maps the world into the camera, with +z forward and
+y down the image. Only the undistorted models training draws through are
read, `SIMPLE_PINHOLE` and `PINHOLE`; a distorted one is refused.
`camera-sized` scales a camera to the size of the photographs actually
loaded, each axis by its own ratio, and `poses-up` is the mean of the
cameras' ups, the up a reconstruction lacks.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/colmap.sld)

## `(snail shell graphics splat-view)`

A `Splats`'s gaussians drawn tile by tile, by `splat-train`'s graph
rendered for viewing, lowered to a program that reads the splats' own
buffers, so writing a cloud or its transforms changes what both draw.
`make-splat-view` makes it, `write-view-camera` writes the camera the quads
use, `encode-splat-view` projects, bins and blends in the caller's compute
pass, and `present-splat-view` puts the image on the caller's target.

It blends front to back in floats over black, stopping where a pixel's
transmittance would fall under 1e-4, as training does; the quads blend back
to front in the target's precision. So it is closer to the photographs a
cloud was trained on, and slower
([the measurements](../graphics/plan.md#scans-sorts-and-gaussian-splats)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/splat-view.sld)

## `(snail shell graphics splat-train)`

Gaussian splatting as a differentiable tensor graph. `render` draws a
`Cloud` of params (`splat-params`) from a camera param (`camera-param`, 16
floats in COLMAP's convention) into an image of a `Sensor`'s size, for
`Training` or `Viewing`, and `grad` differentiates its loss back to every
param (`cloud-views`); `photometric-loss` is L1 with D-SSIM.

Projection is ordinary tensor operations, so its gradient is derived.
Binning into 16x16-pixel tiles is custom kernels around a sort by depth and
a stable sort by tile, and passes no gradient; rasterizing and SSIM are
custom nodes with hand-written adjoints. The sensor's capacity bounds the
tile entries, and the entries asked for are counted on the device, so the
tile sort and the ranges cover only those
([differentiable splatting](../graphics/tensors.md#differentiable-splatting)).

Tiles are `tile-side`, 16, pixels a side, as gsplat's are. Smaller tiles
spend less blending on pixels a gaussian misses, but on bicycle on an RTX
5090 they cost more than they saved. 8-pixel tiles took the backward
rasterizer at step 7,000 from 4.26 ms to 3.39, but the run reached that
step in 136 s against 117, since early gaussians are large and binning
walks every tile each one reaches, a thread a gaussian. 4-pixel tiles took
302 s, and slowed the viewer's frame from 6.7 ms to 11.0, of which
binning's two kernels took 6.3.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/splat-train.sld)

## `(snail shell graphics splat-fit)`

Fitting a cloud to photographs, as three tensor graphs a host lowers once
for a capacity of gaussians and runs on one set of params:
`training-step`, the loss against a target photograph, Adam's step on every
param and the statistics densification decides by; `densification`, which
clones small gaussians and splits large ones whose screen-space gradient is
large, prunes the transparent and the huge, and lays the cloud out again,
kept rows first; and `opacity-reset`. Every row of every param is a
gaussian, and `live` says which are drawn, so a cloud grows within its
capacity. The schedule is the host's
([training on photographs](../graphics/tensors.md#training-on-photographs)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/splat-fit.sld)
