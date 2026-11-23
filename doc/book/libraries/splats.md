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

## `(snail shell graphics radiant-foam)`

Radiant Foam partitions space into convex Voronoi cells. Each site controls
the position of its cell walls and carries a density and radiance. A ray
crossing a cell for distance `d` transmits a fraction `exp(-density * d)`
of the light from behind it. The repository's 3DGS renderer projects
overlapping Gaussians into image-space ellipses and blends their splats.
The paper uses the dual Delaunay graph to walk from cell to cell and can
grow the point set during fitting. [Radiant Foam](https://radfoam.github.io/)

`make-foam` builds a CPU reference for small scenes in the cube
`[-1, 1]³`. Each site carries a position in the cube, finite nonnegative
extinction per model unit, and RGB in `[0, 1]`. Coincident positions share
the first site's material. At box entry, `render-ray` finds the nearest
site. Along the ray the squared distance to every site has the same
quadratic term, so intersecting the remaining straight lines gives the
next cell boundary. Each crossing goes to a site farther along the ray.
The CPU reference considers all `N` sites as candidates at each of `K`
visited cells, taking `O(NK)` work. It composites their contributions
over black. `fit-step` takes a batch of posed RGB samples and returns a new foam.
It differentiates mean squared RGB error through color, extinction, and
the movement of the bisector at each ray crossing. Grazing rays can give
large position gradients, so each batch can move a coordinate by at most
one percent of the box width. The prototype uses
view-independent RGB and a fixed site budget.

### Which surface does the mesh describe?

The foam supplies the geometry of every **volume cell**. Choosing a density
threshold gives one possible **object surface**. `density-faces` intersects
the bisectors separating cells on opposite sides of that threshold with
the other half-spaces. The resulting convex polygons face the sparser
cell. The demo triangulates these polygons and welds shared vertices for
OBJ export. Interfaces that reach the clipping box end there. Density
can also be spread through translucent material or concentrated in
disconnected patches, so a fitted image alone does not establish a
watertight physical object. The paper uses a regularizer to encourage
surface-like densities. [Radiant Foam paper, §3.3](https://openaccess.thecvf.com/content/ICCV2025/papers/Govindarajan_Radiant_Foam_Real-Time_Differentiable_Ray_Tracing_ICCV_2025_paper.pdf)

DefTet starts with a tetrahedralization, learns displacements for its
shared vertices, and predicts an occupancy for each tetrahedron. Once those
occupancies are classified, shared triangular faces between occupied and
empty tetrahedra directly form the object's boundary. Radiant Foam's
Delaunay tetrahedra play a different role. Their edges connect neighboring
Voronoi sites, and those neighbors can change as the sites move.
[DefTet](https://research.nvidia.com/labs/toronto-ai/DefTet/) · [Radiant Foam](https://radfoam.github.io/)

Run the synthetic fit with `./snail-scheme run --target node src/apps/foam/main.scm`.
The application also reads the splat trainer's COLMAP datasets and can
export other thresholds from a saved fit. [Run the prototype](https://github.com/tsnl/snail-scheme/blob/main/src/apps/foam/README.md)

## `(snail shell graphics radiant-foam-gpu)`

`make-device-foam` uploads the CPU model's sites as floats. Sixteen sites
near one another in Morton order share a bounding box. At a cell entry
the current site is nearest. The squared-distance difference between it
and any other site is affine along the ray. If a group's box is farther
away than the current site at the candidate exit, that group can supply
no earlier crossing. The shader uses this test to skip groups and checks
the remaining bisectors directly.

`make-foam-view` allocates a camera uniform and a storage buffer of RGBA
floats. `write-foam-camera!` changes the pose or intrinsics.
`dispatch-foam-view` generates the pinhole rays and composites a frame in
a caller's compute pass. Another pass can consume the view's `pixels`
buffer directly. `read-foam-view` transfers the image when CPU RGB is needed.

`make-foam-trainer` uploads posed training rays once. `train-foam!` takes
the first step's seed, step count, and learning rate. The CPU reference and
GPU sample the same ray indices at each step. Each training ray caches its
first sixteen cell exits and recomputes any later exits for the backward
pass. Gradients pass through both materials and moving Voronoi faces.
The update applies projected gradient descent and refits every group's
bounds on the GPU. The training loop batches up to 32 updates per
submission without reading intermediate parameters.

`read-foam` returns sites in checkpoint order for export or inspection.
Release views and trainers when finished, then release the device foam.
The application measures both backends on Mip-NeRF 360 bicycle.

### Rendering a trained RadFoam checkpoint

`open-foam-checkpoint` takes a GPU, a function that reads each of the four
packed model files, and the output width and height. Sites retain their
COLMAP world coordinates. Each stores extinction per world unit and sixteen
RGB spherical-harmonic coefficients. The checkpoint supplies the Delaunay
edges as neighbor IDs and one range of edges per site. The loader checks the
ranges and indices, uploads the buffers, and caches the displacement across
each edge at the same half precision as the authors' renderer.

`set-checkpoint-camera!` locates the cell containing the pinhole once per
pose. Across a violated Voronoi face the neighboring site is closer to the
eye, so following successively closer neighbors reaches its cell.
`dispatch-foam-checkpoint` generates one ray per pixel. Each ray crosses the
nearest front-facing neighbor bisector, evaluates degree-three color along
its viewing direction, and composites the finite interval. An open cell
with no exit contributes no interval. The residual transmittance reveals
white. The reference stops at transmittance 0.001 or 1,024 visited cells.
`read-foam-checkpoint` returns the clamped floating-point RGB frame.
`release-foam-checkpoint` frees the scene and its frame buffers.

The application includes the one-time packer for the authors' `model.pt`
and scores its renders on the same held-out photographs as the small
from-scratch fitter.
[Application and measurements](https://github.com/tsnl/snail-scheme/blob/main/src/apps/foam/README.md)
