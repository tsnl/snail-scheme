# Eager tensors and symbolic graphs

**Runnable CPU prototype.** Iverson Ghost provides concrete arrays and a typed
operation interface. The same generic function either computes immediately or
constructs a symbolic graph, according to its argument's static type. A graph
interpreter evaluates symbolic operations using concrete tensors.

Enter the development shell and run the commands below from the repository
root. [The build guide](../builds.md) describes the required tools.

## Concrete arrays, including ordinary vectors

`(snail-scheme iverson-ghost)` provides row-major tensors with a shape and an
explicit dtype. `(array dimensions flat-elements dtype)` constructs one.
Omitting the dtype selects `f64`.

| Dtype | Element storage | Use |
| --- | --- | --- |
| `object` | Tagged Scheme values | Mixed values and ordinary vectors. |
| `f64` | Unboxed 64-bit floats | Double-precision numeric operations. |
| `f32` | Unboxed 32-bit floats | Single-precision numeric operations. |
| `i32` | Unboxed signed 32-bit integers | Dense integer data and gather/scatter indices. |

A standard Scheme vector participates as a rank-one `object` tensor with its
existing mutability. Constructed arrays are immutable values. Operations return
new values; numeric reshapes can share private storage. `array->vector` returns
a fresh vector of the flattened elements.

The library implements elementwise arithmetic with trailing-axis broadcasting,
reductions, reshape, transpose, rank-two matrix multiplication, gather, and
functional scatter. Gather uses flattened `i32` indices. Repeated scatter
indices are processed in order: `scatter` keeps the last update and
`scatter-add` accumulates each update. Integer arithmetic wraps at 32 bits;
integer division and means produce `f64`.

This complete program, `examples/iverson-ghost/main.scm`, centers `f32` samples,
computes their covariance, accumulates an `i32` histogram, and gathers Scheme
objects from an ordinary vector:

```scheme
{{#include ../../../examples/iverson-ghost/main.scm}}
```

Its build script, `examples/iverson-ghost/build.scm`, links and executes Wasm:

```scheme
{{#include ../../../examples/iverson-ghost/build.scm}}
```

Run it with:

```sh
chibi-scheme -I src examples/iverson-ghost/build.scm
```

Expected output:

```text
centered: (f32 (3 2) #(-2.0 -2.0 0.0 0.0 2.0 2.0))
covariance: (f32 (2 2) #(2.6666667461395264 2.6666667461395264 2.6666667461395264 2.6666667461395264))
histogram: (i32 (3) #(1 1 3))
gathered names: (object (5) #(two zero two one two))
```

## One algorithm, two representations

`(snail-scheme iverson-typed)` defines the `TensorOperations` class and two nominal
carrier types. The immediate carrier wraps a concrete array; the symbolic
carrier stores an operation and its operands in Scheme records. Each implements
addition, multiplication, transpose, sum, and matrix multiplication.

The library's shared Gram-matrix algorithm is:

```scheme
(: tensor-gram (All (T) (=> ((TensorOperations T)) (-> T T))))
(define (tensor-gram x) (tensor-matmul (tensor-transpose x) x))
```

The constraint makes these operations available while checking the generic
body. Concrete uses select either `<immediate-tensor>` or `<symbolic-tensor>`
and request a specialization. [Static typeclasses](../typeclasses.md) explains
instance selection and first-class specialized procedures.

This complete program, `examples/iverson-ghost/typed.scm`, computes a Gram matrix,
builds the equivalent symbolic expression, and interprets it:

```scheme
{{#include ../../../examples/iverson-ghost/typed.scm}}
```

`tensor` constructs the immediate carrier. `symbolic-input` introduces a named
input. `evaluate` looks up each input with the supplied callback, checks that it
returns an immediate carrier, and evaluates the graph with the eager instance.
Its operation dispatch interprets graph nodes; typeclass instance selection was
already completed by the compiler.

The final `inst` explicitly selects a first-class immediate `tensor-square`
procedure. The numeric array remains a language value available to ordinary
Scheme code and to compiler-recognized kernel calls.

Build with `examples/iverson-ghost/typed-build.scm`:

```scheme
{{#include ../../../examples/iverson-ghost/typed-build.scm}}
```

Run the linked Wasm program:

```sh
chibi-scheme -I src examples/iverson-ghost/typed-build.scm
```

Expected output:

```text
#(10.0 14.0 14.0 20.0)
(matmul (transpose x) x)
#(10.0 14.0 14.0 20.0)
#(1.0 4.0 9.0 16.0)
```

## What the prototype establishes

Carrier selection and generic specialization use static type information.
Element dtype, rank, and dimensions are runtime metadata with checked operation
contracts. Numeric storage is unboxed; object storage contains GC-visible Scheme
values. Current kernels use scalar CPU loops in Wasm.

The symbolic interpreter evaluates a tree without memoization or graph
optimization. Graph-to-program compilation, static shape and dtype refinements,
explicit SIMD kernels, and GPU execution are future work. Differentiation is
deliberately omitted from the MVP.

`make test` checks host behavior and compiler elaboration. `scripts/test-typing`
checks static successes and failures in guarded and optimized modes.
`scripts/test-backend` executes concrete arrays, overloads, and eager/symbolic
tensor programs as linked Wasm on Node.js.

## Training nodes and artifacts (planned)

A future tensor compiler can publish graph programs alongside a training node
and browser artifacts. Compiling the graph performs no training. The training
node can own parameters and device buffers while a browser workbook sends pause,
resume, checkpoint, or cancellation requests and receives progress messages.

The [node model](../nodes.md) separates those states and lifetimes. Device work
must retain its buffers until completion. Checkpoints also need optimizer state,
random-number state, and dataset position. The application decides whether
closing a workbook only disconnects it or stops training. These workflows and
graph compilation extend beyond the runnable array and interpreter prototype.
