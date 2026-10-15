# Focused lattice explanation and review

Scope was the new lattice source adapter, its separate behavioral probes and
narrow preparation-driver integration. Compiler modules and the landed frontend
were not changed. A fresh Astra agent at maximum reasoning received no inherited
conversation or repository access. Its initial brief contained the workload's
inputs, observable output, ordered enumeration, mutation/sharing contract and
available strict language facilities. It did not inspect implementation or diffs.

The independent explanation identified one rank-one polymorphic enumerator over
concrete lattice and binding types. Completed assignments keep reversed source
order because bindings are prepended. The enumerator must materialize branch
results before collection; changing map-plus-sum to a streaming accumulator or
map-plus-flatten to a fused traversal would change the benchmark's work.

The informed debate supplied the original fused select/map behavior, comparator
operand orientations, append's last-argument sharing and the lack of mutable
built-in List tails. The resulting implementation uses one mutable-list model
throughout. Mixing immutable and mutable lists was rejected because conversion
passes would copy spines and obscure identity. Functional reversal was rejected
because it would replace nodes. A right fold of append ending in an extra empty
argument was rejected because it would copy the final argument's spine.

Each node has an immutable head and a Ref tail. Reversal saves the old tail,
writes the previous node and retains the exact current node. Selection maps only
accepted elements, then reverses its fresh nodes. Generic flattening copies all
but the final list and returns a singleton argument by identity. Empty-variant
and Ref allocation costs are disclosed; passing typed empty sentinels through
the whole enumerator was rejected as extra bookkeeping without a simpler model.

The source's outer letrec initializer for `xreverse!` cannot receive a polymorphic
annotation under the value restriction. Eta expansion exposes a function value
without weakening the checker or changing rotation. Supplemental empty-list
probes also name their concrete types explicitly after the compiler rejected
underconstrained test values. Both adaptations preserve concrete storage
and avoid a dynamic fallback.

The review required independent exhaustive small-poset oracles, comparison
traces, reversed source order to exercise upper constraints, and node/element
identity checks. All passed in both Chez forms and raw/optimized Wasm. Exact
canonical optimized-code inspection and separate entry counters establish that
the repeated workload remains. Implementation inspection and execution belong
to the port agent; an independent source-code audit is not claimed.

The compact list operations and transformations each name a complete operation.
Original benchmark functions remain visibly source-correspondent even when over
ten lines. Longer supplemental probe bodies and multi-system validation routines
are tests with ordered observable effects; splitting them into numbered stages
would obscure their contract. The review stopped once representation, reversal,
enumeration and collection mapped directly to that explanation. It did not turn
into a general mutable-list library or unrelated backend cleanup.
