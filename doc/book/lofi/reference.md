# Formal summary

These rules describe the typed kernel after [hygienic macro expansion](macros.md).
The initial Scheme forms are library macros that produce this same kernel.

This is the compact companion to [Terms and definitions](terms.md) and
[Types](types.md). The grammar defines source forms; parsing turns them into
an abstract syntax tree (AST), a structured value representing the program.
Name resolution replaces textual references with binding identities.

<!-- For agents editing this specification: keep the explanatory chapters and
this summary synchronized. Include the named anchors rather than copying their
grammar and rules. If a rule changes, update its surrounding explanation too. -->

## Grammar

`…` repeats the preceding item zero or more times; `[item]` is optional.
Each quoted string is a separate source token. `name` and the literal categories
are reader tokens; other grammar names expand into the rules below. Reserved
keywords distinguish special forms from ordinary calls.

{{#include terms.md:expressions}}

{{#include types.md:types}}

{{#include types.md:schemes}}

{{#include types.md:kinds}}

{{#include types.md:data}}

{{#include types.md:classes}}

Static definitions occur only in a library body for the MVP. The
[library grammar](libraries.md#writing-a-library) embeds them alongside ordinary
statements and defines imports, exports and generation recipes.

## Core typing rules

`Γ` maps binding identities to schemes. Schemes have the form `∀ᾱ. P ⇒ T`;
unquantified types have no bound variables and no requirements.
`Γ ⊢ e ::↑ T |> P` synthesizes T and collects P;
`Γ ⊢ e ::↓ T |> P` checks against T and collects P.
See [Reading the typing rules](types.md#reading-the-typing-rules) for the notation.
Fresh variables are inference holes, which do not appear in source syntax.
Equalities unify after following solved holes; quantified variables are rigid.

{{#include types.md:literals}}

{{#include types.md:instances}}

{{#include types.md:calls}}

{{#include types.md:branches}}

{{#include types.md:subtyping}}

Bindings use their lexical environments as specified in [Definitions and
blocks](terms.md#definitions-and-blocks). A `def` or `let` can supply a signature;
otherwise its type is inferred. Recursive uses within a dependency group have
provisional monomorphic views. After solving a group, generalize each eligible
unannotated binding against the surrounding environment, excluding the group's
own provisional entries. An ineligible binding's free variables remain shared
with the environment and cannot be generalized by another binding in that group.

```text
generalize(Γ, initializer, T, P):
  A = free(T,P) ∖ free(Γ) if eligible(initializer), otherwise ∅
  abstract = {q ∈ P | free(q) ∩ A ≠ ∅}
  return (∀A. abstract ⇒ T, P ∖ abstract)

eligible = literal | name | lambda | instantiation | static-annotation(eligible)

check-block(Γ, statements) = (Γ′, P)       Γ′ ⊢ result ::↑ T |> Q
──────────────────────────────────────────────────────────── TYPE-BLOCK-INFER
Γ ⊢ (begin statements … result) ::↑ T |> P ∪ Q

check-block(Γ, statements) = (Γ′, P)       Γ′ ⊢ result ::↓ T |> Q
──────────────────────────────────────────────────────────── TYPE-BLOCK-CHECK
Γ ⊢ (begin statements … result) ::↓ T |> P ∪ Q
```

`check-block` resolves scopes, checks each initializer or expression, solves
binding groups and collects remaining obligations. An attached signature checks
its initializer; an `All` supplies rigid variables and declared assumptions.
A direct numeric literal initializer with a scalar annotation uses the literal
annotation rules. Expression statements contribute obligations even when their
values are discarded. Generalization does not suppress initializer effects or
initialization checks.

## Kinds

`Δ` maps static names to kinds. Datatypes produce Type or a constructor ending
in Type; typeclasses produce a constructor ending in Constraint; checked
instances produce Evidence of their head requirement. These are static
classifications, not runtime values.

{{#include types.md:kind-rules}}

## Evaluation rules

`ρ` maps value-binding identities to locations; `σ` maps locations to values or
`uninitialized`. A value evaluation is written `⟨e,ρ,σ⟩ ⇓ ⟨v,σ′⟩`.
Environments captured by closures retain locations, so later initialization
and explicit cell mutation can be observed without changing lexical scope.
These locations are an abstract evaluation model, not a requirement to allocate
every binding. Initialized immutable values can be copied into closures; the
[capture rules](terms.md#closure-captures-and-initialization-cells) explain the
hidden initialization cells needed for forward and recursive `def` captures.

```text
σ(ρ(x)) = v
──────────────────────── EVAL-NAME
⟨x,ρ,σ⟩ ⇓ ⟨v,σ⟩

──────────────────────────────────────────────────── EVAL-LAMBDA
⟨(lambda (x̄) body),ρ,σ⟩ ⇓ ⟨closure(x̄,body,ρ),σ⟩

⟨eᵢ,ρ,σᵢ₋₁⟩ ⇓ ⟨vᵢ,σᵢ⟩  (i = 1 … n, in order)
⟨f,ρ,σₙ⟩ ⇓ ⟨closure(x̄,body,ρc),σf⟩
ρb,σb = bind-fresh(ρc,σf,x̄,v̄)       ⟨body,ρb,σb⟩ ⇓ ⟨v,σ′⟩
─────────────────────────────────────────────────────────── EVAL-CALL
⟨(f e₁ … eₙ),ρ,σ₀⟩ ⇓ ⟨v,σ′⟩

evaluate-block(statements, result, ρ, σ):
  reserve fresh uninitialized locations for every value def in this block
  visit statements in source order using their resolved lexical environments
    def: evaluate its initializer, then fill its reserved location
    let: evaluate its initializer, then bind the value at a fresh location
    expression: evaluate and discard its result
  evaluate and return result in the final environment
```

A read of an uninitialized location traps. Library-level datatype and typeclass
definitions establish static identities before value initialization; constructor
arguments run only when a constructor is called. An instance's method
implementations initialize at its source position.
`if` evaluates its condition and selected branch. `match` evaluates its subject
once and selected arm. A trap propagates after the effects that preceded it.
These rules describe results and ordering; implementations must additionally
meet the [proper tail recursion](terms.md#proper-tail-recursion) space guarantee.
