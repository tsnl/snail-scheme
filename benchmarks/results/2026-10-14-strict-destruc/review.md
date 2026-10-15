# Focused explanation and review

Scope: the new `destruc_port.py` adapter and its narrow `measure.py` integration.
No compiler, host, older port, or frontend cleanup was included. The pinned
[simplify skill](../../../.agents/skills/simplify/SKILL.md) was used with a fresh
Astra/max explainer, no inherited conversation, and no repository/file/tool
access. The behavioral brief described inputs, outputs, destructive operations,
node identity, opaque inputs, the complete predicate and required checks. It did
not prescribe the adapter's decomposition or representation.

The independent explanation identified ten stable outer nodes, mutable inner
spines, and distinct integer/empty-list items. A redistribution keeps the right
prefix through its midpoint, detaches the left suffix after its half-length
prefix, and then attaches that suffix. The zero-half case clears the left outer
head and transfers empty; it does not transfer or mutate the discarded singleton.
The previous right suffix also remains intact when its incoming edge is replaced.

The informed debate retained one parametric mutable-list sum with fresh, distinct
head/tail Ref cells per node, instantiated at the two concrete element types.
General helpers have rigid `All` contracts. Expected rows use immutable native
lists prepared before timing; the predicate compares every item tag, integer,
row and list end. The expected-data domain is explicitly bounded to false or
proper nested lists of I64/empty-list items. Other Scheme datums are outside this
reader's contract, rather than being silently coerced.

A proposed false/list result wrapper was rejected as unnecessary. Nonpositive
repeat counts perform the false-result equality decision without any kernel or
opaque-input calls. Positive counts execute the first complete invocation into
a concrete result, then all remaining invocations, then one complete equality
decision. An expected false value does not skip positive-count work.

The reviewer corrected an initial pseudocode ordering: newly appended nodes must
be built before traversal of the existing row's last node, because they are an
argument to the original append operation. The source call expression retains
that ordering, including the last-tail store when `m=0`.

The first ordered probe exposed a second ordering choice. Both compiled Chez
controls evaluated the final tail store's right operand first (left-row split),
while strict evaluated its left operand first (right-row search). Full returned
values and every registered node's final state agreed; ordered effects differed.
A narrow `let*` now evaluates the unchanged left-split body, then the unchanged
right-target body, then the original tail store. Counted substitutions check
that the two introduced names are fresh. Original Chez source remains unchanged.

The reviewer justified this normalization independently of Chez scheduling:
left and right row spines are disjoint; each operand writes only its own nodes.
Clearing the left outer head in the singleton case also cannot affect the right
row. Both computations therefore return the same references and leave the same
complete graph in either order. Detachment precedes attachment, so the final
store preserves disjoint proper rows and acyclicity for the next pair. Probe-held
references do not change these identities or mutate the graph. Trace evidence
establishes the selected order in instrumented programs; it does not establish
uninstrumented Chez native instruction scheduling.

Separate registries identify actual nodes with Ref identity in strict and pair
identity in Chez. No identity field was added to the canonical type. Registries
retain abandoned nodes only in probes. The diagnostic append has a concrete
inner-item signature because its observer names that registry; the canonical
append retains its rigid fully polymorphic contract. Original/adapted Chez and
raw/optimized Wasm agree with the independent graph model on all observed
allocations, stores, complete outputs and all-node snapshots.

The final pass keeps the original long destructive loop intact. Other deliberate
exceptions to the ten-line target are the counted instrumentation substitutions,
the complete graph transition, finite fixture tables, and the small four-form
build/observation dispatch in `measure.py`. Splitting these into forwarding
helpers would hide the checked source sites or the complete atomic transition.
Expected encoding was simplified to a direct nested loop. The pass stopped when
the representations, splice order, boundary conversion and separate observations
mapped directly to the refined explanation. No further framework was needed.

Validation: 112 behavior executions, unchanged output for all 29 previous port
generators/specifications, `make test`, and `make check`. Compiler/build sources
match the 52-file native String basis exactly. Backend changes were unnecessary;
the new canonical and probe modules were assembled and executed in Node in raw
and optimized forms. Clean timing is reserved for the parent-coordinated batch.
