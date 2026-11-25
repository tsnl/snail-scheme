# The GPU

WebGPU as a capability, and the building blocks every graphics and compute
library shares: data laid out as shaders read it, shaders written as
S-expressions, and a scan and a sort on the device. The
[WebGPU design](../graphics/plan.md) explains why the layer is shaped this
way, and how Node gets a device.

## `(snail shell gpu)`

`Gpu`, a record of WebGPU's own operations, so code that uses it reads
like WebGPU, and a `Gpu` parameter says exactly which functions touch the
device:

- **Device access** starts with `request-device`. Its `DeviceInfo` reports the
  canvas format, enabled optional features and maximum storage-buffer binding size
  in bytes. `work-done` waits for submitted commands to finish.
- **Objects**: `create-buffer`, `create-texture`, `create-view`,
  `create-sampler`, `create-shader-module`, `create-render-pipeline`,
  `create-compute-pipeline`, `create-bind-group` and `create-query-set`,
  each from a descriptor record, each answering a handle; `destroy`.
- **Data**: `write-buffer` and `write-texture` from `Bytes`, `read-buffer`
  back, and `decode-image`, the host's decoder.
- **Commands**: `create-command-encoder`, copies, render passes
  (`begin-render-pass`, `begin-timed-render-pass`), compute passes
  (`begin-compute-pass`, `begin-timed-compute-pass`), what a pass sets and
  draws or dispatches, `finish` and `submit`; `submit-timed` and
  `elapsed-seconds` read a timed pass's device time.
- **The canvas**: `current-texture`.

`host-gpu` makes the host's from a `Host`: the page's, or Dawn's on Node.

It is WebGPU itself, without bookkeeping, and three rules follow:

- **The program keeps its objects.** A handle is the id of an object the
  host holds, kept for as long as the program uses it, across frames.
  `destroy` lets an object go at the next `submit`, after the commands that
  use it. An encoder, a pass and a command buffer go once used, and the
  canvas's texture at the next `current-texture`.
- **Misuse is WebGPU's to report.** The `Gpu` checks nothing the device
  checks; Dawn's validation reports misuse on the page's console or on
  Node's standard error.
- **Descriptors cross as fields.** A descriptor is a list of words and
  texts in a fixed order per kind (`fields-bytes`), staged as `Bytes` the
  host reads into the dictionary WebGPU takes; contents cross as views of
  the program's memory, without a copy. A pipeline's layout is `"auto"`,
  so a bind group is made against a pipeline and a group index.

An earlier version kept books for the program: objects found by a path each
frame, released at `submit`, evicted under a budget. Finding every object
again each frame cost Siegework more than its old JavaScript renderer spent
drawing, so the program keeps what it makes
([WebGPU through a capability](../graphics/plan.md#webgpu-through-a-capability)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/gpu.sld)

## `(snail shell gpu record)`

`with-recorded-gpu` hands its work a `Gpu` that runs nothing: it numbers
the objects made and records a line for each operation a page would send to
its host, so a graphics library's test reads what it asked of WebGPU. A
buffer reads back as zeros, an image is as large as its PNG header says,
and the canvas is 640 by 480 (`tests/programs/gpu-record.scm`).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/gpu/record.sld)

## `(snail shell graphics pod)`

Plain old data, laid out as WGSL lays out its types in storage buffers, so
bytes packed here read in a shader as the struct it declares. A record of
`F32`, `I32`, `Vec2f` to `Vec4f`, `Vec2i`, `Vec4i`, `Mat4x4f` and other such
records derives `Pod`; its `Shape`, found by type with `(shape)`, gives its
WGSL `declarations`, its `stride` and alignment, and its `vertex-layout`.
`pack` writes a list of values at the stride, and `pod-bytes` one value:

```scheme
(record Vertex
  ((position Vec3f)
   (uv Vec2f))
  (deriving Pod))

(define vertex-shape (→ (Shape Vertex)) (shape))
(declarations vertex-shape)      ; "struct Vertex {\n  position: vec3f,\n  uv: vec2f,\n}\n"
(pack vertex-shape (list v0 v1)) ; two 32-byte strides
```

A `vec3f` takes 12 bytes but aligns to 16, so an `F32` may follow it in the
same 16. A `Vec4h` is four floats kept as f16s, a WGSL `vec2u` of two
words, which `unpack2x16float` reads two at a time, without the
`shader-f16` some devices lack. A shape is built by walking the record's fields, so a program
keeps each one it uses as a top-level value, made once. In WGSL a hyphen in
a record's or field's name becomes an underscore: `Paint-uniform` is
`Paint_uniform`.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/pod.sld)

## `(snail shell graphics wgsl)`

Shaders as S-expressions, one form to one WGSL construct, printed to WGSL
text by `shader-library`, a `generate-library` recipe that reads each
shader file when its library is built. A program ships WGSL, and a form the
printer does not know fails the build at its line. The header of
`wgsl.sld` tabulates every form. A shader's structs come from `Pod` at run
time, prepended with `declarations`, so a shader names them without
declaring them.

The shader libraries are generated this way:
`(snail shell graphics shaders)` holds the graphics libraries' shaders,
`(snail shell graphics trace shaders)` the path tracer's, and
`(apps train shaders)` the trainer's own.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/wgsl.sld)

## `(snail shell graphics kernel)`

What each library of compute kernels would otherwise write for itself:
`compute-kernel`, a pipeline for one entry point; `kernel-group`, a bind
group laid out as that kernel expects; `dispatch-items`, workgroups enough
for every item, in rows past 65,535, and `dispatch-texels`, a workgroup for
each 8 by 8 tile of texels; `uniform-slots` and `slot-entry`, small uniform records side by
side in one buffer, each at an offset a uniform may bind; and
`uniform-buffer` and `storage-buffer`, the latter one that binds even when
it holds nothing.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/kernel.sld)

## `(snail shell graphics scan)`

An exclusive prefix sum of a storage buffer's `u32` numbers, in place: each
number becomes the sum of those before it, by Blelloch's work-efficient
scan. A workgroup scans a tile of 512 numbers and writes its total a level
up, which is scanned the same way, until a level fits in one tile; each
level's sums are then added back, top down. `make-scan` makes a `Scan` once
for a buffer and a count, and `dispatch-scan` encodes it into a compute
pass as often as the buffer changes; `release-scan` lets it go. Sums wrap
modulo 2^32.

Since a scan's value at an index depends only on what comes before it, a
scan over a buffer's whole capacity is correct below any count the device
computes, whatever lies past it.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/scan.sld)

## `(snail shell graphics radix-sort)`

A stable least-significant-digit radix sort of `u32` keys and their `u32`
values, eight bits a pass. `make-sorter` makes a `Sorter` once for a
`SortLane` it reads from (`from`), one it leaves the sorted pairs in (`to`),
a capacity, how many low bits of each key to sort (8, 16, 24 or 32), and
optionally a buffer whose first `u32` the device writes with how many pairs
to sort. `dispatch-sort` encodes the sort into a compute pass.

- **Lanes.** The passes alternate between `to` and a spare lane of the
  sorter's own, so that the last writes `to`; a sort of 8 bits, one pass,
  makes no spare. So `from` may be `to`, a sort in place, only for an even
  number of passes: 16 or 32 bits. A sort that reads its input where it is
  copies nothing first.
- **Counts.** With a count, the sort writes nothing of `to` past it, and
  its work on keys is that of the pairs counted, whatever the capacity: each
  pass runs at most 4,096 workgroups, which share the counted blocks of 256
  keys in runs. The digit table is sized by the capacity, though: each pass
  writes and scans 256 counts a workgroup, 1,048,576 for a capacity of a
  million keys or more, even when the count is zero. Dispatching exactly the
  workgroups the count needs would take an indirect dispatch, which with
  Dawn's validation takes about half a millisecond of wall time, and costs
  the device more than the runs do
  ([WebGPU on Node](../graphics/plan.md#webgpu-on-node)).
- **The digit table** holds 256 counts a workgroup, laid out digit-major
  and scanned with `(snail shell graphics scan)`. Laid out by block instead,
  it would hold as many words as there are keys.

Ranking a key within its block is a count of the matching digits before it
in workgroup memory, the simplest stable ranking. At step 7,000 of
bicycle's training, sorting 4.2 million depth keys of 32 bits takes 0.60 ms
and 1.66 million tile entries of 16 bits 0.16 ms, on an RTX 5090.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/graphics/radix-sort.sld)
