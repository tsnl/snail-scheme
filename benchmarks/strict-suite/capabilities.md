# Remaining upstream workloads

This inventory began with the 43 workloads left after the frozen array1
reports. Sources remain pinned to `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`;
`capabilities.json` preserves their source/input hashes. The current unmerged
compiler basis is `5abc65d`: result-context overloads, `Default T`, rank-one
specialization, concrete nominal products, closed recursive variants and direct
calls to nonescaping local procedures and structured operators, plus direct captures
of initialized let values, are implemented. Native Unicode strings have
checked owned blocks and Scheme append/copy helpers; measured short-string
overhead remains under investigation. Mutable bindings use
explicit `Ref` cells. Symbols, general mutable
pairs, first-class continuations and a full numeric tower are still outside this
strict subset. Representation support alone does not establish a completed port.

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
Paraffins has reviewed canonical source-program
timing and separate complete-structure probes; unused payload removal is
disclosed. Gcbench has correctness evidence, but its optimized program loses the
intended long-lived
tree root during later allocation. That lifetime issue blocks its GC comparison.

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
| browse | Symbols, generated symbol/string names, heterogeneous pattern trees and mutable property-list pairs. |
| deriv | Measured full ten million differentiations: 4.467× original Chez time, 2.589× adapted Chez and 0.674× Rust/Wasm. Closed datums preserve source pair spines, finite atoms, input sharing and the original quotient rule. Full-expression/error/identity probes and optimized Wasm/V8 inspection pass; Rust has different layouts and reclamation. |
| destruc | Measured complete 4,000 × destructive(600,50): 3.382× original Chez time, 1.344× adapted Chez and 1.167× Rust/Wasm. The full ten-row predicate passes raw/optimized Wasm and original/adapted Chez. Two concrete mutable-list instances, head/tail Ref cells and empty/integer items preserve all splices; explicit operand sequencing matches the original Chez diagnostic trace. Separate graph-model, full-output, node-identity, ordered-store and negative-predicate probes pass. Adapted Chez is already 2.517× original Chez; Ref/variant and Rust Vec/Box/cleanup/predicate differences remain explicit, without isolating their individual costs. No compiler change. |
| puzzle | Measured all 1,000 original 511-size searches: 1.157× original Chez time, 1.168× adapted Chez and 2.434× Rust/Wasm. The result-2005 predicate passes raw/optimized Wasm and untouched/adapted Chez. The local escape becomes explicit Boolean control with matching complete board/mask states, row identity and ordered search effects. Explicit Ref scalars, closed false/count results and truthiness-preserving Bool fills use existing capabilities; this is a source adaptation, not general continuation support. Both setup regions remain untimed. |
| ctak | Essential first-class escape continuations. |
| fibc | Essential first-class continuations, including re-entering captured continuations. |
| mbrotZ | Measured original complex Mandelbrot, 1,000 × 75 × 75 pixels: 0.397× original Chez time, 0.159× adapted Chez and 1.565× Rust/Wasm. Immutable two-F64 products preserve complex arithmetic and all matrix stores. Complete grids, exact component bits and cap/radius probes pass; representation and opacity differences are recorded. |
| nucleic | Trigonometric functions and heterogeneous recursively linked nucleotide/transform records represented by vectors, with symbolic tags. Nominal products/variants now cover the structural representation; trigonometric helpers and a faithful full port remain. |
| pi | Arbitrary precision exact integer arithmetic, powers, exact integer square root and multiple values. |
| ray | Closed optional variants and sphere/hit products are implemented. A faithful port still needs numeric helpers and actual PGM file output; it has not been executed. |
| string | Measured original 100 × 10-trial workload with owned Unicode blocks: 0.983 seconds, 5.04× faster than flat storage; 17.02× idiomatic Rust/Wasm time and 2.11× the u32/fresh/zeroed control. Chez varies 0.949–2.239 seconds, so the 0.553 median ratio is not a stable win. Separate size controls show 2–22% smaller-input overhead; a same-Wasm comparison now favors V8 over archived LLVM/Immix by 2.27×. Full payload/alias checks and the original predicate remain. |
| sum1 | Text file ports, datum reader and EOF, with mixed integer/inexact numeric data. The file read is the measured work. |
| tail | Line/string file input and output, EOF and a list of strings; preserve reverse-file behavior. |
| read1 | General datum reader and file ports, EOF and heterogeneous parsed data. |
| compiler | Symbolic heterogeneous compiler IR, mutable pairs/vectors, strings, files and binary/text output; a scalar kernel slice would not port this compiler workload. |
| conform | Heterogeneous graph/node/edge products, string/symbol names, mutable association pairs and structural equality. |
| dynamic | Dynamic interpreter AST, heterogeneous environments/values, symbols, mutable cells and runtime type dispatch. |
| earley | Symbolic grammar/token data and mixed state/configuration vectors; product/sum data is implemented, while symbolic operations, structural equality and the full port remain. |
| lattice | Measured original count 10, input 44 and result 120549: 1.647× original Chez time, 1.504× adapted Chez and 1.815× Rust/Wasm. Raw/optimized Wasm and untouched/adapted Chez correctness checks pass. Parametric lattice/binding products, mutable-tail list variants and finite I64 comparison codes preserve destructive reversal, ordered constraints, branch-result lists and append sharing. Separate complete-poset, callback-order and node-identity probes pass. Additional Ref/empty objects and Rust vector/enum/Rc layout/control differences are disclosed; the timed Rust artifact has limited complete-payload checks. No compiler changes or dynamic fallback. |
| matrix | Improper heterogeneous products, mutable pair tails, symbol messages and structured search state; fixed-width numeric helpers alone do not represent its matrix enumeration. |
| maze | Heterogeneous cell/wall records, mutable disjoint-set pairs, escape continuations and text output. |
| mazefun | Improper coordinate pairs, cell-or-false data, symbolic wall markers and structural equality; preserve its functional maze algorithm. |
| paraffins | Measured canonical source program. Closed `H`/`C` and `BCP`/`CCP` variants preserve the source algorithm. Canonical optimized code legally removes unused product payloads and radical child edges; this is not a same-allocation GC comparison. Separate modules check complete ordered structures. |
| parsing | Mutable strings/lexer state, file input, symbols and heterogeneous parsed AST. |
| peval | Symbolic recursive expression AST, generated names and destructive pair edits. |
| scheme | Interpreter/compiler with heterogeneous environments and runtime values, symbolic syntax, mutable pairs and dynamic operations. |
| slatex | String/character processing, symbolic token state, destructive list edits and actual TeX file IO. |
| chudnovsky | Arbitrary precision exact integers, exponentiation, exact integer square root/multiple values and rounding/conversions. |
| nboyer | Symbolic term/lemma trees, heterogeneous associations and mutable pairs; preserve rewrite-count check, not only the boolean theorem result. Kernel definitions follow its harness definition. |
| sboyer | Symbolic terms and sharing-cons structures with heterogeneous data; preserve rewrite-count check and sharing behavior. Kernel definitions follow its harness definition. |
| gcbench | Correctness validated; timing blocked by lost live-heap overlap. Top-down mutation and bottom-up construction are preserved with two child Ref cells per node and one empty sentinel per invocation. Optimized code retains the array but releases the intended long-lived tree early. |
| equal | Recursive heterogeneous trees and cyclic mutable pairs; requires cycle-safe structural equality and symbols, including improper tails. |
| bv2string | Bytevectors, UTF-8 string conversions and mutable strings, with the complete round-trip validation. Vector I64 is a different representation. |

The original inventory counts describe its historical selection, not current
measured coverage. Historical strict measurements now cover 30 of 57 workloads,
with 29 paired Chez comparisons; this is not a complete rerun on the current
compiler. The
[data-port report](../results/2026-10-13-strict-data-ports/README.md) distinguishes
passing behavior checks, legal payload elimination, and the gcbench lifetime
blocker. Other rows describe remaining source work; they are not execution claims.
