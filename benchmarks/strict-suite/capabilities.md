# Remaining upstream workloads

This inventory began with the 43 workloads left after the frozen array1
reports. Sources remain pinned to `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`;
`capabilities.json` preserves their source/input hashes. The unmerged compiler
supports result-context overloads, `Default T`, rank-one
specialization, concrete nominal products, closed recursive variants and direct
calls to nonescaping local procedures and structured operators, plus direct captures
of initialized let values, are implemented. Native Unicode strings have
checked owned blocks and Scheme append/copy helpers; measured short-string
overhead remains under investigation. Mutable bindings use
explicit `Ref` cells. The typed datum and reader libraries now provide symbols,
mutable datum pairs and incremental input; structural equality now covers
finite cyclic graphs and shared data with explicit traversal state. The immutable Integer library supplies exact
arbitrary-precision arithmetic over specialized I32 limbs. The datum reader's
exact numbers remain bounded to I64; rational numbers and first-class
continuations remain outside this strict subset. Representation support alone
does not establish a completed port.

The five selected ports and FFT have preceding measured reports. Quicksort,
graphs, mperm and simplex have reviewed canonical measurements against both
Chez controls and Rust/Wasm in the
[call/capture report](../results/2026-10-13-strict-call-captures/README.md).
Deriv and complex Mandelbrot have additional four-system measurements in the
[runtime comparison report](../results/2026-10-14-strict-runtime-comparisons/README.md),
which also records callback and collector-policy ablations.
String has a [bounded-storage comparison](../results/2026-10-14-string-block-comparison/README.md):
the original workload improves 5.04×, with Unicode and fresh copies preserved.
[Size controls](../results/2026-10-14-string-size-controls/README.md) disclose
2–22% overhead for smaller growth/copy inputs. Its [same-Wasm executor comparison](../results/2026-10-14-string-block-native-comparison/README.md)
now favors V8 over archived LLVM/Immix by 2.27×. The earlier [storage controls](../results/2026-10-14-string-storage/README.md)
separate element width, fresh buffers and zeroing. Puzzle now has its
[complete four-system comparison](../results/2026-10-14-strict-puzzle-comparison/README.md).
Lattice has a [full-count four-system comparison](../results/2026-10-14-strict-lattice-comparison/README.md)
with its mutable-list/closure and Rust vector/enum/Rc differences disclosed.
Destruc has a [complete four-system comparison](../results/2026-10-14-strict-destruc-comparison/README.md):
the adapted source is already slower on Chez, and Rust ownership/predicate
materialization differ. The comparison does not isolate a Ref or codegen cost.
Ray has a [complete four-system comparison](../results/2026-10-14-strict-ray-comparison/README.md):
6.584× faster than original Chez, 6.181× faster than adapted Chez, and 2.387×
Rust/Wasm time. All 50 full renders and complete output validation remain.
Mazefun has a [full-count four-system comparison](../results/2026-10-14-strict-mazefun-comparison/README.md):
1.619× faster than original Chez, 1.425× faster than adapted Chez and 3.691×
faster than this Rust/Wasm reference. All 10,000 full 11 × 11 constructions and
the complete supplied grid predicate remain; Rc/GC and layout differences are explicit.
Tail has a [complete four-system comparison](../results/2026-10-14-strict-tail-comparison/README.md):
all 50 reversals and every byte of the 4,460,056-byte output pass. It takes
5.173× original Chez time, 2.712× adapted Chez and 22.658× Rust/Wasm time;
line I/O, storage and ownership differences remain explicit.
Nucleic adds a [complete four-system comparison](../results/2026-10-14-strict-nucleic-comparison/README.md):
V8 takes 0.220574 s, 3.359× faster than original Chez; native takes 1.350× V8
time. All 50 searches and complete ordered-value checks remain.
Bytevector conversion now adds a
[six-system comparison](../results/2026-10-14-strict-bv2string-comparison/README.md):
V8 takes 0.939191 s, 1.992× original Chez time and 20.569× Rust/Wasm time;
native takes 1.029586 s. All 42 processes passed. Unicode-scalar versus UTF-8
storage, native slot widths and ownership differences are explicit. Historical
coverage before Earley was 35 of 57 measured workloads, 34 with paired Chez controls.
The later [native array storage experiment](../results/2026-10-14-native-array-storage/README.md)
changes only native lowering: declared-width array storage reduces bytevector
native time 5.13%, to 0.978197 s versus 0.938474 s for identical-Wasm V8.
Its separate requested-byte count falls 67.99%; coverage does not increase.
Earley adds a [five-system comparison](../results/2026-10-14-strict-earley-comparison/README.md):
production V8 takes 2.644450 s, 1.484× original Chez time and 0.754× adapted
Chez time. Native takes 1.458× V8 on the identical final Wasm, using an explicit
1 GiB arena. All 30 processes passed; the adapter's extra append spines and
optimized payload removal remain disclosed. Matrix adds a
[seven-system comparison](../results/2026-10-14-strict-matrix-comparison/README.md):
production V8 takes 0.705711 s, 1.483× original Chez time and 0.435× Rust/Wasm
time. Native takes 2.713× V8 time on the identical final Wasm. All 56 full-count
runs pass; Rust's different algorithms and layouts remain explicit.
The later [allocation-visibility comparison](../results/2026-10-14-native-allocation-visibility/README.md)
reduces Matrix native time to 1.416101 s versus 0.702953 s for the identical Wasm
on V8 (2.015×). Exposing both allocator layers to LLVM improves native 16.02%
over the preceding bump-path split, with 28.67% more machine-code `.text`.
The bytevector control is 0.901567 s versus V8's 0.649597 s (1.388×), with no
established improvement from this change. These add no Chez or Rust timings.
Historical coverage is now **43 of 57 measured workloads**, **42 with paired
Chez controls**. The explicit name sets are in `capabilities.json`.
Gcbench's unmeasured retention case is excluded;
`cat` has strict measurements without a same-window Chez control.
Paraffins has reviewed canonical source-program
timing and separate complete-structure probes; unused payload removal is
disclosed. Gcbench has correctness evidence, but its optimized program loses the
intended long-lived
tree root during later allocation. That lifetime issue blocks its GC comparison.
The [typed reader library report](../results/2026-10-14-strict-reader-library/README.md)
checks complete canonical `sum1` and `read1` input streams on linked raw Wasm,
optimized Wasm and native against Chez. Their
[seven-system comparison](../results/2026-10-14-strict-reader-comparison/README.md)
now passes all 112 planned processes. Production V8 takes 1.054333 s for Sum1
and 2.703861 s for Read1: 2.621× and 8.450× original Chez time, or 1.074× and
1.850× the same Scheme parser body on Chez. Native takes 0.980× and 1.113×
V8 time on the identical native-final Scheme module. This frozen native build
predates the later allocator changes; provider linkage and representation
differences prevent isolating an engine or collector cost.
The [exact-integer report](../results/2026-10-14-strict-integer/README.md)
adds full-count correctness preparations for pi and Chudnovsky on raw/optimized
Wasm, native64 and three Chez controls. Every original output digit and pi's
rounding-difference columns pass. Their
[eight-system comparison](../results/2026-10-14-strict-integer-comparison/README.md)
passes all 144 planned full-count processes. V8 takes 10.497× original Chez time
for pi and 8.264× for Chudnovsky. Native uses 19.88% and 8.28% less time than
V8 on the identical native-final Scheme modules. Same-limb Chez retains checked
scalar operations and general vectors, and Rust uses num-bigint with bounded
scalar controls; these do not isolate the cost of code generation alone.

The later [bigint loop ablation](../results/2026-10-14-bigint-loop-ablation/README.md)
tests one local backedge in the hot long-division loop against matched assembly
and optimizer controls. All 110 processes pass; Pi regresses 1.25% raw and
2.70% reoptimized, while optimized Chudnovsky differs by -0.44% with overlapping
ranges. Whole-process profiles and V8 code captures remain separate diagnostics.
The result supports no generic compiler loop change and adds no suite coverage.

The [current Ackermann preparation](../results/2026-10-14-strict-ack-preparation/README.md)
passes both original repetitions of `ack(3,12)` on raw/optimized Wasm, native64
and the exact native-final Scheme Wasm on V8, without larger-stack flags.
Generated Scheme and input are byte-identical to the old experiment; its archived
optimized artifact still fails under the same current host. Recursive Rust/Wasm
also still fails the default stack, while its existing explicit heap-frame
variant passes and remains a separate control. The subsequent
[seven-system comparison](../results/2026-10-14-strict-ack-comparison/README.md)
passes all 56 complete processes. Production V8 takes 1.109322 s, native64
0.757917 s and original Chez 0.821724 s. V8 takes 1.350× original Chez time;
native uses 32.04% less time than V8 on the identical native-final Scheme Wasm
and 7.76% less than Chez. Seven retained observations per system preserve all
observed variance, including the wider explicit-heap Rust/Wasm range.

The [complete Browse comparison](../results/2026-10-14-strict-browse-comparison/README.md)
passes all 56 full-count processes. Production V8 takes 4.037493 s, 7.673×
original Chez time, 0.635× adapted Chez time and 2.055× Rust/Wasm time.
Native takes 1.724× V8 time on the identical native-final Scheme Wasm.
Adapted Chez itself takes 12.088× original Chez time, so source-helper and
representation changes jointly affect this comparison. Separate bounded
internal traces and clean matcher retention address the discarded match
results; Rust's Rc/Vec/Boolean control remains a different representation.

| Workload | Capability and required source work |
| --- | --- |
| primes | Measured in the preceding five-port report. Existing I64/List operations; kernel unchanged. Check all 168 expected primes, their order, and list termination. Original count 10,000, limit 1,000. |
| nqueens | Measured in the preceding five-port report. Existing recursive List I64 search plus ordinary homogeneous `append`. Remove the trace body guarded by immutable `trace? = #f`. Original count 10, n = 13, expected 73,712. |
| triangl | Measured in the preceding five-port report. Existing Vector I64 backtracking and Ref(List(List I64)); construct flat integer tables with `list`, box the mutable answer binding, and make an omitted `do` step explicit. Check all 13 expected moves. Original count 50, initial move 22 and depth 1. |
| mbrot | Measured in the preceding five-port report on numeric compiler `320987e`. Preserve all pixel and escape loops; replace `inexact` with explicit `i64->f64`, supply nested-vector/zero fills. Original count 1,000, matrix 75 by 75, predicate checks result 5. |
| pnpoly | Measured in the preceding five-port report on numeric compiler `320987e`. Box its local integer counter. Construct both 20-element F64 input vectors from runtime values; preserve both vector-to-list-to-vector copies and all 12 point tests. Original count 1,000,000, expected 6. |
| graphs | Measured canonical source program: 2.323× the same adapted source on Chez; 3.100× Rust/Wasm. Complete CPS enumeration, Bool matrices and I64 adjacency lists; finite I64 comparison codes and typed helpers replace symbols/`case`. Original count 3, size 7, expected 213,829. Separate complete-value and exhaustive small isomorphism-class probes. Unused result-list payloads are legally eliminated; this is not an equal-allocation comparison. |
| mperm | Measured canonical source program: 3.569× the same adapted source on Chez; 3.624× Rust/Wasm. Original grey-code generator and shared list tails, two explicit Ref bindings, vector queue, initial fill before timing, and final complete predicate. Original M:N:K:L = 20:10:2:1 retained. Separate permutation/queue/predicate probes; source representation and optimized retention recorded before timing. |
| fft | Measured in its preceding report. The canonical F64 kernel uses a separately compiled scalar Wasm sine provider; 65,536 elements and 100 repeats remain intact. |
| quicksort | Measured canonical source program: 0.681× the same adapted source on Chez; 1.251× Rust/Wasm after initialized captures and structured calls. Canonical RNG, explicit procedure/seed refs, per-element mapping, adjacent sortedness checks and original 2,500 × 10,000 input retained. Separate checks cover complete sorted values and RNG sequences. |
| simplex | Measured canonical source program: 0.494× the same adapted source on Chez; 1.589× Rust/Wasm. Full million-invocation two-phase F64 tableau workload; closed result variants and explicit Ref scalar mutation. Original and adapted Chez controls, complete small outputs/store order, final-predicate negatives and original guard checks. One original equality-case discrepancy is preserved and distinguished from mathematical correctness. |
| browse | [Measured complete workload](../results/2026-10-14-strict-browse-comparison/README.md): all 56 processes pass the original 2,000 invocations and complete 100-value predicate. V8 4.037493 s, original Chez 0.526165 s, adapted Chez 6.360476 s, Rust/Wasm 1.964427 s. V8 takes 7.673× original Chez time and 0.635× adapted Chez time; native takes 1.724× V8 on identical native-final Scheme Wasm. Closed Datum, interned symbols, explicit mutable pairs and all three matcher return classes preserve property lists, ring, prefix sharing and shuffle. Internal traces cover counts 1/2; clean matcher retention is separate. Rust Rc/Vec/string/Boolean layout and source helpers differ; no isolated collector or engine claim. |
| deriv | Measured full ten million differentiations: 4.467× original Chez time, 2.589× adapted Chez and 0.674× Rust/Wasm. Closed datums preserve source pair spines, finite atoms, input sharing and the original quotient rule. Full-expression/error/identity probes and optimized Wasm/V8 inspection pass; Rust has different layouts and reclamation. |
| destruc | Measured complete 4,000 × destructive(600,50): 3.382× original Chez time, 1.344× adapted Chez and 1.167× Rust/Wasm. The full ten-row predicate passes raw/optimized Wasm and original/adapted Chez. Two concrete mutable-list instances, head/tail Ref cells and empty/integer items preserve all splices; explicit operand sequencing matches the original Chez diagnostic trace. Separate graph-model, full-output, node-identity, ordered-store and negative-predicate probes pass. Adapted Chez is already 2.517× original Chez; Ref/variant and Rust Vec/Box/cleanup/predicate differences remain explicit, without isolating their individual costs. No compiler change. |
| puzzle | Measured all 1,000 original 511-size searches: 1.157× original Chez time, 1.168× adapted Chez and 2.434× Rust/Wasm. The result-2005 predicate passes raw/optimized Wasm and untouched/adapted Chez. The local escape becomes explicit Boolean control with matching complete board/mask states, row identity and ordered search effects. Explicit Ref scalars, closed false/count results and truthiness-preserving Bool fills use existing capabilities; this is a source adaptation, not general continuation support. Both setup regions remain untimed. |
| ctak | Essential first-class escape continuations. |
| fibc | Essential first-class continuations, including re-entering captured continuations. |
| mbrotZ | Measured original complex Mandelbrot, 1,000 × 75 × 75 pixels: 0.397× original Chez time, 0.159× adapted Chez and 1.565× Rust/Wasm. Immutable two-F64 products preserve complex arithmetic and all matrix stores. Complete grids, exact component bits and cap/radius probes pass; representation and opacity differences are recorded. |
| nucleic | Measured all 50 original searches: V8 0.220574 s, native 0.297789 s, original Chez 0.740948 s and adapted Chez 0.765314 s. V8 is 3.359× faster than original Chez; native takes 1.350× V8 time. Complete constants, ordered solutions, mutation aliases and numeric predicates pass across all five preparation targets. All 20 clean observations and 329 frozen identities pass; layout, collector and transcendental differences remain explicit. See the [four-system report](../results/2026-10-14-strict-nucleic-comparison/README.md). |
| pi | Measured all 100 repetitions, three algorithms and ten precision rows through 500 digits: V8 2.243027 s, native 1.782729 s, original Chez 0.213676 s, Rust/Wasm 0.434312 s. V8 takes 10.497× original Chez time; native takes 0.801× V8 on identical native-final Scheme Wasm. Every rounding-difference column remains. Immutable I32-limb Integers, source adaptations, checked limb-body Chez and Rust num-bigint differences are documented. |
| ray | Measured all 50 original 100 × 100 renders: 0.152× original Chez time, 0.162× adapted Chez and 2.387× Rust/Wasm. Concrete geometry/products/options, world-list Ref and typed scalar Rust I/O preserve scene order, Euclidean distances, shading, rounding and every PGM byte. Separate optimized-site observations retain all 16.5 million sphere visits; file diagnostics retain 50 opens, 49 deletions and 50 closes. Rust inline storage, arithmetic hoisting and scene cleanup differ. |
| string | Measured original 100 × 10-trial workload with owned Unicode blocks: 0.983 seconds, 5.04× faster than flat storage; 17.02× idiomatic Rust/Wasm time and 2.11× the u32/fresh/zeroed control. Chez varies 0.949–2.239 seconds, so the 0.553 median ratio is not a stable win. Separate size controls show 2–22% smaller-input overhead; a same-Wasm comparison now favors V8 over archived LLVM/Immix by 2.27×. Full payload/alias checks and the original predicate remain. |
| sum1 | Measured all 25 reads of the unchanged 100,000-number file: V8 1.054333 s, original Chez 0.402220 s, same Scheme parser body on Chez 0.981268 s, Rust/Wasm 0.195842 s. Sequential F64 accumulation, original tolerance and every open/read-through-EOF/close remain. Native is 1.100904 s versus 1.123597 s for its exact Scheme module on V8; provider/linkage differs. |
| tail | Measured all 50 complete 4,460,056-byte bibliography reversals: 5.173× original Chez time, 2.712× adapted Chez and 22.658× Rust/Wasm. Full outputs and separate file-lifecycle/byte observations pass. Strict Unicode-scalar lists/scalar I/O, adapted Chez helpers and Rust UTF8 Vec<String>/buffered I/O/earlier input-close differ. |
| read1 | Measured all 2,500 complete reads: V8 2.703861 s, original Chez 0.320001 s, same Scheme parser body on Chez 1.461438 s, Rust/Wasm 0.439175 s. Every datum, simultaneous do update, final list predicate and file lifecycle remain. Native is 3.098514 s versus 2.785069 s for its exact Scheme module on V8; provider/linkage differs. The parser and runtime gaps require separate profiling. |
| compiler | Symbolic heterogeneous compiler IR, mutable pairs/vectors, strings, files and binary/text output; a scalar kernel slice would not port this compiler workload. |
| conform | Heterogeneous graph/node/edge products, string/symbol names, mutable association pairs and structural equality. |
| dynamic | Dynamic interpreter AST, heterogeneous environments/values, symbols, mutable cells and runtime type dispatch. |
| earley | Measured complete canonical count 1, length 15 and result 2674440: production V8 2.644450 s, common-artifact V8 2.663772 s, native 3.882573 s, original Chez 1.781515 s and adapted Chez 3.505472 s. Production V8 takes 1.484× original Chez time; native takes 1.458× same-Wasm V8 time with an explicit 1 GiB reservation after default arena exhaustion. All 30 clean processes and 161 identities pass. Complete ordered trees, mutable state/configuration identity and stored lexer/query functions are validated. Finite atom/user-info scope, I64 arithmetic, temporary append spines and legal unused payload removal remain explicit. See the [five-system report](../results/2026-10-14-strict-earley-comparison/README.md). |
| lattice | Measured original count 10, input 44 and result 120549: 1.647× original Chez time, 1.504× adapted Chez and 1.815× Rust/Wasm. Raw/optimized Wasm and untouched/adapted Chez correctness checks pass. Parametric lattice/binding products, mutable-tail list variants and finite I64 comparison codes preserve destructive reversal, ordered constraints, branch-result lists and append sharing. Separate complete-poset, callback-order and node-identity probes pass. Additional Ref/empty objects and Rust vector/enum/Rc layout/control differences are disclosed; the timed Rust artifact has limited complete-payload checks. No compiler changes or dynamic fallback. |
| matrix | Measured all 2,500 complete modular searches with the five ordered 6-by-5 answers: production V8 0.705711 s, 1.483× original Chez time and 0.435× this Rust/Wasm control's time. The exact native-final Wasm takes 0.700726 s on V8 versus native 1.901276 s (2.713×). All 56 clean processes, 70 full observation checks and 60 predicate checks pass. Closed cursor/reply/GCD/answer variants and mutable prime-tail refs preserve full enumeration, callbacks and search; independent small models and a separate Chez spine audit bound the claims. Rust Rc/vector/deque algorithms and lifetimes differ; numeric and symbol support remain explicitly bounded. No compiler change. |
| maze | Heterogeneous cell/wall records, mutable disjoint-set pairs, escape continuations and text output. |
| mazefun | Measured original 10,000 × make-maze(11,11): 1.619× faster than original Chez, 1.425× faster than adapted Chez and 3.691× faster than this Rust/Wasm reference. Concrete coordinate/dimension products, wall/coordinate and result variants, and persistent nested lists preserve deterministic shuffle, ordered flooding, copied prefixes/shared suffixes and complete 121-cell equality. Original/adapted Chez and raw/optimized Wasm correctness probes plus separate retained-work observers pass. Rust Rc, inline values, temporary vectors and destruction schedules differ; no equal-allocation or isolated collector claim. |
| paraffins | Measured canonical source program. Closed `H`/`C` and `BCP`/`CCP` variants preserve the source algorithm. Canonical optimized code legally removes unused product payloads and radical child edges; this is not a same-allocation GC comparison. Separate modules check complete ordered structures. |
| parsing | Mutable strings/lexer state, file input, symbols and heterogeneous parsed AST. |
| peval | Symbolic recursive expression AST, generated names and destructive pair edits. |
| scheme | Interpreter/compiler with heterogeneous environments and runtime values, symbolic syntax, mutable pairs and dynamic operations. |
| slatex | String/character processing, symbolic token state, destructive list edits and actual TeX file IO. |
| chudnovsky | Measured all 1,000 repetitions and ten exact results through 500 digits: V8 0.716851 s, native 0.658789 s, original Chez 0.086746 s, Rust/Wasm 0.177955 s. V8 takes 8.264× original Chez time; native takes 0.917× V8 on identical native-final Scheme Wasm. Complete binary splitting, exact products and the original F64 term-count expression remain. Arithmetic/library, scalar controls and ownership differ across controls. |
| nboyer | Symbolic term/lemma trees, heterogeneous associations and mutable pairs; preserve rewrite-count check, not only the boolean theorem result. Kernel definitions follow its harness definition. |
| sboyer | Symbolic terms and sharing-cons structures with heterogeneous data; preserve rewrite-count check and sharing behavior. Kernel definitions follow its harness definition. |
| gcbench | Correctness validated; timing blocked by lost live-heap overlap. Top-down mutation and bottom-up construction are preserved with two child Ref cells per node and one empty sentinel per invocation. Optimized code retains the array but releases the intended long-lived tree early. |
| equal | Full pinned source port with reusable cycle-aware datum equality. Retains shared DAG parameter 100, unshared tree height 8, vectors 1000, shallow lists 2000, and deep car-chain 5000 with all original repetitions. Original cyclic case stays disabled in the clean workload and runs in separate probes. Private recursive-view IDs support query-local pair memoization without changing Ref or vector storage; coprime-cycle product and deterministic hash-collision worst cases are disclosed. Clean timing pending. |
| bv2string | Measured all 100 invocations with 1,001 roundtrips each: V8 0.939191 s, native 1.029586 s, original Chez 0.471426 s, adapted Chez 0.473761 s, native Rust 0.026631 s and Rust/Wasm 0.045660 s. V8 takes 1.992× original Chez time and 20.569× Rust/Wasm time. All 42 clean runs, 65 separate Scheme stream checks and Rust controls pass. Packed bytevector, Unicode-scalar String, native padding and Rust ownership differences remain explicit; the complete internal trace covers one invocation. |

The original inventory counts describe its historical selection, not current
measured coverage. Historical strict measurements now cover 43 of 57 workloads,
with 42 paired Chez comparisons; this is not a complete rerun on the current
compiler. The
[data-port report](../results/2026-10-13-strict-data-ports/README.md) distinguishes
passing behavior checks, legal payload elimination, and the gcbench lifetime
blocker. Other rows describe remaining source work; they are not execution claims.
