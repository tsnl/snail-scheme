# Radiant Foam

Fit a Voronoi radiance field, render a held-out camera, and export a
triangle mesh at a chosen density. The default backend trains and renders
on WebGPU. Run from the repository root inside `nix-shell`.

```sh
./snail-scheme run --target node src/apps/foam/main.scm
```

The synthetic example fits eight sites to eight views of two colored cells.
The held-out camera lies halfway between training angles. In `build/foam/`,
compare `target.png`, `before.png`, and `render.png`. RGB mean squared error
averages the three channels in `[0, 1]`. Use `backend=cpu` for the F64
reference. The synthetic CPU run works without a GPU.

`model.foam` stores the sites, world-space center, and radius. Both backends
read the same checkpoints. `surface.obj` contains triangulated faces between
cells on opposite sides of the density threshold, in world coordinates.
The default threshold is 1 per normalized unit of distance. Loading a
checkpoint defaults to zero training steps, so the density threshold and
camera can be changed on a single fit.

```sh
./snail-scheme run --target node src/apps/foam/main.scm \
  load=build/foam/model.foam threshold=2.3 view=1 out=build/foam-level-2.3
```

## Photographs

Supply an undistorted single-camera COLMAP `scene` directory ending in a
slash and its `images` folder. The foam and 3DGS trainers use the same
photographs, intrinsics, poses, and filename-ordered split. Every eighth
image is held out. Use the same scene when loading its checkpoint.
[3DGS dataset setup](../train/README.md)

```sh
./snail-scheme run --target node src/apps/foam/main.scm \
  scene=build/datasets/bicycle/ images=images_4 sites=256 \
  steps=4000 batch=512 rate=3 width=1237 frames=15 out=build/foam-bicycle
```

| Argument | Default | Meaning |
| --- | ---: | --- |
| `sites` | 48 | Maximum number of sparse COLMAP points used to seed a new photographic model |
| `steps` | 500 | Projected gradient updates for a new fit |
| `batch` | 96 | Training rays sampled with replacement per update |
| `rate` | 1.0 | Learning rate for the mean squared RGB loss |
| `view` | 0 | Zero-based index in the held-out split |
| `width` | 96 | Held-out image width, up to its native width |
| `frames` | 0 | Warmed passes for the median GPU frame time on a device with timestamp queries |

Training photographs are sampled on grids up to 48 pixels wide. Every
sample uses the original pixel center and its observed RGB. The GPU
keeps these training rays resident, accumulates gradients for site position,
extinction and color, and refits the spatial bounds after each update.
The fitting timer includes minibatch selection, command submission, and
waiting for the final update. Photograph decoding, the initial upload,
checkpoint readback, PNG writing, and CPU mesh export happen outside it.
Floating-point atomic sums can round differently across runs.

The frame timer includes pinhole ray generation and volume compositing into
a device buffer. Readback and PNG encoding happen after the timed pass.
Changing the camera uploads 80 bytes. The library reference covers the
ray traversal, density mesh, and DefTet comparison.
[Radiant Foam in the book](../../../doc/book/libraries/splats.md#snail-shell-graphics-radiant-foam)

## Bicycle measurements

On an RTX 5090, the 256-site command above fit 2,048,000 sampled rays in
2.65 seconds. The CPU backend took 20.31 seconds with the same training
settings. Complete runs from local photographs to the checkpoint, mesh,
and full-size PNGs took 20.27 seconds on the GPU and 55.12 seconds on the CPU.
A larger GPU run used `sites=1024 steps=6000 batch=1024 rate=6`
and took 19.26 seconds to fit.

The table uses all 25 held-out cameras at the native `images_4` size of
1237 × 822. PSNR is averaged over photographs. Frame time is the median
across cameras. For foam each camera was timed over five warmed passes.
For 3DGS each time includes its compute and draw passes using the existing
trained bicycle checkpoint. [3DGS renderer comparison](../splats/README.md)

| Renderer | Mean held-out RGB PSNR | Median GPU frame |
| --- | ---: | ---: |
| Radiant Foam, 256 sites | 16.80 dB | 1.28 ms |
| Radiant Foam, 1,024 sites | 16.93 dB | 4.18 ms |
| 3DGS quads, 4,194,304 Gaussians | 24.98 dB | 3.98 ms |
| 3DGS tiles, same checkpoint | 25.22 dB | 7.04 ms |

On the first held-out photograph, `_DSC8679.JPG`, both foam fits recover
broad patches of color. The bicycle frame and spokes are visible in the
3DGS render. The 1,024-site foam exported 7,793 triangles at density 1.
These models use a fixed site budget and one RGB color per site.
