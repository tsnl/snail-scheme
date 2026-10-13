# Concrete Wasm operations

`(snail unsafe)` is an opt-in library for writing low-level Scheme routines over
Wasm scalars and managed GC references. Import it with a prefix to distinguish
its operations from checked Scheme procedures:

```scheme
(import (scheme base) (prefix (snail unsafe) w:))
(w:: add32 (w:-> w:I32 w:I32 w:I32))
(define (add32 a b) (w:i32.add a b))
(add32 2147483647 1) ; -2147483648
```

The ordinary `+`, `-`, and `*` retain checked signed-64 integer arithmetic.
Low-level `i32.add/sub/mul` and `i64.add/sub/mul` use Wasm wrapping arithmetic.
`i32.eq`, `i32.lt_s`, and `i32.lt_u` produce Scheme booleans; the suffix chooses
signed or unsigned comparison of the same 32-bit patterns.

| Annotation | Semantic values | Concrete storage |
| --- | --- | --- |
| `I32` | Signed 32-bit exact integers | `i32` |
| `I64` | Exact integers (an alias for `ExactInteger`) | `i64` |
| `F32` | Binary32-representable inexact values, including NaNs and infinities | `f32` |
| `F64` | Inexact values (an alias for `InexactReal`) | `f64` |
| `Eqref` | Any ordinary Scheme value (an alias for `Any`) | `eqref` |
| `VectorRef`, `PairRef`, `BytevectorRef` | Existing vector/pair/bytevector categories | `(ref $vector_object)`, `(ref $pair)`, `(ref $bytevector)` |
| `StringRef`, `ClosureRef` | Existing string/procedure categories | `(ref $text_object)`, `(ref $closure)` |
| `RecordRef`, `ComplexRef` | Existing record/complex categories | `(ref $record)`, `(ref $complex)` |

Reference names are aliases for existing semantic categories, not new nominal
heap types. They carry real WasmGC references, never numeric addresses. The engine traces live references through allocations
and callbacks. Generic Scheme calls retain their boxed ABI. Known parameters,
results, bindings, captures, and container fields use concrete storage when the whole-program
constraints permit it. Managed reference conversions preserve object identity.

`I32` has the same value range as the existing checked `i32` annotation, which
continues to permit `i64` intermediate arithmetic. `F32` annotations check that a
finite value survives an `f64`→`f32`→`f64` round trip exactly; both zero signs,
infinities, and NaNs are accepted. Explicit `i32.wrap_i64` truncates to 32 bits;
`i64.extend_i32` sign extends. `f32.demote_f64` rounds to binary32, while
`f64.promote_f32` widens exactly. The `f32` and `f64` families each provide
`add`, `sub`, `mul`, and `div` with Wasm floating-point behavior.

`vector.length`, `vector.new`, `vector.ref`, `vector.set!`, and `vector.copy!`
operate on public GC vectors, with `I32` lengths/indices. Their actual backing
arrays may contain inferred primitive scalars or typed references. Arguments
are `(vector)`, `(length fill)`, `(vector index)`, `(vector index value)`, and
`(destination at source start count)`, respectively. Bounds remain enforced by
WasmGC. Negative bit patterns used as lengths/indices are interpreted by the
Wasm array instruction and can trap. A copy has overlap-safe Wasm `array.copy`
behavior and moves opaque element references without interpreting them as
single values. A loaded element retains unknown cardinality; its consuming
Scheme context supplies the usual single-value check.

Every operation remains an ordinary procedure value with a generic adapter, so
aliases and dynamic `apply` work. Known calls use concrete entries after the
same operand/operator evaluation and boundary checks. Type annotations do not
make a mutable binding or an unknown callback immutable. Source `All` variables
remain rigid while checking the original body; specialization only substitutes
concrete types into already checked copies.

`(Array T)` describes an explicit fixed element contract and `(Storage T)` is a
managed witness used to construct it. Both are invariant in `T`. An `Array F64`
is also a Scheme vector, but it is not an `Array Eqref`; generic and foreign
aliases must respect its original element contract. Ordinary inferred vectors
keep their normal mutation semantics. Annotating an ordinary vector with
`(Array T)` checks for an existing constructor contract and never installs one,
even when the vector is empty or its current elements all have type `T`.

```scheme
(import (scheme base) (snail unsafe))
(: filled (All (T) (-> (Storage T) T (Array T))))
(define (filled storage value) (array.new storage 4 value))
(define numbers (filled storage.f64 1.25))
(array.set! numbers 2 2.5)
(define twice (array.append storage.f64 numbers numbers))
```

The witness constants are `storage.eqref`, `storage.i32`, `storage.i64`,
`storage.f32`, `storage.f64`, `storage.boolean`, `storage.character`,
`storage.pair`, `storage.vector`, `storage.string`, `storage.bytevector`,
`storage.closure`, `storage.record`, and `storage.complex`. Their corresponding
`T` types are the concrete categories above, plus `Boolean` and `Char`.
Exact category aliases such as `ExactInteger` are accepted. Narrower types such
as `True`, a nominal record type, a function signature, or an arbitrary union
cannot be Array/Storage element contracts. A record or closure codec proves
its broad category, not a nominal or callable contract. A rigid `All` variable
can stand for a supported concrete category; unsupported instantiations receive
a located source diagnostic.

| Operation | Arguments | Result |
| --- | --- | --- |
| `array.empty` | storage witness | Fresh empty `Array T` |
| `array.new` | witness, I32 length, fill of type T | Fresh filled `Array T` |
| `array.length` | array | I32 length |
| `array.ref` | array, I32 index | One element of type T |
| `array.set!` | array, I32 index, value of type T | Unspecified |
| `array.copy!` | destination, I32 at, source, I32 start, I32 count | Unspecified |
| `array.append` | witness, left array, right array | Fresh `Array T` |

`array.append` is binary. It is implemented in Scheme over fixed array
construction and bulk copying. Both inputs must have the witness's exact
contract; empty arrays still retain that contract. Length addition rejects
signed overflow before allocation. Numeric arrays contain primitive `i32`,
`i64`, `f32`, or `f64` elements; reference arrays contain real managed GC
references. Known Array operations use codec-native entries even when an opaque
factory produced the object. Equal-codec copying uses Wasm `array.copy`, with
no per-element scalar boxing. Copies are shallow and overlap-safe. Scalar
unboxing and reboxing do not promise numeric box identity under `eq?`.

Every write through a Scheme or foreign alias enforces the constructor contract.
A generic `vector-copy!` into an explicit array checks both ranges and every
incoming value before writing any element. A failed type check leaves the
destination unchanged. Raw copies never consume a values envelope. `Array Eqref`
can store such envelopes through AWI, and its element reads retain the normal
single-value check at their consuming source boundary. Numeric and concrete
reference codecs reject raw envelopes instead of unwrapping them early.

Arbitrary Wasm heap-type declarations, nullable-reference syntax, packed i8/i16
arrays, and raw linear-memory access are not exposed.

The checked `(scheme base)` library implements `vector-append`, `vector-copy`,
and `vector-copy!` in Scheme over the raw copying operation. Results are fresh
shallow vectors; copies preserve managed element references, and overlapping
slices behave like `array.copy`. Single-list `map`/`for-each` and single-vector traversal use
fixed helpers. Vector traversal retains the previous shallow snapshot and
backward element-count validation before invoking callbacks. The snapshot stores
the once-normalized references, including foreign singleton envelopes;
multi-vector calls currently retain their general list-based path.

Known calls to rest procedures pass fixed arguments and one freshly constructed
rest list directly to the existing worker. Specialization can normalize that
rest list to an ordinary parameter. Immutable callback binding identities join
copy keys and select direct entries while retaining the evaluated closure and
its environment. An originally opaque `Procedure` view of an `All` function
still uses the erased generic contract, so stronger target knowledge cannot
move a post-body result check to its arguments. Mutable/unknown callbacks and
exhausted copy budgets retain generic calls.
