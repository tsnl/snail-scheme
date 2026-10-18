# Notable omissions

## Deliberate exclusions

The [macro and Scheme chapter](macros.md) describes hygienic `syntax-rules` and
the initial `(scheme base)`. Procedural transformers, `let-syntax`, `letrec-syntax`,
custom ellipsis identifiers and escaped ellipses remain unsupported. The Scheme
surface is a typed subset, without general Scheme truthiness, quoted datums,
`set!`, multiple values or continuations. It is not R7RS conformant.
Sequential core `let` statements and recursive `def` bindings inside `begin`
supply the binding operations after expansion.
Names cannot be reassigned; explicit cells represent mutable state.
Both `def` and `let` can infer their annotations. Static declarations use
library-level `data`, `typeclass` and `instance` forms.
Their name categories, scopes, and declared arities distinguish them from
ordinary values. Type parameters stand for ordinary types; higher-kinded
parameters, dependent types, and arbitrary computation in types are unsupported.

Lambdas infer their captures. The textual core uses the spellings `lambda`,
`All`, `->` and `<=`; the rules use Unicode mathematical notation. Additional
source aliases are unnecessary for the model. `All` is rank one, and generic
code specializes before emission. There is no silent generic-runtime or JIT
fallback when specialization cannot determine a representation.

Union cases have explicit constructors, not structural subtype membership.
Class instances have concrete heads. There are no generic instance heads,
associated types, overlapping instances, implicit numeric conversions or
multiple return values in this specification. Structs can carry several results.

Imports do not secretly create running instances. Source discovery belongs to
a driver, and instantiation is explicit. Library dependency cycles and
generation dependency cycles are rejected. Reading an uninitialized recursive
binding traps instead of forcing its initializer early.

## Planned language simplification

The following changes are planned, not accepted compiler syntax:

- Use `requires` to state a scheme's class requirements. The final arrangement
  of `All`, requirements, implicit instantiation, and checking remains open.
  The current compiler uses `All` with `=>`; the formal summary explains that
  implementation without committing to its replacement.
- Give the Lofi kernel fixed-arity functions. Scheme variadic procedures will
  need lowering to an explicit packed argument representation and fixed-arity
  calls. The current kernel still accepts dotted and rest-only lambdas and
  `Rest` function types. Polymorphism handles variation in types; packing is
  still needed for variation in runtime argument count.
- Move the language specification into a formal source, with prose and examples
  alongside checked definitions and named rules. The generated reference should
  replace the corresponding handwritten book content as coverage becomes complete.

## Implementation and open work

The [compiler tour](https://github.com/tsnl/snail-scheme/blob/main/TOUR.md) records current module
responsibilities. The [implementation
roadmap](https://github.com/tsnl/snail-scheme/blob/main/doc/roadmap.md#align-with-the-lofi-book)
distinguishes implemented language and library contracts from remaining adapter and validation work.
Each execution adapter documents its supported targets and entry ABI.

Literal defaults are I32 and F64, with explicit annotations for other widths.
Ordinary fixed-width arithmetic uses wrapping integer and IEEE floating-point
operations. Literal construction and narrowing conversions still check their
representation bounds. Explicit checked-arithmetic variants are deferred; the
[extensions](extensions.md) document current operations and compatibility aliases.

The [earlier ownership proposal][ownership] develops affine values and cleanup rules.
The present chapters describe the unrestricted core and reserve `many(T)` for
the property needed at an Any boundary. They do not yet constitute a formal
ownership calculus.

The [builder protocol](https://github.com/tsnl/snail-scheme/blob/main/doc/lofi-builder.md) documents
the implemented structured representation and owned transfer of library data between compiled Lofi
and Chibi. Additional cross-runtime transports, procedural macro interfaces and general target
capability contracts need separate specifications. The [compiler
service](https://github.com/tsnl/snail-scheme/blob/main/doc/lofi-compiler-service.md) and [native
loader](https://github.com/tsnl/snail-scheme/blob/main/doc/lofi-native-loading.md) document their
current interfaces and restrictions.

> TODO: Complete the formal rules for nominal declarations, exhaustive matching,
> rest arguments, datatype and typeclass formers, instance checking, affine ownership,
> and target interfaces. The earlier chapters state their intended behavior;
> the formal summary currently covers the unrestricted functional core.

[ownership]:
  https://github.com/tsnl/snail-scheme/blob/2db2216b/doc/strict-core.md#proposed-affine-ownership
