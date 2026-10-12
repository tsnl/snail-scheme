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
| `VectorRef`, `PairRef`, `BytevectorRef` | Existing vector/pair/bytevector categories | `(ref $vector)`, `(ref $pair)`, `(ref $bytevector)` |
| `StringRef`, `ClosureRef` | Existing string/procedure categories | `(ref $text_object)`, `(ref $closure)` |

Reference names are aliases for existing semantic categories, not new nominal
heap types or parameterized array layouts. They carry real WasmGC references,
never numeric addresses. The engine traces live references through allocations
and callbacks. Containers and escaping closures retain their generic Scheme
ABI; crossing that boundary boxes scalars and preserves reference identity.

`I32` has the same value range as the existing checked `i32` annotation, which
continues to permit `i64` intermediate arithmetic. `F32` annotations check that a
finite value survives an `f64`→`f32`→`f64` round trip exactly; both zero signs,
infinities, and NaNs are accepted. Explicit `i32.wrap_i64` truncates to 32 bits;
`i64.extend_i32` sign extends. `f32.demote_f64` rounds to binary32, while
`f64.promote_f32` widens exactly. The `f32` and `f64` families each provide
`add`, `sub`, `mul`, and `div` with Wasm floating-point behavior.

`vector.length`, `vector.new`, `vector.ref`, `vector.set!`, and `vector.copy!`
operate on the existing GC vector layout, with `I32` lengths/indices. Arguments
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

The implementation currently covers these scalar operations and existing
non-nullable reference categories. Arbitrary Wasm heap-type declarations,
nullable-reference syntax, packed typed element vectors, and raw linear-memory
access are not exposed.

The checked `(scheme base)` library implements `vector-append`, `vector-copy`,
and `vector-copy!` in Scheme over the raw copying operation. Results are fresh
shallow vectors; copies preserve element identity and overlapping slices behave
like `array.copy`. Single-list `map`/`for-each` and single-vector traversal use
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
