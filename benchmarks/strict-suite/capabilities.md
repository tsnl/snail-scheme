# Remaining upstream workloads

This inventory began with the 43 workloads left after the frozen array1
reports. Sources remain pinned to `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`;
`capabilities.json` preserves their source/input hashes. The current unmerged
compiler basis is `35d5baa`: result-context overloads, `Default T`, rank-one
specialization, concrete nominal products, closed recursive variants and direct
calls to nonescaping local procedures are implemented. Mutable fields use explicit
`Ref` cells. Symbols, general mutable
pairs, first-class continuations and a full numeric tower are still outside this
strict subset. Representation support alone does not establish a completed port.

The five selected ports and FFT have preceding measured reports. Quicksort,
graphs and mperm have reviewed canonical measurements in the
[direct-call report](../results/2026-10-13-strict-direct-calls/README.md).
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
| graphs | Measured canonical source program: 4.880× the same adapted source on Chez. Complete CPS enumeration, Bool matrices and I64 adjacency lists; finite I64 comparison codes and typed helpers replace symbols/`case`. Original count 3, size 7, expected 213,829. Separate complete-value and exhaustive small isomorphism-class probes. Unused result-list payloads are legally eliminated; this is not an equal-allocation comparison. |
| mperm | Measured canonical source program: 3.847× the same adapted source on Chez. Original grey-code generator and shared list tails, two explicit Ref bindings, vector queue, initial fill before timing, and final complete predicate. Original M:N:K:L = 20:10:2:1 retained. Separate permutation/queue/predicate probes; source representation and optimized retention recorded before timing. |
| fft | Measured in its preceding report. The canonical F64 kernel uses a separately compiled scalar Wasm sine provider; 65,536 elements and 100 repeats remain intact. |
| quicksort | Measured canonical source program: 0.793× the same adapted source on Chez after direct local calls. Canonical RNG, explicit procedure/seed refs, per-element mapping, adjacent sortedness checks and original 2,500 × 10,000 input retained. Separate checks cover complete sorted values and RNG sequences. |
| simplex | F64 matrices and refs fit most operations, but original success/failure return combines Bool with a list of I64 vectors. The sum/product representation is implemented; its port still needs unary/variadic arithmetic and abs/sign helpers, plus many mechanically boxed scalar bindings. |
| browse | Symbols, generated symbol/string names, heterogeneous pattern trees and mutable property-list pairs. |
| deriv | Symbolic recursive expression trees and number-versus-expression dispatch; recursive nominal ASTs are available, but symbolic operations and the typed port remain. |
| destruc | Mutable pair cars/cdrs; element values mix integers and empty lists. Immutable homogeneous List is insufficient. |
| puzzle | Escape continuation in search, mutable scalar bindings and nested Bool/I64 vectors. Native vectors alone do not supply its control flow. |
| ctak | Essential first-class escape continuations. |
| fibc | Essential first-class continuations, including re-entering captured continuations. |
| mbrotZ | Complex constants, multiplication, `make-rectangular`, real/imaginary extraction and numeric promotion. Do not replace it with mbrot. |
| nucleic | Trigonometric functions and heterogeneous recursively linked nucleotide/transform records represented by vectors, with symbolic tags. Nominal products/variants now cover the structural representation; trigonometric helpers and a faithful full port remain. |
| pi | Arbitrary precision exact integer arithmetic, powers, exact integer square root and multiple values. |
| ray | Closed optional variants and sphere/hit products are implemented. A faithful port still needs numeric helpers and actual PGM file output; it has not been executed. |
| string | Mutable strings, append, substring and length; original mutation/concatenation workload must remain. |
| sum1 | Text file ports, datum reader and EOF, with mixed integer/inexact numeric data. The file read is the measured work. |
| tail | Line/string file input and output, EOF and a list of strings; preserve reverse-file behavior. |
| read1 | General datum reader and file ports, EOF and heterogeneous parsed data. |
| compiler | Symbolic heterogeneous compiler IR, mutable pairs/vectors, strings, files and binary/text output; a scalar kernel slice would not port this compiler workload. |
| conform | Heterogeneous graph/node/edge products, string/symbol names, mutable association pairs and structural equality. |
| dynamic | Dynamic interpreter AST, heterogeneous environments/values, symbols, mutable cells and runtime type dispatch. |
| earley | Symbolic grammar/token data and mixed state/configuration vectors; product/sum data is implemented, while symbolic operations, structural equality and the full port remain. |
| lattice | Improper pairs combine elements with comparison closures; mutable destructive reverse, symbol tags and recursively changing element types. |
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
measured coverage. Historical strict measurements now cover 23 of 57 workloads,
with 22 paired Chez comparisons; this is not a complete rerun on the current
compiler. The
[data-port report](../results/2026-10-13-strict-data-ports/README.md) distinguishes
passing behavior checks, legal payload elimination, and the gcbench lifetime
blocker. Other rows describe remaining source work; they are not execution claims.
