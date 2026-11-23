# Train

3D Gaussian Splatting (Kerbl et al., 2023) trained on a COLMAP scene, with
`(snail shell graphics splat-fit)` on the tensor library
([tensors](../../../doc/book/graphics/tensors.md#training-on-photographs)).
It reads the scene's photographs and sparse reconstruction, starts a
gaussian at each sparse point, and trains for the reference's 30,000
steps, densifying as it does; the console reports the loss every hundred.
Every eighth photograph, in order of name, is held out, and the PSNR on
those is reported at the end.

It runs on Node or in a page. `scripts/fetch-mipnerf360 bicycle` downloads
Mip-NeRF 360's 12.5 GB archive into `~/.cache/snail-scheme/datasets`,
extracts the scene and links it at `build/datasets/bicycle`.

## On Node

```sh
./snail-scheme build --release --target node src/apps/train/node.scm
node build/src/apps/train/node/main.mjs scene=build/datasets/bicycle/ cloud=bicycle.ply
```

The GPU is the one Dawn finds, the photographs are decoded by `@napi-rs/canvas`
([WebGPU on Node](../../../doc/book/graphics/plan.md#webgpu-on-node)), and
nothing is shown. The arguments are the settings below, and `scene` is the
scene's folder, ending in a slash.

`cloud=PATH` keeps what was trained: the `.ply` file the reference
implementation writes, each gaussian's center, a zero normal, its
harmonics, its opacity's logit, its log scales and its quaternion, 248
bytes a gaussian. [Splats](../splats/README.md) flies through it, given the
scene's `sparse/0/images.bin` for which way is up, and so does any viewer
of the reference's files. Without `cloud`, nothing is kept but the report.

## In a page

```sh
./snail-scheme build --release --target browser src/apps/train/main.scm
python3 -m http.server 4194 --directory build
```

Open `http://127.0.0.1:4194/src/apps/train/main/` in a browser with WebGPU
and its `subgroups` feature. Every fiftieth step's image is drawn on the
canvas. The page's query gives the settings, and `scene` is the scene's
URL, by default `/datasets/bicycle/`, beside the page.

## The parts

- `trainer.sld` is the trainer, and knows no file, address or format. It
  trains on a `Scene`, the camera, the posed views and the sparse points
  as data. It asks its `Photographs` for a view's photograph, on the
  device, as a step needs it, and answers what it trained, which
  `trained-cloud` reads back from the device as arrays.
- `dataset.sld` is a COLMAP dataset as such a scene: the settings below,
  where its files are, the decoding, and which photographs are held out.
- `main.scm` and `node.scm`, the page and the program on Node, say how a
  file's bytes are had, fetched or read, and what is kept: on Node, the
  cloud, written by `(snail shell graphics ply)`.

A program with a scene of another kind, made or embedded, calls the
trainer alone: it builds the `Scene` with `make-scene`, and handles
`photographs` with a texture of its own for each view asked for.

## Settings

- `scene`, the scene's address, holding
  `sparse/0/{cameras,images,points3D}.bin` and the photographs;
- `images`, the folder of photographs within it, by default `images_4`,
  a quarter as wide as the originals, at which the paper trains Mip-NeRF
  360's outdoor scenes (its indoor scenes at `images_2`);
- `steps`, by default 30000;
- `gaussians`, the most the cloud may hold, by default 4194304: the
  programs make about 1.9 KB a gaussian, 8.2 GB at the default; past it,
  densification adds only what fits;
- `profile=N`, which times step N's kernels on the device, running the
  step a second time, and prints the slowest and the largest buffers:
  `profile=1 steps=1` for the first, `profile=7000` once the cloud has
  grown, the run going on after it.

## Photographs

A photograph is on the device only around the step that trains on it. It
is read and decoded four steps ahead, in a task of its own, and let go
after its step, so the device holds five photographs, not the scene's.
Bicycle's 194 at full resolution, 4946x3286, would take 12.6 GB as
textures. The scene is asked for a photograph each time a step trains on
it, so a page's scene should be near, or cached.

## Results

On bicycle at `images_4`, on an RTX 5090, 30,000 steps take 18.0 minutes
on Node and reach a held-out PSNR of 25.28; the paper reports 25.25.
[`benches/splat-training`](../../../benches/splat-training/README.md)
trains the reference implementation and gsplat beside it on the same GPU.

At full resolution, `images=images`, the step's own buffers are the limit,
not the photographs. Before binning kept to the tiles a gaussian reaches,
with the default 4,194,304 gaussians, its entries reached 2^27 near step
6,500, and the larger programs no longer fit a 32 GB device beside the
cloud's 14 GB. A smaller cloud left them room: with `gaussians=2097152`,
the 30,000 steps took 48 minutes on Node, the entries grew to 2^27, and
the held-out PSNR at 4946x3286 was 23.76. The paper trains this scene at
a quarter of that width, so it has no number to set beside this one.

COLMAP's cameras must be pinholes: undistort the photographs first, as
Mip-NeRF 360's are.
