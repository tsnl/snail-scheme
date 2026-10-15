# Complete Ray preparation

The original count of 50 complete 100 × 100 renders passes in raw and optimized
linked Wasm, untouched Chez and the adapted-source Chez control. All 160 final
correctness executions pass. No clean performance samples are included.
Source commit `024b3d1d7d6758de9266a7802a25849537fc7e57` follows the general round,
scalar text-output and initialization-trap cleanup prerequisites. The final r2
preparation freezes all 70 compiler/runtime source files against basis
`053a8d85860be536095247e3217db60c45908a70` and verifies 187 case artifact hashes.

The canonical image is 29,517 bytes with SHA-256
`38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d`.
Its 10,000 pixel values retain the independently established upstream checksum
`2504547e212cb609b776f06ac18c74915dac54a988e42f9584d0509c03f044eb`.
The original Chez reference, all image bytes and command records are archived.
Checksums are checked outside workload timing, after the original result predicate.

## Source and representation

The complete scene construction, sphere scans, geometry, coordinate conversions,
rounding, integer formatting and per-character output remain in Scheme. Point
and Sphere are immutable nominal products. Separate Root and Candidate variants
preserve absence versus zero, negative or nonfinite values. A Hit correlates its
sphere and point; one explicit Ref holds the proper world list. Every pixel
visits all 33 spheres in reverse construction order. Candidate selection still
computes Euclidean distance and updates only for strict improvement from the
original finite `1e308` threshold. Negative roots are retained.

Counted source edits make left association of variadic floating operations
explicit and preserve the original conversion sites and single discriminant
square root. Unary negation becomes multiplication by `-1.0`. Two-argument
min/max preserve Chez's NaN propagation and right-operand signed-zero ties.
Bit-pattern probes check these boundaries, including the linear quadratic case,
zero/negative roots, equal-distance spheres, NaN candidates and overflowing
distance calculations. No robustified intersection algorithm is substituted.

The adapted Chez control uses the same kernel, tagged wrappers and exact Scheme
character/decimal formatter bodies as the strict library. Preparation verifies
those formatter bodies against the library and reverses the complete source
transformation back to untouched Chez text. Root/Candidate wrappers can add
allocations, and Hit construction occurs on improvements instead of the
original final two-field vector construction. Native Chez ports and Rust-owned
ports also retain their own runtime layouts. Physical allocation equivalence is
not claimed.

The original result can only be false before any repetition or the symbol `ok`
after a completed render. Strict encodes those as I64 0/1; every other expected
datum maps to 2. This preserves the complete equality answer without restricting
wrong expectations. The actual Chez reader classifies inputs before timing,
including escaped symbols, alternate false spellings, booleans, numbers,
strings and compound data. Wrong expectations still execute every repetition.
Adapted Chez restores the original values for its predicate and diagnostics.

## Linked runtime and ownership

The general `(snail io)` library keeps String traversal and full-I64 decimal
formatting in Scheme. Scalar Rust exports consume staged Unicode pathnames and
own buffered files behind monotonic IDs. A shared Ref makes explicit close
idempotent across Scheme aliases. No Scheme value enters Rust's file registry.
The linker reuses the ordinary Rust crate, removes its private exports and
eliminates the legacy Root interface. Both full optimization and reachability-
only pruning were tested through actual Node execution before the port.

The canonical module imports five scalar benchmark inputs and WASI only. Its
exports are `bench`, `main`, `memory`, `_initialize` and `close-resources`.
The host's cleanup scope begins before reactor initialization and Scheme main.
A real top-level open-then-trap fixture checks that buffered text is flushed and
the descriptor closed. Other raw/optimized Node fixtures cover Unicode paths,
I64 formatting boundaries, aliases, self-closing callbacks, malformed raw IDs,
callback traps and injected write failures. Rust drops removed ports before
fatal reporting and attempts every outstanding close after a returned error.
The instance remains terminal after a trap; arbitrary host-import traps during
cleanup are outside the contract.

## Correctness and retained work

The final preparation includes 12 canonical executions at counts 1, 2 and 50;
144 separate small-image/predicate executions; and four geometry executions with
222 observations each. Small viewports cover resolutions 0, 1, 2 and 3, repeated
renders, Unicode paths, existing-file replacement, nonpositive counts and ten
expected-datum forms. Every complete image agrees across original/adapted Chez
and raw/optimized Wasm. Geometry observations include all 33 complete sphere
records, independently checked in their exact traversal order.

The exact optimized module is
`c0fbff207e707c2de1aa17c063f9f81ecf06b6ba09fa326de5c268b65e8d65ab`.
A separate observer copy counts function entries, WasmGC construction/store
sites, square roots and pixel rounding without reoptimization. Removing the
observer additions restores the original optimized text exactly. Untimed setup
counts are subtracted before the worker. Constant global initializers remain
uninstrumented because Wasm forbids effectful observers there; the initial
validator rejection and corrected assembly record are both retained.

At count 50, the closest-hit loop has 17,000,000 entries: 16,500,000 sphere visits
and 500,000 terminal visits. Pixel rounding occurs 500,000 times. The module
constructs 1,650 sphere products and 320,350 improving Hit products, and computes
405,300 discriminant square roots plus 405,300 candidate-distance square roots.
Geometry and WasmGC construction-site counts scale exactly at counts 1, 2 and
50. The file trace has 50 successful opens/closes and 49 deletions from an
initially absent file. Runtime allocation and pathname-staging counts need not
scale linearly because the first render has no deletion and runtime setup can
be lazy. These are instrumented Wasm sites, not physical engine allocation or
performance counts.

The r2 canonical strict source, raw/optimized Wasm and both Chez source texts
are byte-identical to the r1 artifacts used for that audit. Final Chez binaries
were rebuilt and validated in r2. All 29 preceding port specifications and strict
programs remain unchanged. `make test`, `make check`, all 34 Rust unit tests,
21 native boundary cases and five new round rejection cases passed during the
prerequisite work; the final port also passes `make check` and executes real
linked Wasm. The [focused review](simplify-review.md) records the fresh behavioral
explanations, informed debate and deliberate representation costs.

The preparation covers the canonical workload and these bounded I64 probes.
Arbitrary-precision resolutions, overflowing extents and negative-resolution
termination are not claimed. Viewport overrides, geometry exports and observers
are absent from the canonical artifact. The frozen preparation is ready for a
parent-coordinated clean comparison; none is reported here.

Restore and verify the archive without executing a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-ray-replay \
  --report benchmarks/results/2026-10-14-strict-ray
```

The archive contains 428 regular files under `preparation`, `evidence`,
`pruning-proof`, and the focused I/O/round contract directories. Hash-only replay
verified every member. The preparation and observer command records distinguish
correctness diagnostics from clean performance samples.

The parent integrated the source as `61231c7`, preserving all 30 preceding
strict program texts and specifications byte-for-byte. All 70 frozen compiler
and runtime files match the preparation. The parent verified every one of the
428 archived files, ran `make check`, and executed both linked raw and optimized
Ray modules against the integrated host. Each diagnostic render checked all
10,000 pixels, the complete PGM bytes, and resource cleanup. These count-one
checks are recorded in `parent-integration-review.json`; their durations are not
performance samples.
