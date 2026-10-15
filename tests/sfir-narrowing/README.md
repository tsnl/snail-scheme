# Checked numeric narrowing

Run `scripts/test-sfir-narrowing`. It supplies 55 runtime cases to direct and
first-class conversion calls on raw Wasm, optimized Wasm and native. Native
lowering must consume the same optimized guest bytes. Each run retains its
inputs, commands, outcomes and artifact hashes under `build/sfir-narrowing/`.

Integer expectations use the signed I32 range. Float expectations use Python's
binary32 packing, independently of the SFIR emitter, with explicit expected
answers at seven rounding boundaries. Cases cover both signs,
integer endpoints, ties to even, the finite-overflow rounding boundary,
subnormals, signed zero, infinity and NaN. Explicit argument effects must occur
once, including before a conversion traps. Discarded invalid results must still
trap; untaken runtime branches must leave no effect. Both targets use the existing
scalar effect probe; native writes are unbuffered so effects survive trap
termination. The Wasm checks also call the instance again after a trap; native
failure cases run in separate processes.

The earlier conversion fixture expected I64 `4294967295` to wrap to I32 `-1`.
That behavior conflicts with the book. It now tests an in-range conversion;
this suite requires the overflowing value to trap. The scalar-service suite
likewise preserves its four finite F64-to-F32 overflow inputs as explicit trap
cases rather than accepting infinities.

These checks cover primitive conversions. Runtime arithmetic overflow remains
separate work in the roadmap. Native execution uses the ordinary process
floating-point environment; altered rounding modes and flush-to-zero settings
are outside this verification.

A fresh explanation without repository access and an informed critique kept the
two conversion helpers. Held operands establish evaluation once; a stored F32
establishes rounding once. The review rejected extra conversion-policy state and
a generic numeric framework, and added discarded-result, branch and native trap
effect checks. The test input matrix, build/run orchestration and C dispatch stay
together where splitting them would obscure their complete verification step.
