# Radiant Foam

Fit a small Voronoi radiance field, render a held-out camera, and export
a triangle mesh at a chosen density. The synthetic example runs entirely
on the CPU in Snail Scheme. Run from the repository root inside `nix-shell`.

```sh
./snail-scheme run --target node src/apps/foam/main.scm
```

The example fits eight sites to eight views of two colored cells surrounded
by transparent ones. The held-out camera lies halfway between training
angles. In `build/foam/`, compare `target.png`, `before.png`, and
`render.png`. The printed mean squared error averages the three RGB channels
of the held-out view in `[0, 1]`.

`model.foam` stores the sites and their coordinate frame. `surface.obj`
contains the triangulated interfaces between cells with density at least
`threshold` and cells below it, in world coordinates. The default threshold
is 1 per normalized unit of distance. Change it on the same fit or use
`view=1` for a different held-out camera. Loading defaults to zero training
steps. Each run writes a full set of outputs to `out`.

```sh
./snail-scheme run --target node src/apps/foam/main.scm \
  load=build/foam/model.foam threshold=2.3 out=build/foam-level-2.3
```

After the default 500 steps, the synthetic held-out RGB error falls from
0.06086 to 0.00293. Density 1 gives 20 triangles around the two colored
cells. Density 2.3 gives 12 triangles around the denser one. Reloading the saved sites at either
threshold gives byte-identical volume renders.

## Photographs

For an undistorted single-camera COLMAP dataset, supply the same `scene`
directory (ending in a slash) and `images` folder as the 3DGS trainer. Use
the same scene when reloading its model. The existing WebGPU image decoder
reads the photographs. Fitting and rendering run on the CPU. [3DGS dataset setup](../train/README.md)

```sh
./snail-scheme run --target node src/apps/foam/main.scm \
  scene=build/datasets/bicycle/ images=images_4 steps=500 out=build/foam-bicycle
```

Up to 48 sparse points inside the camera bounds seed position and color.
The mean camera center and the trainer's camera extent map world coordinates
into the model cube. The trainer's filename-ordered split holds out every
eighth photograph. Each step samples 96 rays from the training images
on grids up to 48 pixels wide. Evaluation uses one held-out image,
selected by its zero-based `view` index, on a grid up to 96 pixels wide.
On bicycle, 500 steps reduced RGB error on `_DSC8679.JPG` at 96 × 64
from 0.04980 to 0.04172. At this scale the fit captures broad patches
of color and loses the bicycle's fine structure.

The library reference describes the rendering equation, the density mesh,
and how DefTet's occupancy boundary differs. [Radiant Foam in the book](../../../doc/book/libraries/splats.md#snail-shell-graphics-radiant-foam)
