# Train

3D Gaussian Splatting (Kerbl et al., 2023) trained in the page on a COLMAP
scene, with `(snail shell graphics splat-fit)` on the tensor library
([tensors](../../../doc/book/graphics/tensors.md#training-on-photographs)).
The page fetches the scene's photographs and sparse reconstruction, starts
a gaussian at each sparse point, and trains for the reference's 30,000
steps, densifying as it does; every fiftieth step's image is drawn on the
canvas, and the console reports the loss every hundred. Every eighth
photograph, in order of name, is held out, and the PSNR on those is
reported at the end.

```sh
scripts/fetch-mipnerf360 bicycle
./snail-scheme build --release --target browser src/apps/train/main.scm
python3 -m http.server 4194 --directory build
```

`scripts/fetch-mipnerf360` downloads Mip-NeRF 360's 12.5 GB archive into
`~/.cache/snail-scheme/datasets`, extracts the scene and links it at
`build/datasets/bicycle`, beside the page. Open
`http://127.0.0.1:4194/src/apps/train/main/` in a browser with WebGPU and
its `subgroups` feature. The query chooses:

- `scene`, the scene's URL, by default `/datasets/bicycle/`, holding
  `sparse/0/{cameras,images,points3D}.bin` and the photographs;
- `images`, the folder of photographs within it, by default `images_4`,
  a quarter as wide as the originals, at which the paper trains Mip-NeRF
  360's outdoor scenes (its indoor scenes at `images_2`);
- `steps`, by default 30000;
- `gaussians`, the most the cloud may hold, by default 4194304: the
  programs make about 3.3 KB a gaussian, 14 GB at the default; past it,
  densification adds only what fits;
- `profile=1`, which first runs one step's kernels one at a time and
  prints the slowest and the largest buffers; `steps=0` then trains none.

On bicycle, 30,000 steps take 33 minutes in Chromium on an RTX 5090 and
reach a held-out PSNR of 25.30; the paper reports 25.25.

The page decodes every photograph into a texture before training, so a
scene must fit the device beside the step's buffers. Bicycle's 194
photographs at full resolution, 4946x3286, take 12.6 GB as textures; with
the step's buffers, whose entries grow with the pixels, they ran out of a
32 GB RTX 5090's memory by step 7,300.

COLMAP's cameras must be pinholes: undistort the photographs first, as
Mip-NeRF 360's are.
