# Complete Conform preparation

The complete canonical Conform workload passes raw linked Wasm,
Binaryen-optimized linked Wasm, mechanical native64, original Chez, and the same
adapted Scheme kernel on Chez. Every path executes the original 500 invocations
with names `(a b "c" "d")` and checks all 31 result strings in order, including
the list ending. Seven comparison controls are prepared. This is correctness
and provenance evidence; clean timing remains pending and measured coverage
does not increase.

The upstream revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Preparation
uses compiler/library basis `43322a2`, above `d685a64`, in the isolated worktree
`/tmp/snail-strict-conform-20261014`. This port changes no compiler, library,
runtime, or Rust-reference implementation. The compiler remains Chibi-hosted.
The later `7bd327f` ledger correction changes metadata only, as described below.

| Pinned input | SHA-256 |
| --- | --- |
| Complete 469-line `src/conform.scm` | `5b544ec3ea2416df03ef935d45ad96b7204c35ecaf7344118d3d34bbb3dc9de5` |
| Original `inputs/conform.input` | `9c0f8f0e5a9e61836442b9b85a6f5b844b31f05f14ed3586a9280f4edf138794` |

## Source and representations

[`conform_port.py`](../../strict-suite/conform_port.py) applies counted, reversible
edits to the complete kernel. The original functional sets, alternating
split/merge sort, classification, lattice expansion, graph reduction, and
signature recursion remain. Lattice expansion copies the graph, captures that
copy's current node list, then performs meet followed by join for every ordered
pair in that saved list. Newly added nodes enter subsequent passes. Equivalent
nodes keep the original unstable length ordering when choosing representatives.

Concrete Node and BlueEdge records contain explicit Ref fields corresponding to
the mutable vector slots. A node's fresh name Ref supplies identity even when its
name changes. Name distinguishes actual interned Symbols from Strings. BlueState
distinguishes unresolved construction, NONE's special marker, and a completed
edge list; ANY retains a completed empty list. Optional lookup results distinguish
absence from an existing unfinished node. Datum appears only at the input boundary.

Graph records hold a mutable node list and shared meet/join table identities.
A Table's rows Ref represents the source header pair's mutable cdr; each Row's
entries Ref represents the association pair's mutable cdr. Lookup keeps the
first matching row and entry. Insertion prepends without removing duplicate
entries. Canonicalization creates fresh headers, rows, entries, and list spines,
retains empty rows, maps values, and mutates shared blue-edge endpoints. Green
and red lists retain duplicates after canonicalization.

The source `add-graph-nodes!` takes one Node despite its plural name. Memo insertion
still occurs before recursively constructing blue edges, so cycles find the
unfinished node. Conformity tracks exactly the nodes receiving temporary red
assumptions. Success prepends those red edges to existing green edges; failure
clears every touched node's red list. Operation lookup returns the first matching
edge, and result conformity precedes the contravariant argument check.

The original `vector->list(list->vector(nodes))` graph-copy construction remains
verbatim. The dynamic `apply` into the rest-argument graph constructor explicitly
copies its argument spine. Immutable strict List exposes no pair-identity
predicate: probes observe node identities, order, graph-membership independence,
and shared tables, while the exact construction supplies the list-spine contract.
They do not directly measure physical spine identity or equal allocation counts.

These representations have distinct allocation costs. Original Chez uses
heterogeneous vectors and mutable pairs; adapted Chez uses the exact edited
Scheme body with local vector representations of records and Refs. The typed
`symbol->string` helper returns a fresh string, while original Chez may reuse a
string. String-input sharing and copied-node name sharing remain observable.
Ignored setup/NONE-setter status values become Unit, and the unreachable
missing-class error omits generic node rendering. Membership becomes Boolean
because every original `memq` result is used only as a condition.

## Correctness and complete counted work

`build/strict-conform-preparation-attempt1` is the completed preparation. All
eight fixtures pass their intended predicates on the five Scheme paths: counts
1, 2, and 500; uniformly renamed Greek names; wrong first name; reversed order;
missing final name; and an extra name. Input parsing closes its file once before
the worker; no worker file activity or opacity barrier is introduced. Canonical
behavior is promised for the supplied positive count and these tested fixtures.

The separate [probe fixture](../../../tests/strict-conform/probe.scm) checks 38
identity, alias, ordering, and state assertions. It exercises copied-node fields
and shared edge mutation, graph-membership isolation, shared tables and duplicate
entry precedence, name conversion, equal-length sort/classification ordering,
set order, successful and failed red assumptions, missing/duplicate operations,
special versus merely named nodes, and canonicalization of tables and edge lists.

Original Chez, adapted Chez, raw Wasm, optimized Wasm, and native produce the
same 193,681-byte detailed stream. It contains all ordered node/edge/table fields
before and after each lattice reduction, plus the final graph and targeted
canonicalization graph. Every recorded edge endpoint resolves to a node in its
snapshot; no outside-node sentinel appears.

A second probe runs all 500 original invocations. Each invocation compares its
complete 31-string result, then emits the delta for each of 30 work counters.
Every delta must equal the independently executed original Chez one-invocation
oracle. This checks each invocation separately; matching totals alone would not
exclude compensating differences. All five 99,192-byte streams agree.

| Observed source operation | Per invocation | All 500 |
| --- | ---: | ---: |
| Meet calls | 3,155 | 1,577,500 |
| Join calls | 3,155 | 1,577,500 |
| Recursive conformity calls | 48,695 | 24,347,500 |
| Node construction | 572 | 286,000 |
| Blue-edge construction | 1,008 | 504,000 |
| Memo insertion while unresolved | 568 | 284,000 |
| Cache hit on an unresolved node | 6 | 3,000 |
| Lattice steps and graph copies | 4 each | 2,000 each |
| Total copied node-list lengths | 83 | 41,500 |
| Temporary red assumptions | 24,485 | 12,242,500 |

Four invalid operations are also checked on all five paths: ANY getter, NONE
getter, list use of unresolved blue edges, and ANY setter. All 20 executions fail
with a diagnostic or trap. Original unresolved access first returns a sentinel
symbol and fails when used as a list; the typed accessor rejects that state
earlier. These are fatal-use checks, not identical error-message claims.

The complete native counted run also passes with a 64 KiB minimum collection
threshold and a 64 MiB arena. Its exact in-house tracing collector performs
19,005 collections while all 500 full results and every counter delta remain
unchanged. That separate stress run is neither a clean allocation census nor a
timing sample. Its full GC statistics remain in the evidence.

## Clean code and native execution

The existing source recorder regenerates the clean compiler WAT byte-for-byte.
It maps the source kernel into raw, production-optimized, and native-final Wasm.
The retained-work inspection distinguishes direct calls from constructed
function references and indirect calls. The saved outer and inner list loops
still invoke meet then join; both operators insert their memo entry before the
recursive blue-edge map. Split/merge recursion, list copying, table mutation,
red cleanup, and the counted worker remain. Optimizer inlining and loop-prefix
unrolling change function boundaries without introducing a replacement worker.

Native compilation consumes the optimized Scheme Wasm, runs mandatory Binaryen
optimization, and mechanically lowers the final module to LLVM with native64
reference slots and the in-house collector. The exact native-final Scheme Wasm
also passes on V8 with its separately pruned scalar provider. Only the Scheme
module is identical between that V8 arm and native; provider target, linkage,
optimization opportunities, and reclamation still differ.

The final executable contains the native test/lattice loop, indirect loop
closures, and meet/join functions. Inspection follows both code branches and
the ELF closure records, including position-independent pointer relocations.
The inner loop calls meet and tail-jumps to join. Allocation and collection paths
remain in those functions. This is evidence from the actual executable as well
as its input LLVM; it is separate from the instrumented dynamic traces.

## Distinct Rust controls and timing boundary

The unchanged Rust reference passes its two existing Conform unit tests and all
eight fixtures on native, raw Wasm, and Binaryen-optimized Wasm. Successful runs
print the complete ordered result; negative expectations fail the Rust assertion.

Rust uses arena indices, Vec node/edge/table storage, Vec set operations,
VecDeque split/merge sorting, and Rc names. It clones its root vector for a lattice
pass and retains removed noncanonical nodes in the arena until the invocation
ends. Scheme retains the functional list algorithms and graph-copy construction;
its tracing collector can reclaim unreachable nodes during later passes.
Rust compares UTF-8 byte lengths where Scheme compares Unicode scalar lengths.
The canonical ASCII names and uniform Greek-renaming fixture preserve that
ordering; arbitrary mixed-width Unicode names are outside the Rust equivalence
claim. Rust is an independently represented control, not the native compiler path.

The frozen commands cover production V8, native64, V8 on the exact native-final
Scheme Wasm, original Chez, adapted Chez, Rust native, and optimized Rust/Wasm.
Both final V8 timing hosts were executed for correctness. Setup and input parsing
precede the worker clock; the full count loop and final complete result predicate
are inside it. Output formatting and final cleanup follow. No probe counters,
GC stress settings, nondefault engine stack, or special tiering flag enter the
comparison commands. Incidental clocks in preparation are not retained samples.

## Provenance correction and review

The first archived ledger reversed the edited kernel body but omitted the
prepended type-contract block. Commit `7bd327f` records that prefix as an explicit
offset-zero insertion. The corrected ledger is checked forward to the complete
adapted kernel and backward to the pinned original kernel. All generated clean,
observed, Chez, host, and C source bytes are compared with the actual preparation
snapshot before any metadata is refreshed. Original adapter, ledger, source-proof,
and prepared metadata are retained under historical names. The separate refresh
record preserves their hashes and the unchanged executable/run identities. The
earlier preparation is not relabeled as having consumed the corrected ledger.
Reversibility establishes edit accounting; the behavioral probes establish the
tested equivalence.

The pinned simplify pass used a fresh Astra/max explainer without history or file
access, followed by challenges about graph-copy scope, mutable table aliases,
red-assumption cleanup, empty table rows, unstable ordering, name identity, and
per-invocation work. The resulting adapter keeps concrete role-specific records,
direct source transformations, and a simple touched-node list. A generic mutation
transaction layer and a compiler pair-identity feature were unnecessary. Source
edit groups and complete probe operations exceed the ten-line target where
splitting them would obscure the corresponding upstream operation. No backend
cleanup or frontend restructuring was introduced.

Earlier development failures and logs remain: constructor-name shadowing,
the native diagnostic provider's missing standard header, an overly strong Chez
symbol-string identity assertion, and static inspection assumptions about tail
calls, a Python filename, and ELF relocations. They are separate from the
successful canonical artifacts. Python syntax/diff checks and the complete
target executions validate this adapter-only change; unchanged compiler and
library suites are not rerun here.

The preparation archive contains original/generated sources, compiler snapshots,
raw and optimized modules, native LLVM/executables and providers, unchanged Rust
sources/artifacts, commands, complete traces, historical failures, and the final
source/retention evidence. Its manifest checks every unique regular member.
Recorded commands retain their original absolute paths and external tool hashes;
replay elsewhere requires an explicit verified path mapping. Clean measurement
and branch integration remain separate coordinated steps.

## Stack integration review

Integration above `686f2eb` independently checked all eight source identities,
replayed all 64 reversible edits in both directions, and compared the original
Chez structural stream and every one of the 500 counter deltas against the four
other Scheme paths. All 119 retained process records are terminal. The adapter
is byte-identical to the author version; the probe received indentation-only
formatting to pass `make check`.

A fresh build on the integrated compiler and growing native collector passes the
complete canonical predicate on raw linked Wasm, Binaryen-optimized linked Wasm,
and actual native execution. The original 31 strings and count 500 are unchanged.
These executions are integration checks, not new timing samples. The
[integration record](integration-review.json) retains their commands, terminal
results, module identities, and the independent trace audit. Historical artifacts
and later measurements retain their original compiler basis.
