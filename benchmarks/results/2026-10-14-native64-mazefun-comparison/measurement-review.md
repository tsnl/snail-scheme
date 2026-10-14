# Focused measurement review

The pinned [simplify skill](../../../.agents/skills/simplify/SKILL.md) was applied
to the new scalar provider, entries and narrow measurement driver. A fresh
GPT-6.1 Sol agent at maximum reasoning received only their behavioral contracts,
without repository access, implementation text or diffs. Its independent
explanation proposed immutable inputs, actual target execution, explicit clock
boundaries, fixed alternating fresh-process observations, full-result validation
and raw failure retention. An informed follow-up critique refined those contracts
before the freeze; no production compiler, collector or Rust source was changed.

The critique kept Binaryen's resulting common bytes explicit: the native build
runs optimization again, so V8 must consume its output rather than the historical
input artifact. It distinguished 134 expectation reads during setup from the
timed list predicate, and boundary-call counts from internal work or physical
allocation counts. The changed common artifact receives full-count native/V8
checks, 20,000-boundary diagnostic checks and a last-cell mismatch control.
The original broader observer corpus remains prior input evidence.

The driver reuses the accepted Ray protocol directly, with concrete native/V8
commands and one atomic observation operation. It freezes commands and identities
before the explicit quiet grant, excludes exactly the first V8/native pair,
alternates four retained pairs and stops while preserving any failed trial.
There is no retry/replacement policy or generic experiment callback framework.
Plain measured providers have no diagnostics; separate provider/entry files own
the counter and expectation-flip behavior.

Functions over the ten-line target preserve complete operations: main's setup,
clock, success-check and cleanup sequence; one frozen-input inventory; atomic
process evidence retention; and fixed campaign orchestration. Splitting them
into forwarding fragments would hide ordering and ownership. Broad backend
cleanup is outside the scope. Verification is actual full-count native and Node
execution, unchanged frozen identities, retained negative outcomes, archive
integrity and relocated execution.
