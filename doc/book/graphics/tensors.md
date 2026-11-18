# Tensors and training

`(snail shell tensor)` is a GPU tensor library in the shape of
[Resin](https://github.com/tsnl/resin)'s: a program builds a lazy graph of
nodes, rewrites it symbolically for gradients and optimizer steps, and
compiles it explicitly into WebGPU work that runs as often as a training
loop likes, on the page or on Node ([WebGPU on Node](plan.md#webgpu-on-node)).
All four libraries are **implemented**:

| Library | Provides |
| --- | --- |
| `(snail shell tensor)` | Nodes, ports and views; the operations that build them |
| `(snail shell tensor grad)` | `grad`: reverse-mode gradients as more graph |
| `(snail shell tensor adam)` | `adam-updates`: Adam's step as more graph |
| `(snail shell tensor compile)` | `compile-program`: buffers, kernels and their order |
| `(snail shell tensor eval)` | `evaluate`: the same graph on the CPU, the specification |

## Graphs and views

A node computes one dense buffer for each of its ports. Programs work with
views, each an accessor over a port: an offset, a shape, and a pitch for
each axis, in elements. So `narrow`, `transpose`, `permute`, `squeeze`,
`unsqueeze` and `broadcast-to` make no node; a pitch of 0 repeats an element
along its axis. Binary operations broadcast as NumPy's do, and `View` is an
instance of `Num` and `Fractional`, so `(+ a b)` and `(sqrt v)` build
nodes.

| Kind | Computes |
| --- | --- |
| `Param`, `Constant`, `Fill` | A buffer the host writes, bytes given at build time, one value everywhere |
| `Elementwise` | One of 30 operations (`Op`) on broadcast operands |
| `Reduce` | A sum, maximum or minimum over axes, which keep size 1 |
| `Matmul` | `(..., m, k)` by `(..., k, n)` |
| `Copy`, `Place` | A view made dense; a gradient placed at a view's addresses |
| `Gather`, `ScatterAdd` | Rows by `u32` index, and their adjoint |
| `Concat` | Views joined along an axis; `stack` joins them along a new one |
| `Sort`, `PrefixSum` | `u32` keys and values sorted stably; an exclusive prefix sum |
| `CustomKind` | Kernels a library writes in WGSL, with their own adjoint |

A node is known by its key, a 64-bit hash of its kind, its parameters, its
ports and its arguments' keys and accessors. The language has no reference
equality, and content addressing gives more: building the same computation
twice builds the same node, so a graph shares its common parts, and a param
is known by its name and shape. A constant snapshots its input bytes and
includes them in its key, so constants can reuse a label across uploads.

## Gradients and Adam

`(grad loss wrt)` walks the nodes the scalar `loss` depends on from last to
first, as Resin's `grad` does. Each kind answers the gradient of each
argument given the gradients of its ports, and a custom node answers with
its own adjoint. A view's gradient reaches its port through the view's
accessor: it is summed over the axes the view broadcasts, then reshaped
when the view reads its whole port in order, or placed at the addresses it
reads otherwise. Sorts, prefix sums, comparisons and bit operations pass no
gradient. A custom node's adjoint that needs the node's other ports, as a
backward pass needs what its forward pass kept, builds the same node again
from its arguments, and content addressing gives back the node itself.

`(adam-updates prefix settings trained)` builds Adam's step for each
`Trained` param, gradient and rate, the rate being a view so a schedule is
a param the host writes. The moments and the step count are params named
under `prefix` (`moment-names`). They start at zeros, as every buffer does,
and a host may write them, as densification does when it changes how many
gaussians a param holds.

## Compiling and running

`(compile-program label sinks updates)` turns what the sinks and updates
need into a `Program`, once. Sinks are views to read back; updates are
pairs of a whole param and the value it takes after the run. Both need
the same element count and element type. Use `convert` for a numeric
conversion or `bitcast` to reinterpret the stored bits. Every sink and
update reads the params as they were at the start of the step. Two params
can swap values in one run, and an update can initialize a param that no
sink reads.

```scheme
(let ((program (compile-program "fit" (list loss) (adam-updates "adam" settings trained))))
  (write-param program "points" bytes)
  (for-each (lambda (_) (run-program program)) (iota 1000))
  (read-sink program 0))                 ; loss used by the last update
```

Each node's kernel is generated as WGSL text whose shapes, pitches and
offsets are literals, a thread per output element, so two nodes that
compute alike share a pipeline. A `Fill` argument is a literal too and gets
no buffer. A reduction over more than 256 elements runs in levels: a
workgroup reduces each part of 4,096 elements in shared memory until one
part is left. A float `ScatterAdd` adds with a compare-and-swap loop. Sorts
and prefix sums run on the `radix-sort` and `scan` middleware ([the WebGPU
design](plan.md#scans-sorts-and-gaussian-splats)). Every dispatch is in one
compute pass, so each sees the writes of those before it, and dispatches of
more than 65,535 workgroups are laid out in rows.

A kernel binds at most the eight storage buffers every device allows, so
`concat` joins more than six views in a tree, and a custom node packs what
it reads.

Buffers are pooled by liveness: once the last node reading a port has been
dispatched, its buffer returns to a pool, and a later port of its size
takes it. Params, constants, sinks and updated values keep their buffers.
What is left in the pool once a program is compiled is its scratch, which
holds nothing between runs.

Programs that take turns on one set of params, as a training step and
densification do, are compiled with `(compile-program-sharing label sinks
updates other)`. Its params of the same name and size are `other`'s
buffers, and its pool starts as `other`'s scratch, so the second program
costs little more than its own sinks, which it copies out of the scratch.
It is released no later than `other`. To grow, a host stashes the params
(`stash-params`, copies on the device), releases its programs, compiles
larger ones, and gives the params back (`unstash-params`, as much of each
as both hold), so two sets of scratch are never held at once.

`(profile-program program)` runs each step alone and waits for it,
answering each step's seconds and its kernel's code. Each wait is a round
trip to the device of about two milliseconds, so it shows where a
program's time goes rather than how long a run takes.

`tests/programs/tensor.sld` evaluates each kind on the CPU and checks every
gradient `grad` builds against central differences. On the device, which
`tests/browser/gpu.mjs` and `tests/gpu.mjs` run, `(gpu-test tensor)`
compiles sinks covering the generated kernels, including reductions in
levels, float scatters and a sort. It compares integer outputs exactly and
float outputs to a part in a thousand against the CPU. It then fits a line
with Adam in 1,000 runs of one program.

## Differentiable splatting

`(snail shell graphics splat-train)` is the renderer 3DGS training descends
through, built as a tensor graph. `render` draws a `Cloud` of params
(`splat-params`) from a camera param into an H x W x 3 image, and answers
the projection too, whose centers' gradient densification watches. A
cloud's spherical harmonics are a param for each degree, each shading only
while its entry of `degrees` is 1, so a schedule raises them. Its `live`
mask culls the rows it has not used yet, so a program compiled for a
capacity holds a cloud that grows. Unused rows can be left at zero through
training.

- **Projection is ordinary tensor operations, so `grad` derives its
  gradient.** Each gaussian's normalized quaternion and exponentiated
  scale make its covariance R S Sᵀ Rᵀ. The camera carries it to the screen
  through the pinhole's Jacobian at its center (EWA splatting), with the
  center's slope clamped and 0.3 pixels² added, as the reference does. Its
  spherical harmonics, seen from the eye, give its color, each degree's
  basis times its coefficients as a matrix product. A gaussian is culled,
  its radius 0, behind the near plane, when degenerate, or when the square
  of its radius about its center misses the image, as the reference culls.
  Densification counts the views that drew a gaussian by that radius:
  counting every gaussian in front of the camera, as this once did,
  diluted their mean gradient on bicycle's 360° views, and the cloud grew
  to 750,000 gaussians where the reference's grows to millions.
- **Binning is custom kernels around the middleware's sorts.** The kernels
  are `splat-count`, `splat-keys` and `splat-ranges`. Gaussians are sorted
  by depth, and each one's tiles emitted in that order at the prefix sum of
  their counts. A stable sort by tile then leaves each 16x16 tile's entries
  near to far. The tile count itself marks padding. The radix sort includes
  enough bits for that key, including on grids with 65,536 or more tiles.
  Binning passes no gradient. The sensor's capacity bounds the entries;
  past it the farthest gaussians' are dropped, so a rendering answers how
  many entries its gaussians asked for, and a host compiles room for more
  before they run out.
- **Rasterizing is a custom node** (`splat-forward`), a workgroup per tile.
  It blends as the paper does and keeps each pixel's final transmittance
  and its count of entries. Its adjoint is another custom node
  (`splat-backward`), which walks the entries far to near, undoing the
  transmittance, from as deep as the tile's deepest pixel went. Many pixels
  add to one gaussian's nine gradients, so each subgroup sums its pixels'
  first, and skips a gaussian none of them blended. Each tile sums its
  subgroups' in workgroup memory and adds one sum a gaussian into the
  gradients with a float compare-and-swap loop. On an RTX 5090 at
  4946x3286 that takes 18 ms; adding every pixel's gradients straight into
  the gradients took 4 seconds. It needs WebGPU's `subgroups` feature,
  which the browser host asks for when the adapter has it.
- **The loss is `photometric-loss`:** (1 − λ) L1 + λ (1 − SSIM), the
  reference's. SSIM is a custom node (`splat-ssim`), fused as fused-ssim
  is (Mallick et al., 2024): a workgroup blurs a tile's moments by the
  11-pixel window in workgroup memory, so no blurred moment fills a buffer,
  and keeps each pixel's derivatives by the moments. Its adjoint
  (`splat-ssim-backward`) blurs those back into the image's gradient.
  `rgba8-image` turns texels copied from a texture into the target image.

`(gpu-test splat-train)` checks the renderer on the device at 64x48 pixels:

- one gaussian's pixel equals the paper's blend computed by hand;
- each of three gaussians' 59 params' gradients equals a central difference
  of the loss on the device, to 5%;
- Adam brings a dimmer, smaller cloud's loss against a rendered target down
  by more than four times in 200 steps.

The gradient check's gaussians are wide, so the contour where alpha falls
to 1/255, which the rasterizer skips, is off the image. A pixel crossing
that step changes the loss by more than a small nudge's gradient does, and
the reference's gradient, like this one, ignores the step.

## Training on photographs

`(snail shell graphics colmap)` reads the sparse reconstruction COLMAP's
structure from motion leaves: `cameras.bin`, each camera's pinhole;
`images.bin`, each photograph's pose and file name; and `points3D.bin`,
each point's position and color. A reader answers `(Ok records)` or why
not, a truncated file or a camera model other than SIMPLE_PINHOLE and
PINHOLE, whose photographs must be undistorted first. `camera-values`
turns a camera and a pose into the 16 numbers of `camera-param`, the
intrinsics scaled to the photographs' size.

`(snail shell graphics splat-fit)` is the reference's training as three
tensor graphs a host compiles for a capacity of gaussians, on one set of
params:

- **`training-step`** renders from the camera param, takes the loss
  against the target param, a photograph's texels copied from its texture,
  and answers Adam's updates of the cloud at the reference's rates, the
  centers' at the param `rate`, which falls from 1.6e-4 to 1.6e-6 times
  the scene's extent (`rate-of-means`). It also adds each drawn gaussian's
  screen-space gradient's length, in units of half the image, to
  densification's statistics, and counts the views that drew it. Its sinks
  are the loss, the image and the entries binned.
- **`densification`** decides, a 0 or 1 a row, which gaussians are kept,
  cloned and split: one whose mean screen-space gradient reaches 2e-4 is
  cloned when its largest scale is within 1% of the extent and split
  otherwise, and one is pruned under 0.005 opacity or, once the param
  `prune-big` is 1, past a tenth of the extent. Exclusive scans of the
  kept and the new give each row's place, a custom kernel (`splat-place`)
  writes each slot's source row and kind, and gathers lay every param and
  moment out again, kept rows first. A split's two children take its
  center plus R (s n) for normal samples n (`splat-normals`) and its scale
  over 1.6; a new row's moments start at zero; the statistics are cleared;
  a sink counts the live. The reference's cloud has no capacity; this
  one's does, so rows clone and split in order only while what they add
  fits beside the rows that stay, and the rest wait for a roomier
  program. A full cloud never drops a split gaussian's children. The paper also prunes a gaussian drawn wider
  than 20 pixels, but its code clears the radii before testing them, so
  it never does; neither does gsplat by default, nor this.
- **`opacity-reset`** brings every opacity down to 0.01 and clears its
  moments.

`src/apps/train` runs the reference's schedule, on Node or in a page. The
trainer performs `dataset` for the scene's files, which a page handles by
fetching them from the scene's URL and a program on Node by reading them
from its folder, and is given how a step's image is shown: on the page's
canvas, or nowhere. It starts a
gaussian at each sparse point, its scale the root of the mean squared
distance to its three nearest neighbours (`splat-knn`, on the device), its
opacity 0.1. Each step trains on a photograph not yet visited in this
round, copied on the device into the target param. A photograph is read
and decoded four steps ahead, in a task of its own that posts it to a
mailbox, and let go after its step, so the device holds five photographs
and not the scene's: bicycle's 194 at full resolution would take 12.6 GB
as textures. It raises the
harmonics' degree every 1,000 steps, densifies every 100 steps from 500 to
15,000, and resets opacity every 3,000. When more than half the capacity is
live, up to the page's `gaussians`, or the step's binning asked for more
than three quarters of the entries, it compiles larger programs: it
stashes the params, releases the old programs and gives the params back to
the new ones. A step and densification make about 3.3 KB a gaussian of
capacity, mostly Adam's: each param's value and moments, and its gradient
and new values in scratch. So the 4,194,304 gaussians `gaussians` allows
by default take 14 GB beside the sorts and photographs, and the 8,388,608
that doubling would reach next don't fit a 32 GB RTX 5090. Every eighth
photograph is held out, and the PSNR on those is reported at the end.

On Mip-NeRF 360's bicycle at `images_4`, the paper's resolution for its
outdoor scenes, on an RTX 5090, the 30,000 steps took 33.5 minutes on Node
and 34.8 in Chromium, one run each. The held-out PSNR was 25.28 and 25.34,
against the paper's 25.25. The cloud fills
its 4,194,304 gaussians by step 9,100 and stays near full until densifying
stops at 15,000, where the reference's grows to about 6 million. At full
resolution the photographs no longer limit a run, since they are streamed;
the step's own buffers do. With the default cloud, binning's entries reach
2^27 near step 6,500, and the programs for them no longer fit a 32 GB
device beside the cloud's 14 GB. A cloud of 2,097,152 leaves them room: the
30,000 steps then took 46 minutes on Node, and the held-out PSNR at 4946 by
3286 was 23.77, which the paper, training at a quarter of that width, has
no number to set beside.
