# Radiant Foam

Fit a Voronoi radiance field, render a held-out camera, and export a
triangle mesh at a chosen density. The default backend trains and renders
on WebGPU. A second entry point renders the authors’ trained bicycle
model at photographic resolution. Run the Snail programs from the
repository root inside `nix-shell`. [Render a released model](#render-the-authors-trained-model)

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

## Render the authors’ trained model

The released Mip-NeRF 360 bicycle model contains 4,199,873 sites and
63,719,194 directed neighbor entries. Download its `model.pt` and `config.yaml`.
Convert the checkpoint once in a Python environment with CPU PyTorch and NumPy,
then render in `nix-shell`. Supply the same COLMAP reconstruction used in
training. [Authors’ bicycle checkpoint](https://drive.google.com/drive/folders/1EtHcckGPdVPSQWTB6FrR4WD_2HRSPCve)

```sh
python3 scripts/pack-radfoam.py model.pt build/bicycle-radfoam
./snail-scheme run --target node src/apps/foam/checkpoint.scm \
  checkpoint=build/bicycle-radfoam scene=build/datasets/bicycle/ \
  images=images_4 frames=15 out=build/bicycle-renders
```

The packer applies the checkpoint's softplus density activation and retains
the F32 positions and all 48 color coefficients. It accepts degree-three
models. Pass `--activation-scale` when the checkpoint config specifies a
value other than 1. The bicycle `model.pt` used below has SHA-256
`cd720244c01923037648b92deadcd79295a17395505c2e401de1f16d32fd1a3b`.
The WebGPU program reads the packed files directly. Its largest storage
binding for bicycle is 769 MiB.

By default the program scores every held-out photograph at its decoded
resolution and writes `camera-<COLMAP image ID>.png` for each pose. Set
`views=1` to render the first held-out pose. Optional `frames` measures
the median of consecutive timestamped draws after a warm-up. Camera setup,
readback, scoring and PNG encoding are outside the timed passes.

### How closely does the fitter follow the paper?

The small fitter learns site positions, extinction and one RGB color from
photographs in a clipped cube. It uses a fixed site count, projected gradient
descent on squared RGB error, and a black background. The released trainer
learns degree-three view-dependent radiance, adds sites where position
gradients and cell radii are large, and prunes low-contribution cells.
It uses Adam with separate learning rates, a photometric loss, an opacity
loss and a depth-quantile regularizer. On outdoor scenes its 20,000-step
schedule switches from eighth-size to quarter-size photographs at step
5,000 and targets 4,194,304 sites. The checkpoint renderer can use the
unbounded graph and radiance learned by that trainer.
[Training loop](https://github.com/theialab/radfoam/blob/3e7b52cf74e37ab2ab5e695f53570f515f537e3d/train.py)
· [Scene optimization](https://github.com/theialab/radfoam/blob/3e7b52cf74e37ab2ab5e695f53570f515f537e3d/radfoam_model/scene.py)
· [Outdoor configuration](https://github.com/theialab/radfoam/blob/3e7b52cf74e37ab2ab5e695f53570f515f537e3d/configs/mipnerf360_outdoor.yaml)

## Bicycle measurements

On an RTX 5090, the 256-site command above fit 2,048,000 sampled rays in
2.65 seconds. The CPU backend took 20.31 seconds with the same training
settings. Complete runs from local photographs to the checkpoint, mesh,
and full-size PNGs took 20.27 seconds on the GPU and 55.12 seconds on the CPU.
A larger GPU run used `sites=1024 steps=6000 batch=1024 rate=6`
and took 19.26 seconds to fit.

The table uses all 25 held-out cameras at the native `images_4` size of
1237 × 822. PSNR is averaged over photographs. Frame time is the median
across cameras. The fixed-budget fits used five warmed passes per camera and the released
RadFoam checkpoint used fifteen.
For 3DGS each time includes its compute and draw passes using the existing
trained bicycle checkpoint. [3DGS renderer comparison](../splats/README.md)

| Renderer | Mean held-out RGB PSNR | Median GPU frame |
| --- | ---: | ---: |
| Snail fit, 256 sites | 16.80 dB | 1.28 ms |
| Snail fit, 1,024 sites | 16.93 dB | 4.18 ms |
| Released RadFoam, 4,199,873 sites | 24.13 dB | 12.55 ms |
| 3DGS quads, 4,194,304 Gaussians | 24.98 dB | 3.98 ms |
| 3DGS tiles, same checkpoint | 25.22 dB | 7.04 ms |

PSNR in the table pools RGB mean squared error per image. The
authors’ evaluation averages the three channel PSNRs per image. With that
convention our renderer measures 24.14 dB on the released model. The paper
reports 24.19 dB for bicycle. [Upstream metric](https://github.com/theialab/radfoam/blob/3e7b52cf74e37ab2ab5e695f53570f515f537e3d/radfoam_model/utils.py)
· [ICCV supplement, Table 3](https://openaccess.thecvf.com/content/ICCV2025/supplemental/Govindarajan_Radiant_Foam_Real-Time_ICCV_2025_supplemental.pdf)

As a separate check, the upstream CUDA forward kernel rendered the same
checkpoint from the same 25 COLMAP poses. The largest absolute per-view
RGB PSNR difference from WebGPU was 0.000087 dB. After rounding both
renders to 8-bit RGB, over 99.9999% of channel values agreed within one
level. [Reference CUDA forward kernel](https://github.com/theialab/radfoam/blob/3e7b52cf74e37ab2ab5e695f53570f515f537e3d/src/tracing/pipeline.cu)

Holding the checkpoint's positions, densities, neighbors and constant color
coefficients fixed, zeroing the other 45 floats per site gives **21.97 dB**
pooled RGB. Restoring those coefficients adds **2.15 dB**. The remaining
difference from the small fits combines site count, placement, training
images, background and optimization. On the first held-out photograph,
`_DSC8679.JPG`, the 1,024-site fit scores 14.80 dB. The released foam
scores 20.67 dB and resolves the bicycle frame and spokes. These image
scores evaluate volume rendering. The small fit's density-1 mesh has 7,793
triangles.
