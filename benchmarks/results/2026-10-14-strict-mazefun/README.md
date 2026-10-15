# Strict Mazefun preparation and retained work

The original 10,000 calls to `make-maze(11,11)` pass their complete grid predicate
in original Chez, adapted Chez, raw Wasm and optimized Wasm. This report records
source fidelity, correctness and retained work. It contains **no clean timing
samples or performance claim**. Durations emitted by preparation and correctness
commands remain in the archived records solely as execution provenance.

Source commit: `c1cefdffd5f7663141a1b77a5aab2c3a9e3de8ad`.
Frozen compiler and preparation-time driver commit:
`53008a43e75cc1d1c3d6844ab923807389b84149`.
Upstream benchmark revision: `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
The preparation ran while the Mazefun driver/adapter edits were uncommitted;
`prepared.json` retains that earlier driver commit honestly. The archived driver
and adapter bytes match the committed source exactly, and their SHA-256 hashes
are authoritative. All 52 frozen compiler/build files and 263 case files verify.

Supplemental parent integration checks used the newer compiler at
`2cb4f83c7b0f092fc54ed87250a178e0dec0a931`. Two compiler files differ from the
preparation basis; their exact contents and the complete hash mapping are
archived separately. Rebuilding the frozen maze source produces byte-identical
raw and optimized binaries, and both pass the full 10,000 count with the
integrated host. These two additional executions establish compatibility without
relabeling or replacing the original preparation evidence.

## Source contract

The typed kernel preserves the original increasing `for` construction, nested
persistent lists, deterministic shuffle, copied-prefix removal, duplicate-label
checks and ordered flood recursion. Seventeen original definitions, including
nested fold/for helpers, are byte-identical. The remaining substitutions give
finite pair/symbol roles concrete types and use explicit polymorphic helpers;
the full kernel and complete-program patches are archived. Reversing those
helpers, substitutions and three harness boundary edits recovers original Chez
source exactly. No compiler capability was changed.

`Cavity` is `Wall | Coordinate(I64,I64)`. Coordinates themselves are labels and
positions. Writes reuse a label directly. Dimensions have an independent product
type. `MazeResult` distinguishes initial false, error, a complete Boolean grid and
invalid expected data. The adapted Chez control uses the same kernel/helpers
with vector products/variants. These costs differ from original Scheme pairs
and WasmGC layouts; equal physical allocation is not claimed.

`list-write` copies only the prefix through its changed cell or row, and
`list-remove-pos` shares the remaining tail. Explicit append copies each leading
spine once and shares the final tail. The map helper evaluates its callback
before traversing the remaining list. A flood computes neighbors from its
incoming cave while a left fold carries updated caves through recursive work.
No mutation, union-find, vector conversion, memoization or maze replacement is
introduced.

The actual Chez reader decodes the expected datum before the clock. Exact I64
counts/dimensions and complete proper nested `_`/`*` lists retain their values;
false and interned `error` retain their distinct meanings. Empty/ragged mark
lists remain full lists to be compared. Other datums become an invalid sentinel.
That classification preserves the Boolean predicate result, but the comparison
cost of invalid datums is not equivalent to generic `equal?`. Positive repetition
counts still execute every invocation. Nonpositive counts retain initial false;
even dimensions yield error; negative odd dimensions keep the original empty
construction behavior. Integer-range claims concern the canonical workload and
the bounded probes.

## Correctness evidence

| Check | Executions | Coverage |
| --- | ---: | --- |
| Original 11 × 11 workload | 12 | Counts 1, 2, 10,000 in four forms |
| Complete outputs | 60 | Fifteen dimensions in four forms |
| Ordered cavity traces | 12 | 3 × 3, 3 × 5, 5 × 3 in four forms |
| Complete result predicates | 144 | Thirty-six fixtures in four forms |
| Persistent sharing | 2 | Fifteen assertions in each Chez form |

There are 228 behavior executions plus the two sharing executions. Complete
output probes include skinny grids, even dimensions and negative odd dimensions;
the full canonical output equals the original input datum. Traces contain every
ordered candidate hole, shuffled position and complete cave after each attempted
hole. Predicate fixtures cover initial false, wrong late marks, inner/outer list
lengths, empty/ragged lists, improper lists, Boolean marks and unrelated compound
or scalar datums. Both actual raw and optimized Wasm execute in Node.

The 30 sharing assertions establish prefix copying, suffix and untouched-row
sharing, exact label reuse, original-grid persistence and append/remove tail
identity **in Chez**. Wasm probes compare full values and ordered traces. They do
not inspect managed-reference identity. The unchanged list recursion and direct
cons lowering additionally support the Wasm sharing contract. The failed attempt
to export managed references is preserved; the compiler's scalar export boundary
was kept intact.

Supplemental reader checks reject twelve missing, malformed, inexact, nonnumeric
or out-of-I64 inputs, and accept two reader spelling/I64-boundary cases. All
thirty previous port specifications and generated strict programs match the base
exactly. `make test`, `make check` and Python compilation pass. See
[correctness-summary.json](correctness-summary.json) and [review.md](review.md).

## Retained work in the exact optimized Wasm

The canonical optimized binary is 25,252 bytes. Redisassembling that exact file
reproduces `strict.optimized.wat` byte-for-byte. A separate observer adds exported
I64 counters at 366 function/constructor/store/shuffle expression sites, grouped
into 149 counters. Erasing those insertions recovers the exact original text.
The observer is assembled without reoptimization; it never replaces either
canonical binary. Setup counters are subtracted before the benchmark call.

| Observed work | Count 1 | Count 2 | Count 10,000 |
| --- | ---: | ---: | ---: |
| `make-maze` entries | 1 | 2 | 10,000 |
| Shuffle state advances | 60 | 120 | 600,000 |
| `try-to-pierce` entries | 60 | 120 | 600,000 |
| Retained `change-cavity-aux` entries | 1,250 | 2,500 | 12,500,000 |
| Cavity-list constructor sites | 8,053 | 16,106 | 80,530,000 |
| Outer-list constructor sites | 4,579 | 9,158 | 45,790,000 |
| Complete Boolean mark-list constructors | 121 | 242 | 1,210,000 |
| Complete result-row-list constructors | 11 | 22 | 110,000 |
| Final row-predicate entries | 132 | 132 | 132 |
| Final outer-predicate entries | 12 | 12 | 12 |

Every kernel counter scales exactly across those repetition counts. The loop
entry count is N+1; the export and full final predicate execute once. The 132 row
predicate entries cover 11 × (11 marks + terminator), and the 12 outer entries
cover 11 rows plus the outer terminator. With an invalid expected sentinel at
count 10,000, every kernel counter stays identical, the complete-grid predicate
is skipped, and the result is false. Zero-count false performs no kernel work.

The [retention audit](retention-audit.json) maps source operations to exact
optimized function names and line locations and retains all counter values.
Function counts refer to residual functions after optimizer inlining, not every
corresponding source call. Constructor counters precede operand evaluation; all
recorded canonical observer runs finish normally. Counts concern executed Wasm
sites in the observer, not physical V8 GC allocation, native instruction
scheduling or uninstrumented timings. This evidence supports retained shuffle,
flood, list construction and complete-result work without claiming those
stronger properties.

## Archive and replay

`artifacts.tar.xz` contains the complete ready preparation, source/compiler/tool
hashes, original and adapted Chez programs, canonical raw/optimized Wasm, program
inputs, complete outputs/traces, observer source/binary/results, the behavioral
brief, review summary, integration checks and original oracle records. Both
failed preparations remain under `failed-attempts/`: r1 rejected duplicate Chez
`even?`/`odd?` definitions; r2 rejected managed-reference exports in a diagnostic.
Private helper names fixed r1, and scalar-only probes replaced the r2 diagnostic.
No failure is relabeled as a successful run.
Supplemental compiler compatibility records are under
`evidence/parent-integration/` and are counted separately from the 228 executions
in the ready preparation.

Restore and verify every archived byte without running workloads:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/mazefun-replay \
  --report benchmarks/results/2026-10-14-strict-mazefun
```

The [protocol](protocol.md) describes rebuilding the observer and the separate,
future timing procedure. The original `prepared.json` and its absolute command
paths remain unchanged. The archive verifier checks contents and hashes; it
does not promise those original temporary paths exist after restoration.
