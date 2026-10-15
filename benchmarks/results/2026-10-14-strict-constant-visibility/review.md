# Focused explanation and entry audit

Scope: the new scalar-read helpers in `strict-wasm.sld`, and the completed
global-prefix annotation in `strict-specialize.sld` plus its Wasm context.
The existing frontend, typeclass machinery, closure representation and native
lowering were read as needed but were not refactored.

The pinned [simplify skill](../../../.agents/skills/simplify/SKILL.md) was used
with a fresh Astra/max explainer, no inherited history and no repository/file
access. The initial behavioral brief separated immutable values from runtime
initialization: forward references can have known answers and must still trap.
It requested pseudocode, invariants and counterexamples without supplying the
implementation decomposition. The initial explanation proposed general
dominating-readiness flow. The implementation owner then challenged that
machinery with the narrower required cases and concrete creation-site facts.

The debate supported two small, separate mechanisms. A direct scalar literal
can reuse the existing literal emitter without evaluating arbitrary initializer
expressions. Global initialization before a function's owned creation can be
represented by a persistent source-order prefix. Branch joins and a call-graph
fixed point would broaden the proof without helping these cases. The final
model was shared before the focused finishing edits and regression checks.

## Scalar value versus binding readiness

Only direct `Bool`, `Char`, `I32`, `I64`, `F32` and `F64` literal initializers
qualify. Reusing the emitter preserves target numeric representation. Their
source binds still run and publish payload/readiness in their original order.
Every source read retains its old readiness expression in the first commit.
Allocated values, Ref contents, computed expressions and aliases are outside
this literal rule. Captured literal payload wrappers may become unused and
ordinary mandatory Binaryen can simplify them.

## Preconditions for completed-global facts

The second commit walks concrete code only after demand and capture settling.
It uses the following audited contracts:

1. A source site owns its initialization event; demanded concrete copies do
   not move that event. `initialize-instance!` uses the site's lexical context.
2. `clone-lambda` creates a unique function record and creation node. Traversal
   follows owned initializers and syntax children. Gets do not follow binding
   targets, and calls visit operator/arguments rather than callee definitions.
   Later calls therefore cannot overwrite an earlier function's proof.
3. Ordinary closures must be constructed before invocation. Global procedures
   remain ordinary closures. Captured aliases retain their own source events.
4. A direct-only local worker has an exact lambda initializer. Its existing
   operator evaluation and per-activation readiness token remain. That token
   witnesses the same original creation event even when closure allocation is
   removed. Recursive and specialized calls obey this entry rule.
5. Export wrappers require successful `main` completion and read the original
   closure. Before-main and during-main exports cannot bypass creation. Main
   is one-shot; reentry, repetition and retry after failed initialization trap.
6. Each top-level global is added only after its complete bind event. The
   current initializer receives only earlier globals. Nested functions inherit
   that same prefix; local binds and later invocation times add no facts.
7. Prefix lists are immutable snapshots built with `cons`. Functions not
   reached by the owned-creation walk default to the empty proof. Global
   readiness is monotone; explicit Ref mutation does not reset binding readiness.

The Wasm read omits a readiness expression only for an exact global site in
the function's prefix. Other entry contexts start empty. Payload loads and
nullable casts retain their normal behavior. A callback invoked during a
global initializer may use earlier globals, but a read of a later one still
traps after any preceding effects.

The adversarial factory fixture demands an early Boolean specialization and
a later integer specialization of a factory returning a closure over a future
global. Both nested closures retain the factory's original source prefix, so
the early invocation traps. A unit test separately checks multiple concrete
copies, nested direct workers, own-site exclusion and local-site exclusion.

The newly added production helpers are within the ten-line logic target.
The cohesive unit fixture is longer to keep its setup and expected prefixes
visible together, as permitted for tests. The review stopped when the code
directly expressed these two proofs; no further abstraction was supported.
