# Retained work and source controls

This inspection uses the exact successful attempt-5 artifacts. The adjacent
script records full function excerpts, source/excerpt hashes and static call
counts in `retained-work.json`. Function numbers belong only to this frozen
artifact. The semantic descriptions below come from following their bodies and
the source; function-number coincidence is not a source map.

## Scheme Wasm

The `bench` export (`export0`) reaches `function179`. Its initial branch
preserves the nonpositive-count false result. The positive branch calls both
`foreign2` opacity imports and invokes the complete worker (`function156`).
The repetition function (`function181`) compares the running index with count,
calls both opacity imports and the worker again, then tail-calls itself with
index plus one. The final branch reaches the complete answer comparator
(`function54`), which checks list termination, answer variants and all nested
matrix/row values (`function52`). The expected input is not returned as the
worker result.

The worker computes the determinant bound (`function150`), constructs the prime
chain (`function147`) and inverse vector (`function95`), enumerates signed rows
(`function165`), and enters the search (`function169` and `function172`). Prime
construction retains mutation and recursive candidate testing. The inverse
builder retains array allocation/stores and GCD continuation calls. Row and
subset folds retain recursive calls and indirect callbacks (`function165` and
`function161`). Search retains row-space tests, dependency filtering,
maximality/permutation branches (`function91`/`function92`) and result collection
(`function152`/`function153`). Complete data payload construction remains visible.

Unused generic instantiations may disappear from production Wasm. In particular,
keeping unused `puke` and invalid-message source paths does not require the
production optimizer to emit unreachable branches. The separate executable
fixtures instantiate and exercise these behaviors. Allocation sites in excerpts
do not prove that every source object is allocated on every path.

## Actual native backend

The separately compiled non-counting native provider consumes the same optimized
Scheme Wasm. In its generated LLVM, `wasm.bench` reaches `f.92`, then `f.87` and
the repetition function `f.89`. Both initial and repeated paths retain two calls
to `f.2` (the external `hide_i64` thunk) and one to `f.69` (the complete worker).
The repeated path compares count/index, adds one and tail-calls `f.89`. The
provider remains a distinct external translation unit; only counter increments
are absent. The final native executable passes the unchanged count and predicate.

These excerpts precede the native LLVM optimizer. They show the native input
and compiler-generated control/data path, not a count of surviving machine-code
allocations. WasmGC objects become explicitly rooted native objects. The frozen
native runtime uses eight-byte array slots, and reference/object padding differs
from both WasmGC and Rust. No later native storage change is included here.

## Rust native and Wasm controls

The unchanged Rust source reads expected results before `Instant::now`, loops
the original count, passes both dimensions and each result through `black_box`,
compares the complete result and then reports. Its native LLVM retains the
opaque assembly boundaries and search call; the optimized Wasm main retains
the loop and search call. The extracted `row_reduce`, `collect_tests`, `zebra`
and `search` bodies in both targets retain modular reduction, subset generation,
permutation/partition recursion and result construction. Search is not replaced
by a precomputed answer or scalar count. Rust's complete result serialization
occurs after its workload clock and is validated by the timing runner.

The source control is intentionally weaker than identical-kernel Chez: Rust
uses methods and vectors for several operations, computes only the needed GCD
coefficient, uses explicit `drop(tester)` and reference counting, and accumulates
answers in a mutable deque. Complete canonical and independent small-case
outputs agree on native and both Wasm artifacts. This establishes a useful
validated algorithm/layout control, without asserting identical internal traces,
arbitrary failing-input equivalence, or equal allocation/lifetime.
