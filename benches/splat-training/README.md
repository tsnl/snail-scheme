# Splat training against the reference trainers

How long the train app ([`src/apps/train`](../../src/apps/train/README.md))
takes to train 3D Gaussian Splatting on a Mip-NeRF 360 scene, and how
well, against two reference trainers on the same GPU:

- **gsplat**, Nerfstudio's CUDA library (Ye et al., 2024), the fastest
  widely used reproduction of the method, at its latest commit, since its
  latest release does not train the method (below);
- **the INRIA code**, the method's reference implementation (Kerbl et al.,
  2023), at its latest commit.

## Running it

```sh
benches/splat-training/compare
```

The scene is Mip-NeRF 360's bicycle, the one the train app links
([datasets](../../doc/book/libraries/datasets.md)). `setup` runs
`dataset.scm`, which reads bicycle's files into the machine's cache as the
train app's build does, its full-size photographs too, which gsplat lists,
and links them into the bench's scene. `compare` sets up the reference
trainers (`setup`), trains each trainer twice, taking turns (`train`), then
scores every run the same way and writes the table (`score`). Everything it makes is in
`build/benches/splat-training`: the trainers' sources and environments,
the scene, each run's console, GPU samples and outputs under `runs/`, and
`report.md`. Each script can also be run alone; its header says how.
The first `setup` takes about an hour, most of it compiling gsplat's
kernels; the runs and the scores take about two and a half hours more.

The reference trainers are PyTorch programs that compile CUDA kernels as
they install. `default.nix` gives them CUDA 12.9, the GCC that CUDA
release supports and Python 3.12 from the repository's pinned nixpkgs, in
an FHS environment. pip installs each trainer's packages into a virtual
environment of its own, at the versions `requirements-*.txt` pins, as the
trainers' own instructions do, with PyTorch 2.9.1, which gsplat pins, for
both: the INRIA code names PyTorch 1.12, which predates the RTX 5090.
`nix-shell benches/splat-training` enters that environment. The train
app runs in the repository's own shell.

## What is the same

- **The photographs.** bicycle's quarter-size photographs, `images_4`, at
  1237 by 822, with every eighth, in order of name, held out. gsplat would
  downscale the full photographs itself, to 1236 by 822, so `setup` gives
  it `images_4` as PNG, under the name it looks for.
- **The method.** 30,000 steps of the paper's schedule: densifying every
  100 steps from step 500 to 15,000 at its thresholds, resetting opacity
  every 3,000 steps, and raising the harmonics' degree every 1,000. Each
  reference trainer runs as its own benchmark runs it: gsplat's
  `simple_trainer.py default` as `examples/benchmarks/basic.sh` does, and
  the INRIA code's `train.py` as `full_eval.py` does. None evaluates while
  it trains.
- **The clock.** Each trainer's own, from its loop's first step to its
  last, which leaves out loading the scene and evaluating.
- **The scores.** The INRIA code's `metrics.py` scores every run at once:
  PSNR, SSIM, and LPIPS with VGG, against the held-out photographs as its
  loader decodes them. Each trainer renders its own views, except the
  train app, which writes no images: its cloud, a `.ply` file in the INRIA
  code's format, is rendered by the INRIA code's `render.py`, whose PSNR
  agrees with the train app's own to three thousandths of a decibel.

`setup` changes one line in each reference trainer. gsplat writes its
renders cut to 8 bits, where torchvision, which writes the others, rounds;
cut, they would lose PSNR, more the darker they are, so gsplat rounds too,
and its scores then match those it reports itself. The INRIA rasterizer's
header uses fixed-width integers without including `<cstdint>`, which
GCC's headers stopped including along the way in GCC 13, so it includes it.

## What differs

- **The cap on gaussians.** The train app stops growing the cloud at
  4,194,304 gaussians, its default, and reaches it at step 10,300. Its
  programs make 6.6 GB at that capacity, and every kernel over the
  gaussians covers every row of it, live or not; the next capacity,
  8,388,608, would take 13 GB and double those rows. The reference
  trainers have no cap, so from there on they train more gaussians than
  it does.
- **gsplat's camera.** gsplat's loader divides the camera by 4, sizes
  the photographs by whole division, 4946 // 4 = 1236, then scales the
  camera by their real size, 1237 by 822. Its camera comes out 0.04%
  wider and 0.06% taller than the photographs, so its views sit up to
  half a pixel off them at the right and bottom edges, in training and in
  its evaluation alike. The quarter-size photographs gsplat makes itself,
  1236 by 822, are off by as much. The INRIA code's camera and the train
  app's fit the photographs. Trained once with its loader sizing them by
  `cam.width / factor`, which fits its camera to them, gsplat scored a
  PSNR of 25.29, SSIM 0.769 and LPIPS 0.203 in 620 seconds.
- **Saving.** Each reference trainer saves its cloud at step 7,000
  inside its timed loop, as its benchmark does: the INRIA code's save
  takes about 11 seconds and gsplat's about half a second. The train app
  saves nothing until the end.
- **The API.** The train app runs on WebGPU, through Dawn on Node; the
  reference trainers run on CUDA.

## Results

The runs were on 2026-11-22, on an RTX 5090 (driver 595.104, at its
600 W limit) beside an Intel Core Ultra 7 270K Plus. gsplat at 512d366b
and the INRIA code at 54c035f ran on PyTorch 2.9.1 for CUDA 12.8, two
runs each, taking turns. The train app at 641327b22 ran on Node 26.8.1
and Dawn (the `webgpu` package 0.6.2) over Vulkan. It ran once, after
them: its two runs in the first comparison (below) finished 4 seconds
and 0.001 dB apart.

| Run | Seconds | Gaussians | Peak MiB | PSNR | SSIM | LPIPS | Own PSNR |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gsplat-1 | 626.2 | 6,381,922 | 13,326 | 25.118 | 0.7631 | 0.2062 | 25.120 |
| gsplat-2 | 626.1 | 6,395,089 | 14,540 | 25.187 | 0.7643 | 0.2055 | 25.189 |
| inria-1 | 1027.0 | 4,896,996 | 14,948 | 25.208 | 0.7654 | 0.2085 | |
| inria-2 | 1032.0 | 4,929,436 | 14,120 | 25.245 | 0.7653 | 0.2096 | |
| ours, one run | 857.5 | 4,194,304 | 10,759 | 25.287 | 0.7643 | 0.2119 | 25.289 |

| Run | Seconds to 7,000 | Gaussians at 7,000 |
| --- | ---: | ---: |
| gsplat-1 | 70.3 | 3,769,144 |
| gsplat-2 | 70.8 | 3,788,424 |
| inria-1 | 132.0 | 3,250,034 |
| inria-2 | 133.0 | 3,255,640 |
| ours, one run | 152.6 | 3,250,768 |

The INRIA code takes 1.20 times as long as the train app to train
bicycle, to a held-out PSNR 0.06 dB lower: 25.23 on average, against
25.29. gsplat takes 73% of the train app's time, to 25.15. The train
app's LPIPS is the highest of the three, 0.212 against 0.209 and 0.206,
from the smallest cloud. gsplat's camera costs it about 0.14 dB: fitted
to the photographs, it scores 25.29 (above).

Up to step 7,000 the train app and the INRIA code densify alike, to 3.25
million gaussians, and the INRIA code takes 87% of the train app's time.
gsplat's cloud grows 16% larger by then, and it takes 46%. After step
7,000 the INRIA code's cloud grows on to 4.9 million, and its steps
average 39 ms against the train app's 30.6 ms.

A step's time shows where the gap to gsplat opens. gsplat's grows with
its cloud: 7.3 ms at 1.1 million gaussians, 18.1 ms at 4.2 million and
25.0 ms at 6.4 million. The train app's barely grows: 26.2 ms at 1.2
million and 30.6 ms at 4.2 million. From step 2,700 its programs are made
for 4,194,304 gaussians, however many are live, and every kernel over
the gaussians runs over every row of that capacity. Sizing those kernels
to the live rows is the next step of
[#891](https://github.com/tsnl/snail-scheme/issues/891). Even at the cap, with every
row live, a step takes 1.7 times gsplat's at the same number of
gaussians.

The train app's peak memory lasts a moment: about a second at step
2,700, while it moves the cloud into the larger programs. From then on
it holds about 6,700 MiB. The reference trainers' peaks come with their
largest clouds.

### Since the first comparison

The first comparison was the same morning, at 204ce650f. Each change
after it was measured with one run of this bench:

| Train app | Seconds | Seconds to 7,000 | Peak MiB | PSNR |
| --- | ---: | ---: | ---: | ---: |
| First comparison, two runs | 1369.3, 1373.1 | 239.6, 238.3 | 16,944, 17,104 | 25.271, 25.272 |
| Binning keeps to the tiles a gaussian reaches ([#894](https://github.com/tsnl/snail-scheme/pull/894)) | 1295.9 | 233.1 | 15,214 | 25.317 |
| Updates are written in place ([#895](https://github.com/tsnl/snail-scheme/pull/895)) | 1191.4 | 212.1 | 13,694 | 25.278 |
| A device-computed count sizes the tile sort ([#896](https://github.com/tsnl/snail-scheme/pull/896)) | 1094.4 | 195.6 | 13,118 | 25.274 |
| The radix sort takes eight bits a pass ([#897](https://github.com/tsnl/snail-scheme/pull/897)) | 1077.8 | 191.1 | 13,697 | 25.274 |
| A gradient's parts are joined, not placed ([#898](https://github.com/tsnl/snail-scheme/pull/898)) | 857.5 | 152.6 | 10,759 | 25.287 |
| Adam's updates of a param are one kernel ([#911](https://github.com/tsnl/snail-scheme/pull/911)) | 797.9 | 144.8 | 10,792 | 25.275 |
| A map writes what later kernels read ([#914](https://github.com/tsnl/snail-scheme/pull/914)) | 788.7 | 140.7 | 10,888 | 25.270 |
| The harmonics' basis is one map, and so is its gradient ([#915](https://github.com/tsnl/snail-scheme/pull/915)) | 686.2 | 119.4 | 10,887 | 25.287 |

A run is not deterministic: the backward pass adds each gaussian's
gradients in whatever order its threads arrive. Two runs of one trainer
here differ in PSNR by up to 0.07 dB.

## gsplat's release

gsplat's latest release, 1.5.3 of July 2025, decides when to reset
opacity with `step % reset_every == 0 & step > 0`. Python binds `&`
tighter than `==`, so that reads `step % reset_every == (0 & step) > 0`,
which is never true: the release never resets opacity, so it never prunes
the gaussians that a reset would have left faint. Its main branch fixed
the test a month later (#776), in no release yet. Trained here as
released, its cloud grew to 8,230,817 gaussians in 1,047 seconds, and it
scored a held-out PSNR of 24.05, SSIM 0.740 and LPIPS 0.222; the paper
reports a PSNR of 25.25.
