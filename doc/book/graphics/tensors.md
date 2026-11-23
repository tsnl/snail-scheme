# Tensors and training

`(snail shell tensor)` is a GPU tensor library in the shape of
[Resin](https://github.com/tsnl/resin)'s: a program builds a lazy graph of
nodes, rewrites it symbolically for gradients and optimizer steps, and
lowers it explicitly to plain WebGPU objects the caller owns, which run as
often as a training loop likes, on the page or on Node ([WebGPU on
Node](plan.md#webgpu-on-node)). Its six libraries, from `(snail shell
tensor)` to `(snail shell tensor eval)`, are listed with their entry points
in the [library reference](../libraries/tensors.md); this chapter explains
how they work, and how 3D Gaussian Splatting trains on them.

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
| `Map` | A typed expression, a value or a small tile, at each element of its leading axes |
| `Reduce` | A typed expression summed, or its maximum or minimum taken, over trailing axes |
| `Place` | A gradient placed at a view's addresses |
| `Gather`, `ScatterAdd` | Rows by `u32` index, and their adjoint |
| `Concat` | Views joined along an axis; `stack` joins them along a new one |
| `Sort`, `PrefixSum` | `u32` keys and values sorted stably, all or as many as a count says; an exclusive prefix sum |
| `CustomKind` | Kernels a library writes in WGSL, with their own adjoint |

A map's body is an `Expr`: `Load k`, argument k's element at the map's
index; a `Literal`; or `Apply`, one of 34 operations (`Op`) on others. Each
carries its element type, so a body may convert or reinterpret between
types. A load never addresses: its argument is a view, and the view's
accessor says where its elements are. An operation such as `+`, `exp` or
`where` builds a map of one `Apply` over loads, a `Fill` operand becoming a
literal, so a map reads only buffers. A copy is a map of one load, and it is
the one way a view becomes a buffer.

Each expression also carries its tile: the shape of the block of values it
is, `()` for one value. A map computes its body once at each element of its
leading axes, and its port is those axes followed by the body's tile. A
load of a tile reads as many trailing axes of its argument there, and an
elementwise operation applies to each element of its operands' tiles, a
value standing for every element. Four operations are of tiles: `Pack`
joins its operands' elements into one tile, `Pick` takes elements at
places counted row-major, so it transposes, reshapes and selects, `Product`
multiplies a tile of `(m, k)`, or a row of `k`, by one of `(k, c)`, and
`Fold` combines a tile's elements into one. So a map can build a gaussian's
rotation matrix from its quaternion and multiply it by its scales, one
thread a gaussian.

A reduction has a body too. It computes it at each element of its
arguments' shape, its port's axes followed by its span, and combines it
over the span. The constructors choose between the two by size. `(matmul a
b)`, of `(..., m, k)` by `(..., k, c)`, is a map of tiles when `k` and `c`
are at most 16: the whole product at each matrix when it has at most 16
elements, a row at a time otherwise. A larger product sees both at `(...,
m, c, k)` and sums their product over `k`. `sum`, `amax` and `amin` see
their operand with the reduced axes last and keep those axes at size 1;
over at most 16 elements each is a map folding a tile, and over more a
reduction of one load. `concat` along the last axis into at most 16 is a
map packing each element's tile; any other is a `Concat`.

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
its own adjoint. A map's gradient goes back through its body from the top,
whose value is the map's port: each operation hands its operands their
shares, and each load adds its share to its argument's. The shares of tile
operations are built of the same operations: a product's are two products,
a pack's its gradient narrowed to each operand, and a fold's its gradient
spread over the tile, or over the elements equal to the result. A
reduction's gradient is spread over its span, to every element for a sum
and to those equal to the result for a maximum or minimum, and goes back
through its body the same way, so a large matrix product's gradients are
products summed again. A view's gradient reaches its port through the
view's accessor: it is summed over the axes the view broadcasts, then seen
back through the view when the view reads its whole port in some order of
its axes. Otherwise it is a part, kept with the addresses it reads, and a
port's parts are gathered once every node reading the port has handed one
back. Parts that each read a run of one axis of the port, all of its other
axes in the port's order, are joined along that axis in order, with zeros
where none reads: a concat, which a kernel reading the gradient takes in
when the axis is the last and at most 16 wide. Any other part is placed
among zeros at the addresses it reads, and the places are added. Placing
every part so, as this once did, wrote and read the whole port once a
part: the harmonics' basis, 16 numbers a gaussian that each degree reads a
run of, cost 2.5 ms of step 7,000 in three places and their sum. Sorts, prefix
sums, comparisons and bit operations pass no gradient. A custom node's
adjoint that needs the node's other ports, as a backward pass needs what
its forward pass kept, builds the same node again from its arguments, and
content addressing gives back the node itself.

`(adam-updates prefix settings trained)` builds Adam's step for each
`Trained` param, gradient and rate, the rate being a view so a schedule is
a param the host writes. The moments and the step count are params named
under `prefix` (`moment-names`). They start at zeros, as every buffer does,
and a host may write them, as densification does when it changes how many
gaussians a param holds.

## Fusing

`(fuse-program sinks updates)` rewrites a program's graph so that a map
takes in the maps it reads, as Resin's `fuse_elementwise` fuses its
dispatches. One kernel computes both, and the producer's buffer is not
written unless something else reads it. The answer is views of the same
values computed by fewer nodes, for `lower` to lower as it lowers any
graph; `(fuse roots)` does the same for a list of views.

```scheme
(let ((fused (fuse-program sinks updates)))
  (lower gpu "step" (● fused first) (● fused second)))
```

A producer is inlined into each map that reads it: the consumer's load
becomes the producer's body, whose loads are seen through the consumer's
view. A view of a view is an accessor when each axis of the outer view
steps along the axes of the port it sees without carrying into the next.
Broadcasting, permuting, narrowing, squeezing and splitting an axis all do
that, and any view passes through a producer that read its argument
densely. Merging the axes of a port whose producer read a strided view is
not an accessor, so that producer stays a node. A map of tiles computes
each tile once, so a view of it is taken in only where it reads whole
tiles, the same places of each, which a pick takes: a column of a map of
3×3 matrices is three places of each. A map of values that reads a map of
tiles a whole tile at a time becomes a map of those tiles to take it in,
so Adam's moments of the harmonics' coefficients, whose gradient is
computed a row of three colors at a time, are too. A body stays within 256
expressions, since a producer read twice is inlined twice. A kernel binds
at most seven buffers besides its port, so a sum of eight params is two
maps. Types do not stop fusing: each expression carries its own. A
reduction's body takes in maps as a map's does, so a large matrix product
computes its products as it sums them, but nothing takes in a reduction.
Any other node keeps the map that feeds it, so reductions, gathers,
concats, sorts and custom kernels are where fused kernels end.

Fusing plans from the roots down: a map takes in what it can, from its
first argument on, until nothing more fits, before anything it reads takes
in anything. So what a map took in never leaves it too wide for the map
reading it. A kernel taking in a producer reads what the producer reads in
place of its port, and that may be more: a pick of one element of each
tile of a product reads every tile the product reads, since a view
stepping through a buffer a few elements at a time touches all of its
memory. So a producer is taken in only where, were every reader to take it
in and its own kernel go, they would read no more than they save. One that
a reader planned before keeps is computed anyway, at its first place in
the fused order, so it is taken in only where that reads less than its
port. A producer whose readers see more than its elements is computed
again in each kernel taking it in, and what it reads stays alive until the
last of them, so it is taken in only where that also holds no more bytes,
for no more of the program's steps, than its own buffer would. What it
reads is the buffers under the maps only it reads, which go with it, and
any map others read too, which stays a buffer; one the kernel binds
already, or one that a later node reads anyway, counts as nothing. So the
quaternions' gradient, gathered from the columns the rotation matrices
read, is written once for Adam's moments to read; the projected
covariances that some twenty kernels of the backward pass read are
written once rather than computed from the rotations in each; and the
rotations, which the backward pass reads by column, are written in the
forward pass rather than kept as their parts until then. Since this weighs
every node reading a producer, a program's sinks and updates are fused
together.

On bicycle, fusing took a training step from 779 dispatches to 348, and
the splats viewer's frame from 272 to 80; with gradients' parts joined
since, the step is 197. Of the viewer's 10 ms for 4
million gaussians, its sorts and its rasterizer take 4.5; of its generated
kernels, the harmonics' color costs most, reading each gaussian's 48
coefficients.

## Lowering and running

`(lower gpu label sinks updates)` lowers what the sinks and updates need to a
`Program`, once. Sinks are views to read back; updates are
pairs of a whole param and the value it takes after the run. Both need
the same element count and element type. Use `convert` for a numeric
conversion or `bitcast` to reinterpret the stored bits. Every sink and
update reads the params as they were at the start of the step. Two params
can swap values in one run, and an update can initialize a param that no
sink reads.

```scheme
(let ((program (lower gpu "fit" (list loss) (adam-updates "adam" settings trained))))
  (write-param gpu program "points" bytes)
  (for-each (lambda (_) (run-program gpu program)) (iota 1000))
  (read-sink gpu program 0))                 ; loss used by the last update
```

Everything a program holds is ordinary WebGPU, and the caller's: its
`steps`, each a dispatch with its WGSL text, entry, pipeline, bind group and
workgroups, or a sort or a scan; its params and sinks, each with its
buffer; and `made`, every buffer it made, with its use and size.
`(encode-steps gpu pass program)` encodes the steps into a compute pass the
caller began, among its own work; `run-program` is that in a pass and a
submission of its own. `release-program` destroys what the program made and
nothing it was given.

Each node's kernel is generated as WGSL text whose shapes, pitches and
offsets are literals, a thread per output element, or per element of a
map's leading axes, so two nodes that compute alike share a pipeline. A
`Fill` argument is a literal too and gets no buffer. A map's body becomes
one `let` for each element of each distinct load and operation, a product
written out as sums of products and a pack or a pick only renaming its
operands' elements, so an expression fusing copied into two places is
computed once and no expression nests another, and a map binds each port
its arguments see once. A reduction computes its body as it combines it: a
thread an output element when its span is at most 256 elements, and in
levels otherwise, a workgroup combining each part of 4,096 elements in
shared memory, the first level computing the body, until one part is left.
A float `ScatterAdd` adds with a compare-and-swap loop. Sorts and prefix
sums run on the `radix-sort` and `scan` middleware ([the WebGPU
design](plan.md#scans-sorts-and-gaussian-splats)). Every dispatch is in one
compute pass, so each sees the writes of those before it, and dispatches of
more than 65,535 workgroups are laid out in rows.

Shapes are fixed when a program is lowered, so a buffer has room for the
most it may hold, but a count the device computes can size the work: a
port of one `u32`, read where it is written, never by the host, so nothing
waits. `sort-first-pairs` sorts as many pairs as its count says and writes
none past them, which are unspecified. Each of the sorter's passes runs a
fixed number of workgroups, at most 4,096, that share the blocks counted in
runs, so a pass costs the keys counted, not the capacity. A custom kernel
does the same with a count among its arguments. Dispatching only the
workgroups a count needs would take an indirect dispatch, which Dawn
validates on the host: half a millisecond each, against a microsecond or
two for a direct dispatch
([WebGPU on Node](plan.md#webgpu-on-node)).

A sort's first pass reads its keys and values where they are, and its last
writes its ports, so a sort copies nothing. A fill or a part of a buffer is
copied first into scratch the pool lends for the sort.

A kernel binds at most the eight storage buffers every device allows, so
`concat` joins more than six views in a tree, whether as a map packing them
or as a `Concat`, and a custom node packs what it reads.

Buffers are pooled by liveness: once the last node reading a port has been
dispatched, its buffer returns to a pool, and a later port of its size
takes it. Params, constants, sinks and updated values keep their buffers.
What is left in the pool once a program is lowered is its scratch, which
holds nothing between runs. An update is copied into its param after
every node, unless a map computes the whole of it and nothing could tell
the map wrote it in place: the map reads the param only at the elements
each of its threads writes, and no later node, sink or other update reads
the param. Then the map's port is the param's buffer, which its kernel
binds once and reads the param from, since WebGPU lets a dispatch bind a
buffer it writes no other way. Adam's updates are such maps, so a step
holds no second copy of the cloud's params and moments.

A caller gives a program buffers with `(lower-with gpu label sinks updates
given)`. A `Given` holds buffers for params by name, which the program
reads and writes in place of making its own, and free scratch to start its
pool with. `(bound given view buffer)` adds the caller's buffer for the
param `view` sees whole, as a viewer gives the buffer its gaussians are
already in; the buffer must be the param's size. Programs that take turns
on one set of params, as a training step and densification do, give the
second what the first has, `(given-by first)`: its params, and its scratch,
so the second costs little more than its own sinks, which it copies out of
the scratch. It is released no later than the first. To grow, a host
stashes the params (`stash-params`, copies on the device), releases its
programs, lowers larger ones, and gives the params back (`unstash-params`,
as much of each as both hold), so two sets of scratch are never held at
once.

`(profile-program gpu program)` answers each step's seconds on the device,
with its kernel's entry and code. Each step runs in a compute pass of its
own, begun with timestamp writes, and every pass goes in one submission,
so the device runs the steps back to back, as a run does, and the times
are read once, after the last. It needs the device's `timestamp-query`
feature. Node's times are not rounded; a browser's are, to 100 μs, so a
program is best profiled on Node. A pass per step costs a little that one
pass would not, so the sum is a little more than a run takes.

`tests/programs/tensor.sld` evaluates each kind on the CPU and checks every
gradient `grad` builds against central differences. On the device, which
`tests/browser/gpu.mjs` and `tests/gpu.mjs` run, `(gpu-test tensor)`
lowers sinks covering the generated kernels, including reductions in
levels, float scatters, a sort, and small products, packs, picks and folds
with a gradient through them, unfused and fused. It compares integer
outputs exactly and float outputs to a part in a thousand against the CPU.
It runs a program whose param is a buffer the test made, in the test's own
pass, and reads the buffer back after releasing the program. It then fits a
line with Adam in 1,000 runs of one program.

## Differentiable splatting

`(snail shell graphics splat-train)` is the renderer 3DGS training descends
through, built as a tensor graph. `render` draws a `Cloud` of params
(`splat-params`) from a camera param into an H x W x 3 image, and answers
the projection too, whose centers' gradient densification watches. A
cloud's spherical harmonics are a param for each degree, each shading only
while its entry of `degrees` is 1, so a schedule raises them. Its `live`
mask culls the rows it has not used yet, so a program lowered for a
capacity holds a cloud that grows. Unused rows can be left at zero through
training.

A rendering has a `Purpose`. One for `Training` keeps what the backward
pass starts from. One for `Viewing` keeps only the image, and has no
gradient. The trainer renders its held-out views for viewing, and so does
the splats viewer, which draws its clouds with this renderer as well as
with quads ([`splat-view`](plan.md#scans-sorts-and-gaussian-splats)). A
viewer's cloud may also carry a `Placement`: each gaussian's affine map
into the world, which carries its center and covariance there and a
direction back into its own frame for its harmonics. A training cloud
stands in the world and has none, so its graph is unchanged.

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
  their counts. A gaussian's tiles are those it reaches: those with a pixel
  center where its alpha is at least 1/255, the least the rasterizer
  blends, so binning drops nothing the rasterizer would draw. Each tile in
  the bounding box of the gaussian's ellipse at that alpha is tested where
  its conic's quadratic is least over the tile's pixel centers, on the
  side nearest the center across or down. Binning as the reference does,
  every tile of the square three standard deviations along the widest
  axis about the center, made 4.5 million entries for step 7,000's view
  of bicycle where this makes 1.7 million, and cut an opaque gaussian at
  three deviations, where its alpha passes 1/255 out to 3.33. A stable
  sort by tile then leaves each 16x16 tile's entries near to far. The
  radix sort includes enough bits for every tile's key, including on grids
  with 65,536 or more tiles. The entries asked for, the last gaussian's
  offset and count, are counted on the device, and the tile sort and
  `splat-ranges` cover only those, so the capacity's room costs memory and
  no time. Binning passes no gradient. The sensor's capacity bounds the
  entries; past it the farthest gaussians' are dropped, so a rendering
  answers how many entries its gaussians asked for, and a host lowers room
  for more before they run out.
- **Rasterizing is a custom node** (`splat-forward`), a workgroup per tile.
  It blends as the paper does and hands each pixel's final transmittance
  and its count of entries to `keep`. The purpose chooses `keep`'s text:
  rendering for training puts `splat-forward-state.wgsl.scm` first, which
  binds two buffers and stores both, and rendering for viewing an empty
  function. A WGSL `override` could only skip the stores. The bindings
  would stay, since WGSL counts a binding named in a dead branch as used.
  Its adjoint is another custom node
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

- one gaussian's pixel equals the paper's blend computed by hand, rendered
  for training and for viewing;
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
PINHOLE, whose photographs must be undistorted first. `camera-sized` is
a camera as it took photographs of another size, as a dataset's smaller
copies are, scaled across as their width is and down as their height
is, since the two round apart. `camera-values` turns a camera and a pose
into the 16 numbers of `camera-param`.

`(snail shell graphics splat-fit)` is the reference's training as three
tensor graphs a host lowers for a capacity of gaussians, on one set of
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

`src/apps/train` runs the reference's schedule, on Node or in a page, in
three parts:

- **The trainer**, `(apps train trainer)`, knows no file, address or
  format. It trains on a `Scene`: the camera, the posed views to train on
  and those held out, and the sparse points, as data. It asks its
  `Photographs` for a view's photograph, a texture on the device, and is
  given how a step's image is shown: on the page's canvas, or nowhere.
- **The dataset**, `(apps train dataset)`, is a COLMAP dataset as such a
  scene: where its files are, the camera scaled to its photographs, the
  decoding, and every eighth photograph held out.
- **The entry points** say how a file's bytes are had and what is kept. A
  page fetches them from the dataset's URL and keeps nothing; a program
  on Node reads them from its folder and keeps the cloud.

A program whose scene is made or embedded calls the trainer alone, with a
`Scene` of its own and a texture for each view asked for.

The trainer starts a
gaussian at each sparse point, its scale the root of the mean squared
distance to its three nearest neighbours (`splat-knn`, on the device), its
opacity 0.1. Each step trains on a photograph not yet visited in this
round, copied on the device into the target param. A photograph is asked
for four steps ahead, in a task of its own that posts it to a
mailbox, and let go after its step, so the device holds five photographs
and not the scene's: bicycle's 194 at full resolution would take 12.6 GB
as textures. It raises the
harmonics' degree every 1,000 steps, densifies every 100 steps from 500 to
15,000, and resets opacity every 3,000. When more than half the capacity is
live, up to the page's `gaussians`, or the step's binning asked for more
than three quarters of the entries, it lowers larger programs: it
stashes the params, releases the old programs and gives the params back to
the new ones. A step and densification make about 1.9 KB a gaussian of
capacity, mostly Adam's: each param's value and moments, which its
updates write in place, and its gradient in scratch. So the 4,194,304
gaussians `gaussians` allows by default take 8.2 GB beside the sorts and
photographs, and the 8,388,608 that doubling would reach next would take
16 GB. The PSNR on the views held out is reported at the end.
`train` answers the programs it trained, and `trained-cloud` reads their
cloud back from the device as arrays. The program on Node writes those
with `write-ply`, as the `.ply` file the reference implementation writes,
at `cloud=PATH`, and `src/apps/splats` flies through it.

On Mip-NeRF 360's bicycle at `images_4`, the paper's resolution for its
outdoor scenes, on an RTX 5090, the 30,000 steps take 14.3 minutes on
Node, to a held-out PSNR of 25.29 against the paper's 25.25. The cloud
fills its 4,194,304 gaussians by step 9,100 and stays full until
densifying stops at 15,000, where the reference's grows to 4.9 million.
[A bench](https://github.com/tsnl/snail-scheme/blob/main/benches/splat-training/README.md)
trains the reference and gsplat beside it on the same GPU: they take 17.2
and 10.4 minutes, to 25.23 and 25.15. Their steps take longer as their
clouds grow; the programs here have shapes fixed by their capacity, so a
step takes as long with a million gaussians live as with four. At full
resolution the photographs no longer limit a run, since they are streamed;
the step's own buffers do. Before binning kept to the tiles a gaussian
reaches, the default cloud's entries reached 2^27 near step 6,500, and the
programs for them no longer fit a 32 GB device beside the cloud's 14 GB.
A cloud of 2,097,152 left them room: the 30,000 steps took 48 minutes on
Node, and the held-out PSNR at 4946 by 3286 was 23.76, which the paper,
training at a quarter of that width, has no number to set beside. Until about step 9,000 a step waits on the
program's thread, where each photograph's bytes arrive and its texels are
read, and takes about 90 ms; after that it waits on the device.
