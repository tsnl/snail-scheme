# Focused explanation review

Scope: the new `matrix_port.py` module and its small shared-driver registration.
The upstream kernel is preserved, so this review does not refactor its algorithm
or the landed compiler/frontend. The pinned skill is
`.agents/skills/simplify/SKILL.md` at
`f09cc98ec9796e1616a8db2127b67ee1aaef6f81`.

A fresh Astra/max child received no conversation history and no repository,
file, implementation or diff access. Its neutral brief described the complete
modular search, input and ordered outputs, mutation/alias/callback requirements,
full-count source comparison, bounded process ownership and required evidence.
It did not prescribe current helper names or a favored decomposition. The child
gave a behavioral explanation, pseudocode, invariants and open questions. One
informed critique followed; the child then finished and released its slot.

The explanation separated source correspondence, execution, complete observation
comparison and later timing. It identified the lazy permutation protocol,
prime-tail mutation, continuation behavior and best-result state as different
semantic obligations. Search size, answer count and benchmark repetition count
must remain distinct. Removing a payload or replacing the search with a count
would fail that model even if the canonical result predicate passed.

The informed critique supplied the concrete tagged cursor/reply design and
prime-tail refs, the lack of a strict immutable-list identity API, the source's
echelon rather than reduced-echelon representation, the GCD eta expansion and
the proposed cap fixture. The useful refinements were:

- Reach the cap through actual collector transitions, then compare the complete
  answer list and marker order. The implemented probe performs 2,998 transitions
  before the 2,999/3,000/3,001 boundaries.
- Check row-space rank and span independently without demanding a different
  echelon layout. Exact source order is still compared against original Chez.
- Separate mutable element/tail alias checks from immutable spine identity.
  Strict probes establish the former; the supplemental Chez audit checks the
  latter without presenting it as strict physical-allocation evidence.
- State the one-invocation observation scope and the eta-expansion/allocation
  limit beside the correctness claim.

Flattening the cursor to eager permutations would obscure the original lazy
callbacks and sharing. Adding a general symbol runtime or a new immutable-list
identity API would broaden the compiler task. A generic transformation framework
would hide the exact source edits. These alternatives were rejected.

The local read-through maps input parsing to explicit answer values, counted
edits to complete source correspondence, independent models to observations,
and owned process groups to terminal records. The focused review stopped when
these steps were visible and the remaining state served the original semantics.
No broad cleanup was needed. The final preparation executes every affected
correctness path and the separate alias audit.

Functions over the ten-line target were reviewed as complete operations. The
adaptation ledger is one ordered, reversible set of edits; splitting it would
hide source correspondence. Scheme source/probe strings retain original control
flow or exhaustive observation cases. Gaussian elimination, finite enumeration,
canonical validation, predicate fixtures and toolchain freezing keep their
invariants and terminal records together. The outer preparation function lists
its full sequence explicitly. These are deliberate cohesive-operation
exceptions, not compressed statements or forwarding helpers introduced to meet
a line count.
