# Checked numeric narrowing

Run `scripts/test-lofi-narrowing`. It supplies 55 runtime cases to direct and
first-class conversion calls on raw and optimized Wasm. Each run retains its
inputs, commands, outcomes and artifact hashes under `build/lofi-narrowing/`.

Integer expectations use the signed I32 range. The retained float expectations
use independent binary32 packing, with explicit expected
answers at seven rounding boundaries. Cases cover both signs,
integer endpoints, ties to even, the finite-overflow rounding boundary,
subnormals, signed zero, infinity and NaN. Explicit argument effects must occur
once, including before a conversion traps. Discarded invalid results must still
trap; untaken runtime branches must leave no effect. Both Wasm forms use the
scalar effect probe. The host records effects before a trap and also calls the
instance again afterward.

The earlier conversion fixture expected I64 `4294967295` to wrap to I32 `-1`.
That behavior conflicts with the book. It now tests an in-range conversion;
this suite requires the overflowing value to trap. The scalar-service suite
likewise preserves its four finite F64-to-F32 overflow inputs as explicit trap
cases rather than accepting infinities.

These checks cover primitive conversions. The
[arithmetic suite](../lofi-arithmetic/README.md) separately checks runtime
wrapping integer and IEEE floating-point arithmetic.

A fresh explanation without repository access and an informed critique kept the
two conversion helpers. Held operands establish evaluation once; a stored F32
establishes rounding once. The review rejected extra conversion-policy state and
a generic numeric framework, and added discarded-result, branch and trap effect
checks. The test input matrix, build/run orchestration and JavaScript oracle keep
the complete verification step visible.
