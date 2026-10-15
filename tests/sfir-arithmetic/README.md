# Checked fixed-width arithmetic

Run `scripts/test-sfir-arithmetic`. It executes 2,074 calls on raw Wasm,
Binaryen-optimized Wasm and native, including direct primitives, ordinary
overloads and function values selected from mutable storage. Both targets must
consume identical optimized guest bytes. Commands, inputs, terminal results and
artifact hashes are retained under `build/sfir-arithmetic/`.

Integer expectations use arbitrary-precision arithmetic. Floating expectations
compute an exact rational result, choose its binary spacing, and round once to
nearest with ties to even. Fixed anchors cover finite overflow and underflow
boundaries. Zero division, explicit infinities/NaNs and signed zeros retain IEEE
behavior. Tests include products that wrap to zero or a plausible inverse,
discarded results, untaken runtime branches and constant arithmetic.

Two foreign effects observe argument order before every operation. A third
effect observes evaluation of an indirect operator after its arguments. Native
output is unbuffered, so a trapping operation cannot hide its preceding effects.
Unit exports use the public void ABI. Native checks use the ordinary process
floating-point environment; modified rounding modes are outside this scope.

`libraries.sfir` separately checks the explicit wrapping/IEEE primitives,
nominal Number overflow, and exact-to-F64 rounding at the finite boundary. These
exceptions preserve documented algorithms without making ordinary fixed-width
operators unchecked. Existing Datum hash and Integer/Number suites cover the
migrated production callers.

A fresh independent explanation and critique established the integer sign tests
and multiplication recovery proof. The existing operand locals prevent repeated
source effects; one retained result suffices for checking. I32 operations use an
exact I64 intermediate; I64 multiplication conditionally divides its wrapped
result back, never evaluating division for zero. Float checks examine the
rounded result, preserving finite rounding back to the maximum. The review
rejected additional argument state, a generic numeric framework and an
unnecessary special MIN/-1 multiplication branch. Exhaustive test dispatch,
input matrices, exact binary rounding and build/run orchestration stay cohesive
where splitting them would obscure their complete operation.

The unchanged checked-call suite rejects the preceding compiler at `MAX32 + 1`,
so it detects the former unchecked behavior. During test authoring, the exact
oracle's sign extraction and the Unit ABI observer were corrected before the
successful target runs. The library fixture was also corrected to link its
ordinary scalar runtime services. Those failed command records remain retained.
