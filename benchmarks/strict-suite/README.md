# Strict Scheme kernel measurements

This diagnostic adapts thirty-five original R7RS kernels to the strict compiler:
`ack`, `tak`, `cpstak`, `fib`, `fibfp`, `sum`, `sumfp`, `takl`, `ntakl`,
`diviter`, `divrec`, `array1`, `primes`, `nqueens`, `triangl`, `mbrot`, and
`pnpoly`, `fft`, `quicksort`, `paraffins`, `gcbench`, `graphs`, `mperm`, `simplex`, `deriv`, `mbrotZ`, `string`, `puzzle`, `lattice`, `destruc`, `ray`, `mazefun`, `tail`, `nucleic`, and `bv2string`.
It records failures alongside successful cases. It is
an explicit subset, separate from the complete default R7RS benchmark command.

The kernel bodies come from the pinned upstream sources. Small Scheme macros
express `cond` and `do` using the strict surface. The earlier floating ports use
explicit F64 operations; mbrot and pnpoly use ordinary binary operators from
the tested, unmerged numeric branch (`320987e`, cherry-picked as `a23fbdc`).
This interim baseline precedes the result-context overload and `Default T` work.
The allocation benchmarks annotate their list of empty
lists as `List (List Never)`. All original inputs and repetition counts remain.
Later ports record their library prerequisites separately. Tail adds scalar
text-file input to the existing strict I/O library.
Nucleic adds scalar binary64 sine, cosine and unary arctangent to `(snail math)`;
both production targets call the same Rust implementations.

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

Select `--benchmarks mbrotZ --compiler-basis 7ff18c0` for the complex Mandelbrot
workload. Its original 1,000 repetitions, 75-by-75 matrix, 64-step escape limit,
radius 4.0 and final result-equals-5 predicate remain intact. `mbrotz_port.py`
adapts the original complex-number source to one immutable nominal product of
two F64 components. It adds no production compiler capability.

Complex addition creates both component sums. Complex multiplication keeps four
component products, one subtraction and one addition; multiplying by the real
step keeps its two products. The kernel retains the separate magnitude test,
complex square and addition, and all descending pixel and row-allocation loops.
It does not substitute the real-valued `mbrot` source or reuse the magnitude
squares by hand. Rectangular construction and component access become typed
operations, and `inexact` becomes I64-to-F64 conversion. This port covers the
benchmark's inexact complex arithmetic, not Scheme's general numeric tower.

The `-1.0-0.5i` literal becomes one shared nominal value before timing. A shared
empty I64 row supplies the outer vector's required fill; every slot is replaced
before use. Inner rows receive explicit zero fills. The same adapted kernel and
arithmetic-helper text runs on Chez with two-element vectors as complex values.
The original Chez source and its native complex values remain a separate
control. Their allocation costs differ from WasmGC structs. Optimizers may
remove unobserved intermediate complex objects; retained work is inspected
separately before timing.

Unlike a managed datum, the I64 matrix size crosses the existing value-returning
hiding import on every invocation. Zero or negative repetitions fail because the
original numeric result predicate receives its initial false value. The strict
wrapper rejects these counts before its homogeneous loop; positive counts
replace the loop's I64 initializer before it becomes observable. Empty and
negative matrix sizes also preserve failure, without promising identical error
messages across systems.

Separate modules compare all values and every ordered pixel store for six grids,
including the full 5,625-pixel input, ten exact component-bit cases, and eight
escape-boundary/cap cases. Signed zeros, subnormal results, rounding and overflow
are included. Seven harness cases exercise small inputs, altered expected
results and invalid counts/sizes. The canonical modules export only `bench` and
`main`; complete-output diagnostics do not add observability to those artifacts.
Preparation passes all four systems at counts 1, 2 and 1,000. No clean mbrotZ
timing has been collected.

Select `--benchmarks string --compiler-basis 2def994` for the full original
string workload: 100 repetitions, ten reset-and-grow trials per repetition,
threshold 500,000 and final length 524,278. `string_port.py` changes only the
mutable global binding to an explicit `Ref`: six counted source-edit groups
preserve every append, both substrings, all constants and all three loops.
Each grow still constructs the five-segment first append, copies its right and
left halves (including the shared midpoint), then appends those copies.

The compiler's concrete Unicode `String` uses one WasmGC I32 array: a private
mutability word followed by Unicode scalar values. Ordinary Scheme functions
implement append and substring over checked native allocation and `array.copy`.
The adapter adds no string wrapper. Original Chez remains untouched; the second
Chez control uses the exact adapted kernel and portable one-field vector Ref
helpers. Three counted surrounding-harness edits give that control the same
numeric result initializer, reconstructing the original initial `#f` from the
loop counter for both the unchanged `equal?` predicate and failure printing.
Reversing these edits, helpers and kernel changes must recover the complete
original source exactly.

Strict exports an I64 acceptance flag. Expected `#f`, `#t` and I64 inputs have
explicit scalar tags: zero or negative repetitions accept only `#f`; positive
repetitions compare the final length only with an I64 expected value. This
checks the original predicate inside the workload timer without allocating a
result wrapper. Native failure output reports the rejected flag rather than
printing the original actual value; both Chez controls retain that diagnostic.
Inputs are restricted to I64 count/threshold and Boolean-or-I64 expectations.
Out-of-safe-range JSON integers travel as decimal strings into the host's
`BigInt` conversion. Finite storage limits still apply to large thresholds.

Each invoked trial group receives the actual value returned by `hide_i64`;
validation checks one hiding call per positive outer repetition and none for
nonpositive counts. The threshold's opacity does not by itself make string
payload contents observable. The canonical predicate observes only length, so
its retained payload work must be inspected separately from result correctness.

Separate probe modules compare all characters, including the complete canonical
524,278-character output, against an independent character oracle. Small cases
include empty, NUL, non-ASCII, supplementary and combining-character seeds;
ordered replacement traces check both growth stores and all ten resets.
Independent-copy probes retain old, first-append, both substring and final
strings across allocation, mutate each in turn, and check the other four.
Harness probes distinguish false from integer zero, test zero/negative counts,
signed I64 boundaries and incorrect expected lengths. These extra observations
are absent from the canonical timing module. Copy/constructor completion counts
and uninstrumented native-code inspection are separate evidence, not physical
allocation totals or performance samples. No clean timing is recorded here.

The [string preparation report](../results/2026-10-14-strict-string/README.md)
records all 144 four-system checks and the frozen compiler's 283 strict
contracts. Canonical count-100 diagnostics complete 60,000 String constructors,
135,000 copy spans covering 3,145,167,000 Unicode scalars and 31,000 global Ref
stores after setup. The unchanged optimized binary retains both growth stores,
array allocation/zero-fill paths and scalar/bulk copying in V8 native code.
These observations support retained payload work without equating WasmGC and
Chez physical representations or claiming an exact engine allocation total.

Select `--benchmarks puzzle` for all 1,000 original searches at size 511, with
expected counter 2,005. The search keeps candidate order, inclusive mask scans,
conditional board reads/writes and every reset. Its one local escape continuation
becomes ordinary Boolean search control: test a nonzero class count before fit,
place before recursive search, run that search before checking the zero sentinel,
remove only a failed candidate, and increment the counter exactly once on each
normal trial return. No continuation capability is added to the compiler.

Global vectors still allocate before the harness definition. The original list
construction and `for-each` allocate thirteen distinct rows after that definition
and before timing. Strict requires explicit fills: Boolean true preserves the
pinned Chez implementation's truthy numeric-zero fill for board and mask tests.
The canonical full reset overwrites every such cell before use; probes project
initial and partially reset cells through truthiness rather than claiming raw
numeric-zero/Boolean identity. The typed outer vector also gets one shared empty
row sentinel, replaced by all thirteen real rows before timing.

The global piece cursor and search counter use two explicit Ref cells. The
assigned orientation index and initial next-hole binding also use Refs; trial's
local placement result is immutable because its old zero is never read. A
shared false variant and a count constructor preserve false versus integer zero.
The adapted Chez control has identical kernel regions and the same representations;
three harness edits unwrap results for the original predicate and diagnostics.
Reversing all edits recovers the complete original program, including trailing
setup. These representation costs are not claims of equal physical allocation.

Preparation checks all canonical counts in four forms and separately compares
7,202 scalar observations after every probe step: both globals, 512 board cells,
13 × 512 mask cells, counts/classes/maxima, retained row identities and row
independence. Fifteen state/trace cases include full search, place/remove round
trips, terminal recursive trial zero, failed-branch restoration, count/mask
short-circuiting, partial stores before bounds errors, partial/repeated resets
and initial placement failure with its original newline/`Error.` effects and
continued search. Fourteen harness cases preserve nonpositive-repeat false,
Boolean-versus-I64 equality, signed I64 boundaries and wrong expected values.
A separate hiding control returns known-valid size 511 from requested size 512
and checks that the returned value drives the search. Inputs accept decimal I64
counts/sizes and Boolean-or-I64 expectations; oversized active resets retain
the original first failing access. The canonical predicate observes the counter,
so optimized retained-work evidence remains separate from these extra probes.

Select `--benchmarks lattice` for the original ten invocations of `run(44)` and
the result predicate `120549`. Each invocation constructs the same successive
lattices, performs all four preliminary counts, then enumerates maps from the
ten-element lattice to itself. Runtime scalar input passes through the returned
hiding value. The original `33`, `45`, `54` and `55` branches remain in the source;
the supplemental `33` check returns `10`. The larger alternatives are not claimed
to have been executed or to fit I64. Nonpositive repeat counts trap, matching the
original harness's numeric predicate error on its initial false result.

Parametric lattice and binding products replace the two improper-pair roles.
A closed mutable-list type carries each proper-list head and an explicit Ref
tail. Selection retains its fresh reversed accumulator and destructively reverses
those exact nodes. Both constraint scans, lower-before-upper short-circuit tests,
mapped branch-result lists, recursive summation and append's final-tail sharing
remain. Four finite I64 comparison codes replace symbols; membership still
traverses the two original constant tag lists and yields Bool. Quoted base/tag
lists are initialized before timing. The outer initializer of `xreverse!` is
eta-expanded to a function value so its explicit `All` contract satisfies the
value restriction; its local rotation body is unchanged.

The adapted Chez control shares the complete adapted kernel and list helpers.
Its list node uses a pair and one-element mutable vector, whereas strict uses
a concrete variant and Ref. Strict may also allocate explicit empty variants.
The extra Ref and closure/layout differences preclude equal-allocation claims.
Preparation reverses the full kernel/helper replacement to recover the original
Chez source exactly and archives both complete-source and kernel patches.

Separate modules compare every ordered element of the three- and ten-element
lattices, every comparison pair, and the four preliminary counts. An exhaustive
Python assignment oracle checks empty, reversed-source and diamond-poset maps.
Original/adapted Chez and raw/optimized Wasm agree on comparator callback traces,
selector/map callback ordering, short-circuiting, original reverse-node identity,
shared elements, untouched input spines, and append's final-tail identity.
Counts 1, 2 and 10 execute the complete canonical workload in all four forms;
wrong expected results are rejected. These probes and optimized-work diagnostics
remain outside the canonical artifact and clean measurements.

Select `--benchmarks destruc` for the original 4,000 calls to `destructive(600,50)`.
Each call constructs ten outer nodes, refills empty rows, marks inner prefixes,
detaches left suffixes and attaches them to the next row. The final predicate
compares all ten rows and every item, including list termination. Both scalar
inputs pass through returned opaque values on every invocation. Expected data
decodes before timing; the final comparison stays inside the workload. Zero and
negative repeat counts compare the original initial false result without calling
the kernel or hiding inputs.

A parametric mutable-list variant supplies fresh head and tail Ref cells.
The two concrete instances hold rows and items; items distinguish integers from
the empty-list datum. General list operations and append have rigid `All`
contracts. This represents the original proper-list operations with additional
Ref, item-variant and empty objects; physical layouts and allocations differ from
Scheme pairs. It adds no compiler capability or dynamic fallback. The bounded
input adapter accepts nonnegative I64 `n,m` and an expected `#f` or proper nested
rows of I64/empty-list items; it is not a general Scheme datum reader.

Scheme leaves the final `set-cdr!` operand order unspecified. Compiled original
and adapted Chez diagnostic traces evaluate the left-row split before locating
and marking the right-row target. A narrow `let*` makes that order explicit in
the adapted source, retaining both operand bodies exactly. The rows are disjoint,
so either permitted operand order produces the same complete node graph; the
final tail store follows both. The trace evidence concerns instrumented controls,
not uninstrumented native instruction scheduling. Original Chez source remains
unchanged, and reversing the recorded representation, sequencing and boundary
patches recovers its complete source exactly.

Separate probes compare full outputs, ordered logical node allocations/stores,
and snapshots of every allocated node against an independent Python graph model.
Identity comes from actual Ref locations in strict and pair identity in Chez.
The diagnostic registries retain abandoned suffixes and cleared singleton rows;
they do not enter the canonical module. Small cases cover empty rows, empty-list
items, odd/even splits, later refills and consecutive calls with fresh nodes.
The complete canonical output is also observed separately. Predicate probes
reject changed late items, item tags, inner/outer lengths and false expectations.
Counts 1, 2 and 4,000 run the original workload in raw/optimized Wasm and both
Chez forms. No clean measurement is produced during preparation.

Select `--benchmarks ray` for the original 50 complete 100 × 100 renders. Every
invocation rebuilds the 33-sphere scene, visits every sphere for every pixel,
replaces the destination file and closes it before returning `ok`. Geometry,
coordinate conversions, decimal formatting and character iteration stay in
Scheme. The existing Rust runtime supplies owned buffered files through the
strict scalar I/O library; explicit export pruning removes the legacy value
interface. The dedicated Ray host initializes runtime inputs before timing and
brackets reactor initialization, Scheme main and the worker with final cleanup.

Immutable Point/Sphere products replace heterogeneous vectors. Explicit root
and point options retain absent versus zero/negative intersections; a correlated
Hit carries its selected sphere and point. The world uses one explicit Ref.
All 33 visits, Euclidean candidate distances, strict-less-than tie selection,
reverse construction order and the finite `1e308` initial distance remain.
Binary floating expressions explicitly preserve the original left association,
single discriminant square root and conversion sites. Two-argument min/max
preserve the pinned Chez implementation's NaN propagation and right-operand
signed-zero ties. Round uses the general ties-to-even numeric operation.

The adapted Chez control uses the identical adapted kernel, concrete tagged
wrappers and the strict library's exact Scheme character/decimal formatting
bodies. Root/Candidate wrappers and a Hit at each improvement can add allocations;
the original allocates its two-field hit vector only after traversal. Physical
allocation parity is not claimed. Native Chez ports and Rust's scalar port
registry also retain their respective runtime representations.

The original result domain is false before any iteration and symbol `ok` after
a completed render. Strict encodes those as I64 0/1 and classifies every other
expected datum as 2, preserving the complete equality answer. Chez's actual
reader performs that classification before timing, including escaped symbols,
booleans, numbers, strings and compound data. Wrong expectations still execute
every requested render. The adapted Chez harness restores the original values
for the predicate and diagnostics. Reversing the counted edits restores the
complete original Chez program, including its formatting compatibility prelude.

Preparation checks counts 1, 2 and 50 in original/adapted Chez and raw/optimized
linked Wasm. The complete canonical file is 29,517 bytes with SHA-256
`38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d`;
the established pixel checksum is checked separately. Separate viewport modules
test complete small images at resolutions 0, 1, 2 and 3, Unicode pathnames,
existing-file replacement, nonpositive counts and wrong expectations. Separate
geometry modules compare floating bit patterns, optional results, tie order,
nonfinite cases and every scene field against original Chez and an independent
ordered-scene oracle. These viewport changes and observers never enter the
canonical artifact. The supported evidence covers these bounded I64 inputs;
arbitrary-precision resolutions or overflowing extents are not claimed.

Select `--benchmarks mazefun` for the original 10,000 functional maze generations
at 11 by 11. Both dimensions pass through returned opaque values on every call.
The kernel retains nested immutable lists, increasing construction loops,
deterministic shuffle/removal recursion, duplicate-cavity checks, ordered flood
relabeling and the complete final grid. A cell write copies the outer prefix
through its row and the row prefix through its cell; untouched suffixes remain
shared. Flood neighbors come from the incoming cave, while its left fold carries
each updated cave to the next neighbor. The final predicate compares every mark,
row end and outer list end inside the workload.

The `Cavity` variant is either a wall or a coordinate with I64 row and column.
Position lists contain coordinates, and writes reuse those exact labels.
Dimensions have their own product type. A finite result variant distinguishes
initial false, the error symbol, a complete Boolean grid and an invalid expected
datum. Two- and four-operand append helpers copy each leading spine once and
share the final tail. The explicit map calls its callback before recursing over
the tail. These helpers and the adapted kernel are identical in the adapted
Chez control; its variants/products use vectors. Their representation costs
differ from both original Scheme pairs and WasmGC structs.

The actual Chez reader decodes the original input before timing. Counts and
dimensions must be exact signed I64 integers. Expected false and the interned
`error` symbol keep their meaning, including reader spellings such as `#false`
and `|error|`. Any proper nested list of `_` and `*` marks is preserved, including
empty and ragged lists; other datums become the invalid-expected variant. This
classification preserves the original predicate's Boolean answer, but does not
claim equal comparison cost for invalid datums. Every positive-count invocation
still executes. Nonpositive counts retain false; even dimensions return error;
negative odd dimensions retain the original empty construction behavior.

Preparation executes counts 1, 2 and 10,000 in original/adapted Chez and
raw/optimized Wasm. Separate probes compare fifteen complete outputs, ordered
hole/shuffle/cavity traces for three small grids, and thirty-six predicate
fixtures in all four forms. Fifteen persistent-sharing assertions run in each
Chez form. Wasm probes compare complete values and traces; they do not export
managed references or claim to measure their identity. The unchanged recursive
list writes/removals and direct cons lowering support the sharing contract.
Observers and retained-work counts stay separate from canonical artifacts and
clean measurements. This port changes no compiler capability.

## Tail files and line input

`tail` keeps all 50 original repetitions over the complete 4,460,056-byte,
31,102-line `inputs/bib`. Each repetition opens input, deletes existing output,
opens output, retains every line in a reversed Scheme list, writes every line
plus LF, closes output, then closes input. Its original predicate remains always
true. Separate checks compare every output byte and ordered file lifecycle.

The source edits extract String from the concrete `LineResult`, rename its EOF
predicate for the Chez boundary, and use an explicit typed `for-each`. The
adapted Chez program shares the exact kernel and the strict library's Scheme
line builder and character writer. Its concrete line cases use vectors; its
native ports and character-copy primitive retain their Chez representations.
The strict library uses a geometrically growing String buffer, scalar Rust
read/peek operations and existing host UTF-8 decoding. All line construction,
retention and reversal remain in Scheme.

The unchanged upstream Chez prelude uses `get-line`, which recognizes LF and
retains CR. Strict and adapted Chez follow the repository text-reader contract
for CR, LF and CRLF. The canonical bibliography contains no CR, so its complete
bytes agree across both controls, raw/optimized linked Wasm and native execution.
The [preparation report](../results/2026-10-14-strict-tail/README.md) records 95
supplemental cases and explicitly preserves the differing original Chez bytes
for CR fixtures. It also records Unicode, EOF, empty/unterminated lines, buffer
boundaries, file replacement, nonpositive counts and 50-iteration lifecycle
traces. No clean timing samples are included.

## Complete Nucleic preparation

Select `--benchmarks nucleic` for all 50 original searches, the empty partial
assignment and expected value `33.797594890762724`. The complete 3,485-line
upstream program, every coordinate and constant, and the original numeric ratio
predicate remain in the evidence. The 46 nucleotide constants use a concrete
base variant and mutable vectors of F64 coordinate/transform vectors. All 57
getter/setter pairs remain; a field ledger accounts for moving the original
symbol tag out of slot 29. Mutable assignments use a shared Ref containing an
immutable ID/transform/nucleotide product, retaining alias-visible updates.
This adds a wrapper allocation and a product replacement on assignment setters.
The canonical search does not call those setters, but probes exercise each one.

The source adapter records counted substitutions and verifies their reversal
recovers the original kernel exactly. All 6,719 decimal tokens retain spelling
and order. The original `math-atan2` branches remain Scheme code, including
its x=0 behavior; ordinary typed externs supply only sine, cosine and unary
arctangent. Points, transforms, list construction, linked search and maximum
selection remain in Scheme. The original Chez program remains untouched, while
the adapted Chez control uses the same kernel and corresponding helpers.

Preparation checks counts 1, 2 and 50, then compares complete database values,
ordered pseudoknot and anticodon solutions, every solution ID/nucleotide/transform,
geometry outputs and retained mutation aliases in both Chez forms, raw/optimized
linked Wasm and native execution. Separate zero/negative counts and wrong or
near-boundary expected values check the original predicate. Computed float probes
use relative and absolute tolerance `1e-11`, with signed zero checked explicitly;
database and mutation probes require exact numeric agreement. The comparison
itself rejects shortened, extended, changed and reordered observations.

Nucleic preparation gives each complete compile/link/native build an explicit
1,200-second bound. A timeout retains output and terminates that build's entire
owned process group, including a child that ignores the initial termination
signal. This larger bound follows retained five-minute attempts that emitted
complete WAT/raw Wasm and then expired in mandatory Binaryen optimization.
Compile-stage durations are diagnostic provenance, not workload measurements.
The [preparation report](../results/2026-10-14-strict-nucleic/README.md) freezes
complete sources, artifacts, raw failures and full-value checks separately from
performance measurements.

The [clean four-system Nucleic comparison](../results/2026-10-14-strict-nucleic-comparison/README.md)
records V8 0.220574 s, native 0.297789 s, original Chez 0.740948 s and adapted
Chez 0.765314 s. One complete round is discarded and four retained rotations
balance all system positions. All 20 full-count runs and 329 frozen identities
pass; source/layout and transcendental differences remain explicit.

## Bytevector and UTF-8 roundtrips

The [six-system comparison](../results/2026-10-14-strict-bv2string-comparison/README.md)
records Snail/V8 at 0.939191 s, native Snail at 1.029586 s, original Chez at
0.471426 s, adapted Chez at 0.473761 s, native Rust at 0.026631 s and Rust/Wasm
at 0.045660 s. All 42 planned processes passed; six retained observations per
system used rotating order. Snail/V8 takes 1.992× original Chez time and
20.569× Rust/Wasm time. The report separates storage and ownership differences
from these descriptive timings and discloses its post-campaign hardware snapshot.
Historical measured coverage is now 35 of 57 workloads, with 34 paired Chez
comparisons; this is not a fresh whole-suite run.

Select
`--benchmarks bv2string` to prepare the original 100 repetitions, each with one
initial sanity roundtrip and 1,000 random roundtrips with maximum size 1,000.
The original failure-count expectation is zero. The strict host receives the
Boolean result of that numeric predicate as an integer flag. Both original
opacity calls remain in every repetition.

The adapter keeps the copyright, local RNG, three conversions and every string
comparison. Mutable RNG state and the global reverse-ordered failure-name list
become explicit refs; diagnostic text and complete names cross a typed character
output boundary. The two unused bytevector generators remain in the source and
are exercised separately. The multiple-of-four generator uses an exact integer
equivalent of rational `round(n/4)`, including ties to even. An omitted `do`
result becomes Unit, with every edit reversed and checked against the original.

Preparation executes raw/optimized Wasm, the actual native backend, and original
and adapted Chez at the unchanged full input. Separate probes compare every RNG
transition, generated byte, decoded character, re-encoded byte and final decoded
character against an independent integer/UTF-8 oracle. They cover RNG reset,
large-bound RNG branches, all ASCII bytes, both unused generators, all canonical
rounding inputs, and failures with NUL/Unicode names and reverse list order.
The complete canonical trace covers one invocation's 1,001 roundtrips; the
unchanged full-count executions retain all 100 invocations. Repeated-call probes
separately check RNG reset. The Rust reference runs its full input and complete
canonical trace natively and as raw and Binaryen-optimized Wasm on V8. Its
`String` stores UTF-8 bytes, while Scheme strings store Unicode scalar values;
Wasm bytevectors have packed i8 storage, while the native executor currently uses
eight-byte slots. Rust accumulates a numeric failure count; the Scheme kernel
retains failure names. Their validated canonical zero-failure equivalence does
not assert identical behavior on arbitrary failing inputs. A separate native
timing provider preserves opacity calls without diagnostic counter increments.
Preparation records these representation differences and does
not treat its incidental validation durations as benchmark measurements.
