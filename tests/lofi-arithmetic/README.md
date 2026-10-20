# Fixed-width arithmetic

Run `scripts/test lofi-arithmetic`. It executes 2,074 calls on raw and
Binaryen-optimized Wasm, including direct primitives, ordinary overloads and
function values selected from mutable storage. Commands, inputs, terminal results
and artifact hashes are retained under `build/lofi-arithmetic/`.

I32/I64 addition, subtraction and multiplication wrap modulo their width.
Integer expectations use arbitrary-precision arithmetic reduced to that signed
width. Floating expectations retain the independently rounded binary results:
nearest with ties to even, including infinity on overflow, subnormals, signed
zero and NaN classification. No NaN payload or sign is required. Inputs cover
both signs, endpoints, products that wrap to zero, discarded results, untaken
runtime branches and constant arithmetic.

The corpus retains the same inputs as the preceding checked-arithmetic suite.
379 formerly trapping calls now succeed. The other 54 trap cases still test
integer division by zero, signed minimum divided by minus one, and remainder
by zero. Remainder of signed minimum by minus one is zero. The separate
[narrowing suite](../lofi-narrowing/README.md) retains checked conversions;
literal construction also remains checked.

Two foreign effects observe argument order before every operation. A third
effect observes evaluation of an indirect operator after its arguments. Discarding
an arithmetic result must preserve these effects and any required division trap.
The JavaScript host records effects before a trap. Unit exports use the public
void ABI.

`libraries.sld` checks ordinary arithmetic, the compatible named wrapping/IEEE
aliases, nominal Number overflow, and exact-to-F64 rounding at the finite
boundary. Existing Datum hash and Integer/Number suites exercise production
callers. Unbounded Integer arithmetic remains exact.

A fresh independent explanation and critique reduced lowering to the existing
Wasm opcodes shared by direct calls and primitive workers. The review rejected a
new arithmetic framework or constant folder: remove the overflow guards, retain
operand evaluation and checked conversions, and let Binaryen optimize the
result. Explicit checked-arithmetic variants remain future work. The initial
typed Scheme library shares the default Lofi arithmetic policy.
