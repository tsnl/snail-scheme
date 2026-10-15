# Remaining upstream workloads

This inventory covers the 43 workloads left unported after the frozen array1
reports. It inspects canonical upstream sources at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`; `capabilities.json` records their
source and input hashes. Classification is source inspection, not an execution
claim. The unmerged experiment uses numeric commit `320987e`, cherry-picked as
`a23fbdc`. This is an interim baseline pending the result-context overload and
`Default T` work. Its surface includes homogeneous
I32/I64/F32/F64 arithmetic and comparisons, floating division and square root,
explicit conversions, homogeneous lists/vectors, refs, and higher order functions.

The next five preserve their original algorithms and inputs. Their adapted Chez
controls will use the same kernel text as strict Scheme; host wrappers and static
type information remain different.

| Workload | Capability and required source work |
| --- | --- |
| primes | Next port. Existing I64/List operations; kernel unchanged. Check all 168 expected primes, their order, and list termination. Original count 10,000, limit 1,000. |
| nqueens | Next port. Existing recursive List I64 search plus ordinary homogeneous `append`. Remove the trace body guarded by immutable `trace? = #f`. Original count 10, n = 13, expected 73,712. |
| triangl | Next port. Existing Vector I64 backtracking and Ref(List(List I64)); construct flat integer tables with `list`, box the mutable answer binding, and make an omitted `do` step explicit. Check all 13 expected moves. Original count 50, initial move 22 and depth 1. |
| mbrot | Next port with tested numeric compiler commit `320987e`. Preserve all pixel and escape loops; replace `inexact` with explicit `i64->f64`, supply nested-vector/zero fills. Original count 1,000, matrix 75 by 75, predicate checks result 5. |
| pnpoly | Next port with tested numeric compiler commit `320987e`. Box its local integer counter. Construct both 20-element F64 input vectors from runtime values; preserve both vector-to-list-to-vector copies and all 12 point tests. Original count 1,000,000, expected 6. |
| graphs | Later candidate; inspect and compile its entire original graph enumeration, not a substitute. Homogeneous Bool adjacency matrices and I64 edge lists fit. Three comparison symbols (`less`, `equal`, `more`) need an explicit finite integer tag encoding and `case` support; Bool identity and ordinary list helpers need typed definitions. Its CPS permutation fold and graph result types still need compiler validation. |
| mperm | Later candidate. Homogeneous shared List(List I64), vector queue and explicit refs can represent its original grey-code permutation generator. Box two mutable list bindings; retain pre-timer queue fill, fill/flush lifetime schedule, embedded harness, full queue predicate and sum check. Variadic wrappers, helpers and exact predicate division need typed ports. Original M:N:K:L = 20:10:2:1 must stay intact. |
| fft | Homogeneous F64 vectors fit; needs `sin` beyond current numeric surface, explicit I64-to-F64 conversion and typed zero/power helpers. Preserve transform loops and original 65,536-element, 100-repeat workload. |
| quicksort | Sorting kernel fits Vector I64. Full workload also needs floating RNG truncation/conversion, mutable closure bindings and seeds, vector-map, and the original escape-continuation result checker. Do not drop RNG or replace its predicate with a length check. |
| simplex | F64 matrices and refs fit most operations, but original success/failure return combines Bool with a list of I64 vectors. Needs a sum/product representation, unary/variadic arithmetic and abs/sign helpers, plus many mechanically boxed scalar bindings. |
| browse | Symbols, generated symbol/string names, heterogeneous pattern trees and mutable property-list pairs. |
| deriv | Symbolic recursive expression trees and number-versus-expression dispatch; needs symbols and recursive heterogeneous data. |
| destruc | Mutable pair cars/cdrs; element values mix integers and empty lists. Immutable homogeneous List is insufficient. |
| puzzle | Escape continuation in search, mutable scalar bindings and nested Bool/I64 vectors. Native vectors alone do not supply its control flow. |
| ctak | Essential first-class escape continuations. |
| fibc | Essential first-class continuations, including re-entering captured continuations. |
| mbrotZ | Complex constants, multiplication, `make-rectangular`, real/imaginary extraction and numeric promotion. Do not replace it with mbrot. |
| nucleic | Trigonometric functions and heterogeneous recursively linked nucleotide/transform records represented by vectors, with symbolic tags. F64 coordinate vectors alone are insufficient. |
| pi | Arbitrary precision exact integer arithmetic, powers, exact integer square root and multiple values. |
| ray | Nullable intersections/surfaces, heterogeneous sphere/hit products, rounding/conversions and actual PGM file output. Homogeneous point vectors and square root cover only part of the workload. |
| string | Mutable strings, append, substring and length; original mutation/concatenation workload must remain. |
| sum1 | Text file ports, datum reader and EOF, with mixed integer/inexact numeric data. The file read is the measured work. |
| tail | Line/string file input and output, EOF and a list of strings; preserve reverse-file behavior. |
| read1 | General datum reader and file ports, EOF and heterogeneous parsed data. |
| compiler | Symbolic heterogeneous compiler IR, mutable pairs/vectors, strings, files and binary/text output; a scalar kernel slice would not port this compiler workload. |
| conform | Heterogeneous graph/node/edge products, string/symbol names, mutable association pairs and structural equality. |
| dynamic | Dynamic interpreter AST, heterogeneous environments/values, symbols, mutable cells and runtime type dispatch. |
| earley | Symbolic grammar/token data and mixed state/configuration vectors; needs product/sum data and structural equality as well as vectors. |
| lattice | Improper pairs combine elements with comparison closures; mutable destructive reverse, symbol tags and recursively changing element types. |
| matrix | Improper heterogeneous products, mutable pair tails, symbol messages and structured search state; fixed-width numeric helpers alone do not represent its matrix enumeration. |
| maze | Heterogeneous cell/wall records, mutable disjoint-set pairs, escape continuations and text output. |
| mazefun | Improper coordinate pairs, cell-or-false data, symbolic wall markers and structural equality; preserve its functional maze algorithm. |
| paraffins | Recursive tagged heterogeneous radical/tree records (`H`, `C`, `BCP`); homogeneous partition vectors alone are insufficient. |
| parsing | Mutable strings/lexer state, file input, symbols and heterogeneous parsed AST. |
| peval | Symbolic recursive expression AST, generated names and destructive pair edits. |
| scheme | Interpreter/compiler with heterogeneous environments and runtime values, symbolic syntax, mutable pairs and dynamic operations. |
| slatex | String/character processing, symbolic token state, destructive list edits and actual TeX file IO. |
| chudnovsky | Arbitrary precision exact integers, exponentiation, exact integer square root/multiple values and rounding/conversions. |
| nboyer | Symbolic term/lemma trees, heterogeneous associations and mutable pairs; preserve rewrite-count check, not only the boolean theorem result. Kernel definitions follow its harness definition. |
| sboyer | Symbolic terms and sharing-cons structures with heterogeneous data; preserve rewrite-count check and sharing behavior. Kernel definitions follow its harness definition. |
| gcbench | Recursive mutable Node records with nullable child fields, plus F64 arrays and numeric/printing helpers. Do not replace the tree with a different list algorithm. |
| equal | Recursive heterogeneous trees and cyclic mutable pairs; requires cycle-safe structural equality and symbols, including improper tails. |
| bv2string | Bytevectors, UTF-8 string conversions and mutable strings, with the complete round-trip validation. Vector I64 is a different representation. |

There are five selected ports, two later candidates with substantial mechanical
work, and 36 workloads needing additional language/library capabilities or typed
data representations. Existing frozen coverage is 13 passing measured ports or
slices (including cat/wc); Ack has a visible default-stack failure. This inventory
does not change historical reports or claim coverage for these 43 workloads.
