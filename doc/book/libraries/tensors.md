# Tensors

A GPU tensor library in the shape of [Resin](https://github.com/tsnl/resin)'s:
a program builds a lazy graph of nodes, rewrites it symbolically for
gradients and optimizer steps, fuses it, and lowers it explicitly to plain
WebGPU objects the caller owns, which run as often as a training loop likes,
on the page or on Node. Splat training is its main user
([tensors and training](../graphics/tensors.md)).

A program uses them in this order:

```scheme
(let* ((loss ...)                                    ; (snail shell tensor)
       (dw (list-ref (grad loss (list w)) 0))        ; (snail shell tensor grad)
       (updates (adam-updates "adam" (adam 0.9 0.999 1e-15)
                              (list (new Trained (param w) (grad dw) (rate (scalar 0.01))))))
       (fused (fuse-program (list loss) updates))     ; (snail shell tensor fuse)
       (program (lower gpu "fit" (● fused first) (● fused second))))
  (run-program gpu program))                         ; (snail shell tensor lower)
```

## `(snail shell tensor)`

Nodes, ports and views, and the operations that build them. A node computes
one dense buffer for each of its ports, and a program works with `View`s:
an accessor over a port, an offset, a shape and a pitch for each axis, in
elements. So `narrow`, `transpose`, `permute`, `squeeze`, `unsqueeze` and
`broadcast-to` make no node, and a pitch of 0 repeats an element. `View` is
an instance of `Num` and `Fractional`, so `(+ a b)` and `(sqrt v)` build
nodes, broadcasting as NumPy does.

- **Leaves**: `param` (a buffer the host writes, by name), `constant`,
  `fill`, `scalar`, `zeros-like`, `ones-like`.
- **Maps and reductions**: the elementwise operations (`exp`, `log`,
  `sigmoid`, `where`, `maximum`, comparisons, `convert`, `bitcast`, …;
  `halves` reads each u32 of a row as the two f16s it holds),
  `sum`, `sum-all`, `mean`, `amax`, `amin` and `matmul`; `mapped` and
  `reduced` take an `Expr` body directly, and `mapped-ports` a map of
  several bodies, one kernel writing a port for each, as fusing also
  makes them.
- **Data movement**: `copy`, `reshape`, `gather`, `scatter-add`, `concat`,
  `stack` and `place`.
- **Sorts and scans**: `sort-pairs`, `sort-first-pairs` (only as many pairs
  as a one-element `u32` view says, the rest unspecified) and
  `exclusive-scan`.
- **Filters**: `filter-rows` keeps the rows whose value is not 0, as a
  `Filtered`: their indices packed to the front and 0 past them (`ids`),
  1 for each row below their count and 0 from it (`live`), and the count,
  one `u32` on the device. `kept-rows` takes a view's kept rows by them,
  0 past the count.
- **Custom kernels**: `custom` runs WGSL a library writes, with its own
  adjoint, on ports the lowering zeroes first.

A node is known by its key, a hash of what it computes: its kind, its
parameters, and its arguments' keys and accessors. Building the same
computation twice builds the same node, so a graph shares its common parts,
and a custom node's adjoint can rebuild its forward node and get the same
one back ([graphs and views](../graphics/tensors.md#graphs-and-views)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/tensor.sld)

## `(snail shell tensor grad)`

`(grad loss views)` answers the gradient of a scalar with respect to each
view, as views of new nodes; nothing runs. It walks the nodes the loss
depends on from last to first, and each kind of node hands each argument
its share of its ports' gradients: a map back through each of its bodies,
a reduction over its span, a custom node by its own adjoint. A port that
nothing the loss depends on reads has no gradient, and adds nothing.

A body of one operation, as every elementwise operation, `matmul`, `concat`
and small reduction builds, hands each argument a node built by that
operation's rule. A body of several operations, which a library writes with
`mapped`, is differentiated as one expression: its gradient is one map for
each argument, which a kernel computes whole. The splat trainer writes the
harmonics' basis so, sixteen numbers a gaussian from its direction
([gradients and Adam](../graphics/tensors.md#gradients-and-adam)).

A port's shares are gathered once every node reading it has handed one
back. A share through a view that reads the whole port comes back as a
view. Shares through views that each read a run of one axis, as the
columns of a matrix do, are joined along it with zeros between, a concat
the reading kernel takes in; anything else is placed among zeros and added.
Joining took bicycle's training step from 35.6 ms to 27.6 ms on an RTX 5090,
since placing wrote and read the whole port once a share
([gradients and Adam](../graphics/tensors.md#gradients-and-adam)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/tensor/grad.sld)

## `(snail shell tensor adam)`

Adam (Kingma and Ba, 2015) as more graph. `adam-updates` builds the update
of each `Trained` param and of the two moments Adam keeps for it, as
`(param new-value)` pairs a program commits after each run. The moments and
the step count are params of the program (`moment-names`), which start at
zeros as every buffer does and which a host may write, as densification
does. A learning rate is a view, so a schedule is a param the host writes
each step.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/tensor/adam.sld)

## `(snail shell tensor fuse)`

`fuse-program` rewrites a program's sinks and updates into fewer nodes
computing the same values: a map whose argument another map computes takes
that map's body in place of the load, so one kernel computes both and the
producer's buffer is written only if something else reads it. A
reduction's body takes in maps the same way, so a large matrix product
computes its products as it sums them; nothing takes in a reduction, a
gather, a concat that is not a pack, a sort or a custom kernel.

Two limits shape it: a body stays within 256 distinct expressions, each
counted once however many times it is inlined, and a kernel
within the eight storage buffers every device allows, its ports among them.
A producer read by several kernels is computed in each, so it is taken in
only where that holds no more memory, for no longer, than its own buffer
would. A producer whose port is kept anyway, such as an update's value or
a buffer a later kernel reads, is written by the map reading it whole, as
a port of its own, so Adam's three updates of a param are one kernel
([fusing](../graphics/tensors.md#fusing)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/tensor/fuse.sld)

## `(snail shell tensor lower)`

`lower` turns the nodes a program's sinks and updates need into plain
WebGPU objects, once: a buffer for each port, a pipeline and bind group for
each dispatch, and their order, all in a `Program` the caller owns.
`run-program` runs it in a compute pass of its own, or `encode-steps` into
the caller's, as often as it likes; `write-param`, `read-param` and
`read-sink` move data; `release-program` lets it all go.

- **Kernels** are generated per node with every size a literal, so two
  nodes computing alike share a pipeline. A `Fill` argument is a literal
  too, with no buffer. A choice of zero, `(where condition value 0)` with
  one condition a row, computes its value inside an `if`, so the rows the
  condition culls skip what the value computes in that kernel: a mask.
  A kernel computes each choice once, however many places fusing copied
  it to.
  A filter packs the rows it keeps, so a choice by its `live` skips the
  rest together.
- **Buffers** return to a pool once the last node reading them has run;
  params, constants, sinks and updates keep theirs. An update that a map
  computes whole is written in place, into its param's buffer, each port
  of a map of several into its own param.
- **Counts the device computes** size the work of sorts and of custom
  kernels that take them: a fixed number of workgroups loop over the work
  below the count ([lowering and running](../graphics/tensors.md#lowering-and-running)).
- **Sharing params**: `lower-with` and `given-by` lower programs that take
  turns on one set of params, as a training step and densification do, and
  `stash-params` and `unstash-params` carry them into a larger program.
  `profile-program` times each step alone, and `program-memory` totals the
  bytes its buffers take, by use.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/tensor/lower.sld)

## `(snail shell tensor eval)`

`(evaluate sinks inputs)` evaluates the same graph on the CPU, each port an
array of `F64` rounded or wrapped as the GPU computes it: the executable
specification each kind of node's kernels are tested against, and the way
gradients are checked by finite differences without a device. A custom
node has no CPU form, so a graph with one is not evaluated here.
`bytes->values` and `values->bytes` convert a port's buffer.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/tensor/eval.sld)
