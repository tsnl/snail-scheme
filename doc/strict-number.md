# Explicit Number boundaries

`(snail number)` combines the immutable Integer/Rational libraries with F64
and rectangular complex values. This is a concrete data type for boundaries
that admit several numeric kinds. It does not change the representation or
bounded behavior of an explicitly typed I64 operation.

`exact-number` and `exact-scalar` retain their I64 constructor arguments.
`rational-number` and `rational-scalar` carry a normalized `Rational`, including
arbitrary integers whose denominator is one. `number-from-integer`,
`number-from-rational` and `scalar-from-rational` select the small representation
when an integral value fits I64. Exact arithmetic uses Integer/Rational
operations before choosing the result representation, so small inputs can
produce an arbitrary exact result without overflow.

The existing `+`, `-`, `*`, `/`, comparisons and `truncate` families have static
Number methods, with named `number-add`, `number-divide` and corresponding
procedures exposing the same behavior. Exact components stay exact. Inexact
scalar arithmetic promotes exact operands to F64 explicitly. Rectangular
arithmetic applies the component formulas; inexact intermediate operations
retain IEEE overflow, underflow and NaN behavior. It does not promise a scaled
complex division algorithm or correctly rounded transcendental results.

Finite mixed comparisons use the exact dyadic value of the F64 operand rather
than rounding the exact operand: exact `9007199254740993` exceeds F64
`9007199254740992.0`. NaN is unordered. Ordering and real conversions reject a
nonzero imaginary component, checking exact zero before any float conversion.

`number-exact` preserves every finite binary64 component as its exact dyadic
value, and rejects infinity/NaN. `number-inexact` performs the explicit
nearest-even conversion. `number-truncate` returns an integral Number with the
input's exactness. `number->integer` requires an exact integral real value;
`number->rational` accepts finite real values and exactly decodes any F64.
`number-real-part`, `number-imag-part`, `number-numerator` and
`number-denominator` return Numbers. Scalar input has exact zero imaginary
part; numerator and denominator retain the input real scalar's exactness.
The numerator of inexact negative zero retains its sign. An inexact denominator
too large for finite binary64 becomes positive infinity.

`number-rectangular` first collapses an exact imaginary zero, then promotes a
surviving mixed pair. Inexact imaginary zero preserves complex shape and its
sign. Public raw data constructors retain their supplied representations.
`number-equivalent?` keeps that shape and exactness, distinguishes signed zero,
and equates NaNs. Numeric `=` compares values across shapes and exactness.

`number->string` emits normalized exact decimal text or binary64 text from the
shared Rust formatter; rectangular output retains both components. Formatting
uses a temporary Rust-owned text handle, copies characters into a fresh Scheme
String, and closes the handle without invoking user code. Trap cleanup releases
unfinished handles. The associated reader and formatter never store Scheme
roots in Rust.

`scripts/test-strict-numbers --domain` checks arithmetic beyond I64, exact and
inexact comparisons, numeric domains, projections, formatting round trips and
failure paths on linked raw/optimized Wasm and native64. The separate arithmetic
oracle specifies full exact results independently with Python `Fraction`.
