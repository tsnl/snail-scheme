# Resolved Lofi IR

The direct [frontend](../src/lofi/compiler/frontend.sld) turns located s-expressions
into the expression and binding records in [ir.sld](../src/lofi/compiler/ir.sld).
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
| Lambda | Fixed positional parameters and body |
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
emission never use it. The completed program retains source, binding schemes, class evidence and an
immutable [typed expression tree](../src/lofi/compiler/typed.sld). Each expression
carries its type and the decisions needed by specialization. Checking does not
retain a table of lexical scopes or function signatures for later replay.

Every body is checked, including unused functions. Each block plans binding
recursion groups before checking. A quantified recursive group first solves a
private monomorphic relation, then checks the source bodies with independent
rigid interpretations. The optional identity mapping of `copy-ir-graph` preserves
enclosing nominal, class and type-variable identities at that boundary.

Expression judgments construct provisional typed children while the solver owns
mutable holes. After obligations settle, freezing replaces remaining holes with
consistent immutable parameters. Unchanged immutable type structure is shared;
nominal identities remain opaque. Solver convergence tracks unresolved hole roots
for one round, rather than copying all resolved constraints before and after it.
Binding summaries release their provisional
judgments and scopes at this boundary.

Specialization substitutes each requested implementation into the typed tree and
constructs an immutable [concrete tree](../src/lofi/compiler/concrete.sld). It
records selected binding IDs, function IDs, match arms, concrete call signatures,
explicit representation conversions and tail positions. It does not rerun
inference or probe source expressions. Concrete substitution resolves types and
checks representation availability; references reuse the instance selected while
checking their obligations. No expression-keyed fact map is needed.
Literal width remains intrinsic except at a direct annotation or declaration.

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

Generation drains typed implementation requests to discover storage, reads and
nested closures, retaining each concrete body. A capture fixed point propagates
the values required to construct nested closures, excluding each function's own
locals and globals. Emission consumes concrete bodies after storage and captures
settle; it cannot introduce implementation requests.

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

A known lexical self call can reuse the current closure environment. Its concrete
binding instance must select the enclosing implementation, and its complete
initializer must be that implementation's literal lambda. Each activation
initializes this binding once, so a successful read identifies the executing
closure even when several factory activations share code. Module initialization
rejects repeated or reentrant execution. Aliases, computed
initializers, nested owners and other specializations do not establish this proof.
The call still evaluates every argument and then reads the operator, including
its readiness and payload null checks. Only the redundant held-local null check
and closure environment load disappear; closure allocation and capture stay intact.

## Current tradeoffs

Concrete construction and emission remain separate traversals because capture
and storage layouts must settle before closures are emitted. Their shared
immutable tree carries the decisions directly; neither traversal repeats typing.

Local functions currently use ordinary closures. Primitive, foreign and data
operations still emit directly, and known closure workers use direct calls, but
removing closures for exclusively invoked local functions and eliding proven global
readiness checks are deferred optimizations. The emitter's private local/layout
registries remain mutable; the demand graph and worklist are persistent values.
This representation preserves the WasmGC and scalar-resource ownership boundary.

The [tour](../TOUR.md) gives a reading order through `src/lofi/`, and the
[compiler reference](compiler.md) describes each module's contract.
[The Lofi book](book/lofi/index.md) is the language contract.
