# Ott definitions and Rocq proofs

[`lofi.ott`](lofi.ott) defines Lofi's documented syntax and the first formal
judgments. Ott generates both the typeset grammar/rules and the Rocq inductive
definitions from this file. [`Proofs.v`](Proofs.v) imports those generated
definitions; it does not restate the language in another proof assistant.
This is an incremental draft, not a complete metatheory of Lofi.

## Build and read

From the repository root:

```sh
nix-shell doc/spec/shell.nix --run scripts/spec
```

The pinned environment supplies Ott 0.34, Rocq 9.1.1, its standard library, and
LaTeX. The build compiles the two required helpers from the pinned Ott source,
generates `Lofi.v`, checks it and the handwritten proofs with `rocq compile`, and
independently rechecks the compiled development with `rocqchk`. No generated
definition is edited or committed. Ott's older unqualified standard-library
imports produce deprecation warnings in Rocq; they still compile unchanged.

Outputs are under `build/spec/`:

- `lofi.pdf`: Ott's typeset grammar and named rules.
- `generated/Lofi.v`: the exact generated definitions being proved about.
- `html/toc.html`: linked definitions and proofs, rendered by Rocq's documentation tool.
- `kernel-check.log`: the independent kernel check.

The `Ott and Rocq` workflow runs the same command and uploads these files as
the `ott-rocq-reference` artifact. With the tools and `OTT_COQ_LIB` (the directory
containing Ott's Coq helper sources) available, `make spec` runs the same build.
The book's [Ott and Rocq chapter](../book/lofi/mechanized.md) includes the actual
Ott source using anchors, so those excerpts cannot drift from the checked file.

## Coverage and assumptions

The grammar covers the formal summary's canonical library/import/export forms,
expressions, definitions, datatype/class/instance declarations, and types. It
also includes `define-extern`, `define-overload`, and current rest forms. It
separates library statements from expression-block statements, and ordinary
types from schemes and class requirements. Legacy `=>` signatures and kind
annotations are excluded, matching the compiler. `syntax-rules` expansion,
staging, and expanded core declaration forms are outside this grammar. This is
symbolic syntax, not a replacement for the compiler's reader or hygienic name
resolver.

The five name categories have distinct Rocq types, each with an unbounded
natural-number supply. Reader token categories are abstract payloads: the
development does not yet interpret integer/float spellings, Unicode, or strings.
Formation starts after name resolution, with visible declaration identities and
their arities supplied by the surrounding environment. Each declaration map is
a partial function, so an identity has at most one arity. Source shadowing
introduces a fresh identity, so scheme freshness checks concern identity rather
than spelling. There is no separate kind calculus.

The generated judgments check:

- Primitive types, scoped variables, containers, and fixed/rest function types.
- Visible datatype and class names with exactly their declared argument counts.
- Rank-one schemes with distinct fresh binders, a well-formed body type, and
  well-formed requirements in the extended scope, including empty lists.
- Closed instance heads, using an empty type-variable scope.

The seven proved properties are scope weakening, scope containment for all
nested variable occurrences, closed instance heads, nonzero and zero datatype
application arity, class arity, and omitted/empty requirement formation
equivalence. `Print Assumptions` reports each closed under the global context:
no additional axioms
or admitted proofs. Examples also reject an open instance, wrong class arity,
unbound variables, repeated binders, nested schemes, requirements used as types,
and class names used as datatype names.

These are **formation proofs**. A well-formed requirement need not have an
instance. The `requires` equivalence theorem concerns formation, not compiler
execution. Rigid definition checking, implicit/explicit instantiation,
substitution, evidence discharge, expression typing, initialization, evaluation,
progress/preservation, and compiler correspondence remain future proof work.
The handwritten book chapters continue to explain those implemented behaviors.

## Tool choice

[Ott](https://github.com/ott-lang/ott) supports Coq, HOL, Isabelle/HOL, Lem,
LaTeX, and OCaml syntax output, plus an experimental Menhir parser and pretty
printer. It has no built-in Agda or Lean backend. The Coq output is checked here
using Rocq, the renamed Coq prover; this avoids maintaining an independent Agda
translation. Generating inductive definitions does not generate the proofs.

The [formalization PR](https://github.com/tsnl/snail-scheme/pull/325) remains a
draft while the remaining judgments and proofs are developed.
