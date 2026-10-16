# Notable omissions

## Deliberate exclusions

Lofi has no user macro system. Frontends expand their own languages before
producing library values. There is no function-definition shorthand, named
`let`, `let*`, `cond`, `and`, `or`, `when` or `unless`. Sequential `let` statements
and recursive `def` bindings inside `begin` supply the binding operations.
Names cannot be reassigned; explicit cells represent mutable state.
Both `def` and `let` can infer their annotations. Static definitions use
`datatype`, `typeclass` or `instance` as the direct body of a library-level `def`.
Kinds distinguish these definitions from ordinary values; dependent types and
arbitrary computation in types are future work.

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
and Chibi. Additional cross-runtime transports, frontend macro interfaces and general target
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
