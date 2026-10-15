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

A sequential `let` resolves its initializer before introducing a fresh identity
for subsequent statements. A `def` initializer sees every definition and only
the preceding lets. Both resolve to ordinary binding nodes; their distinct scope
rules have already selected the identities used by every reference. A source-form
field retains `def` versus `let` for syntax inspection and transfer; owned IR
copies preserve it. Runtime
storage can be reserved conservatively without making a later let visible.

Value and type scopes are separate. An attached `All` scopes its type-variable
identities over its initializer, including nested annotations; lambda parameters
only extend the value scope. Static definitions retain nominal, class and named
instance identities. Library body clauses concatenate before resolution, while
an expression `begin` remains a nested scope.

## Records and evidence

| Object | Information it retains |
| --- | --- |
| Binding | Identity, source location, initializer, attached declaration and inferred scheme |
| Expression | Source location, operation and type slot |
| Source literal | Decoded value and original numeric spelling; checking selects and rounds its representation once |
| Reference | The resolved binding being read |
| Lambda | Positional parameters, optional rest parameter and body |
| Application | Operator and ordered argument expressions |
| Block | Lexically scoped definitions, declarations and ordered expressions |
| Conditional | Boolean condition and both result branches |
| Annotation or instantiation | The explicit source type requirement |
| Data/class/instance/overload/extern declaration | Identities and contracts needed by checking and specialization |

A hole means that inference must solve a type, never that a value should be
boxed into `Any` (currently spelled `Top` inside the solver). Declared signatures belong to their definitions; no later
pass must guess which same-named overload a detached annotation describes.

## Pass ownership

Inference takes an owned copy of the resolved graph. It plans binding dependency
groups once, checks explicit quantifiers rigidly, solves constraints and
retains generalized schemes and class requirements. Dependency groups establish
checking order; they do not change runtime initializer order. Mutable state
limits generalization.

For a recursive group with quantified annotations, a private source copy solves
the group's monomorphic template before the original bodies are checked against
their rigid signatures. `copy-ir-graph` accepts one optional identity mapping:
mapped objects and their children remain owned by the enclosing check, while
unmapped group nodes and binders are copied. This preserves external nominal,
class and type-variable identities without cloning their dependency graphs.
Checked name nodes retain their ordinary binding and substitution evidence for
specialization; the private template does not become executable IR.

Specialization requests concrete instances of those checked templates and
resolves overloads and class methods for each instance. It retains explicit
conversions, concrete function signatures and storage types. Unresolved runtime
polymorphism is an error. The concrete program then supplies Wasm function,
closure and data layouts to the emitter.

The [tour](../TOUR.md) names each implementing module. The internal
`snail-scheme`/`strict-*` module names are migration remnants; they do not expose
a second product language. [The SFIR design](sfir.md) is the language contract.
