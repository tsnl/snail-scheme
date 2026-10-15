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

## Complete pi and Chudnovsky ports

Both full original workloads pass the following controls, each comparing the
entire numerical result rather than a checksum or selected digits:

| Workload | Original repetitions | Digit arguments | Complete output |
| --- | --- | --- | --- |
| pi | 100 | 50 through 500, step 50 | All ten rows, each containing Borwein2 and the two original difference columns |
| Chudnovsky | 1,000 | 50 through 500, step 50 | All ten arbitrary-precision results |

Every row was checked on untouched-algorithm Chez, source-adapted Chez using
native big integers, the same limb Scheme body on Chez with checked I64/I32
arithmetic, raw Wasm, mandatory Binaryen-optimized Wasm, and actual native64.
The full original Brent–Salamin, quadratic Borwein, quartic Borwein, and
Chudnovsky binary-split algorithms remain in the adapters. Pi's original
rounding differences are preserved exactly.

The [pi source ledger](pi/edits.json) and
[Chudnovsky source ledger](chudnovsky/edits.json) restore the original files
byte-for-byte, including the replaced multiple-value square-root wrappers.
Bounded source constants are lifted explicitly; arbitrary-precision calculations
never narrow to I64. The adapter associates three exact n-ary products into
binary products and supplies the original floating term-count expression using
explicit F64 conversion and floor. Repetition/digit controls retain I64 types.
The tested canonical inputs and full precisions are unchanged.

The native-bigint Chez adapter is a source-equivalence control. The separate
same-limb Chez control executes the exact library algorithm body, translating
only typed records, declarations, vector-copy argument conventions and bounded
scalar operations. Its scalar arithmetic traps outside I64/I32; it cannot mask
an unintended fixed-width overflow with Chez big integers. Native Chez number
reading/writing is used for the independent expected data and final serialization,
after all limb computation finishes.

The frozen [pi archive](pi.tar.gz) and [Chudnovsky archive](chudnovsky.tar.gz)
contain all three Chez programs and outputs, strict source, complete inputs and
expected tables, raw/optimized Wasm, native binaries/LLVM, command records and
build metadata. The reviewable complete outputs are
[pi/complete.output](pi/complete.output) and
[chudnovsky/complete.output](chudnovsky/complete.output).

Optimized modules are 19,458 bytes (pi) and 18,558 bytes (Chudnovsky), including
full result comparison and observation. Their six remaining imports transport
bounded inputs, expected decimal characters, opacity calls and output characters.
They contain direct I32 GC arrays and no legacy value-ABI imports or `i31`
number operations. The [representation records](pi/representation.json) and
[Chudnovsky counterpart](chudnovsky/representation.json) preserve that inspection.
These sizes describe preparation artifacts; they are not performance results.

Reproduce with
`python3 benchmarks/strict-suite/integer_ports.py pi chudnovsky`.
The dedicated runner verifies the clean pinned corpus, completes all preparation
before any later timing, and preserves failures. Its public scalar providers do
no numerical work. These two workloads are prepared for later suite integration
and coordinated clean measurement; the suite's measured-coverage count is not
changed by this report.

## Review follow-up

The [follow-up manifest](followup/manifest.json) records 2,904 oracle cases:
2,861 complete answers and 43 required traps on raw Wasm, Binaryen-optimized
Wasm, and native64. Forty-two ownership/interface/exponent cases also passed
with native collection at every allocation. Eight added long-division cases
cover all sign combinations with normalization scale one, including an addback
witness. They retain both input values, their negations and absolute values,
then check both division equations and every retained alias after division.

Small direct interface assertions now call `integer-power`, `root-value`, unary
`-`, all four ordered comparison overloads, and sign predicates. Static checks
also reject the private `integer-limbs` accessor. The first ownership run and
the final interface run have separate source snapshots and command archives.
The library changed only one proof comment: `B^2 = 2^60` replaces the incorrect
strict inequality; arithmetic code is byte-for-byte unchanged.

The runner now records only groups executed in its current invocation and
removes an older summary before starting. A focused synthetic runner check
confirms stale unit/oracle files cannot credit an omitted group, and a failed
invocation cannot leave a successful summary. The final follow-up used
`--only oracle`; the exhaustive radix checks remain the earlier recorded
evidence. No timing was taken.

The [independent integration run](integration-validation.json) then rebuilt the
final source above the typed reader and both allocator-inlining annotations.
All three groups passed in this fresh output directory: both 64,512-pair radix
checks and the 2,904-case production oracle on raw/optimized Wasm and native,
including forced collection and the source rejections. The record retains every
test command and its output, plus compiler/runtime source identities. Required
source errors leave three incomplete compiler trace files; those are recorded
separately and are not used as test outcomes. `make test` and `make check` also
passed during integration.

The [preparation review](integration-preparation-review.json) independently
verifies the three initial archive hashes, reversible source ledgers and
unchanged canonical inputs. All six archived complete outputs match for each
numeric workload. These checks add correctness evidence, not timing samples.
