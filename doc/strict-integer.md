# Exact integers in strict Scheme

`(snail integer)` implements arbitrary-precision signed integers in ordinary
strict Scheme. `Integer` is a concrete immutable nominal value. Its private
little-endian `(Vector I32)` stores radix-2^30 limbs directly in WasmGC array
storage. The value never crosses the legacy Rust rooted-value ABI. The same
optimized Wasm representation also lowers to the native64 executor.

```scheme
(import (snail strict) (snail integer))
(define n (integer-from-string "123456789012345678901234567890"))
(integer->string (* n n))
(integer->string (integer-sqrt n))
```

The library adds `Integer` methods to the existing static `+`, `-`, `*`, `=`,
`<`, `<=`, `>`, `>=`, `quotient` and `remainder` families. Unary `-` negates an
integer. Conversions are explicit: an ordinary source integer literal remains
`I64`, and `integer-from-i64` lifts its exact value. Existing I64 arithmetic
retains its existing bounded behavior. There is no dynamic numeric fallback.

| Operation | Contract |
| --- | --- |
| `integer-from-i64`, `integer->i64` | Exact conversion; narrowing traps outside signed I64. |
| `integer-from-string`, `integer->string` | Decimal grammar `[+-]?[0-9]+`; canonical decimal output with no leading zeros or negative zero. |
| `integer-zero?`, `integer-negative?`, `integer-abs`, `integer-negate` | Sign operations on immutable values. |
| `integer-compare` | Returns I64 `-1`, `0` or `1`. Named comparison and arithmetic procedures accompany the operator methods. |
| `integer-divide` | Returns `IntegerDivision`, inspected with `division-quotient` and `division-remainder`. |
| `integer-expt`, `integer-power` | Repeated squaring with an Integer or I64 nonnegative exponent respectively; exponent zero returns one, including `0^0`. |
| `integer-sqrt` | Floor square root of a nonnegative Integer. |
| `integer-sqrt/remainder` | Returns `IntegerRoot`, inspected with `root-value` and `root-remainder`; `n=s*s+r` and `0<=r<2*s+1`. |

Division truncates toward zero: `a=q*b+r`, `abs(r)<abs(b)`, and a nonzero
remainder has the dividend's sign. Division by zero, negative square root or
exponent, malformed decimal text and narrowing overflow trap. General rational
numbers and implicit numeric promotion are not implemented by this library.

Raw constructors and limb accessors are private. Every operation that writes
limbs owns fresh scratch storage, including division when its normalization
factor is one. Published arrays are never written again. Negation and absolute
value can therefore share them safely. Decimal inputs are parsed without being
retained; each formatted string is independently mutable.

Addition and subtraction traverse the magnitudes once. Schoolbook multiplication
is quadratic, with every accumulated product bounded by `2^60-1`, including the
old output digit and carry. Normalized long division checks the next divisor
digit after estimating a quotient digit, then corrects a remaining borrow by
adding the divisor back. Its cost is `O((n-m+1)*m)` for `n` dividend limbs and
`m` divisor limbs. The code records the borrow/carry bounds beside those loops.
In the trial-product subtraction, the product is nonnegative and at most
`B*(B-1)` for `B=2^30`. Its low limb and high carry therefore use the ordinary
I64 bitwise-and and logical-right-shift primitives. If the high carry reaches
`B-1`, the low limb is zero, so subtraction cannot add another borrow. Signed
division elsewhere keeps its truncation-toward-zero behavior.
Newton square root starts at `2^ceil(bitlength(n)/2)` and stops when the next
estimate does not decrease. This also terminates correctly for `n=3`.

Decimal conversion processes nine digits per magnitude pass; it is quadratic
with this binary radix. This trades linear decimal formatting for simple bounded
binary arithmetic and a direct square-root seed. Faster multiplication or
recursive division would add complexity without a measured need at the current
benchmark precisions.

`scripts/test-strict-integer` builds and executes raw Wasm, mandatory Binaryen
optimized Wasm and native64. Python's arbitrary-precision integers specify full
results independently. Cases include signed division, carries, borrows,
quotient-estimate corrections, addback, I64 endpoints, square-root bounds,
large exponents, decimal ownership and failure paths. Forced native collection
checks retain operands and shared immutable magnitudes across allocations;
compile rejections check the private constructor and explicit I64 conversion. The final module-local
`Tests` section supplies an exhaustive bounded-machine oracle. Its runner
materializes the same arithmetic at radix 4 as a separate diagnostic source,
retaining both changed constants and all generated artifacts. This small-radix
copy tests arithmetic; production decimal grouping remains radix 2^30.
