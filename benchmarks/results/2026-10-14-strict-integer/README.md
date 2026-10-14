# Strict exact-integer preparation

`(snail integer)` now provides reusable arbitrary-precision exact arithmetic
using a private immutable nominal product and little-endian 30-bit limbs in a
specialized WasmGC I32 array. Constructors and limb accessors are private.
Every mutable arithmetic buffer is freshly owned, including normalized division
when its scale is one. Negation and absolute value share only published immutable
arrays. No compiler primitive, Rust numeric object, rooted-value ABI, or
fixed-width fallback was added.

The public methods provide exact signed arithmetic, comparison, truncating
quotient/remainder, exponentiation, floor square root, and checked I64/decimal
conversion. Integer source literals still mean I64 until explicitly lifted.
See [the API and invariants](../../../doc/strict-integer.md).

## Executed checks

| Check | Result |
| --- | --- |
| Independent Python arithmetic/decimal oracle | 2,884 cases: 2,842 complete answers and 42 required traps on raw Wasm, Binaryen-optimized Wasm, and native64 |
| Exhaustive module-local arithmetic | 64,512 `(a,b)` pairs, `0<=a<1024`, `1<=b<64`, at radix 4 and radix 2^30, on all three targets |
| Native collection stress | 25 retained-operand, mutable-text ownership, and exponent cases with `SNAIL_NATIVE_GC_INTERVAL=1` |
| Static interface rejection | Raw Integer constructor remains inaccessible; mixing I64 and Integer without conversion is rejected |
| Repository checks | `make check`, `make test` passed |

The oracle includes all signed division combinations, long carry/borrow chains,
I64 endpoints, quotient-estimate corrections and addback, large squares and
neighbors, negative-operation failures, and exponent parity above I64 range.
At production radix `B=2^30`, its correction witnesses include
`B^3 / ((B/2)*B^2+1)` and
`((B/2-1)*B^2) / ((B/2)*B+B-1)`.
The same division code runs at small radix; the small-radix diagnostic does not
exercise production decimal chunk grouping.

## Evidence and reproduction

Run `scripts/test-strict-integer` with the tool paths in [manifest.json](manifest.json).
The [arithmetic archive](arithmetic.tar.gz) retains every oracle value, complete
command stdout/stderr, all expected failures, generated small-radix sources,
raw/optimized Wasm, native executables, native LLVM lowering, and build metadata.
The original tests ran against source SHA
`e5f08db0140df8e0930423eb9455343b11015cb53171087bbafcb18dfb9a6cf0`.
The repository formatter subsequently changed whitespace only;
[the token comparison](formatting-proof.json) proves the tested arithmetic body
is unchanged in the [final source snapshot](integer.sld).

Every process handle reached a terminal result. The checked-in runners own their
process groups, terminate timed-out descendants, and reject a remaining executing
group. These executions are correctness preparation; no clean performance
measurement was taken.

The independent simplify explanation used a fresh Astra/max agent with no
repository access. The resulting model kept one product rather than a separate
zero tag, retained checked negative accumulation for I64_MIN, and kept
normalization scratch independent even when scaling by one. Schoolbook products
and normalized division are deliberate quadratic algorithms for this tested
precision range. Their bounds and corrections remain beside the code. The
cohesive subtraction/normalization transitions and exhaustive test loop are the
small number of functions longer than the ten-line target.
