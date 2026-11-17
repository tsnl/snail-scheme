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
gradient.

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

Buffers are pooled by liveness: once the last node reading a port has been
dispatched, its buffer returns to a pool, and a later port of its size
takes it. Params, constants, sinks and updated values keep their buffers.

`tests/programs/tensor.sld` evaluates each kind on the CPU and checks every
gradient `grad` builds against central differences. `tests/browser/gpu.mjs`
compiles ten sinks covering every generated kernel, reductions in levels,
float scatters and a sort, and finds each equal to the CPU's evaluation to
a part in a thousand. It then fits a line with Adam in 1,000 runs of one
program.
