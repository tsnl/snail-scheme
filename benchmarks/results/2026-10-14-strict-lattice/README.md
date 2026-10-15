# Full lattice preparation

The original ten invocations of `run(44)` return `120549` in raw Wasm, optimized
Wasm, untouched Chez and the adapted-source Chez control. All 36 behavior checks
pass. No clean timing measurements are included. Source port `b47381a` and
validation-record fix `4f1dedc` add no compiler changes: all 52 compiler/build
files match native String basis `2def9941eb85f211e116e6955799fdc9ef561da8`.

Parametric immutable products represent lattices and partial source/target
bindings. Proper lists use a closed empty/node variant with an immutable head
and explicit Ref tail. This preserves selection's reversed accumulator and
destructive reversal of its exact nodes, the two complete constraint scans,
lower-before-upper short-circuiting, candidate order, shared binding tails,
mapped branch-result lists, recursive summation and append's final-tail sharing.
The four comparison symbols become I64 codes; membership traverses the two
original constant tag lists and normalizes its truth result to Bool. Quoted
base/tag lists stay in untimed initialization.

All generic operations have rigid explicit `All` contracts. The original
`xreverse!` initializer is eta-expanded to a function value to satisfy the value
restriction; its local rotation still reads the old tail, mutates the current
tail, then returns or recurses with those same nodes. The original Chez source
is unchanged. The adapted control shares the strict kernel and generic list
helpers, with pair/vector constructors in place of concrete WasmGC products and
Refs. Reversing the full kernel/helper replacement recovers original Chez text
byte for byte. Both source patches are archived.

Each mutable node adds a Ref allocation compared with an upstream pair; strict
also has explicit empty variants and different closure/record layouts. Physical
allocation equivalence is not claimed. The strict scalar harness uses the actual
returned hidden input on every repetition and checks the final integer result
before stopping its timer. Nonpositive repeat counts trap, matching the original
numeric predicate's error on initial false. All run branches remain in source;
`33` is checked separately, while `45`, `54` and `55` are neither executed here
nor claimed to fit I64.

[Correctness evidence](correctness-summary.json) includes twelve canonical runs
at counts 1, 2 and 10; sixteen supplemental executions; and eight alternate-branch
or wrong-predicate checks. Separate modules expose all ordered elements of the
three- and ten-element lattices, their full comparison matrices and the four
preliminary counts `3, 10, 6, 4`. An exhaustive Python assignment oracle checks
empty source/target, reversed source order and a diamond partial order. Original
Chez, adapted Chez, raw Wasm and optimized Wasm agree on all 400 observations
per form, including comparator/callback ordering, short-circuiting, reverse-node
identity, shared elements, untouched source spines and append's final-tail
identity. These probes never enter the canonical artifact.

The [retention audit](retention-audit.json) examines the exact canonical optimized
module, whose only exports are `bench` and `main`. It retains the four preliminary
count calls before runtime input dispatch, both constraint scans, recursive
enumeration, materialized I64 branch-count lists, recursive sum and destructive
tail stores. A separate instrumented copy counts entry to each of its 119
functions without reoptimization. Erasing the observer additions recovers the
original optimized text exactly; setup entries are subtracted before observing
the benchmark.

At count 10, `run` is entered ten times. The four preliminary enumerators have
60, 200, 100 and 100 entries; the main ten-element-to-itself enumerator has
2,758,700 entries, and its deep-list rotation has 15,238,600 entries. Count-1 and
count-2 observations scale exactly. These are instrumented Wasm function entries,
not physical allocations, V8 machine-code counts or performance samples. The
initial observer assembly enabled every Binaryen proposal and Node rejected it;
the successful assembly uses the compiler's exact feature list. Both records
are retained separately from canonical artifacts.

`make test` and `make check` pass. All 28 preceding strict specifications and
generated sources remain byte-identical. Existing backend contracts are inherited
from the unchanged compiler; linked raw/optimized Wasm and actual Node executions
are included here. The fresh no-history/no-file Astra maximum-reasoning review
and informed debate are recorded in [simplify-review.md](simplify-review.md).
The final r3 preparation freezes commit `4f1dedc` and preserves distinct strict
and Chez scalar-validation logs. Its canonical source, binaries and Chez control
sources are byte-identical to the r2 artifacts used for the retention diagnostic.

Restore and hash-verify all archived files without running a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-lattice-replay \
  --report benchmarks/results/2026-10-14-strict-lattice
```
