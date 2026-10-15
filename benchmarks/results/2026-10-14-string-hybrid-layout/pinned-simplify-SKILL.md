---
name: simplify
description: Simplify a handful of recently written modules through independent behavioral explanations, pseudocode, critical debate, and verified refactoring. Use for focused clarity reviews; whole-program simplification requires explicit user authorization.
---

# Simplify

Make the implementation a readable representation of the intended behavior.
Work within the requested files and interfaces, preserving earlier approved
behavior unless the user asks to change it. Carry the user's corrections, scope,
style constraints, and verification requirements through every pass.

## Bound the scope

By default, restrict simplification to a handful of recently written modules.
Identify that set from the user's request and the current task's recent work, then state the
scope before editing. If neither a clear, small set nor an explicitly authorized
broader scope is established, ask which modules to simplify. Recent Git history
can help locate candidates; it does not authorize refactoring every changed file.

Whole-program simplification is allowed only when the user explicitly sanctions
it. Existing explicit scope authorization remains valid across passes. An
instruction to keep simplifying or repeat until no further improvement is
possible extends the number of passes, not the set of modules.

Read dependencies when needed to understand behavior, but keep refactoring edits
within the agreed modules. Do not expand into older callers, shared utilities,
or previously approved code to make a local simplification easier. Keep any
test or documentation edits within the user's permitted remit too. If a useful
change requires broader scope, describe it and obtain authorization before
making that change; continue useful work inside the existing scope.

## Obtain an independent explanation

Use a fresh explainer subagent for each simplification pass, with no inherited
conversation history. Continue debating with that agent within the pass; start
a new one for the next pass. The parent owns code inspection, edits, and checks.
The explainer must not inspect repository files, implementation, or diffs.

Use the host's delegation facilities and honor the user's model and reasoning
effort choices. This workflow does not require a particular provider or tool
name. If isolated delegation or a requested configuration is unavailable,
disclose that limitation. A local explanation-and-critique pass can still help
when permitted, but do not describe it as an independent review.

Give the explainer a neutral behavioral brief: purpose, inputs, observable
outputs, required semantics, representative examples, and relevant constraints.
Distinguish requirements from assumptions and known implementation limitations.
Do not include current helper names, internal decomposition, favored changes,
previous proposals, or earlier agents' conclusions. Even a behavioral summary
can bias the answer if it quietly prescribes the existing architecture.

Ask for a high-level explanation, then more detailed pseudocode, invariants,
edge cases, and unresolved assumptions. Each proposed stage or piece of state
should have an explainable purpose. The aim is the simplest sufficient model,
not a speculative redesign or a complete solution to adjacent problems.

## Debate the model

Treat the explanation as a hypothesis. Challenge it before adopting it:

- Trace concrete examples, including failures and boundary cases.
- Ask what breaks if a stage, representation, or piece of state is removed.
- Test ordering, identity, scope, lifetime, and error behavior where relevant.
- Challenge proposals that add generic machinery or merely move bookkeeping.

Let the explainer defend or revise its reasoning. Revise your own position when
the evidence warrants it; agreement alone does not establish correctness.

After the independent explanation, comparison with code may reveal facts needed
to assess a proposal. Introduce only the relevant facts and distinguish required
constraints from current design choices. This is informed critique, not another
independent explanation. Do not promote an incidental implementation choice into
a requirement for future agents.

Share the refined explanation before substantial edits. Ask the user when
intended behavior is materially unclear; routine comparison with the code is a
self-review step and does not require approval.

## Compare and simplify

Ask: **Does the implementation directly represent this explanation?**

Map each conceptual step to the code and its data. Look for places where a
reader must reconstruct the model from nested branches, repeated interpretation,
unrelated responsibilities, or state whose purpose cannot be explained locally.
For a mismatch, decide whether the explanation omitted an invariant, the code
contains unnecessary complexity, or behavior needs clarification. Neither the
existing code nor an elegant explanation automatically settles that question.

Refactor at those conceptual boundaries. Give helpers names that describe their
role in the explanation. When validation and execution separately interpret the
same input, consider parsing once into structured data that execution can
consume directly. Reuse existing representations when they already express the
needed distinctions. Introduce a record, flag, or abstraction only when it makes
the model clearer. Fewer lines or traversals do not by themselves establish a
simplification; separate straightforward passes may be easier to understand.

## Keep functions small and code direct

**Target at most 10 LOC per function by default**, including local and anonymous
functions. Measure complete functions after normal formatting, following the
repository's counting convention when one exists. Split at meaningful operations;
do not pack statements onto fewer lines, remove useful comments, or introduce
numbered continuation helpers to meet the count. Respect line-width and other
style constraints. Review every function over the target. A coherent exhaustive
dispatch or operation may remain longer when splitting would obscure its meaning;
report such exceptions and explain why. Explicit user requirements take precedence.

Use Per Vognsen's [Bitwise](https://github.com/pervognsen/bitwise), preserved at
[tsnl/bitwise](https://github.com/tsnl/bitwise), as an important style reference.
The [Ion constructors](https://github.com/tsnl/bitwise/blob/5a261e99efea080e1111a312d897f8d794f061a7/ion/ast.c)
and [parser](https://github.com/tsnl/bitwise/blob/5a261e99efea080e1111a312d897f8d794f061a7/ion/parse.c)
give concrete examples. Apply the following interpretation, also developed in
[Resin's Bitwise essay](https://github.com/tsnl/resin/blob/7a19915229414242bad5ecd7763299532610a02b/doc/bitwise.md):

- Let data representations expose the important objects and their relationships.
  Construction should establish the guarantees later operations depend on.
- Make control flow follow the problem: visible cases, stages, loops, and
  structural recursion that a reader can explain locally.
- Give each helper a complete decision or guarantee with a descriptive name.
  Share semantic rules; similar-looking statements alone do not justify an
  abstraction. Keep useful repetition when it makes distinct cases easier to read.
- Prefer existing language facilities and a small public interface. Add custom
  utilities or generic machinery only for a demonstrated need. Keep explanatory
  comments about invariants, ownership, and deliberate tradeoffs.

Adapt this taste to the target language and repository. The 10-LOC target is this
skill's convention, not a claim that Bitwise itself imposes that limit. Judge a
change by the reasoning it saves the reader, as well as the size of its functions.

## Verify and repeat

Make a small, reviewable change and run relevant checks, exercising any affected
invariants. Update design notes within the authorized scope when they would
otherwise describe the old structure. A pass that justifies keeping the code is
also a useful result; do not manufacture edits to demonstrate progress.

Read the main operation again from its caller's perspective, then follow helpers
one level at a time. For another pass, brief a fresh explainer with the task
contract and verified behavioral facts, excluding previous proposed solutions.
Keep a short account of accepted changes and rejected alternatives in the parent
context so the loop does not repeatedly rediscover the same tradeoff.

Honor a requested single pass or explicit time/pass limit. When asked to iterate
to convergence, continue until the user stops or redirects the work, or until
no further useful simplification is supported by the review. Stop when the major
steps are visible in the code, helper responsibilities are coherent, and remaining
complexity serves concrete behavioral invariants. Do not keep cycling through
cosmetic variants or claim that simplification is mathematically impossible.

Report the useful conceptual changes, verification, and why the loop stopped.
Mention a rejected alternative when it explains necessary remaining complexity.
