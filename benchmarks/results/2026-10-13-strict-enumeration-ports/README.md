# Graphs and mperm canonical preparation

Both complete canonical workloads pass on raw Wasm, optimized Wasm, original
Chez and adapted Chez. **Neither port has clean performance observations.**
Compiler source is frozen at
`a4030ce190058db3e9d64f6942401b5fa38dbd58`; runtime driver source is frozen at
`37e11e67a0fbc7b3c9bd336d4f1f4f7f03d2833b`. This checkpoint prepares the ports for
independent review before any coordinated timing.

| Workload | Complete canonical work | Final predicate |
| --- | --- | --- |
| graphs | Three enumerations with seven vertices | Result-list length = 213,829 |
| mperm | M:N:K:L = 20:10:2:1; one setup batch and 20 timed permutation batches | Original first-permutation check and complete sum 199,584,000 |

The full input files are retained, including mperm's read-but-ignored final datum
16,329,600. The canonical predicates run once after all repetitions and inspect
only the final result. Graphs computes a list length on every work invocation;
its final outer predicate compares the last numeric result. Supplemental checks
do not alter this workload.
[Preparation](prepared.json) preserves source, input, binary and tool hashes;
each archived case includes the original kernel, adapted kernel, exact patch,
strict source, original/adapted Chez programs and all build/execution records.
The adapted kernel text is identical in strict and its Chez control.

Graphs preserves the full continuation-passing permutation fold, mutable Boolean
matrices, adjacency lists, reachability, backtracking and ordered result-vector
construction. Its three comparison symbols become I64 codes 0/1/2; `case`
becomes a single-evaluation comparison followed by `cond`. Named typed helpers
replace Boolean identity, zero tests and list traversal. One ignored loop result
becomes Unit, and unreachable comparison branches trap. These changes introduce
no replacement algorithm or shortened input.

The graph set has a distinguished last/root vertex, no edge into that root, no
self edge, out-degree at most two, and reachability of every vertex from the
root. Non-root vertices may be relabeled. The small complete checks compare every
graph, row and edge in generation order against original Chez. An independent
exhaustive oracle checks the required isomorphism classes, completeness,
uniqueness, bounds and reachability for N=1..4: 1, 1, 5 and 44 classes. An early
guessed count of 16 at N=3 was wrong because it ignored the no-edge-into-root rule;
the corrected oracle and initial failures are retained.

Mperm preserves prefix-reversal order, suffix sharing, the original queue and
its mutation schedule. Its two mutable local bindings become explicit `Ref`
cells per permutation generation. All cons operations and unchanged tails
remain; original Chez may itself box captured mutable bindings, so this is not
a claim of exactly two extra runtime allocations. Typed helpers replace generic
numeric/list predicates and complete first-permutation equality. Three-argument
arithmetic becomes binary arithmetic, and an exact even numerator uses integer
quotient. Canonical arithmetic fits I64.

The queue is allocated and positions [0,K-L) filled before the workload clock.
Each iteration fills [K-L,K), shifts references left by L and clears the final L
positions. The implementation therefore generates K-L setup batches and M×L
timed batches. The source algorithm constructs 13,492,900 pairs per N=10 batch, before
cell/closure storage. This source-derived count is not a dynamic allocator
measurement.

A small immutable `PermutationPlan` holds the original work/predicate closures
after initial fill so strict's existing host timer can call the work later.
The four original input-hiding calls occur during setup. The adapted Chez
callback constructs the original benchmark label after initial fill, while the
original constructs it before that fill; both are outside the workload clock.
Strict omits this string metadata and allocates the plan outside its clock.
These untimed wrapper differences are disclosed rather than treated as equal
setup allocation. This port's equivalence claim covers positive repetition
counts and supported inputs; M=0 and invalid-argument diagnostics are outside
that claim. Invalid strict arguments trap instead of printing the source error.

[Correctness evidence](correctness-summary.json) records eight successful
canonical executions, 144 complete/negative scalar probe outcomes across the
four systems, and 21 original-Chez oracle extractions checked independently.
Of the 144 probe outcomes, 60 are expected rejections of changed, shortened or
extended expectations. Graph checks cover N=1..4. Mperm checks every permutation
and its order for N=1..6 against an independent array-based reversal model, plus
initial and per-step queue snapshots for (M,K,L) = (1,2,1), (3,4,1), (2,4,2),
(2,2,0) and (2,2,2) at N=4. The predicate probes distinguish changed sums,
changed first values preserving the sum, empty slots and complete flush.

Four additional sharing-witness executions pass: raw/optimized Wasm and both
Chez controls. They check unchanged-tail sharing, independent generation,
reference-preserving queue shifts, fresh batches and vector identity. Chez also
checks complete unique pair counts at N=1..6. The archive's
`supplementary/mperm-sharing/README.md` explains every check. Its Wasm observer is
hand-written diagnostic code appended before assembly and optimization; it
returns scalar identity flags. It does **not** implement Scheme GC-reference
imports or exports. It has no effect on canonical module liveness.

[Retention inspection](retention-audit.json) uses the exact canonical optimized
Wasm, original layouts and located source maps. Both canonical modules export
only `bench` and `main`; supplemental encoders and identity readers are separate.
Graphs retains CPS/permutation enumeration, matrices, reachability, backtracking,
result-vector construction/fill, list spines, final length and repetitions.
Binaryen removes the result-list head field, and discards each fresh result
vector before allocating a cdr-only list node. That is valid optimization of
this count-producing source program. It prevents a claim of equal allocation
or equal retained result graphs; static Wasm does not rule out further V8
allocation elimination.

Mperm retains both list fields, queue storage, explicit cell mutation, reversal
and sum/equality traversals. Its global plan reaches the work closure, which
reaches the mutable queue and every graph stored in its slots. The optimized
work thunk fills before flushing; the fill routine publishes its new queue
entry only after complete generation. For K=2,L=1, the old batch stays strongly
reachable in queue[0] while queue[1]'s new batch is built. This establishes the
required path and ordering in optimized Wasm. It does not establish machine-code
liveness, dynamic heap size/allocation counts, or original/adapted Chez retention.

All 52 compiler files match the frozen base. The [identity check](compiler-identity.json)
and [final verification](freeze-verification.json) distinguish compiler, driver
and artifact identities. All 21 earlier specifications and generated strict
sources remain byte-identical in the [regression check](prior-port-regression.json).
[Environment](environment.json) records Chibi 0.12, Node 24.19.0, Binaryen 132,
Chez 10.4.1 and the build environment. Node uses default V8 settings. Validation
runs were sequential; durations embedded in correctness records are not clean
performance samples. No canonical workload was shortened or substituted.

[Preparation history](preparation-history.json) preserves corrected source,
oracle, helper-name and read-only audit-script failures. Where an initial log
was overwritten, that limitation is explicit. [Archive replay](replay-check.json)
verifies all 351 members and executes eight bounded checks from the restored
artifacts. Restore without running a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-enumeration-replay \
  --report benchmarks/results/2026-10-13-strict-enumeration-ports
```

The new module is `enumeration_ports.py`: exact typed source edits, supplemental
encodings and independent finite oracles. `measure.py` remains the preparation
and later measurement coordinator. The [neutral behavioral brief](simplify-behavioral-brief.md)
received a fresh independent explanation and informed critique under the pinned
simplify skill. [Parent review](parent-review/review.json) kept the cohesive
source adapters and immutable plan, and added an independent permutation-domain
completeness guard to future preparations. The frozen archive remains the
original preparation; its driver identity is unchanged.

The parent independently verified all 351 archived files, checked the complete
permutation domains for N=1..6, and rejected a duplicate model with the correct
cardinality. Twelve new raw/optimized/original-Chez/adapted-Chez executions
check hand-derived complete queue snapshots for one-element no-flush/full-flush
and overlapping shifts. All 23 generated strict sources remain byte-identical.
The persistent plan-to-queue root and fill-before-flush ordering are visible in
the exact optimized module. This does not establish Chez or V8 machine-code
liveness. No compiler features, gcbench lifecycle changes, clean timing or
landing are part of this checkpoint.
