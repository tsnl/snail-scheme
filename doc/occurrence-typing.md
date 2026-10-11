# Occurrence typing and check elimination

Design proposal. A bounded subset is now implemented; see
[the prototype report](typing-prototype.md) for authoritative current syntax,
limits, soundness findings, and measurements. The implemented rank-one subset is documented there; higher-order contracts
and the broader polymorphic rules below remain proposals.

Add occurrence typing to resolved Scheme IR, using verified predicate summaries
to narrow types at individual uses. Use the same facts to check optional
annotations and remove redundant runtime checks. Keep the current WasmGC value
representations and AWI ownership contract.

Occurrence typing is the refinement mechanism in scope: propositions describe
membership in types, their negations, and Boolean combinations. Arithmetic
refinements, SMT solving, dependent type computation, public effect annotations,
and totality checking are outside this proposal. Internal mutation information
exists only to determine whether facts remain valid.

Build ordinary annotation checking and local inference first. Occurrence
propositions are an extension of that checker, introduced after its basic
function and boundary rules work.

The companion [typing rules](typing-rules.md) define the proposed judgments,
subtyping, gradual check obligations, occurrence filters, and record interfaces.
They also sketch the subsequent rank-one polymorphism rules and state the
remaining proof and runtime-enforcement obligations.

## Baseline and proposed compiler boundary

[`ir.sld`](../src/snail-scheme/ir.sld) contains resolved expressions and binding
identities. [`wasm.sld`](../src/snail-scheme/wasm.sld) analyzes assignment,
initialization, and captures before emitting structured Wasm. Checks appear in
that emission and in [`wasm-runtime.sld`](../src/snail-scheme/wasm-runtime.sld); the current IR has
no explicit type-check instructions. The prototype now adds annotation and
schema metadata and records required guards in a separate analysis result.

The proposed pipeline is:

```text
located syntax → expansion → resolved IR
                            → occurrence analysis and annotation checking
                            → facts and check decisions for each use
                            → WasmGC emission → existing linking and optimization
```

Initially, analysis results live in tables keyed by IR occurrences and binding
identities. Preserve the frontend's structure. Add annotation metadata only
when implementing source annotations; locations and resolved identities must
survive expansion. A binding's declared type is separate from the narrower type
known at one use.

One lambda body may execute from several call sites. Facts used to emit its
shared worker must hold at every possible entry, including its generic adapter
when reachable. Caller-specific facts cannot silently specialize that shared
body. An immediate, nonescaping lambda can use its sole caller's facts; otherwise
join the possible inputs or retain the checks. Function cloning is unnecessary
for the initial implementation.

The compiler remains hosted by Chibi. This work follows the measured executable
backend and uses its existing linked Wasm as the comparison baseline.

## Basic typing first

Propose `(snail typing)` as the public library. The compiler's implementation
libraries remain under `(snail-scheme ...)`. The ordinary library loader can
find a public facade at `src/snail/typing.sld`; its annotation forms need
compiler support before such an import works.

```scheme
(import (scheme base) (snail typing))

(: increment (-> ExactInteger ExactInteger))
(define (increment x)
  (let ((step 1))
    (+ x step)))

(increment 41)
```

The import exposes type syntax and names. A declaration opts its definition
into checking; merely importing the library does not make every definition
strict. Existing `define`, `lambda`, and `let` forms retain their syntax.

Start with two annotation forms:

| Proposed form | Meaning |
| --- | --- |
| `(: name T)` | Check the named definition against `T`, and make `T` its declared type |
| `(ann expression T)` | Check this expression against `T` and give it that static type |

For `increment`, collect its declared function type before checking the body.
It accepts one `ExactInteger` and returns one `ExactInteger` on normal return.
The signature supplies `x`'s type; the literal supplies `step`'s type. The
primitive specification for `+` establishes an exact-integer result for these
arguments, which satisfies the declared result type. Overflow checking remains:
a result type does not promise that a call always succeeds.

Use two mutually supporting operations:

```text
infer(expression, environment) → type and result count
check(expression, expected-type, environment) → checked expression and obligations
```

Inference synthesizes types for literals, names, applications, and local
initializers. Checking a lambda against a function signature supplies its
parameter types and checks its body against the expected result. Checking
other expressions compares their inferred type with the expectation. This is
bidirectional checking. For example, an anonymous function needs no new binder
syntax:

```scheme
(ann (lambda (x) (+ x 1))
     (-> ExactInteger ExactInteger))
```

Require signatures for named functions in this initial checked subset, including
recursive groups. Reserve every group's signatures before checking any body.
Infer local values and contextually typed lambdas. Unannotated functions remain
dynamic; general polymorphic inference is a later design.

The basic checker handles conditionals without narrowing the variables used in
the test. It checks each branch in the same type environment and joins their
result types. Scheme still permits any single value as a test, with only `#f`
false. Thus `(if flag 1 "one")` can have type `(U ExactInteger String)`, but
testing `(string? x)` does not yet make `x` usable as a `String` inside a branch.
That is the later occurrence-typing step.

Assignments to declared bindings must satisfy their declared type. For mutable
locals in a checked body, require an annotation when the initializer does not
describe the intended type of all writes. Binding initialization and multiple
values remain separate obligations. Start with fixed-arity, single-result
signatures; unsupported signatures must be diagnosed rather than silently
treated as returning one value.

Statically incompatible expressions in checked definitions are rejected at
their source locations. Calls arriving from untyped code use checked entries.
A known typed call can discharge the argument obligations statically. The
initial executable slice must include entry guards for its supported scalar
and category-union signatures. Richer boundaries can remain unsupported until
their checks exist. The gradual rules below describe unknown values inside a
checked body.

Annotation syntax must survive expansion until checking. The expander resolves
the imported `:` and `ann` bindings, retains located declarations and expression
ascriptions, and associates each declaration with the existing value-definition
identity. Recognize type names and constructors through their bindings too,
preserving import renaming. An ordinary macro that erases the annotation would
lose the obligation. Type syntax is not executed as a runtime procedure.

The `:` and `ann` surface follows
[Typed Racket's annotation forms](https://docs.racket-lang.org/ts-guide/more.html);
the proposed import and per-definition checking policy are Snail's design.

## Record declarations

Record declarations introduce nominal types: two distinct declarations remain
different types even when their fields have the same names and types. In a type
expression, the record name denotes its instances; in a value expression, the
current implementation binds that name to its runtime descriptor. The descriptor
is not itself an instance. Preserve that distinction in the typing metadata.

Ordinary `define-record-type` continues to work, with unknown field types until
more information is provided. Preserve a record schema through expansion so
the checker can associate its nominal identity with its constructor, predicate,
accessors, and optional setters. The schema records their resolved binding
identities, field names and order, constructor argument order, field types,
mutability, and locations. Do not recognize generated procedures by spelling.

Extend Snail's existing `define-record-type` binding from `(scheme base)` with
optional field annotations. `(snail typing)` supplies `:`, annotation forms,
and type names; it does not introduce a second `define-record-type` binding.
The field annotation syntax remains provisional:

```scheme
(import (scheme base) (snail typing))

(define-record-type <point>
  (make-point x y)
  point?
  (x : ExactInteger point-x set-point-x!)
  (y : ExactInteger point-y))
```

Keep the existing field forms and allow annotated and unannotated fields in
the same declaration:

```scheme
(field accessor)
(field accessor setter)
(field : Type accessor)
(field : Type accessor setter)
```

Recognize `:` by its annotation binding, including renamed imports. The base
macro and the typing facade can share an internal annotation binding without
making `(scheme base)` depend on `(snail typing)`. Keep the base library's exports
unchanged; export the new public syntax from `(snail typing)`. Existing record
declarations need no typing import. A separate `struct` convenience form is
unnecessary for this design; any later shorthand should use the same record
schema and rules.

The checker derives these signatures for `<point>`:

```text
make-point    : (-> ExactInteger ExactInteger <point>)
point?        : (-> Any Boolean)
point-x       : (-> <point> ExactInteger)
point-y       : (-> <point> ExactInteger)
set-point-x!  : (-> <point> ExactInteger Unspecified)
```

`Unspecified` describes the value currently returned by the runtime setter.
Unannotated fields use `?` in the corresponding signatures. A missing setter
means the declaration exposes no field-update operation. Field types and these
generated signatures suffice for ordinary checking:

```scheme
(: sum-coordinates (-> <point> ExactInteger))
(define (sum-coordinates p)
  (+ (point-x p) (point-y p)))
```

No occurrence typing is needed here: `p`'s declared type supplies the receiver
type and each accessor supplies its result type. In the basic checker,
`point?` only returns a Boolean. Later, the schema supplies its verified
truthy/false propositions about the same nominal identity.

Constructors and setters check field types statically at checked calls and
dynamically at unknown entries. With shallow boundaries, nominal membership
establishes the record kind; an accessor must still validate its returned field
value whenever the field invariant is not established. The core
`%record-set!` operation currently permits arbitrary field values, so guarding
only the generated setter does not prove that every write preserves an
annotation. Keep accessor result checks unless analysis establishes all
construction and mutation paths, or a later runtime design enforces those
invariants universally. Even fields without public setters need this accounting
when low-level operations can reach them.

R7RS permits constructor argument order to differ from field order and allows
fields omitted from the constructor to start with unspecified contents.
Initially, require every precisely typed field to appear in the constructor.
Ordinary untyped records retain their existing behavior.
Recursive field types and staged field initialization are subsequent work.
See [R7RS section 5.5](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-7.html#TAG:__tex2page_sec_5.5).

Initially support precise typed schemas for library/script-level declarations
whose descriptor bindings are not reassigned. Local record factories require
additional care: the current runtime and bootstrap test give each invocation
a fresh record identity. One source declaration is therefore not always one
runtime type. Keep these local declarations dynamic, with runtime identity
checks, until a design for scoped generative types preserves that distinction.
Diagnose unsupported explicit annotations rather than silently discarding them;
ordinary local records remain valid.

The existing macro in
[`bootstrap/scheme/base.sld`](../bootstrap/scheme/base.sld) expands records into
ordinary procedure definitions calling `%make-record-type`, `%make-record`,
`%record?`, `%record-ref`, and `%record-set!`. Add compiler-visible schema metadata
alongside that expansion. Extend the macro to retain optional field annotations
in the schema. Preserve the descriptor plus field-vector representation.
Evidence of a specific record identity can later remove redundant descriptor
comparisons; a field result check requires its own evidence.

### R7RS compatibility

[R7RS section 1.3.1](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-3.html#TAG:__tex2page_sec_1.3.1)
allows implementations to extend standard identifiers when the extensions do
not conflict with standard behavior. Optional field annotations fit that rule:
standard field clauses have two or three elements, while annotated clauses have
four or five. This is a Snail extension; annotated source is not portable R7RS.

Match complete field clauses. Never interpret a standard clause such as
`(value : set-value!)` as an incomplete annotation: `:` is the chosen accessor
name there. The annotation marker is meaningful only in the new clause shapes
and with its imported binding. Preserve ordinary identifier use, macro hygiene,
and import renaming.

Unannotated declarations retain the record behavior of
[section 5.5](https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-7.html#TAG:__tex2page_sec_5.5):
empty records, constructor argument order, omitted fields with unspecified
initial contents, arbitrary field values and updates, and distinct identities
from locally executed declarations. Importing `(snail typing)` alone adds no
field restrictions. The initialization requirement above applies only to
explicitly typed fields, never to ordinary record declarations.

For unannotated records, schema-derived procedure types describe the generated
procedure values; they do not impose new restrictions on reassigning their
local bindings. Discard facts when reassignment can replace those values.
Likewise, an observed field value must not become a restriction on later writes.
These are requirements for the extension, not a claim of full compiler
conformance.

## Polymorphism

Rank-one `All` and `inst` are now implemented for shallow signatures, with
concrete checks at typed calls and diagnostics for unenforceable abstract
boundaries. See [the implementation contract](typing-prototype.md#rank-one-polymorphism).
The higher-order and parameterized-record extensions below remain proposals.

After the initial occurrence-typing milestone, add explicitly declared
parametric polymorphism with inferred type arguments at calls. This is separate
from inferring polymorphic signatures for unannotated definitions. Proposed
syntax follows Typed Racket's
[`All` declarations](https://docs.racket-lang.org/ts-guide/types.html)
and [`inst` form](https://docs.racket-lang.org/ts-reference/special-forms.html):

```scheme
(: identity (All (A) (-> A A)))
(define (identity x) x)

(identity 42)        ; i32 (a subtype of ExactInteger)
(identity "hello")   ; String
((inst identity String) "hello")
```

Check the definition once with a fresh, rigid type variable `A`: its body must
work for any instantiation, not choose a convenient type for `A`. Infer fresh
type arguments independently at each call, using argument types and expected
results. If inference cannot solve the constraints, request explicit `inst`
arguments rather than silently substituting `Any` or `?`.

The signature preserves an input/output type relationship. A function of type
`(-> (U ExactInteger String) (U ExactInteger String))` may return a string when
given an integer; `identity` instantiated at `ExactInteger` must return an
`ExactInteger` on normal return. Generic code that only passes values through
needs no occurrence narrowing. `All` does not establish purity, termination,
or behavioral independence from runtime type tests.

Start with rank-one signatures: `All` appears at the outside of a function's
declared type, not inside its parameter types. Ordinary higher-order functions
remain possible, with type arguments chosen before passing a polymorphic
function as an argument. Initially check recursive calls at the same type
parameters. Defer higher-rank types, polymorphic recursion, higher-kinded type
parameters, and automatic let-generalization.

Parameterized records can extend the same declaration, with provisional syntax:

```scheme
(define-record-type (<box> A)
  (make-box value)
  box?
  (value : A box-value set-box-value!))
```

The parameterized name is a new syntax case; the standard identifier-only
record name remains unchanged. Derived signatures include:

```text
make-box       : (All (A) (-> A (<box> A)))
box-value      : (All (A) (-> (<box> A) A))
set-box-value! : (All (A) (-> (<box> A) A Unspecified))
```

The declaration establishes one nominal record family. Type applications carry
static arguments and share its runtime identity; they do not allocate a new
descriptor for each type argument. Consequently `box?` cannot distinguish
`(<box> ExactInteger)` from `(<box> String)`. It can narrow a known union of
`(<box> ExactInteger)` and `String` to the former, but from `Any` it establishes
only the record family. Unknown element type must not be confused with the
mutable type `(<box> Any)`; Typed Racket's
[`BoxTop`](https://docs.racket-lang.org/ts-reference/type-ref.html)
illustrates this distinction.

Start record parameters invariant. In particular, do not implicitly widen
`(<box> ExactInteger)` to `(<box> Any)`: the latter would permit storing a string
through an alias. Each allocation has one chosen static element type. Do not
generalize shared mutable storage into a value usable at unrelated element
types. Read-only variance can be considered separately after the mutation and
boundary rules support it.

Erase type parameters for the ordinary value representation and share generic
function bodies. An abstract `A` supplies no concrete runtime predicate and
justifies no category-specific check elimination. Generic record accessors
still need the field-read checks described above when writes are unverified;
their obligations depend on the chosen type arguments. Concrete instantiation
adapters or propagated checks at typed uses must discharge those obligations
before their results become optimizer facts. An opaque callable cannot acquire
a verified universal signature through `procedure?`. Initially support verified
generic code and concrete boundary instantiations whose guards can be generated;
diagnose unsupported boundaries involving abstract type variables. The precise
transport of these obligations must be settled before implementing generic
records or higher-order gradual crossings.

Typed collection signatures such as `map` can use the same mechanism once
element types and their mutation rules are supported. Keep that work separate
from the first milestone's shallow `Pair` and `Vector` categories.

## Types and propositions

Start with shallow value categories: false, true, null, exact integer, inexact
real, character, string, symbol, pair, vector, bytevector, procedure, and the
other runtime categories. Form finite unions of these types. Function signatures
add argument types, required/rest arity, and result types and counts.

`Any` is the static type containing every ordinary Scheme value. `Never` contains
no values. The proposed gradual type `?` represents missing static information;
it permits checked transitions to more precise types. It is not evidence that
a value belongs to one of those types. Internal uninitialized sentinels and
multiple-value packets are tracked separately from ordinary source values.

Begin with this proposition language:

```text
P ::= true | false
    | is(object, T) | not-is(object, T)
    | and(P, P) | or(P, P)
```

Here, `T` describes a known set of values, never `?`. An object identifies an
evaluated value or a stable binding, not arbitrary source text. Two evaluations
of the same expression do not necessarily identify the same value.

Intersection narrows a possible type; exclusion removes known alternatives.
For example, excluding `String` from `String ∪ Pair` leaves `Pair`. When the
domain cannot express a difference precisely, retain a conservative
approximation. Missing information must never exclude a possible value.

Keep proposition growth bounded. A join preserves facts common to every
reachable predecessor, with limited disjunction where useful. If a size budget
is exceeded, discard precision. No external solver is required for this domain.

An expression analysis produces:

```text
result types and value count
result object, when identifiable
propositions if the single result is truthy
propositions if the single result is false
outgoing initialization and mutation information
```

Only `#f` is false. Tests first require a single result. `Never` describes the
absence of a normal result; it does not prove termination or justify deleting
the computation that produces it.

## Resolving predicate meaning

Primitive specifications attach to the original core binding identities.
Renaming an import preserves a specification. Shadowing its name does not.
Assignment to a primitive binding prevents treating subsequent calls through
that binding as calls to the original primitive.

For the actual `pair?` procedure, the specification is:

```text
argument: Any
result: one Boolean
truthy: is(argument-0, Pair)
false:  not-is(argument-0, Pair)
mutation: none
```

At a call, substitute the evaluated argument's object for `argument-0`. Keep the
runtime predicate when its result is not already established. Its outcome
supplies information for subsequent analysis; the compiler does not execute an
arbitrary predicate while checking types.

The primitive catalogue records arity, preconditions, normal results, predicate
propositions, and mutation behavior. It is a trusted description of the runtime,
audited against its implementation. In particular, `integer?` accepts some
inexact values, while `exact-integer?` establishes an exact integer. A Wasm
structural type is also insufficient to distinguish strings from symbols: both
use the text wrapper, whose category tag must be modeled.

Function summaries travel through immutable aliases:

```scheme
(define p pair?)
(if (p x) (car x) #f)
```

An opaque function known only as `Any → Boolean` has no predicate propositions.
Neither its spelling nor a question mark at the end of its name grants any.

For user procedures, infer propositions from the body or verify explicitly
declared propositions. Prove the two outcomes independently. For example:

```scheme
(define (nonempty-string? x)
  (and (string? x)
       (> (string-length x) 0)))
```

The truthy outcome establishes `String`. The false outcome gives no additional
category information, since an empty string also returns false. This analysis
does not record the length inequality. Typed Racket likewise supports separate
positive and negative predicate propositions. See its
[predicate documentation](https://docs.racket-lang.org/ts-guide/occurrence-typing.html).

A declared summary becomes usable only after checking its body. Initially infer
summaries for nonrecursive procedures and leave recursive predicate summaries
unknown. Extending this to recursive groups requires an explicitly checked
inductive rule or sound fixed-point algorithm; a declaration cannot certify
itself merely because its recursive calls repeat that declaration.

Export propositions about stable formal argument values. Do not export a fact
about a reassigned parameter or mutable captured storage as though it described
the caller's original argument.

## Branches and aliases

Analyze a conditional's test first. Apply its truthy propositions to the
consequent and its false propositions to the alternate. Join the resulting
states. The chosen branch can use every fact still valid at that point.

```scheme
(if (pair? x)
    (car x)
    #f)
```

In the consequent, `x` is a pair. This says nothing about the types of its fields
or whether its cdr forms a finite proper list.

Preserve both value aliases and saved predicate results:

```scheme
(let ((ok (pair? x)))
  (if ok (car x) #f))
```

When `x` and `ok` are stable, the relation between `ok` and `x` survives the
binding. Merely recording `ok : Boolean` would lose that relation.

This matters for existing expansion: `and` becomes conditionals, while `or` and
some `cond` clauses introduce `let`, which expands into lambda applications.
Analyze immediate lambda applications with their actual argument facts,
including predicate-result relations. Use the same substitution rules as other
known calls, without adding source-level special cases for those macros.

Preserve the emitter's evaluation order: operands are evaluated in order before
the operator. Facts established while evaluating an earlier operand may be
invalidated by a later operand before the call. Preserve evaluation even when
its returned value or a later check is unnecessary.

## Mutation and unknown calls

The initial policy excludes occurrence narrowing for any binding assigned with
`set!`, including assignment from a nested closure. The backend already collects
these identities. Declared types remain enforceable on writes, but a transient
predicate result cannot establish a stronger invariant for such a binding.

Do not initially track facts about repeated reads of mutable fields. A pair
remaining a pair does not imply its car still has the same type. An immutable
local snapshot is different:

```scheme
(let ((value (car p)))
  (if (string? value)
      (string-length value)
      #f))
```

Mutation of `p` cannot replace the value already bound to `value`. Its string
category remains valid. This does not establish anything about a later `(car p)`.

Calls into unknown Scheme procedures or Rust may mutate reachable state and
invoke callbacks. Preserve stable value-category facts, and invalidate facts
whose storage dependencies may change. The first implementation can treat all
unknown calls as potentially writing every reachable mutable location. More
precise write sets are an improvement within the same contract, not a prerequisite
for occurrence typing.

Track definite initialization separately. A name's inferred function or value
type does not establish that its initializer has executed, especially for early
calls through recursively captured bindings.

Infer caller-dependent facts only for procedures whose complete call set is
known. A procedure exposed to an unknown caller, including an escaped Rust
callback, receives unknown arguments unless entry checks establish more.
Using an argument in arithmetic creates a check obligation, not proof that every
caller supplies a number.

## Optional annotations and gradual checking

Inference and optimization remain available without source annotations.
Existing unannotated programs retain their dynamic behavior, including failure
behavior. A statically evident failure in such a program is not automatically
converted into a compile-time rejection.

For opt-in checking, propose a type library with declarations and expression
annotations. These spellings are illustrative and are not current Scheme forms:

```scheme
(: string-size-or-false (-> Any (U ExactInteger False)))
(define (string-size-or-false x)
  (if (string? x) (string-length x) #f))
```

User predicate declarations additionally carry distinct truthy and false
propositions; use the internal notation above until surface syntax is settled.

Declarations attach to resolved identities and make their definitions subject
to checking. Expression annotations request a static check; a distinct checked
cast permits a dynamic test. Within checked code, `Any` requires narrowing or
an explicit cast before a narrower operation, whereas `?` permits an inserted
runtime check. Statically incompatible values are errors in checked code.

A declaration is not an optimizer assumption. Arguments from unknown callers
are checked at entry, assignments preserve declared types, and results from
unknown calls are checked where a narrower type is required. Eliminate these
checks only when their obligations are already established.

Propose shallow enforcement at higher-order boundaries: validate a callable's
shape, then check arguments and results at typed interactions. A one-time
`procedure?` check cannot verify a function's signature or its predicate
propositions. Only verified predicate implementations carry trusted narrowing
summaries; an opaque imported predicate cannot acquire one through a cast.

Initially, `Pair` and `Vector` describe outer categories, with unrestricted
contents. Element types, recursive structural types, polymorphic inference, and
deep mutable-container contracts need subsequent designs. This restriction
keeps the first gradual boundary implementable without changing object identity
or storage. Declared record fields use the guarded accessors described above;
their annotations do not imply a deep contract over arbitrary mutation.
Typed Racket's
[shallow semantics](https://docs.racket-lang.org/ts-reference/behavior-of-types.html)
provide a reference for checking values at typed uses rather than promising that
all future interactions satisfy a deep contract.

## Evidence for check elimination

Every removable check has a precondition. At its original program point,
record whether the available facts establish that precondition and why. Unknown
facts retain the existing checked operation. Checking a precondition at runtime
establishes its fact only on the continuation after successful checking.

| Check | Required evidence | Initial lowering opportunity |
| --- | --- | --- |
| `$defined` | This read follows definite initialization | Omit the helper at that read |
| `$single` | Exactly one ordinary result, without a packet requiring unpacking | Omit packet checking |
| Predicate result | The argument's category determines the outcome | Replace the test result while preserving required evaluation |
| Primitive type guard | Every argument meets the operation's category requirement | Omit that guard or select a helper with the proven precondition |
| Closure or arity check | Known callable and compatible arguments | Reuse or extend direct calls; preserve generic entry checks |

Knowing a user predicate's result on normal return does not justify deleting
its call: it may perform effects, fail, or diverge. Fold the subsequent branch
selection while preserving the call. Removing the call itself requires an
independent guarantee, initially limited to suitable built-in predicates and
established argument preconditions.

Exact-integer membership alone proves neither signed-64-bit overflow safety nor
which of the immediate and boxed integer representations is present. Preserve
overflow, divisor, and index-range checks unless independent existing constant
reasoning proves them unnecessary. Arithmetic refinement analysis is not part of
this work. A `procedure?` result likewise proves no particular arity.

Wasm validation still applies. The current `car` uses a `ref.cast` before
`struct.get`; a Scheme fact does not make an `eqref` statically acceptable to
`struct.get`. Retain a narrower Wasm reference where the emitted control flow
can establish it, or expose the relationship to Binaryen and the engine.
Narrowing a reference does not change object layout. Otherwise retain the cast.
Array access retains Wasm's bounds-trapping semantics. See the
[WasmGC operations](https://github.com/WebAssembly/gc/blob/main/proposals/gc/Overview.md).

Keep generic runtime and AWI entries checked for callers without evidence.
Any internal helper accepting proven inputs must state those preconditions next
to its implementation. Preserve GC roots, tail calls, initialization order,
argument evaluation, and the existing failure path for every retained check.

Provide an analysis report with source location, check kind, removed/retained
decision, and reason. Distinguish compiler decisions from subsequent Binaryen
or engine optimization. Typed Racket demonstrates the use of occurrence facts
to remove redundant pair checks; our Wasm lowering still has to realize each
opportunity. See its
[optimization guide](https://docs.racket-lang.org/ts-guide/optimization.html).

## Implementation sequence

1. **Basic types and annotation checking.** Add a cohesive `types.sld` for types
   and primitive specifications, and `type-analysis.sld` for checking, inference,
   and analysis results. Both are proposed modules. Add the `(snail typing)`
   facade, preserve `:` and `ann` metadata through expansion, and implement
   the fixed-arity examples above. Handle literals, local inference, declared
   recursion, assignment, and value counts without branch narrowing. Keep the
   existing runtime checks and add scalar entry guards for dynamic callers;
   basic checking must not introduce unchecked entries. Diagnose unsupported
   higher-order boundaries until their checks are implemented.
2. **Gradual boundaries.** Implement checked scalar transitions and shallow
   function boundaries, distinguishing `Any` from `?`. Freeze cast syntax with
   examples before extending the frontend. Add nominal record schemas and
   derive generated procedure signatures, enforcing precise field types at
   constructors, setters, and reads where needed. Keep unannotated code dynamic.
3. **Occurrence analysis.** Extend types with propositions and predicate
   summaries. Add branch narrowing, aliases, saved predicate
   relations, immediate lambda applications, and nonrecursive user summaries.
   Reuse assignment identities and apply the conservative mutation policy.
   Ordinary recursive result analysis must widen to a bounded domain and leave
   unsupported summaries unknown. Add verified predicate declarations to the
   annotation language.
4. **Use evidence during emission.** Wire per-use decisions into `wasm.sld`.
   First remove justified `$single` and `$defined` calls, then implement a
   focused category-check elimination example. Keep an analysis-disabled mode
   for comparison. Add runtime helper variants only where an actual obligation
   can be discharged; do not duplicate the runtime speculatively.
5. **Measurements and documentation.** Record retained/removed checks, compile
   time, Wasm size, and runtime against the same optimized backend. Update
   `TOUR.md` when module responsibilities are implemented and keep this proposal
   distinct from the current behavior in `doc/backend.md`.

The explicit-polymorphism design above is a follow-on to this sequence. Begin
with declared generic functions and call-site instantiation, then parameterized
records after their field and boundary obligations have an enforcement design.

Keep the new modules educational, with named sections and colocated unit tests.
Apply the repository's pinned simplify workflow to the newly implemented
modules. This proposal does not authorize broad frontend or backend cleanup.

## Acceptance and validation

The basic typing milestone must accept the `increment` and anonymous-function
examples, reject incompatible operands and declared results, enforce declared
types on assignment, and check recursive bodies against predeclared signatures.
It must preserve dynamic failures in unannotated code and retain checks on
unverified calls. It must not use a predicate result to narrow a branch yet.

Record checking must distinguish equal-shaped declarations, respect constructor
argument order, reject missing initialization of precisely typed fields, and
retain field-result checks when low-level writes can bypass generated setters.
Accept the combined base and typing imports, mixed annotated and unannotated
fields, and renamed annotation bindings. Regression fixtures must cover empty
records, reordered and omitted constructor fields, changes in an unannotated
field's value category, `:` as an ordinary accessor name, renamed and
macro-generated record declarations, and reassignment of generated procedure
bindings. Read an omitted field without assuming a particular unspecified value.
Preserve existing unannotated record declarations and the local record-factory
generativity test. Run these fixtures as linked Wasm when implementing the
extension.

The occurrence-typing milestone must understand direct and aliased predicates,
preserve the relation in the saved-Boolean example, infer the one-sided
`nonempty-string?` summary, and remove at least one justified check in an
executed linked Wasm fixture. It must also retain checks after invalidating
operations and report the reason.

Use tests that distinguish safe and unsafe conclusions:

- Built-in identity survives import renaming; shadowing and reassignment lose
  the built-in specification. An opaque Boolean function provides no narrowing.
- Truthy and false branches refine independently. An empty string exercises
  the false outcome of `nonempty-string?`; a false declaration claiming that
  every false result excludes `String` is rejected.
- `and`, `or`, `cond`, immutable aliases, and saved predicate results work after
  expansion. Two calls with the same printed expression are not assumed equal.
- Assignment through closures and mutation through aliases preserve required
  checks. An immutable snapshot retains its category across those operations.
- Unknown callbacks do not inherit facts from an incomplete set of known calls.
  Shared workers remain valid for every caller. Tests preserve
  operand-before-operator evaluation and effects of arguments and predicate
  bodies even when a predicate result is statically known.
- Early recursive reads, rest arity, zero/multiple values, numeric boundaries,
  integer-valued floats, and Rust callbacks preserve their existing behavior.
- Typed boundaries reject invalid dynamic inputs before using narrower facts;
  incorrect user predicate summaries never authorize unchecked operations.

Compare analysis-enabled and baseline compilation with identical inputs. Check
results, failure diagnostics, and observable effect order by executing the full
linked Wasm. Inspect emitted check decisions as well as optimized output; source
helper counts alone do not establish a performance gain.

Implementation checks are `make test`, `make check`, `cargo test --offline`,
`cargo fmt --all -- --check`, `scripts/test-backend`, and `scripts/test-build`.
Any change to the native executor also requires actual native execution.
Use the current workloads and timing boundaries in
[`benchmarks/README.md`](../benchmarks/README.md), including the existing
Binaryen optimization settings. Report compile time and runtime separately.
