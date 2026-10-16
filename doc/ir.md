# Resolved Lofi IR

The direct [frontend](../src/snail-lofi/frontend.sld) turns located s-expressions
into the expression and binding records in [ir.sld](../src/snail-scheme/ir.sld).
It resolves names and attaches binding declarations. Expressions have no inferred
type or constraint fields. The frontend does not
expand macros, infer types or optimize expressions.

## Identity and scope

A reference points to a binding identity, not a printed name. Import renaming
changes the name visible to a client while preserving the original identity.
Each overload family likewise has an identity; its members retain separate
explicit signatures and initializers. Overload signatures are available before
checking bodies; they are never inferred from the implementations or call sites.

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
| Expression | Source location, operation and source children |
| Source literal | Decoded value and original numeric spelling; transient typing selects and rounds its representation |
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

## Checking and generation

Inference owns a copy of the resolved binding graph, preserving immutable binding
origins. Expressions contain only kind, location and source data. Frontend import
resolution and graph copying have a construction-only data setter; checking and
emission never use it. The completed program retains source, binding schemes,
lexical scopes, lambda signatures, its result type, and class evidence. There is
no expression-type map and no lowered or monomorphized expression tree.

The Scheme record `pass` names callable operations for each source arm. Its shared
visitor dispatches the arm; structural visitors arrange child dependencies and
supply returned judgments to separate typing rules. The concrete visitor manually
interleaves typing, child generation and emission operations. It is explicit code,
not a higher-order pass-interleaving combinator.

Every body is checked, including unused functions. Each block plans binding
recursion groups before checking. A quantified recursive group first solves a
private monomorphic relation, then checks the source bodies with independent
rigid interpretations. The optional identity mapping of `copy-ir-graph` preserves
enclosing nominal, class and type-variable identities at that boundary.

Expression judgments are temporary records containing the current arm's type,
obligations and immediate result information. They contain no child judgments.
Binding summaries retain only initializer type, obligations, nonexpansiveness and
the lexical proof scope; they do not retain arm details. Those obligations are
saturated after enclosing monotypes settle and discharged before generation.
The private solver still mutates unification holes and owned binding schemes.
Lambda scopes retain their checked function signature so requesting a closure
does not recheck its body. Scopes created for the private recursive relation are
discarded when that check finishes.

The concrete visitor returns three values: this arm's typing judgment, its target
fragment, and the updated request context. It supplies completed immediate child
judgments to the typing arm, then supplies generated children to the emission arm.
There is no unconditional subtree typing step at expression entry. Concrete call
signatures and inherited result types provide child demands directly. Literal
width is still intrinsic except at a direct annotation or binding declaration.

## Concrete demand and storage

A persistent SRFI 146 hash map reserves stable IDs before appending implementation
requests to a pending list. A binding request is keyed by lexical site, concrete
type and indexed concrete quantifier substitutions. Function requests include the
source identity and concrete lexical instance identity. No cache key contains a
unification variable. Composite key lists and type structure use structural
equality; source, binding and nominal records use identity equality and hashing.
Hashing a key therefore never traverses a source body or a binding graph.
Requests reuse reserved IDs, including during recursion; there is no mutable
pending/emitted status object. The visitor threads each returned context through
subsequent siblings.

Generation first drains source-based implementation requests to discover storage,
reads and nested closures. Only binding/function summaries survive this stage.
A capture fixed point propagates the values required to construct nested closures,
excluding each function's own locals and globals. Each demanded body is then
emitted from source after its storage and capture layouts are settled. Emission
asserts that it introduces no unplanned implementation IDs.

A source site owns initialization; a concrete value owns its payload; a function
owns code. Demanding code does not execute an initializer. All source bind events
remain in order, including unused effects and unused polymorphic alias reads.
Forward reads use readiness guards. A readiness token preserves an erased alias's
source read even when no payload specialization is demanded. Captured recursive
bindings use shared cells; parameter and pattern values are captured directly.

Runtime operands evaluate from left to right before the operator. Type constraints
can inspect the operator earlier to determine operand expectations. Explicit Any
conversions retain precise semantic type witnesses, including nominal identities.
Proper tail calls remain target tail calls, including a Unit-valued call followed
only by an inert Unit constructor.

## Current tradeoffs

Summary discovery and target emission are still separate concrete traversals:
capture and storage layouts must settle before closures are emitted. Within each
traversal, concrete demands use the fused visitor. Calls whose generic signature
cannot yet select argument representations probe the unresolved arguments with
shared constraints. Unknown branch or pattern result demands likewise use a
type-only probe when checked root facts cannot determine their representation.
These probes retain only the boundary's result; they do not cache descendant
judgments. They can revisit source, so this is not a promise of one visit for every
possible nesting or every concrete implementation.

Local functions currently use ordinary closures. Primitive, foreign and data
operations still emit directly, and known closure workers use direct calls, but
removing closures for exclusively invoked local functions and eliding proven global
readiness checks are deferred optimizations. The emitter's private local/layout
registries remain mutable; the demand graph and worklist are persistent values.
No native lowering or runtime ownership protocol changes with this representation.

The [tour](../TOUR.md) names each implementing module. The internal
`snail-scheme`/`strict-*` module names are migration remnants; they do not expose
a second product language. [The Lofi design](lofi.md) is the language contract.
