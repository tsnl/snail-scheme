# Focused Earley explanation and review

Scope: the new `earley_port.py`, its narrow driver registration and the evidence
wrappers. The compiler and landed frontend are unchanged. The pinned
[simplify skill](../../../.agents/skills/simplify/SKILL.md) guided one bounded
pass. A fresh Astra/max explainer received a neutral behavioral brief with no
history and no tools/files. It gave an independent explanation, followed by one
informed critique after relevant representations were disclosed. The following
is a summary of that exchange, not a verbatim transcript.

The parser accepts an ordered grammar and a lexer callback. It first establishes
production/configuration identities, then builds mutable evidence of spans and
derivations. A parse supports three distinct queries: acceptance, ordered tree
materialization and numerical tree counting. Enumeration must preserve rule and
derivation order, production multiplicity and terminal user information. Replacing
materialization with the numerical query would erase the benchmark's work.

Absent membership differs from every valid link value, including negative list
sentinels and zero. State and configuration identity matters because later
operations mutate an existing object through earlier aliases. Lexer state must
remain a captured mutable value; storing a callback is behavior, not metadata.
Unknown nonterminals returning false differ from known rejected spans returning
empty trees or zero counts. Nullable and duplicate rules stress these boundaries.

The informed critique found the concrete products and option types proportionate
to these roles. It asked that state heads be verified always initialized, old
aliases be read after writes, complete ordered trees be compared separately from
an independent multiplicity oracle, and canonical retained work be traced from
the exported entry. The final source initialization loop and probes address each
point. The small-tree independent oracle is only a control; the original parser
establishes the source's precise enumeration order.

The useful local clarification was an explicit stack-bounded append helper. It
copies the original prefix in order onto the same suffix, with an extra temporary
reversed spine whose allocation cost is disclosed and controlled by adapted Chez.
A direct recursive helper exhausted the canonical stack, while a count-only
replacement would violate the source workload. No compiler prerequisite or
frontend reorganization was justified.

The Python functions over the ten-line target were reviewed:

- `adaptation` keeps 93 exact edit rules, occurrence counts and reverse proof
  together. Splitting the table into forwarding fragments would hide the scope.
- `specification` keeps the external reader's input transaction, equality-class
  decisions and concrete returned input contract together.
- `bounded_execute` keeps the spawn, timeout, output retention and mandatory
  process-group cleanup in one visible ownership operation.
- `read_tree` is exhaustive decoding of the three tree element roles.
- `validate_harness`, `check_tree_oracle`, `validate_probes` and `prepare_case`
  are cohesive build/test sequences; their complete target and fixture coverage
  remains visible. The emitted probe procedures are explicit tests. Original
  parser functions retain their source structure regardless of length.

The report's inspection, freeze and measurement scripts likewise keep balanced
WAT scanning, process ownership and frozen protocol validation together. They do
not add a general callback framework or change the benchmark driver architecture.
No further refactoring was supported once these data roles and invariants were
explicit. Verification covers complete source reversal, original/adapted control
identity, actual Wasm/native/Chez execution, full small output encodings, mutation
and closure probes, reachable optimized work, clock framing and descendant cleanup.
