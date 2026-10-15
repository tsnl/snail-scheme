# Exact rational values

`(snail rational)` represents a `Rational` as an immutable numerator and
denominator from `(snail integer)`. `make-rational` rejects a zero denominator,
moves its sign to the numerator, and divides both components by their greatest
common divisor. The denominator is always positive. Zero is always `0/1`.
Raw construction is private; the public numerator and denominator accessors
return immutable Integer values.

```scheme
(import (snail strict) (snail integer) (snail rational))
(define half (make-rational (integer-from-i64 2) (integer-from-i64 -4)))
(rational->string half)                 ; "-1/2"
(rational->string (+ half half))        ; "-1"
(integer->string (truncate half))       ; "0"
```

The existing static `+`, `-`, `*`, `/`, `=`, `<`, `<=`, `>`, `>=` and `truncate`
families have concrete Rational methods. `/` on two Integers constructs a
Rational. Other mixed types still require an explicit conversion. Named
procedures expose the same operations; `rational-truncate` and `rational-floor`
return Integers. Numerators and denominators are multiplied exactly before a
result is reduced, so intermediate size affects allocation rather than value.

`rational-from-f64` preserves the exact value of a finite binary64 argument.
For example, binary64 `0.1` becomes `3602879701896397/36028797018963968`.
Negative zero becomes exact zero; NaN and infinities are rejected. Scaling a
fractional value by an exact power of two until integral exposes that dyadic
value without narrowing through I64. `rational->f64` uses the Integer library's
single nearest-even rounding of the exact ratio, including subnormals, signed
underflow and overflow. `rational->string` emits reduced decimal `n/d`, omitting
the denominator when it is one.

`scripts/test-strict-numbers` compares complete numerator/denominator text and
every binary64 output bit with Python `Fraction`. It exercises reduction,
negative denominators, all arithmetic operations, comparisons, truncation,
floor, exact float conversion, zero denominators and nonfinite failures on raw
Wasm, optimized Wasm, native64 and forced native collection.
