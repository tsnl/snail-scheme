---
name: explain-and-refactor
description: Refactor code for clarity by explaining its intended behavior independently of its implementation, comparing the two, and simplifying until the code follows the explanation. Use for conceptual reviews and readability refactors guided by a high-level model.
---

# Explain and refactor

Make the implementation a readable representation of the intended behavior.
Work within the requested files and interfaces, preserving earlier approved
behavior unless the user asks to change it.

## Explain before inspecting mechanics

Start with the purpose and observable result, setting aside current function
names, loops, helper objects, and control flow. Refine that explanation into
conceptual steps: what each step receives, what it produces, and which ordering,
identity, or failure rules connect the steps. Use a small example when it makes
one of those rules clearer.

Distinguish intended behavior from assumptions and implementation limitations.
Do not rationalize an accidental structure merely because it already exists.
Share the explanation before substantial edits. Ask the user when intended
behavior is unclear; routine comparison with the code is a self-review step.

## Compare and simplify

Ask: **Does the implementation directly represent this explanation?**

Map each conceptual step to the code and its data. Look for places where a
reader must reconstruct the model from nested branches, repeated interpretation,
unrelated responsibilities, or state whose purpose cannot be explained locally.

Refactor at those conceptual boundaries. Give helpers names that describe their
role in the explanation. When validation and execution separately interpret the
same input, consider parsing once into structured data that execution can
consume directly. Introduce a representation only when it makes the model
clearer; a collection of forwarding helpers can also obscure it.

If the user requests a function-length target, measure formatted functions,
including local and anonymous functions. Split by responsibility rather than
compressing expressions onto fewer lines or adding numbered continuation
helpers. Treat the requested target as a constraint of that task, not a universal
limit.

## Repeat from the caller's perspective

Read the main operation again, then its helpers one level at a time. Explain it
afresh without following the code line by line, and ask the comparison question
again. Revise the explanation when a necessary invariant was missing; simplify
the code when its structure still obscures an already clear concept.

Stop when the major steps are visible in the code, helper responsibilities are
coherent, and remaining complexity follows from the behavior being preserved.
Run relevant existing checks and exercise any newly affected invariants. Report
the useful conceptual change and its verification, and update design notes when
they would otherwise describe the old structure.
