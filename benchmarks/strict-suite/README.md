# Strict Scheme kernel measurements

This diagnostic adapts seventeen original R7RS kernels to the strict compiler:
`ack`, `tak`, `cpstak`, `fib`, `fibfp`, `sum`, `sumfp`, `takl`, `ntakl`,
`diviter`, `divrec`, `array1`, `primes`, `nqueens`, `triangl`, `mbrot`, and
`pnpoly`. It records failures alongside successful cases. It is
an explicit subset, separate from the complete default R7RS benchmark command.

The kernel bodies come from the pinned upstream sources. Small Scheme macros
express `cond` and `do` using the strict surface. The earlier floating ports use
explicit F64 operations; mbrot and pnpoly use ordinary binary operators from
the tested, unmerged numeric branch (`320987e`, cherry-picked as `a23fbdc`).
This interim baseline precedes the result-context overload and `Default T` work.
The allocation benchmarks annotate their list of empty
lists as `List (List Never)`. All original inputs and repetition counts remain.
No compiler or runtime implementation changes are part of this experiment.

## Run

Use the tools in `benchmarks/shell.nix`, with `CHIBI`, `NODE`, `CHEZ`, `WASM_AS`,
`WASM_OPT`, and `WASM_DIS` optionally selecting explicit executables:

```sh
python3 benchmarks/strict-suite/measure.py prepare --output build/strict-suite
python3 benchmarks/strict-suite/measure.py measure --output build/strict-suite --cpu 5
```

Preparation records generated source, compiler sources, build commands, raw and
optimized Wasm, disassembly, and Chez programs. It executes each strict kernel
with one and two repetitions in raw and optimized Wasm. Errors remain in
`prepared.json` and the individual command records; failed cases are excluded
from timing and must be reported explicitly. `array1` instead checks small
runtime-supplied lengths and repeat counts, including empty vectors and zero
repeats, before timing. Its original full workload is checked by both systems
in the discarded pair before any retained measurements.

The five newer ports include original and source-matched Chez programs from
preparation onward. Their raw and optimized strict modules and both Chez
programs run one and two repetitions with unchanged algorithm inputs. Primes
also checks an empty result, and pnpoly checks all-zero runtime input vectors.
Primes and triangl compare every expected list value, order and ending. Both
modules must reject equal-length wrong values, a missing expected element and
an extra expected element. `source-proof.json`, the extracted kernel files and
`kernel-adaptation.patch` document the exact shared kernel and mechanical edits.

To prepare and measure only these ports from the repository root:

```sh
python3 benchmarks/strict-suite/measure.py prepare --output build/strict-next-five --benchmarks primes nqueens triangl mbrot pnpoly
python3 benchmarks/strict-suite/measure.py measure --output build/strict-next-five --cpu 5 --rounds 3
```

Their measurements use one complete discarded trio and three retained trios,
rotating strict, original Chez and adapted Chez through all three retained
positions for each workload. An invalid observation is saved and stops the
batch; an incomplete batch has no reported medians. Source-matched means equal
kernel text, with different imports, helper definitions, static type knowledge
and host wrappers. The [remaining-workload inventory](capabilities.md) records
the specific capabilities needed for every currently unported workload.

Measurement uses fresh processes, default V8 tiering, one discarded full run,
and three retained rounds with rotating benchmark/system order. Hashes of all
prepared case files, the host, and tools are checked. Run in a quiet window.
Replaying compiled artifacts still requires the recorded tool paths, including
the compiler tools, because measurement verifies every recorded executable.

To select only the vector workload, pass `--benchmarks array1` to preparation.
Its pinned input is `go(500, 1000000)` with one outer harness invocation and
expected result `1000000`. Both original element loops remain: increasing fill
of a fresh source vector, then decreasing element-by-element copy into a fresh
second vector. The port adds an explicit zero fill to both `make-vector` calls
and changes `go`'s initial result from an empty list to I64 zero. The positive
original repeat count always replaces that initial result. Zero and negative
repeat counts therefore have different results from upstream and are outside
the promised equivalence. The complete original source remains the Chez input.

The [checked report](../results/2026-10-13-strict-kernels/README.md) preserves the
balanced batch and default-stack failure. `replay.py DESTINATION` verifies and
restores its archive without executing workloads. `flonum.py` provides a separate
paired control using the unchanged strict artifacts and explicit Chez flonum
operations; its `prepare` and `measure` commands take the same `--output` path.
The supported controls are `fibfp`, `sumfp`, `mbrot`, and `pnpoly`; select cases
during preparation with `--benchmarks`. The latter two start from their prepared
same-source Chez programs. Only floating operations in `count` or `pt-in-poly2`
change; the escape counter and polygon indices keep their integer operations.
Preparation freezes the exact patch, source proof, inputs, drivers, and binaries,
then checks the original result predicates at counts 1 and 2. For example:

```sh
python3 benchmarks/strict-suite/flonum.py prepare --output build/strict-next-float-controls --benchmarks mbrot pnpoly
python3 benchmarks/strict-suite/flonum.py measure --output build/strict-next-float-controls --cpu 5
```

Measurement uses every prepared control, with one discarded and three retained
fresh-process pairs, and verifies the frozen files before each sample.
The [array1 vector report](../results/2026-10-13-strict-vector-array1/README.md)
adds one original-size workload. Restore its archive with
`replay.py DESTINATION --report benchmarks/results/2026-10-13-strict-vector-array1`.
`array1-control.py` compares its frozen strict/original artifacts with Chez after
the same three kernel edits. The [three-system report](../results/2026-10-13-strict-vector-array1-same-source/README.md)
preserves rotating positions and exact source equality. Run its `prepare` and
`measure` commands with the restored output directory as `--output`.

## What the timer includes

The strict timer covers one `bench(count)` export call, every repeated kernel,
opacity calls, and final result validation. Input creation and initialization
precede the timer. Lists used by `takl`, `ntakl`, `diviter`, and `divrec` are
constructed before timing, matching upstream input preparation. List traversal
for final result length is inside Wasm and timed. Scalar equality is checked
in JavaScript before stopping the timer. Loading, compilation, instantiation,
and startup are excluded; tiering during execution remains included.

Chez runs the complete original source with its original timed harness and
result predicate at optimization level 2. The strict subset currently lacks
the upstream generic `hide` implementation, which uses vectors and multiple
values. Numeric hide sites use typed I64/F64 imports returning the argument.
List hide sites use a Boolean import and return the already prepared list.
Those lists are constructed from runtime-supplied lengths, not compiler-known
input constants. The Boolean barrier alone does not hide a known value.
Host-call costs are included in strict timings. Diagnostic call counters run
only during validation, not during clean measurements.

Primes and triangl construct expected lists from runtime scalar imports before
timing, then perform their complete equality predicate once inside `bench`.
Pnpoly constructs its two F64 vectors from imported lengths and contents before
timing. Its Boolean hide preserves those runtime vectors; both original
vector-to-list-to-vector copies remain inside every kernel invocation. Explicit
refs preserve triangl's answer reset and pnpoly's counter updates. Chez ref
helpers use one-element mutable vectors outside the shared kernel.

`array1` loads its I64 repeat and length inputs before timing. Each outer
invocation performs the original two hide sites using scalar identity imports;
all vector allocation, filling, copying, and the inner repeat loop are timed.
Its integer elements and indices fit I64 at the unchanged original size.
Its result predicate checks the returned length, so disassembly must establish
whether the element work survives optimization before interpreting timings.

These harness differences prevent treating the ratio as an isolated engine,
collector, or type-inference measurement. In particular, a checked final answer
and a count of opacity calls do not prove every intervening kernel survived
optimization. The accompanying result report records inspection of the exact
optimized modules and separate V8 machine-code diagnostics for repeated
summation and list allocation.

All integer operations use I64. The selected inputs keep intermediate values
in range: Fibonacci is bounded by F40, summation by 50,005,000, the Takeuchi
arguments by their small decreasing counters, and Ackermann by A(3,12)=32,765.
Both floating kernels preserve the original double operations and ordering;
their nonnegative intermediate sums remain below 2^53. This equivalence claim
applies to these inputs, not arbitrary Scheme arithmetic.
