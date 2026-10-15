# Neutral behavioral brief for independent simplify review

Review the new strict benchmark adaptations and validation for the complete
upstream graphs and mperm programs. The compiler is frozen at PR91's stack head
`a4030ce190058db3e9d64f6942401b5fa38dbd58`; compiler changes, gcbench lifecycle
work, old report edits, publishing and clean timing are outside this checkpoint.
The existing benchmark harness remains responsible for preparation, source
identity, raw and optimized execution, original/adapted Chez controls and later
separately coordinated timing. Earlier ports must retain their generated source.

Use the complete pinned upstream source and input files. Every original kernel
operation, traversal, repetition, mutation and final predicate must remain. Small
typed replacements for unsupported source forms are permitted when their exact
changes and semantic bounds are recorded. The adapted Chez control must execute
the same adapted kernel text as strict Scheme; original Chez keeps its original
source and wrapper. Preserve unread or ignored datums. Failed preparation and
corrected assumptions must remain visible rather than becoming successful data.

Graphs requests three invocations with seven vertices and a final count of
213,829. It builds and mutates Boolean adjacency matrices while enumerating
bounded directed graphs through a continuation-passing permutation fold. The
last vertex is the distinguished root; no edge targets that root. There are no
self edges, every out-degree is at most two, and the root reaches every vertex.
Exactly one representative of each class under relabeling the non-root vertices
is returned. Preserve generation order, adjacency-list order, backtracking
restoration, closure behavior and result-vector allocation. Three comparison
symbols may be represented by explicit finite scalar codes. The final timed
predicate still checks only the result count.

Supplemental graph checks must compare every edge of every returned graph in
order against original Chez for small inputs. Independently enumerate the
required isomorphism classes for those inputs to test completeness and
uniqueness, as well as bounds and reachability. Changed values, shortened output
and extra suffixes must be rejected by all implementations. Do not replace the
upstream kernel with the independent oracle or add these traversals to timing.

Mperm's canonical M:N:K:L is 20:10:2:1. It generates all permutations of 1..N by
prefix reversal in grey-code order, sharing unchanged list tails. Two mutable
local bindings may become explicit cells; immutable pair sharing must remain.
A vector queue is allocated and its first K-L entries are filled before timing.
Each of M timed iterations fills positions [K-L,K), shifts surviving references
left by L, clears the final L slots, and returns the same queue. The final
predicate runs once after all iterations. It checks the appropriate first
permutations and sums every integer in the first remaining permutation batch.
The input's last datum is read and ignored; derive the sum from N as upstream
does. Preserve the initial fill boundary and queue lifetime schedule.

For small N, compare every permutation and its order with original Chez and an
independent array-based prefix-reversal model. Observe complete queue values
after initial fill and each step, including no flush and complete flush.
Separately test malformed queues that distinguish the predicate's first-value
equality from its full sum check. Establish concrete witnesses of tail sharing,
fresh independent generation and queue-reference shifting. Scheme's public
import/export contract remains scalar-only. A diagnostic-only hand-written Wasm
identity observer, if needed, must be labeled and isolated from canonical code.

Inspect the exact canonical optimized modules independently of supplemental
observers. Report retained work and any legal field/allocation elimination;
passing values alone does not prove allocation volume or lifetime. Do not infer
collector equivalence from static Wasm instruction counts. Freeze source,
compiler, driver, tool and artifact identities separately before any clean run.

Please explain the behavior, then give pseudocode, invariants, edge cases and
unresolved assumptions without reading implementation, files or diffs. Challenge
unnecessary stages or state without redesigning adjacent compiler features.
