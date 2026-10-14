# Focused Boyer adapter review

Scope: the new `benchmarks/strict-suite/boyer_port.py` module. The landed
frontend, shared compiler passes and existing library representation were
outside the refactoring scope. This review used the pinned repository
[`simplify` skill](../../../.agents/skills/simplify/SKILL.md).

The parent created a fresh Astra/max explainer with no history or file access.
Its initial behavioral brief described pinned source bytes, complete original
inputs, numeric rewrite predicates, SBoyer identities, reversible adaptation,
the required execution systems, process ownership and failure behavior. The
brief did not supply helper names, decomposition or proposed edits. The
explainer never inspected repository files. Subsequent implementation facts
were explicitly introduced as informed critique.

The independent explanation identified a direct sequence: retain the pinned
program, adapt explicit representation boundaries, construct quoted constants
before worker entry, execute the complete programs on every required target,
then retain artifacts and evidence. It distinguished the theorem result from
the required 51,507,739 rewrites, source pair identity from structural equality,
and correctness preparation from clean measurement.

The debate produced these concrete changes:

- Exact reversal, source retention, program preparation, result framing and
  diagnostic trace retention now have separate, complete operations.
- A unification failure probe checks that partial source bindings survive the
  failed attempt. A subsequent top-level unification resets that environment.
  Transactional rollback was rejected because the source does not provide it.
- Clean execution requires the exact expected output frame and empty stderr.
  Native GC statistics belong to separately labeled diagnostic invocations.
- Native heap reservations are explicit choices in the workload specification;
  correctness preparation does not retry with progressively larger heaps.
- Exact setup comparison exposed a changed lemma lookup/translation order.
  An explicit `let*` records the observed original Chez ordering. The source
  language itself leaves operand evaluation order unspecified.
- Adding a symbol-entry logger changed Chez inlining and the resulting order.
  That logger was removed. Structural-order and identity probes now use kernel
  bodies without work-counter edits; counters run in a separate program.
  Both Chez diagnostic programs compile at optimize level 2, like the complete
  original/adapted controls. Failed exact comparisons remain retained evidence.

The module retains several coherent operations over the ten-line target:
the full output-frame validator, the loop that compares one observation across
five systems, probe program assembly, and source-level diagnostic assertions.
Splitting these into numbered stages or callback frameworks would hide the
protocol or state being checked. The quoted fixture definitions and preserved
upstream recursive functions are data and source evidence, rather than new
general compiler passes.

The source refinement stops here because the preparation stages, ownership and
failure checks are explicit. Complete validation of the refined programs is
recorded separately; agreement with the explainer alone is not a correctness
claim. No whole-program simplification or clean benchmark timing was performed.
