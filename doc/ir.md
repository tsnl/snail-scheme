# Resolved SFIR IR

The direct [frontend](../src/snail-sfir/frontend.sld) turns located s-expressions
into the expression and binding records in [ir.sld](../src/snail-scheme/ir.sld).
It resolves names and attaches declared types or inference holes. It does not
expand macros, infer types or optimize expressions.

## Identity and scope

A reference points to a binding identity, not a printed name. Import renaming
changes the name visible to a client while preserving the original identity.
Each overload family likewise has an identity; its members retain separate
signatures and initializers.

A lexical block reserves its immediate definitions before resolving their
initializers. This admits recursion and forward references without reordering
runtime initialization. A premature value read remains a checked failure.
Nested `begin` blocks create scopes and must not be flattened into their parents.

A `let` resolves every initializer in the enclosing scope, left to right, then
introduces all its local bindings for its one body expression. Its IR is an
immediate lambda application. The inference pass recognizes this local-binding
shape when deciding which definitions may generalize.

## Records and evidence

| Object | Information it retains |
| --- | --- |
| Binding | Identity, source location, initializer, attached declaration and inferred scheme |
| Expression | Source location, operation and type slot |
| Reference | The resolved binding being read |
| Lambda | Positional parameters, optional rest parameter and body |
| Application | Operator and ordered argument expressions |
| Block | Lexically scoped definitions, declarations and ordered expressions |
| Conditional | Boolean condition and both result branches |
| Annotation or instantiation | The explicit source type requirement |
| Data/class/instance/overload/extern declaration | Identities and contracts needed by checking and specialization |

A hole means that inference must solve a type, never that a value should be
boxed into `Top`. Declared signatures belong to their definitions; no later
pass must guess which same-named overload a detached annotation describes.

## Pass ownership

Inference takes an owned copy of the resolved graph. It plans binding dependency
groups once, checks explicit quantifiers rigidly, solves constraints and
retains generalized schemes and class requirements. Dependency groups establish
checking order; they do not change runtime initializer order. Mutable state
limits generalization.

Specialization requests concrete instances of those checked templates and
resolves overloads and class methods for each instance. It retains explicit
conversions, concrete function signatures and storage types. Unresolved runtime
polymorphism is an error. The concrete program then supplies Wasm function,
closure and data layouts to the emitter.

The [tour](../TOUR.md) names each implementing module. The internal
`snail-scheme`/`strict-*` module names are migration remnants; they do not expose
a second product language. [The SFIR design](sfir.md) is the language contract.
