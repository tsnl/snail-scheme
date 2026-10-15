# Notable omissions

## Deliberate exclusions

SFIR has no user macro system. Frontends expand their own languages before
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

## Open work

The [compiler tour](https://github.com/tsnl/snail-scheme/blob/main/TOUR.md)
record current compiler behavior; this specification's surface changes and
library APIs require implementation work. They are not compatibility aliases
silently accepted by the existing compiler.

Literal defaults are I32 and F64 in this design, with explicit annotations for
other widths. Diagnosing representation overflow is required behavior, but the
compiler MVP may not yet enforce every runtime overflow check.

The [earlier ownership proposal][ownership] develops affine values and cleanup rules.
The present chapters describe the unrestricted core and reserve `many(T)` for
the property needed at an Any boundary. They do not yet constitute a formal
ownership calculus.

The representation and transport of library data across runtimes, frontend
macro interfaces, and target-specific capability contracts need their own
detailed specifications. Their boundaries are stated here so those mechanisms
can be developed without making ordinary imports or value evaluation magical.

> TODO: Complete the formal rules for nominal declarations, exhaustive matching,
> rest arguments, datatype and typeclass formers, instance checking, affine ownership,
> and target interfaces. The earlier chapters state their intended behavior;
> the formal summary currently covers the unrestricted functional core.

[ownership]:
  https://github.com/tsnl/snail-scheme/blob/2db2216b/doc/strict-core.md#proposed-affine-ownership
