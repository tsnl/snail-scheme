# Types

A type describes which values and operations fit together. The compiler infers
expression types and unannotated bindings, and checks the signatures you supply
on `def` or `let`. Passing a string to a function that requires an integer is an
error before execution.

A *type variable* stands for a type chosen at a use of a generic definition. A
*type constructor*, such as `List`, takes element types to describe a compound
type. Resolution distinguishes type variables and nominal type names from
ordinary value names. A nominal application must have its declared arity.

<!-- ANCHOR: types -->
```text
type ::= primitive_type
       | type_variable
       | nominal_type
       | nominal_application
       | reference_type
       | list_type
       | vector_type
       | function_type

primitive_type ::= "I32" | "I64"
                 | "F32" | "F64"
                 | "Bool" | "Char" | "Unit"
                 | "String" | "Bytevector"
                 | "Never" | "Any"

type_variable ::= name

nominal_type ::= name

nominal_application ::= "(" nominal_type type type … ")"

reference_type ::= "(" "Ref" type ")"

list_type ::= "(" "List" type ")"

vector_type ::= "(" "Vector" type ")"

function_type ::= "(" "->" type … type ")"
                | "(" "->" type … "(" "Rest" type ")" type ")"
```
<!-- ANCHOR_END: types -->

## Reading the typing rules

A rule puts its premises above a horizontal line and its conclusion below.
The name at the right of the line identifies the rule. A line with no premises
states an axiom: the conclusion holds directly.

`Γ` is the environment mapping available bindings to their signatures. `e` is
an expression and `T` a type. Following the bidirectional convention, `::↑`
means *synthesize*: determine a type from the expression. `::↓` means *check*:
verify the expression against a type already supplied by its context.

```text
Γ ⊢ e ::↑ T |> P    infer type T for e, collecting requirements P
Γ ⊢ e ::↓ T |> P    check e against T, collecting requirements P
```

`|>` separates the type judgment from its collected class requirements. It is
notation in the specification, not an SFIR operator or a stage boundary.
`P = ∅` means no requirements; `P₁ ∪ P₂` combines requirements from two
subexpressions. For example, using `to-hex-string` at an abstract type T can
collect `{(ToHexString T)}`. A generic signature can carry that requirement;
a concrete use must supply the corresponding instance.

Subscripts distinguish related expressions or types. A bar over a variable,
as in `ᾱ`, denotes a sequence. Repeated sequences in a rule have matching
lengths. Unification solves inference variables, while an explicitly quantified
variable is rigid when its definition is checked.

## Primitive types

| Type | Values |
| --- | --- |
| I32, I64 | Signed integers of the indicated width |
| F32, F64 | IEEE floating-point numbers of the indicated width |
| Bool | `#t` and `#f` |
| Char | Unicode scalar values, such as `#\a` |
| Unit | One value, constructed by `(unit)` |
| String | Text |
| Bytevector | A sequence of bytes |

An unannotated integer literal such as `42` has type I32. An unannotated floating
literal such as `1.5` has type F64. To select another width, annotate the literal:
`(ann 42 I64)` or `(ann 1.5 F32)`. A direct binding annotation also counts:
`(def scale F32 1.5)` selects F32 for that initializer. Function argument types
and overload candidates do not silently change a literal's default width.

<!-- ANCHOR: literals -->
```text
integer ∈ range(I32)
────────────────────────────────── TYPE-I32-INFER
Γ ⊢ integer ::↑ I32 |> ∅

float fits F64 after rounding
────────────────────────────────── TYPE-F64-INFER
Γ ⊢ float ::↑ F64 |> ∅

W ∈ {I32, I64}     integer ∈ range(W)
──────────────────────────────────────────── TYPE-INT-LITERAL-ANN
Γ ⊢ (ann integer W) ::↑ W |> ∅

W ∈ {F32, F64}     float fits W after rounding
──────────────────────────────────────────── TYPE-FLOAT-LITERAL-ANN
Γ ⊢ (ann float W) ::↑ W |> ∅

────────────────────────────────── TYPE-BOOL-INFER
Γ ⊢ boolean ::↑ Bool |> ∅

────────────────────────────────── TYPE-CHAR-INFER
Γ ⊢ character ::↑ Char |> ∅

────────────────────────────────── TYPE-STRING-INFER
Γ ⊢ string ::↑ String |> ∅

────────────────────────────────── TYPE-BYTEVECTOR-INFER
Γ ⊢ bytevector ::↑ Bytevector |> ∅
```
<!-- ANCHOR_END: literals -->

The literal annotation rules choose a representation before the unannotated
literal is synthesized. Thus `(ann 2147483648 I64)` is valid even though
`2147483648` alone is outside I32's range. A direct numeric literal initializer
with a binding annotation uses the same rule. Other annotated initializers are
checked normally. `Unit` is constructed by the ordinary `(unit)` operation with
signature `(-> Unit)`.

An out-of-range literal is a compile-time error. Arithmetic and conversions must
report representation overflow instead of silently wrapping or silently
widening the type. Floating-point rounding within range is expected; an overflow
of the finite range is an error. Integer division by zero and signed minimum
divided by minus one are errors as well. Some runtime overflow checks may be
absent in the compiler MVP; that implementation gap does not change the intended
contract. Programs must not rely on wraparound while those checks are incomplete.

An annotation on a computed numeric value is not a conversion. For example,
`(ann (+ 1 2) I64)` is a type error because the sum has type I32; an explicit
conversion operation is required. Similarly, a function expecting F32 requires
an explicitly F32 argument rather than accepting an unannotated F64 literal.

## Function types and polymorphism

`(-> I32 I32)` describes a function taking one I32 and returning an I32.
`(-> I32 I32 Bool)` takes two integers and returns a Boolean. `(-> Unit)` takes
no arguments. A signature on a binding checks its initializer:

```scheme
(def increment (-> I32 I32) (lambda (x) (+ x 1)))
(increment 41) ; I32, result 42
```

The compiler checks a lambda's body with its parameters in scope. At a call it
checks the arguments against the function's parameter types. Here `Tᵢ` and `R`
are types, `xᵢ` are parameter names, `eᵢ` are argument expressions, and `Pᵢ` are
sets of class requirements.

<!-- ANCHOR: calls -->
```text
Γ, x₁:T₁, …, xₙ:Tₙ ⊢ body ::↓ R |> P
────────────────────────────────────────────────────── TYPE-LAMBDA-CHECK
Γ ⊢ (lambda (x₁ … xₙ) body) ::↓ (-> T₁ … Tₙ R) |> P

T₁, …, Tₙ fresh     Γ, x₁:T₁, …, xₙ:Tₙ ⊢ body ::↑ R |> P
────────────────────────────────────────────────────── TYPE-LAMBDA-INFER
Γ ⊢ (lambda (x₁ … xₙ) body) ::↑ (-> T₁ … Tₙ R) |> P

Γ ⊢ f ::↑ (-> T₁ … Tₙ R) |> P₀     Γ ⊢ eᵢ ::↓ Tᵢ |> Pᵢ  (1 ≤ i ≤ n)
───────────────────────────────────────────────────────────────── TYPE-CALL-INFER
Γ ⊢ (f e₁ … eₙ) ::↑ R |> P₀ ∪ ⋃ᵢ Pᵢ
```
<!-- ANCHOR_END: calls -->

When a lambda has no expected type, give each parameter a fresh inference
variable and infer its body. Solving constraints determines those types.
A rest signature, `(-> I32 (Rest String) Unit)`, checks the first argument as
I32 and each remaining argument as String. The rest parameter is bound to an
immutable `(List String)` containing those remaining arguments.

A generic binding can be used at several types. `All` binds type parameters:

```scheme
(def identity (All (T) (-> T T)) (lambda (value) value))
(identity 42)                        ; I32
(identity "hello")                   ; String
((inst identity I64) (ann 42 I64))    ; explicitly choose I64
```

The implementation checks the definition once, then specializes its uses into
concrete code. There is no generic runtime representation of `All`. Polymorphism
is rank one: `All` occurs at the outside of a binding signature, not inside
parameters, results or stored element types. Each resulting closure has a
concrete function type.

<!-- ANCHOR: schemes -->
```text
signature ::= type
            | "(" "All" "(" name … ")" type ")"
            | "(" "All" "(" name … ")" qualified_type ")"

qualified_type ::= "(" "=>" "(" obligation … ")" type ")"

obligation ::= "(" name type … ")"
```
<!-- ANCHOR_END: schemes -->

Internally, write a signature as `∀ᾱ. P ⇒ T`: quantified variables, requirements,
and the resulting type. Each use replaces quantified variables with fresh
inference variables. Explicit `inst` replaces them with the supplied types.
Type variables from an attached `All` are rigid while checking that definition:
its body must work for every allowed type, not just its current callers. These
parameters also scope over type annotations inside the initializer, so a nested
`def` can refer to its enclosing definition's type parameters.

<!-- ANCHOR: instances -->
```text
Γ(x) = ∀ᾱ. P ⇒ T       β̄ fresh
────────────────────────────────────────────── TYPE-NAME-INFER
Γ ⊢ x ::↑ T[ᾱ := β̄] |> P[ᾱ := β̄]

Γ(x) = ∀ᾱ. P ⇒ T       |ᾱ| = |Ū| ≥ 1
────────────────────────────────────────────── TYPE-INST-INFER
Γ ⊢ (inst x U₁ … Uₙ) ::↑ T[ᾱ := Ū] |> P[ᾱ := Ū]
```
<!-- ANCHOR_END: instances -->

An unannotated `def` or `let` can infer an `All`. Inference generalizes variables
not fixed by the surrounding environment, subject to the *value restriction*:
only literals, names, lambdas, explicit instantiations and static annotations of
these forms can generalize. Applications and allocations stay monomorphic. This
prevents one mutable cell from being used at incompatible element types. An
explicit `All` cannot override this restriction.

For typing, resolve each binding's lexical scope, then form dependency groups
from references in its initializer, including references in lambda bodies.
Annotated definitions are checked against their signatures; unannotated ones
get provisional monotypes. Recursive uses within a group are monomorphic, so
type-changing polymorphic recursion is not supported. Solve groups in dependency
order and generalize eligible bindings afterward. This is a checking order,
not a change to initializer execution order. Every body is checked, even if no
caller uses it.

## Kinds and static definitions

`def` also names a type, a typeclass or an instance. The body uses a former,
just as a function definition uses `lambda`:

```scheme
(def Flag (datatype () (off) (on)))
(def Display (typeclass (T) (: display-text (-> T String))))
(def flag-display
  (instance (Display Flag)
    (display-text (lambda (flag) (match flag ((off) "off") ((on) "on"))))))
```

A *kind* classifies these static definitions. `Flag` has kind `Type`: it is a
type of ordinary values. `Display` has kind `(Kind-> Type Constraint)`: applying
it to a type forms a class requirement. `flag-display` has kind
`(Evidence (Display Flag))`: it supplies an implementation of that requirement.
A generic datatype such as Vec3 has kind `(Kind-> Type Type)`.

These kinds are inferred from the formers. An optional annotation on a static
`def` states its kind, for example `(def Flag Type (datatype () (off) (on)))`.
Ordinary value definitions have types rather than kinds. `Type`, `Constraint`
and `Evidence` are not runtime value types and cannot be stored in Any.

<!-- ANCHOR: kinds -->
```text
kind ::= "Type"
       | "Constraint"
       | "(" "Kind->" kind kind … ")"
       | "(" "Evidence" obligation ")"

static_definition ::= "(" "def" name [kind] static_former ")"

static_former ::= datatype
                | typeclass
                | instance
```
<!-- ANCHOR_END: kinds -->

For the MVP, these three formers appear only as the outermost body of a
library-level `def`. Their parameters have kind Type, instance heads are
concrete, and they cannot be returned from functions or selected by a runtime
`if`. This is a simple kind discipline, not yet dependent typing. A later
language can make more computations available in types without reserving
separate definition keywords now.

Kind checking verifies that fields and method parameters are types, class
applications form requirements, and instances implement the requirement named
in their head. With `Δ` mapping static names to kinds, representative rules are:

<!-- ANCHOR: kind-rules -->
```text
Δ(F) = (Kind-> Type … Type)     Δ ⊢ Tᵢ : Type  (1 ≤ i ≤ n)
──────────────────────────────────────────────────────── KIND-TYPE-APPLY
Δ ⊢ (F T₁ … Tₙ) : Type

Δ(C) = (Kind-> Type … Constraint)     Δ ⊢ Tᵢ : Type  (1 ≤ i ≤ n)
────────────────────────────────────────────────────────────── KIND-CLASS-APPLY
Δ ⊢ (C T₁ … Tₙ) : Constraint
```
<!-- ANCHOR_END: kind-rules -->

The number of arguments matches the constructor's or class's declared arity.
Checking an instance's method implementations establishes its Evidence kind;
a kind annotation alone cannot assert that an implementation is correct.

## Struct and union types

A struct groups named fields into one value. A closed union selects one of a
fixed set of cases. `datatype` describes both using constructors: one constructor
for a struct, several for a union. Fields are immutable; a field of type
`(Ref T)` can hold an explicitly mutable cell.

<!-- ANCHOR: data -->
```text
datatype ::= "(" "datatype" "(" name … ")" constructor_clause constructor_clause … ")"

constructor_clause ::= "(" name field_clause … ")"

field_clause ::= "(" name type [name] ")"
```
<!-- ANCHOR_END: data -->

The names in the parameter list bind type variables over the field types.
A constructor clause names a constructor; a field clause gives a field name,
its type and an optional accessor name.

```scheme
(def Tree
  (datatype (T)
    (leaf (value T))
    (branch (left (Tree T)) (right (Tree T)))))

(def leftmost (All (T) (-> (Tree T) T))
  (lambda (tree)
    (match tree
      ((leaf value) value)
      ((branch left right) (leftmost left)))))
```

Constructor arguments follow field order. `match` evaluates the subject once
and selects its constructor's arm, binding one name per field. Each constructor
must appear exactly once; patterns are shallow, with no guards or wildcard
arms. Arm results must have compatible types, just as for `if`.

## Type definitions and identity

Every `def` with a `datatype` body creates a distinct nominal type identity.
Two definitions with the same fields still describe different types. Recursive
and mutually recursive datatype definitions may refer to one another.
Constructors and optional accessors are ordinary function values with signatures
determined by the fields. An accessor for a field present in only one union case
checks the case and traps on a different one.

The [color example](index.md#a-first-look) therefore uses `(primary (red))` to
construct a Color from a PrimaryColor. PrimaryColor is not a subtype of Color;
the explicit constructor records that choice. Datatype parameters describe
stored field types. Constraints on arithmetic or formatting belong on the
functions that perform those operations.

## Typeclasses and overloads

A typeclass names a set of required operations. An instance supplies those
operations for a particular tuple of types. The `ToHexString` example defines
one method and supplies separate instances for PrimaryColor, `(Vec3 F32)` and
Color. A qualified signature such as
`(All (T) (=> ((ToHexString T)) (-> T String)))` permits using that method in a
generic body.

<!-- ANCHOR: classes -->
```text
typeclass ::= "(" "typeclass" "(" name … ")" method_signature … ")"

method_signature ::= "(" ":" name function_type ")"

instance ::= "(" "instance" obligation method_implementation … ")"

method_implementation ::= "(" name expression ")"
```
<!-- ANCHOR_END: classes -->

A typeclass's parameters scope its method signatures. An instance supplies every
method exactly once; its head has no free type variables. Instance selection
uses the resolved class identity and complete type tuple. The instance's `def`
name identifies the implementation evidence; it is not an ordinary runtime
function binding. Duplicate instances for the same class and type tuple are
errors even if named differently. Importing the same instance through several
paths does not duplicate it.

Available instances do not determine unknown types. Once types are known,
concrete obligations must be discharged, even in unused definitions; generic
obligations can remain in a generalized signature. An instance body's method
expressions still initialize in source order. Static selection never runs their
effects early.

Overloaded operations are selected by argument and result constraints together.
Exactly one compatible complete signature must remain. Declaration order and
the availability of an implementation's prerequisites do not rank candidates.
Numeric promotion, where offered, is an explicitly provided operation. Selected
implementations retain their normal initialization and effect ordering.

## Any, Never and subtyping

`Any` holds a value together with enough type information to check what it is.
It lets a dynamically typed frontend represent values whose precise types are
unknown at a particular boundary. Injecting a value into Any preserves its
complete semantic type, including nominal identity and type arguments.
Recovering a precise type requires an explicit checked projection:

```scheme
(begin
  (let boxed Any 42)
  (+ (ann boxed I32) 1)) ; 43; the annotation checks the stored type
```

Projecting that value to String traps. Passing an Any value directly to a
function requiring I32 is a type error: only `ann` requests the dynamic check.
Any is the universal value type used at these dynamic boundaries.

`Never` has no values. An expression that always traps or diverges can have
type Never because it never returns a value of the wrong type. It can occur
where any result type is expected. This does not prove that it terminates.

Here `U <: T` means a U value can be used where T is expected. `many(U)` means
U values may be copied and discarded. The core types in these chapters have
that property; an ownership extension must check it for additional types.

<!-- ANCHOR: subtyping -->
```text
────────────── SUBTYPE-REFLEXIVE
T <: T

────────────── SUBTYPE-NEVER
Never <: T

many(T)
────────────── SUBTYPE-ANY
T <: Any

Γ ⊢ e ::↑ U |> P       U <: T
────────────────────────────── TYPE-SUBSUME-CHECK
Γ ⊢ e ::↓ T |> P

Γ ⊢ e ::↓ T |> P
────────────────────────────── TYPE-ANN-INFER
Γ ⊢ (ann e T) ::↑ T |> P

Γ ⊢ e ::↑ Any |> P      many(T)
────────────────────────────── TYPE-PROJECT-INFER
Γ ⊢ (ann e T) ::↑ T |> P
```
<!-- ANCHOR_END: subtyping -->

`TYPE-PROJECT-INFER` inserts a runtime type check; a mismatch traps. Literal
annotations additionally use the width-selection rules above. These are the
only subtyping relations, apart from transitivity. Ref and Vector are invariant
in their element types; no function or container variance conversions are
inferred. An affine value would require an explicit shared ownership wrapper
before injection into Any. Unrelated branch types do not silently widen to Any;
a known expected Any type can request injection in each branch.

<!-- ANCHOR: branches -->
```text
Γ ⊢ c ::↓ Bool |> P₀    Γ ⊢ a ::↑ A |> P₁    Γ ⊢ b ::↑ B |> P₂    T = join(A,B)
─────────────────────────────────────────────────────────────────────────── TYPE-IF-INFER
Γ ⊢ (if c a b) ::↑ T |> P₀ ∪ P₁ ∪ P₂

Γ ⊢ c ::↓ Bool |> P₀    Γ ⊢ a ::↓ T |> P₁    Γ ⊢ b ::↓ T |> P₂
────────────────────────────────────────────────────────── TYPE-IF-CHECK
Γ ⊢ (if c a b) ::↓ T |> P₀ ∪ P₁ ∪ P₂

join(Never,T) = T; join(T,Never) = T; otherwise unify the two types or report an error.
```
<!-- ANCHOR_END: branches -->

Unification solves inference variables with an occurs check, which rejects a
variable equal to a type containing itself. It never solves rigid quantified
variables. Unknown representations or class operations at specialization are
errors; they do not silently introduce Any, generic runtime code or a JIT.
