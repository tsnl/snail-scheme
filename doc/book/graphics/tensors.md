# Tensors and training

`(snail shell tensor)` is a GPU tensor library in the shape of
[Resin](https://github.com/tsnl/resin)'s: a program builds a lazy graph of
nodes, rewrites it symbolically for gradients and optimizer steps, and
compiles it explicitly into WebGPU work that runs as often as a training
loop likes. All four libraries are **implemented**:

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
is known by its name and shape.

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
pairs of a param and the value it takes after the run. So a training step
reads the params it started with and leaves the next ones:

```scheme
(let ((program (compile-program "fit" (list loss) (adam-updates "adam" settings trained))))
  (write-param program "points" bytes)
  (for-each (lambda (_) (run-program program)) (iota 1000))
  (read-sink program 0))                 ; the loss after the last step
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

`tests/programs/tensor.sld` evaluates each kind on the CPU and checks every
gradient `grad` builds against central differences. `tests/browser/gpu.mjs`
compiles eleven sinks covering every generated kernel, reductions in levels,
float scatters and a sort, and finds each equal to the CPU's evaluation to
a part in a thousand. It then fits a line with Adam in 1,000 runs of one
program.

## Differentiable splatting

`(snail shell graphics splat-train)` is the renderer 3DGS training descends
through, built as a tensor graph. `render` draws a `Cloud` of params
(`splat-params`) from a camera param into an H x W x 3 image.

- **Projection is ordinary tensor operations, so `grad` derives its
  gradient.** Each gaussian's normalized quaternion and exponentiated
  scale make its covariance R S Sᵀ Rᵀ. The camera carries it to the screen
  through the pinhole's Jacobian at its center (EWA splatting), with the
  center's slope clamped and 0.3 pixels² added, as the reference does. Its
  degree-3 spherical harmonics, seen from the eye, give its color.
- **Binning is custom kernels around the middleware's sorts.** The kernels
  are `splat-count`, `splat-keys` and `splat-ranges`. Gaussians are sorted
  by depth, and each one's tiles emitted in that order at the prefix sum of
  their counts. A stable sort by tile then leaves each 16x16 tile's entries
  near to far. Binning passes no gradient.
- **Rasterizing is a custom node** (`splat-forward`), a workgroup per tile.
  It blends as the paper does and keeps each pixel's final transmittance
  and its count of entries. Its adjoint is another custom node
  (`splat-backward`), which walks the entries far to near, undoing the
  transmittance. It adds each gaussian's nine gradients with a float
  compare-and-swap loop.
- **The loss is `photometric-loss`:** (1 − λ) L1 + λ (1 − SSIM), the
  reference's. SSIM's 11-pixel window is a custom separable blur
  (`splat-blur`), which is its own adjoint since its weights are symmetric
  and its edges zero; the rest of SSIM is tensor operations.
  `rgba8-image` turns texels copied from a texture into the target image.

`tests/browser/gpu.mjs` checks the renderer on the device at 64x48 pixels:

- one gaussian's pixel equals the paper's blend computed by hand;
- each of three gaussians' 59 params' gradients equals a central difference
  of the loss on the device, to 5%;
- Adam brings a dimmer, smaller cloud's loss against a rendered target down
  by more than four times in 200 steps.

The gradient check's gaussians are wide, so the contour where alpha falls
to 1/255, which the rasterizer skips, is off the image. A pixel crossing
that step changes the loss by more than a small nudge's gradient does, and
the reference's gradient, like this one, ignores the step.
