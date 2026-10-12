# Typing rules

Draft companion to [the occurrence-typing proposal](occurrence-typing.md).
These are proposed declarative rules and obligations for elaborating runtime
checks. [The implementation](typing-prototype.md) supports a restricted kernel;
the complete rules below are a design target, and a soundness proof has not
been completed. The implementation uses shallow function domains, supports
rank-one `All` and `inst` with enforceable shallow boundaries, and does not
implement arrow subtyping or higher-order contracts. It uses `ann` for supported
explicit assertions from `Any`. It also adds a checked i32 range type and an
optional representation pass, outside this original kernel.

The first kernel has fixed-arity functions, one ordinary value on normal return,
finite unions, nominal records, assignment, and occurrence facts about stable
values. Rank-one polymorphism is a subsequent extension. Arithmetic refinements,
heap-path refinements, totality, and changes to value representation are outside
this kernel.

## Types and contexts

Use the following notation. A bar denotes a finite sequence.

```text
B ::= False | True | Null | ExactInteger | InexactReal | Character
    | String | Symbol | Pair | Vector | Bytevector | Procedure
    | Record | Unspecified | ...                 shallow runtime categories

T ::= Never | Any | B | α | family(R) | R[T̄] | (T̄ → T) | (U T̄)
G ::= Never | Any | B | α | family(R) | R[Ḡ] | (Ḡ → G) | (U Ḡ) | ?
S ::= G | All(ᾱ).(Ḡ → G)
```

T is a static monotype; G may contain unknown positions. S is a binding's type
or explicitly quantified function scheme. The first milestone omits α and
parameterized records. A nonparameterized record R has an empty argument list.
Boolean abbreviates (U False True). R is a resolved nominal identity, not a
record's name or field layout.

Membership propositions use a smaller language K: shallow categories, nominal
record identities, and finite unions of these. They cannot assert an arbitrary
function signature, a record's mutable field invariant, or membership in an
erased type parameter. The category for one record family is written family(R).
For a nonparameterized record, family(R) and R coincide.

```text
Δ   in-scope rigid type variables
Γ   binding identities, declared/storage types, and saved value information
Φ   facts true on the current path
Σ   primitive specifications, record schemas, and verified procedure summaries
M   bindings assigned anywhere in their scope, including nested closures

C = (Δ, Γ, Φ, Σ, M)
```

Γ describes a binding's contract; Φ describes an occurrence of its value.
A precise declared binding is usable only after its initializer or entry guard
has established the type. Every subsequent write must respect its storage type.
An unannotated mutable binding cannot acquire a permanent restriction merely
because its first value happened to be an integer.

## Judgments and evidence

The judgments produce result information r and located check obligations Ω:

```text
C ⊢ e ⇒ S ▹ r ⊣ Ω       synthesize a type or scheme
C ⊢ e ⇐ S ▹ r ⊣ Ω       check against an expected type or scheme

r = (o, P+, P−, κ)
```

Here o identifies the evaluated result, P+ holds if it returns a non-false
value, and P− holds if it returns #f. κ records independently established
procedure identity or verification evidence. An arrow annotation alone does
not supply κ. A saved Boolean can retain propositions about other objects.

Rules below suppress r and Ω where they do not change the displayed type
relationship. Their obligations remain mandatory. A checking judgment grants
the expected type at its checked continuation, after its guards succeed; it
does not turn an unexecuted guard into an earlier fact.

Premises express logical dependencies, not runtime evaluation order.
Elaboration must retain Snail's current order: evaluate operands in order,
then the operator, then perform the invocation. Call-boundary argument guards
run after those source evaluations. Guards belonging to explicit inner casts
or nested operations stay at their own sites. Reading a declared signature
early to supply an expected lambda type does not evaluate the operator early.

Each use requiring a single ordinary value has a separate value-count
obligation. Unknown producers retain the existing single-value handling;
only an exact count and the appropriate value representation discharge it.
Likewise, a variable read retains its initialization guard unless definite
initialization has been proved separately. The type rules never discharge
either obligation just by assigning a value type.

The first occurrence domain contains only facts that survive mutation of
reachable storage: value categories and record identities of stable values.
It contains no reusable facts about mutable field contents. Therefore the
displayed rules can share Φ across sibling premises. A future domain with
heap facts would require explicitly threading invalidation state through them.

## Static subtyping and unions

Static subtyping is the relation generated by reflexivity, transitivity, the
category hierarchy, and these rules:

```text
                         T ≤ Any          Never ≤ T


T ≤ Tj
------------------ Union-right
T ≤ (U T1 ... Tn)


T1 ≤ T    ...    Tn ≤ T
----------------------- Union-left
(U T1 ... Tn) ≤ T


B1 ≤ A1    ...    Bn ≤ An    A ≤ B
--------------------------------- Arrow
(A1 ... An → A) ≤ (B1 ... Bn → B)


R = Q       Ti = Ui for every i
-------------------------------- Record
R[T̄] ≤ Q[Ū]
```

Every arrow is below Procedure. Every record type is below its family category,
which is below Record. Different nominal families are disjoint. Initially,
record parameters are invariant; the Record rule does not compare field shapes.

Normalize unions by flattening, ignoring order, removing duplicates and Never,
and dropping a member already covered by another static member. The empty union
is Never. These are structural identities, not new nominal declarations.
Do not normalize the gradual unknown ? to Any.

Subtyping is a proof relationship. For example, (U String ExactInteger) is not
below String, even though some of its values are strings. A later occurrence
fact can narrow a particular value before applying subtyping.

## Ordinary bidirectional rules

The following rules describe the static kernel. Gradual checking extends the
transition from synthesis to checking in the next section.

```text
-------------------------------- Literal
C ⊢ c ⇒ literal-type(c)


Γ(x) = G       G' = narrow(G, Φ, object(x))
----------------------------------------- Variable
C ⊢ x ⇒ G'


C ⊢ e ⇒ T       T ≤ U
---------------------- Sub
C ⊢ e ⇐ U


C ⊢ e ⇐ G       Δ ⊢ G well-formed
-------------------------------- Annotation
C ⊢ (ann e G) ⇒ G


C, x1:G1, ..., xn:Gn ⊢ body ⇐ G
------------------------------------- Lambda
C ⊢ (lambda (x1 ... xn) body) ⇐ (G1 ... Gn → G)


C ⊢ f ⇒ (G1 ... Gn → G) ▹ (..., κf)
C ⊢ e1 ⇐ G1    ...    C ⊢ en ⇐ Gn
call-plan(κf, (G1 ... Gn → G)) is supported
--------------------------------------- Application
C ⊢ (f e1 ... en) ⇒ G


C ⊢ initializer ⇒ G ▹ r
C, x:(G,r) ⊢ body ⋆ H
--------------------------------------- Let
C ⊢ (let ((x initializer)) body) ⋆ H


storageΓ(x) = G       C ⊢ e ⇐ G
--------------------------------------- Assignment
C ⊢ (set! x e) ⇒ Unspecified
```

In Let, ⋆ is either ⇒ or ⇐; the body's mode is also the whole form's mode.
An explicitly annotated initializer is checked at its annotation. There is no
automatic generalization at let. Lambdas get their parameter types through
checking; the initial checked subset has no rule synthesizing an arbitrary
unannotated lambda's signature.

Lambda checks its body under fresh parameter objects. Its generic entry must
enforce the declared parameter interface before executing that body. Body
obligations belong to invocation, not closure creation. Captured occurrence
facts are retained only when they concern stable objects available to the
closure.

Application adds callable, arity, argument, result-count, and result-interface
obligations at their corresponding call sites. A verified implementation can
discharge obligations that its proof establishes. A function parameter or
foreign result with only an arrow interface retains the checks needed at
typed interactions. In particular, an unknown callee's result does not become
a proved String merely because its expected arrow returns String.

Calling a value of type ? uses a dynamically checked interface with unknown
argument and result types and a checked arity for this invocation. Any and
Procedure alone do not provide a particular arrow interface; in checked code,
a more precise interface requires narrowing that actually proves it or an
explicit supported cast. Unannotated Scheme calls retain their dynamic behavior.

For a recursive group, reserve all declared signatures before checking bodies:

```text
Γ' = Γ, f1:S1, ..., fn:Sn
(Δ, Γ', Φ, Σ, M) ⊢ lambda-i ⇐ Si       for every i
------------------------------------------------ Recursive group
accept the group's declared interfaces
```

This is the ordinary assumption used to check recursion, not a verified
predicate-summary assumption. Publish procedure verification evidence only
after checking the whole group. Keep initialization guards for reads that
might precede an initializer's execution.

The first implementation treats the return of set! as Snail's current
Unspecified value. This does not promise a particular portable R7RS value.

## Gradual checking and runtime obligations

Keep consistent subtyping, written ≲, separate from static subtyping. Define
it by interpreting unknown positions as possible static monotypes:

```text
γ(T) = {T}                              for a static T
γ(?) = all well-formed static monotypes in Δ
γ((Ḡ → G)) = pointwise static instantiations
γ(R[Ḡ])    = pointwise static instantiations
γ((U Ḡ))   = unions of pointwise static instantiations

G ≲ H  iff  some T ∈ γ(G) and U ∈ γ(H) satisfy T ≤ U
```

This definition is for monotypes. It is not a rule for casting an opaque value
to All. Rigid type variables stay rigid; ? does not permit solving a universally
quantified variable to a convenient concrete type.

```text
C ⊢ e ⇒ G       G ≲ H       plan(G,H) is supported
------------------------------------------------- Gradual-check
C ⊢ e ⇐ H ⊣ obligations(plan(G,H))
```

Include obligations already produced while checking e. A plan may contain no
runtime work when a static proof discharges the conversion. Otherwise it
must enforce the supported target interface. At minimum:

| Transition | Required plan |
| --- | --- |
| Static T ≤ U | Forget precision; no new type guard |
| G to ? | Forget static precision; no proof of a narrower category |
| ? to a scalar or category union K | Check membership in K |
| ? to a monomorphic record R | Check the record's runtime identity |
| Unknown callable to a supported arrow | Callable/arity handling and checks at typed calls; no predicate certificate |
| To an abstract α or universal scheme | Unsupported without a separate enforcement design |

A shallow arrow view is an interface for guarded interactions, not proof that
an arbitrary procedure satisfies an extensional function contract. It must
carry no fabricated verification or predicate evidence. Casting to a record
similarly establishes identity, not an invariant over its mutable fields.

Consistent subtyping is not transitive:

```text
ExactInteger ≲ ?       ? ≲ String       ExactInteger ≰ String
```

In particular, this cannot justify a check-free path from an integer to a
string. At a concrete use, static facts about the actual value remain relevant.

Any is deliberately different:

```text
? ≲ String       not (Any ≤ String)       not (Any ≲ String)
```

An Any value requires occurrence narrowing or an explicit checked cast.
For clarity, the explicit cast rule is:

```text
C ⊢ e ⇒ G       explicit-plan(G,H) is supported
------------------------------------------------ Explicit-cast
C ⊢ (cast e H) ⇒ H ⊣ obligations(explicit-plan(G,H))
```

The spelling cast remains provisional. This rule may introduce a check even
when consistent subtyping fails, such as from Any to String. It guarantees
the target interface only on successful return. Unsupported target contracts
are diagnosed instead of being accepted with an inadequate category check.

These rejection rules govern opted-in definitions and annotated expressions.
They do not turn every statically detectable error in unannotated Scheme into
a compile-time rejection. Dynamic code keeps its checks and failure behavior.

## Occurrence information

Objects identify evaluated values. A stable binding aliases the same object
at every read. Reading a binding in M produces a fresh snapshot object, with
no reusable alias to the mutable binding. Reading a field also produces a fresh
snapshot; two reads are not the same object. This allows a stable local copy
of a mutable field to narrow without narrowing the field itself.

```text
P ::= ⊤ | ⊥ | is(o,K) | not-is(o,K) | P ∧ P | P ∨ P
```

For any result object o, its truthy branch entails not-is(o,False) and its
false branch entails is(o,False). A literal #f has filters (⊥,⊤); an always
truthy literal has (⊤,⊥). Unknown results have no additional propositions.
Boolean-returning procedures are not automatically type predicates.

For a verified predicate value p with a summary about its argument:

```text
κ(p) verifies summary (Q+, Q−)
C ⊢ a ⇒ G ▹ (o, ...)
------------------------------------------------ Predicate
C ⊢ (p a) ⇒ Boolean ▹ (fresh, Q+[o/arg], Q−[o/arg], none)
```

The ordinary application and single-value obligations still apply. Resolve p
by value/binding identity, not identifier spelling. An immutable alias can
carry its certificate; a reassigned binding or arbitrary arrow cast cannot
manufacture one. A declared summary is not available while proving itself.

For the actual string? procedure:

```text
Q+ = is(arg, String)
Q− = not-is(arg, String)
```

The two propositions are independent. For a predicate that recognizes only
nonempty strings, the supported domain can prove a positive String fact and
no negative String fact.

A condition need not be Boolean. Both if rules only require one ordinary test
value, and use its truthy and false propositions:

```text
C ⊢ test ⇒ G0 ▹ (o0, P+, P−, ...)
C[Φ ∧ P+] ⊢ yes ⇐ G
C[Φ ∧ P−] ⊢ no  ⇐ G
---------------------------------------- If-check
C ⊢ (if test yes no) ⇐ G


C ⊢ test ⇒ G0 ▹ (o0, P+, P−, ...)
C[Φ ∧ P+] ⊢ yes ⇒ G1
C[Φ ∧ P−] ⊢ no  ⇒ G2
---------------------------------------- If-infer
C ⊢ (if test yes no) ⇒ join(G1,G2)
```

Join forms a normalized union; with gradual members it must conservatively
retain their uncertainty. In the basic non-occurrence milestone use ⊤ for
both branch refinements, preserving the same checking/inference structure.

If the branch result filters are (Y+,Y−) and (N+,N−), the if expression carries:

```text
result+ = (P+ ∧ Y+) ∨ (P− ∧ N+)
result− = (P+ ∧ Y−) ∨ (P− ∧ N−)
```

Retain a shared result object only if both branches establish that alias;
otherwise use a fresh result object. Existentially forget inaccessible local
objects when exporting a result or procedure summary, approximating with ⊤
when the domain cannot represent the projected proposition.

A stable let binding saves its initializer's object and both filters.
Consequently the Variable rule for ok in the following program recovers
the propositions about x:

```scheme
(let ((ok (string? x)))
  (if ok (string-length x) 0))
```

This also applies to immediate lambda applications introduced by macro
expansion. For an escaping/shared lambda, use only information justified at
every entry; a fact from one caller does not specialize its body.

## Narrowing and summary verification

For static T, narrow must overapproximate the values satisfying the path facts.
Conceptually its two elementary operations are intersection and subtraction:

```text
narrow(T, is(o,K), o)     ≈ T ∩ K
narrow(T, not-is(o,K), o) ≈ T ∖ K

narrow((U String R), is(o,String), o)     = String
narrow((U String R), not-is(o,String), o) = R
```

The approximation must contain every possible surviving value. Conjunction
can accumulate restrictions; disjunction joins alternatives. If a subtraction
or intersection is not representable, preserve a conservative type and keep
the proposition separately. Do not conclude Never merely because a type
operation is inconvenient.

A positive membership fact can narrow ? to the proved category. A negative
fact that cannot be represented leaves ? and records the exclusion separately.
For a rigid α, retain both the original α constraint and the new membership
fact; forgetting α would lose valid input/output relationships in generic code.
Represent that information internally as a restricted type view, written T ∩ K
or T ∖ K. These extend the internal static domain, not the surface type grammar,
and have the following safe projections:

```text
(T ∩ K) ≤ T       (T ∩ K) ≤ K       (T ∖ K) ≤ T
```

For example, α ∩ String can satisfy either an expected α or an expected String.
It does not allow an arbitrary newly constructed string to satisfy α. The
implementation can store the original type and membership propositions instead
of allocating an intersection-type node. Gradual concretization extends to
these views pointwise; the membership restriction must itself come from a
proved path fact. These restrictions need no new surface refinement syntax.

If Φ is provably contradictory, the path has no normal value and can synthesize
Never. This does not delete evaluation of the test that led to it. Name
resolution and syntax checking still happen for unreachable source.

Suppose a checked predicate body has result filters B+ and B− and a proposed
summary has filters Q+ and Q− over stable formal argument objects. Require:

```text
Φentry ∧ B+ ⊨ Q+       Φentry ∧ B− ⊨ Q−
---------------------------------------- Verify-summary
publish (Q+, Q−) for this verified implementation
```

Inference chooses supported consequences of B+ and B− projected onto the
arguments. It need not find the strongest possible summary. Initially infer
only nonrecursive summaries and bound proposition size. Fall back to ⊤ when
precision is exhausted. An opaque predicate has (⊤,⊤).

## Records and mutation

A schema in Σ records a fresh nominal identity R, fields fi:Gi, constructor
argument order, and the resolved generated bindings. For constructor fields
i1 ... ik it supplies interfaces:

```text
constructor : (Gi1 ... Gik → R)
predicate   : (Any → Boolean)
accessor-i  : (R → Gi)
setter-i    : (R Gi → Unspecified)       when declared

predicate filters:
    is(arg, family(R))
    not-is(arg, family(R))
```

These interfaces become usable through generated code that enforces them.
Constructor and setter value arguments follow the checking rules. A record
access is represented conceptually by:

```text
check record identity R
read field fi once into fresh object o
establish Gi for that value, retaining a field-result guard where needed
```

Knowing R does not prove Gi. The identity check and the field-result check
are different obligations. The low-level record setter can bypass a generated
setter, so removing a field-result guard requires proof that every relevant
construction and write preserves the field invariant. This applies even when
the declaration exposes no setter.

The initial schema rule covers library/script-level records with stable
descriptor bindings. Ordinary local generative declarations remain dynamic;
each execution must retain its distinct runtime identity. Unsupported typed
local schemas are diagnosed as an extension limitation. Standard field forms,
constructor omissions, and arbitrary unannotated field values keep their
existing semantics. Only explicitly precise fields have the proposed initial
requirement to appear in the constructor.

For ordinary assignment, compare a write against storageΓ(x), never the
narrowed type of one read. Exclude bindings in M from reusable occurrence
narrowing. Unknown Scheme/Rust calls can mutate reachable fields and call back
into Scheme; the first kernel has no persistent field facts for them to retain.
Stable category and nominal-identity facts survive those calls.

## Rank-one polymorphism

These rules specify the static polymorphism layer. The implemented subset uses
shallow domains, results, and instantiation arguments. Concrete checks at typed
calls establish the substituted domains; abstract obligations require static
proof. `inst` preserves procedure identity, and opaque calls use the generic
entry's erased interface. See [the boundary rules](typing-prototype.md#rank-one-polymorphism).
These rules do not authorize unimplemented gradual enforcement at abstract type
variables or parameterized records.

```text
Γ(f) = All(ᾱ).F
--------------------------------- Scheme-variable
C ⊢ f ⇒ All(ᾱ).F


ᾱ fresh and rigid       Δ,ᾱ; Γ; Φ; Σ; M ⊢ lambda ⇐ F
---------------------------------------------------- All-introduction
Δ; Γ; Φ; Σ; M ⊢ lambda ⇐ All(ᾱ).F


C ⊢ e ⇒ All(ᾱ).F       Δ ⊢ T̄ well-formed monotypes
--------------------------------------------------- Instantiation
C ⊢ (inst e T̄) ⇒ F[T̄/ᾱ]
```

Substitution avoids capture. Fresh rigid variables cannot escape into types
of pre-existing mutable bindings. The initial introduction rule is for checked
function values, not an allocation of shared mutable storage.

For implicit instantiation at a call, create fresh inference variables for
the quantified parameters. Constrain actual argument types against the
instantiated parameter types and, in checking mode, constrain the result
against its expected type. Solve within the variables' scopes. A solution
cannot replace a rigid variable or silently turn an unresolved obligation
into Any or ?. Require explicit inst when the supported solver cannot find
a solution. Bidirectionality does not claim complete polymorphic inference.

Inside a recursive generic definition, recursive references initially use
the same rigid parameters as the body. The callable interface outside the
definition remains universal. Higher-rank arguments, polymorphic recursion,
and general let-polymorphism are outside this rule set.

For a parameterized record, instantiate its schema by substituting type
arguments into the generated signatures. The nominal head is unchanged.
The Record subtyping rule remains invariant. A family predicate can eliminate
other nominal families or scalar alternatives; it cannot distinguish two
instantiations of the same family.

The runtime erases type arguments. A generic field read at type α therefore
cannot emit a concrete α membership test. Before enabling such gradual
crossings, require an explicit implementation plan for concrete-instantiation
adapters or propagated checks at typed uses. Until that plan exists, those
boundaries are unsupported. In particular, family(R) is not evidence for
R[Any] when mutable parameters are invariant.

## Check elimination

Typing produces obligations; a separate proof at the check's program point
decides whether an obligation needs runtime work:

```text
facts-at(p) ⊨ precondition(check)
the evidence is valid at p
-------------------------------- Elide-check
omit that check at p
```

Only facts established before p may discharge it. Unknown types, consistent
subtyping, declared signatures without enforcement, and future guards are
not such facts. A successful guard can establish facts on its normal successor.

Category membership does not prove arity, initialization, result count,
integer representation, arithmetic range, or bounds. Record membership does
not prove field contents. Each needs its own obligation and evidence. Shared
workers require facts valid at every entry, including generic adapters.

Eliding a check preserves evaluation of its operands. Knowing the outcome
of an effectful predicate preserves the predicate call even if the subsequent
branch can be selected statically. The Wasm emitter must still meet Wasm's
reference typing requirements and preserve ABI roots and lifetime rules.

## Worked derivation

Consider this checked definition:

```scheme
(: measure (-> (U String <point>) ExactInteger))
(define (measure x)
  (if (string? x)
      (string-length x)
      (point-x x)))
```

The function signature supplies x:(U String R). Its entry checks establish
that interface for unknown callers. The trusted string? summary gives:

```text
then: Φ ∧ is(x,String)       narrow((U String R), ...) = String
else: Φ ∧ not-is(x,String)   narrow((U String R), ...) = R
```

In the then branch, String ≤ String discharges string-length's argument
obligation. In the else branch, R ≤ R discharges point-x's receiver obligation.
Both calls produce ExactInteger on normal return, so If-check establishes the
declared result.

The record field's value check can remain: proving the receiver's identity
did not establish a field invariant. Likewise, the generated accessor's shared
entry cannot assume that every other caller already checked its receiver.

These distinguishing cases belong in the eventual implementation tests:

| Case in checked code | Required outcome |
| --- | --- |
| Lambda checked against ExactInteger → ExactInteger | Parameter type flows inward |
| String operation on String ∪ ExactInteger without narrowing | Reject |
| String operation on ? | Insert the supported membership guard |
| String operation on Any without narrowing/cast | Reject |
| Saved predicate Boolean over a stable x | Recover its branch facts |
| Reassigned x tested and later reread | Do not reuse the earlier read's narrowing |
| Equal-shaped distinct record declarations | Preserve nominal distinction |
| Typed field reached through unchecked mutation | Retain field-result enforcement |
| identity used at integer and string types | Independent polymorphic instantiations |
| Mutable box widened from integer to Any | Reject implicit widening |
| Same-family generic union tested with its family predicate | Retain both type arguments |
| An annotated opaque predicate | No verified narrowing summary |

## Proof obligations and references

The intended safety claim is about checked uses: assuming correct primitive
specifications and guard elaboration, an operation either receives values
meeting its required runtime preconditions or takes its explicit failure path.
For shallow higher-order interfaces, this is not a promise that arbitrary
untyped interactions satisfy a deep function or mutable-container contract.

A proof still needs an operational semantics for the supported core, preservation
for the elaborated terms, the soundness of predicate summaries and narrowing,
and simulation of each check-elimination step. Error/effect order, result counts,
initialization, and the Wasm representation must be included in that simulation.
The scalar rules are a concrete starting point; polymorphic gradual boundaries
and the full Scheme runtime are not covered by a completed theorem.

The synthesis/checking split and rigid-variable discipline use
[Dunfield and Krishnaswami's bidirectional account](https://arxiv.org/abs/1306.6032)
as a reference, while keeping Snail's first polymorphic layer rank one.
The separation between unknown types and justified conversions follows the
concretization approach in
[Garcia, Clark, and Tanter's Abstracting Gradual Typing](https://www.cs.ubc.ca/~rxg/agt.pdf);
this document does not claim their metatheory for Snail's shallow semantics.
Predicate filters and conservative mutation handling are informed by
[Typed Racket's occurrence-typing guide](https://docs.racket-lang.org/ts-guide/occurrence-typing.html)
and [Tobin-Hochstadt and Felleisen's formal account](https://arxiv.org/abs/1106.2575).
