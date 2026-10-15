# Strict Scheme kernel measurements

This diagnostic adapts twenty-five original R7RS kernels to the strict compiler:
`ack`, `tak`, `cpstak`, `fib`, `fibfp`, `sum`, `sumfp`, `takl`, `ntakl`,
`diviter`, `divrec`, `array1`, `primes`, `nqueens`, `triangl`, `mbrot`, and
`pnpoly`, `fft`, `quicksort`, `paraffins`, `gcbench`, `graphs`, `mperm`, `simplex`, and `deriv`.
It records failures alongside successful cases. It is
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
with one and two repetitions in raw and optimized Wasm, or the documented
canonical/full-value checks for later ports. Errors remain in
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

Select `--benchmarks fft` for the canonical FFT kernel: 100 repetitions, a
fresh 65,536-element F64 vector filled with zero inside every iteration, and
the original first-element result check. The kernel text is unchanged. Its
`inexact` binding is an I64-to-F64 helper outside the kernel, and `sin` imports
a separately compiled Rust/Wasm F64 function. The provider has no imports;
its linked sine implementation executes inside Wasm. Only F64 scalars cross
that boundary; the vector remains in the consumer's WasmGC heap.

FFT preparation records the Rust compiler, linker and target-library hashes,
passes the original full-size workload at counts 1 and 2 in raw/optimized
Wasm and Chez, and checks all components of small nonzero and impulse
transforms against a direct positive-phase DFT. The tolerance is
`1e-12 * max(1, abs(expected))`. Wrong, short and long expected vectors are
rejected by both implementations. These probes use a separate `fft-probe`
export or Chez validation wrapper. The source-matched Chez program and binary
are exact copies of the compiled original program; measurement uses two
systems and the same original counts. FFT alone also requires `RUSTC`.

Select `--benchmarks quicksort` for its complete canonical workload: 2,500
iterations sorting separately mapped copies of a 10,000-element vector, with
random values below 1,000,000. The six-state F64 RNG generates that base vector
before timing. The full input retains its final unused `ignored` symbol.
`quick-1`, `partition`, the RNG arithmetic and the six state transitions stay
byte-identical. Concrete procedure refs start with typed trap stubs and receive
all three real closures before any RNG call; an explicit vector ref preserves
seed replacement. Native `inexact`/`exact` bindings sit outside the RNG equations.

An ordinary element mapper calls the identity procedure once per element and
allocates a separate vector; it does not call `vector-copy!`. The strict timer
covers all 2,500 maps/sorts and the final complete adjacent-pair predicate. The
original three hide sites, vector allocation and RNG generation occur before
the timer. A short-circuit predicate preserves the canonical continuation's
early false return for its positive input length. Its empty-vector behavior is
only a supplemental extension. The original Chez source stays intact; the
adapted control shares the mapper, predicate, ref adapters and sorting/RNG
kernel. Its complete source patch records both wrapper edits explicitly.

Preparation checks counts 1, 2 and 2,500 in both Wasm artifacts and both Chez
controls. Small cases compare every sorted value, multiplicity, length and
source preservation. Nonempty cases also check fresh copy identity. The full
10,000 generated input values are checked against an independent binary64 RNG
reference; seed reset/read and first/middle/last inversions receive separate
checks. Changed, short and long expected sorting/RNG outputs must be rejected
by both systems. Expected-vector length never determines generation length.
These correctness runtimes are not performance samples. The
[quicksort report](../results/2026-10-13-strict-quicksort/README.md)
preserves the corrected checks and earlier probe failures. Its completed timing batch uses one
discarded trio and three rotating retained trios in a coordinated quiet window.

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

Select `--benchmarks paraffins gcbench --compiler-basis af02dac` for the nominal
data ports. Preparation verifies every frozen compiler file against that commit;
`driver_commit` records the harness checkout separately. Full upstream inputs
are preserved, including paraffins' unread alternative workload and gcbench's
unused output datum. Paraffins has canonical timing results, while gcbench remains
unmeasured, in the [data-port report](../results/2026-10-13-strict-data-ports/README.md).

Paraffins retains 10 repetitions at n = 23 and the result 5,731,580. Its `H`/`C`
radicals and `BCP`/`CCP` products become closed immutable variants; partition
vectors, loops and accumulation order remain intact. The adapted Chez kernel is
byte-identical to the strict kernel and uses tagged-vector constructors, including
one allocated `H` per invocation in place of the original symbol. Separate Wasm
and Chez probes encode every product and recursive child in order for n = 1, 2,
4, 6, 8 and 10. They check lengths, variant arities and carbon counts and reject
changed, short and long expected outputs. No probe export is present in the
canonical module. Its optimized code legally discards product payloads and
radical child edges while retaining enumeration and list work. The recorded timing
compares the count-producing source program, not equal allocation volume.

Gcbench retains one repetition at stretch depth 20, its top-down updates,
bottom-up construction, half-filled F64 array, and the original always-true
outer result predicate. A node becomes an immutable record with two mutable
child `Ref` cells and two I64 padding fields. This adds two cells per source node;
one `Nil` sentinel is allocated per invocation instead of the original integer
zero sentinel. The adapted Chez control makes the same representation change.
These are source-level allocation costs; compiler closure storage and optimization
may change the actual allocation count and layout.

The fixed diagnostic strings and integer formatting use scalar host imports at
the original print sites. Node writes synchronously; Chez uses its normal string
formatting and display. Thus the printed text and placement match, while host
crossing, formatting and I/O costs differ. Separate structural probes traverse
every node and every array element at small depths, check the order and
multiplicity of completed-tree observations, reject malformed nodes and changed arrays, and check independent child mutation.
They do not strengthen the timed predicate.

Gcbench is explicitly `retention-blocked`, so the measurement action excludes
it. Binaryen legally removes unused padding fields, but also proves the original
final tree check false and releases the intended long-lived tree before later
allocations. The array survives through its final numeric check. A future opaque
reference-lifetime boundary is proposed in the report; it is not implemented.
Passing output checks alone cannot establish this benchmark's live-heap overlap.
The original tree check compares a constructed record with the empty list and is
also necessarily false. Neither Chez control has a verified lifetime guarantee
in this preparation; canonical correctness alone is insufficient on every system.

The canonical outer predicates run once after all repetitions and check only the
final result. Supplemental gcbench events observe completed trees plus array and
edge-case checks; they are not traces of individual allocations or every internal
construction step. Independent review accepted the unchanged runtime code and
added a passing raw/optimized witness for fresh child Ref cells across distinct
nodes. The coordinated paraffins batch is complete; gcbench remains excluded.

Select `--benchmarks graphs mperm --compiler-basis a4030ce` for the complete
enumeration ports. Their preparation preserves the complete input files and
runs the canonical workload in raw/optimized Wasm and both Chez controls. They
have no clean timing results at this checkpoint.

Graphs retains three repetitions at seven vertices, with the original final
count 213,829. The CPS permutation traversal, matrix mutations, reachability
computation, backtracking and result accumulation remain. The three comparison
symbols become I64 codes 0/1/2, with explicit tests in place of `case`. The two
Boolean identity checks and list iteration use ordinary typed helpers. An omitted
`do` result becomes Unit. Graphs have no self edges or edges into the last/root
vertex, out-degree at most two, and reachability from the root. Separate probes
check every ordered adjacency list for sizes one through four against original
Chez and independently enumerate all required isomorphism classes.

Mperm retains M:N:K:L = 20:10:2:1. Its initial K-L batches are generated before
timing; every timed step fills [K-L,K), shifts the surviving references and clears
the final L slots. Two explicit Ref cells replace mutable local bindings in each
permutation generation. Prefix reversal still allocates only the reversed prefix
and shares its unchanged tail. Binary arithmetic and typed list equality replace
the corresponding generic operations; the exact, even predicate numerator uses
integer quotient. N=10 and the full predicate stay within I64. The ignored input
datum 16,329,600 is retained; the actual sum derived from N=10 is 199,584,000.

The strict host captures the work and final predicate after the initial fill,
then invokes the prepared work from `bench`. The adapted Chez control uses the
same kernel text and its original timing harness. Label formatting remains
outside timing. For small inputs, separate probes compare all permutation
values/order, complete queue snapshots, and malformed queues exercising the
first-permutation and sum checks independently. These observations do not add
work or roots to the canonical modules. Positive M and N are the supported
measurement inputs; invalid arguments trap in strict instead of printing the
upstream diagnostic. The canonical predicate still rejects complete flushing.

Select `--benchmarks simplex --compiler-basis a4030ce` for the complete simplex
port. Its million repetitions each construct the original 6-by-5 F64 tableau
and execute the unchanged two-phase pivot algorithm. The read input 740.0 is
still passed through `hide` every time, although upstream `test` ignores it.
Both result vectors are compared only after all repetitions. The full input
file, including the expected two-vector list, is preserved.

Ten mutable scalar binding sites use explicit Ref cells. Typed overloads supply
the original unary and variadic arithmetic. A nominal result distinguishes
infeasible, unbounded, and solved; solved retains the original two list nodes
and their mutable I64 vectors. The source-matched Chez control uses the exact
adapted kernel, matching Ref cells and tagged result wrappers, then unwraps only
for the original final predicate. These representation costs are disclosed;
original Chez may itself box captured mutable bindings.

Separate probe modules compare complete results, every final tableau element,
and every matrix store in order on twelve finite cases. They also test malformed
expectations, signed zero, the complete canonical predicate, and all explicit
upstream argument guards. An independent rational LP oracle agrees with eleven
cases, including the canonical optimum 681/40. The original solver incorrectly
returns unbounded for `max x, x = 2, x >= 0`; this behavior is reproduced by the
unmodified original kernel and preserved by the port. Source equivalence and
mathematical correctness are recorded separately. The
[preparation report](../results/2026-10-13-strict-simplex/README.md) contains the
exact evidence and optimized-work inspection. No clean timing is recorded.

Select `--benchmarks deriv --compiler-basis 7ff18c0` for the full derivative
port. Its input remains `(+ (* 3 x x) (* a x x) (* b x) 5)` with ten million
repetitions and the original complete-expression predicate. The upstream
quotient rule is deliberately incorrect; the port preserves it, including
ignoring extra quotient operands. This source port adds no compiler capability.

`deriv_port.py` keeps the original derivative body through exact operation
renaming. Its closed datum type has the seven finite symbols, I64 integers,
booleans, empty and a two-edge pair. One source pair becomes one nominal pair
node, preserving proper/improper list spines and shared input subtrees.
Fixed three/four-argument list constructors avoid temporary variadic lists.
Operator atoms and derivative zero/one are allocated once before timing.
Arbitrary symbols, strings, vectors and non-I64 numbers are outside this port's
declared domain; the canonical input and all documented probes are inside it.

Input and expected datums are constructed from runtime scalar imports before
timing. The repeat loop starts with the false datum, retains only its current
result and compares every final atom and ordered pair edge once inside the
timer. The unchanged original Chez program remains a control. The second Chez
control uses identical adapted kernel text, tagged vectors for corresponding
closed nodes, input/expected conversion before timing, and the same structural
comparison. Its initial false marker is adapted as well. The restoration proof
and complete-program patch account for all four wrapper changes. Native Chez
pairs and WasmGC nominal objects still have different layouts and allocation
costs; matching source does not make their physical allocations identical.

Separate probe programs compare nineteen complete literal derivatives, reject
seven changed expected trees, exercise ten failure cases and five repeat-loop
boundaries. Chez probes check reused product/operand/denominator identity and
fresh output spines. The latter checks establish identity in the two Chez
controls; source and optimized-Wasm reference flow must also be inspected for
strict. The canonical Wasm module exports only `bench` and `main`.

The current extern contract rejects managed references. Strict therefore
preserves the original number of hiding sites with a Boolean host call followed
by returning the runtime-constructed datum. This does **not** hide the datum's
identity from the compiler. A barrier count and a correct final expression do
not establish that earlier derivative results were constructed. Inspect the
canonical optimized repetition loop and derivative constructors before treating
the preparation as suitable for measurement; eliminating unobserved earlier
results would be a legal optimization, not a semantic bug. These source and
probe additions alone make no timing or native-allocation claim.

A later typed-reference extern design could import a nominal `Datum -> Datum`
identity function and preserve the actual value-returning boundary. It would
need concrete module-local WasmGC signature types, provider/consumer type
compatibility, engine-owned reference lifetime across calls and explicit host
encoding rules. This is a separate proposed capability, not part of this port.

The [deriv preparation report](../results/2026-10-13-strict-deriv/README.md)
records passing canonical runs at counts 1, 2 and 10,000,000 on all four systems,
the separate probes, and exact compiler identity. Optimized Wasm and default-tier
V8 machine code retain derivative calls within the repetition loop and pair
construction. Separate instrumented runs complete 49 pair constructors per
invocation, including 490,000,000 for the full workload; these are instruction
completions, not native allocator events or timing samples. No clean deriv
measurement has been collected.
