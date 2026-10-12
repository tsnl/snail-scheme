# Iverson Ghost

`(snail-scheme iverson-ghost)` is a small eager tensor library. It has four
dtypes, immutable concrete arrays, trailing-dimension broadcasting, reductions,
matrix multiplication, and flat gather/scatter. Numeric operations compile to
whole-operation builtins with unboxed buffers. Chibi supplies an executable
Scheme reference of the same contracts.

```scheme
(import (scheme base) (snail-scheme iverson-ghost))

(define x (array '(3 2) '(1 2 3 4 5 6) 'f32))
(define centered (sub x (mean x 0)))
(define covariance (div (matmul (transpose centered) centered) 3))

(define index (array '(5) '(2 0 2 1 2) 'i32))
(define histogram (scatter-add (array '(3) '(0 0 0) 'i32) index 1))
;; (array->vector histogram) => #(1 1 3)
(gather '#(zero one two) index)
;; Object tensor containing: #(two zero two one two)
```

## Running the prototype

From the repository root:

```sh
# Execute the Scheme reference.
chibi-scheme -I src examples/iverson-ghost/main.scm

# Build and execute linked Wasm.
chibi-scheme -I src examples/iverson-ghost/build.scm

# Compile the same Scheme program to a native executable.
chibi-scheme -I src tests/build-native.scm . examples/iverson-ghost/main.scm build/iverson-ghost
build/iverson-ghost

# Exercise contracts and diagnostics through both backends.
scripts/test-backend --target both
```

## Implemented interface

Shapes are lists of exact nonnegative dimensions. Storage is dense, contiguous,
and row-major; numeric dimensions and allocation sizes must fit the target's
address space. `()` is a scalar shape with one element; any zero dimension makes
an empty tensor. Constructors take a flat list or vector and require exactly the
shape's element count. Dtype is explicit storage information, including for
empty arrays; it is never inferred by inspecting the elements.

| Operation | Contract |
| --- | --- |
| `(array shape elements [dtype])` | Copy elements into a tensor; default dtype is `f64`. |
| `(array? value)` | Recognize concrete tensors and standard Scheme vectors. |
| `(dtype value)`, `(shape value)`, `(size value)` | Inspect storage type, dimensions, and element count. Bare numbers have scalar shape and default `f64` dtype. |
| `(array-ref value i ...)` | Read one element with exactly one index per axis. |
| `(array->vector value)` | Return a fresh flat Scheme vector. |
| `(astype dtype value)` | Explicit conversion with the same shape. |
| `(iota count [dtype])` | Rank-one sequence from zero to `count - 1`; default `f64`. |
| `(reshape shape value)` | Preserve element count; immutable tensor storage may be shared. |
| `(transpose value)` | Reverse all axes, materializing the new row-major order. |
| `(add a b)`, `(sub a b)`, `(mul a b)`, `(div a b)` | Binary operations with trailing singleton broadcasting. |
| `(sum value [axis])`, `(mean value [axis])` | Reduce all elements or one zero-based axis; remove the reduced axis. |
| `(matmul a b)` | Multiply two rank-two arrays with matching inner dimensions. |
| `(gather value indices)` | Read flat offsets from an `i32` index tensor; output has index shape and source dtype. |
| `(scatter base indices updates)` | Return a copy of base with indexed replacements. |
| `(scatter-add base indices updates)` | Return a copy of base with indexed additions. |

Broadcasting aligns shapes on their trailing dimensions. Dimensions must be
equal or one must be `1`; `(2 1)` and `(3)` produce `(2 3)`. A `0` dimension
combined with `1` remains `0`. This follows NumPy's
[broadcasting rules](https://numpy.org/doc/stable/user/basics.broadcasting.html).

Scatter updates must have the index shape or be a scalar, including a rank-zero
tensor. An index is always a dense `i32` tensor, including a rank-zero tensor;
a bare integer is not accepted. Indices must be nonnegative and less than the
flattened base size; negative indexing is unsupported. Repeated indices execute in input order:
`scatter` keeps the last replacement; `scatter-add` accumulates each update.
The base remains unchanged. An object tensor can receive arbitrary scalar Scheme
values through `scatter`. To store a vector itself as one object, wrap it in a
rank-zero object tensor; a bare vector participates as an update tensor.

An empty sum is zero in the result dtype. A mean whose reduction length is zero
raises an error, including when another axis also makes its output empty.
Reducing a positive-length axis with an empty output is valid.

## Dtypes and ownership

| Dtype | Compiled storage and arithmetic |
| --- | --- |
| `object` | Tagged Scheme values in GC-visible slots; Scheme arithmetic and object identity. |
| `f64` | Unboxed IEEE binary64 elements; binary64 operations and accumulation. |
| `f32` | Unboxed IEEE binary32 elements; each operation and accumulation step rounds to binary32. |
| `i32` | Unboxed signed 32-bit elements; add/subtract/multiply/sum/scatter-add wrap modulo 2^32. |

Reductions traverse each selected axis in increasing index order. Matrix
products use separate multiplication and addition in increasing inner-index
order; the API does not permit replacing these steps with fused multiply-add.

`i32` construction and casts require integral values within the signed 32-bit
range. They reject fractions, NaNs, infinities, and out-of-range values. True
division and mean of `i32` arrays return `f64`; mean widens before summation so
its accumulator does not wrap. Floating conversions may round or overflow to
infinity. Chibi's reference stores floating values in host vectors and rounds
`f32` explicitly.

Two numeric arrays must have the same dtype; use `astype` for a conversion.
A bare numeric scalar adopts the array's dtype and is validated before the
operation, including before `i32` division widens. `object` takes precedence
when combined with a numeric tensor. Object arithmetic keeps the host's ordinary
Scheme number semantics; compiled Scheme currently supports integers and reals.

Every standard Scheme vector participates as a rank-one `object` tensor, with
its existing vector predicates, reads, and mutation semantics. This is protocol
compatibility; the runtime has not replaced the standard vector representation.
`reshape` of a mutable vector snapshots its slots. Constructed object tensors
have private immutable slots, so reshapes can share them safely. Copies are
shallow: a pair, vector, procedure, or other object stored in a slot keeps its
identity and can retain its own mutable state.

Numeric tensors are first-class Scheme extension values. Rust stores their
shape and reference-counted numeric payload in a resource registry. The registry
retains no Scheme roots, and a wrapper's finalizer holds only scalar resource
IDs. Reshapes share numeric payloads, and finalization releases each wrapper's
ownership. Object tensors instead keep their slots in Scheme record fields so
cycles remain visible to the Scheme collector. Resource cleanup is eventual;
the native adapter drains finalizers after guest frames return.

## Compiler and typing direction

The implemented boundary is in
[`iverson-ghost.sld`](../src/snail-scheme/iverson-ghost.sld),
[`iverson.rs`](../src/iverson.rs), and the primitive inventory/lowering in
[`bootstrap.sld`](../src/snail-scheme/bootstrap.sld) and
[`wasm.sld`](../src/snail-scheme/wasm.sld). Immutable primitive identities lower
directly to whole-operation calls; one AWI argument vector crosses the boundary
per operation. The numeric element loops contain no Scheme callbacks or boxed
element arithmetic. Passing an operation as a first-class procedure still works
through ordinary dispatch.

The companion [static interface](typeclasses.md) implements selection between
eager and symbolic carriers today. Dtype/rank refinements remain a design
direction, **not an implemented type syntax**. A tensor type should carry dtype
and rank, optionally refining known dimensions. Unknown dtype or shape facts can
retain gradual runtime checks.
The existing vector type can remain the mutable rank-one object case; treating
all object slots as `Any` must not erase the tensor's known shape. In particular,
gather/scatter require `i32` indices, matmul requires rank two, and `i32` mean and
division change the result dtype. These are operation contracts that a checker
can reason about without knowing the storage implementation.

Eager concrete tensors and symbolic tensors should implement that same typed
operation interface. A symbolic node records an operation and tensor metadata;
an interpreter applies it to concrete operands, and a compiler lowers it to
concrete target operations. Concrete values remain language values throughout.
The eager core exposes these operation boundaries and validates them at runtime.
The companion [static interface](typeclasses.md) now integrates with the checker:
it specializes operations for immediate or symbolic nominal carriers and supplies
a symbolic interpreter. Element dtype and shape remain runtime metadata. It does
not fuse kernels, generate GPU programs, or implement differentiation.

Kernels are scalar in this MVP. Explicit SIMD can be added within numeric
kernels or introduced by compiler lowering without changing the Scheme API.
There are no performance claims or benchmark results yet. Other deliberate
limits are contiguous layouts, flat gather/scatter, binary elementwise
operations, one-axis reductions, and rank-two matmul.
