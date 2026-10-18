# Ott and Rocq

The language definition is being moved into **Ott**, with proofs in **Rocq**
(formerly Coq). This draft covers the documented grammar and type formation.
Expression typing and evaluation still use the [formal summary](reference.md).

Ott generates both a typeset reference and Rocq inductive definitions from the
same source. Handwritten Rocq proofs import those generated definitions. The
first proofs establish variable scope, declaration arity, closed instance heads,
and agreement between the formation rules for the `All`/`requires` spellings.
They do not yet prove that the compiler implements the specification.

Build the checked reference from the repository root:

```sh
nix-shell doc/spec/shell.nix --run scripts/spec
```

Open `build/spec/lofi.pdf` for the grammar and named rules, or
`build/spec/html/toc.html` for linked definitions and proofs. The `Ott and Rocq`
CI workflow also uploads these as the `ott-rocq-reference` artifact.

## Read the source

The excerpts below are included directly from the checked Ott file. A production
ends with `:: ::` followed by its branch name; a rule's horizontal line is
followed by `::` and its rule name. `a1 .. ar` is a list. Its length is independent
of a different list such as `q1 .. qu`. `{{ coq ... }}` specifies how mathematical
notation is represented in Rocq.

The full grammar also includes terms, static declarations, and libraries. It
keeps library declarations outside expression blocks. Name categories use
distinct identity types after resolution; source names can share spellings.

```text
{{#include ../../spec/lofi.ott:types}}
```

## Formation and scope

`Delta` maps visible datatype identities to their arities; `Xi` does the same
for classes. Each identity has at most one arity. `A` is the set of in-scope
type-variable identities, represented as a list. These environments record
declarations and scope, without introducing a kind calculus. A class or datatype has as many arguments as its declared
arity, including zero arguments.

```text
{{#include ../../spec/lofi.ott:formation}}
```

## Schemes and instance heads

`All` extends the type-variable scope for both its body and requirements. The
freshness premise refers to resolved identities, so a source binder may still
shadow a name with the same spelling. An instance head must form under an empty
type-variable scope; the Rocq proof establishes that no variable occurs anywhere
inside its arguments.

```text
{{#include ../../spec/lofi.ott:schemes}}
```

Formation establishes that a requirement is meaningful. It does not establish
that an instance supplies it. The next steps are formalizing substitution,
instantiation, rigid checking, and requirement discharge, then expression
typing and evaluation. The current proofs do not claim progress, preservation,
or compiler correctness.
