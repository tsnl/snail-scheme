# Types

A type describes which values and operations fit together. The compiler infers
expression types and unannotated bindings, and checks the signatures you supply
on `def` or `let`. Passing a string to a function that requires an integer is an
error before execution.

A *type variable* stands for a type chosen at a use of a generic definition. A
*type constructor*, such as `List`, takes element types to describe a compound
type. Resolution distinguishes type variables and nominal type names from
ordinary value names. A nominal application must have its declared arity.

## Names and binding identities

<!-- ANCHOR: names -->
`name` is a source identifier token, such as `value`, `T`, or `Display`.
The following grammar categories all use that lexical syntax. Their distinct
roles determine which binding a name must resolve to:

```text
value_name    resolves to x ∈ ValueNames        = {x₀, x₁, …}
type_variable resolves to α ∈ TypeVariableNames = {α₀, α₁, …}
datatype_name resolves to D ∈ DatatypeNames     = {D₀, D₁, …}
class_name    resolves to C ∈ ClassNames        = {C₀, C₁, …}
instance_name resolves to d ∈ InstanceNames     = {d₀, d₁, …}
```

These are disjoint, countably infinite supplies of possible binding identities.
A particular program declares only finitely many. The same spelling can denote
different identities in different scopes; membership in a universe does not
itself bring a name into scope. Type variables must be bound by an enclosing
`All`, datatype, or typeclass declaration. Constructor, accessor, and method
bindings are value names. Field labels and library-name components are also
identifier tokens, but do not themselves introduce value bindings.

A nominal type is identified by its datatype declaration. A scheme quantifies
type variables over a type and its requirements. These describe different
properties: a scheme can mention a nominal type, such as `(Tree T)`.
<!-- ANCHOR_END: names -->

## Type syntax

```text
<!-- ANCHOR: types -->
type ::= primitive_type
       | type_variable
       | datatype_name                                  ; zero parameters
       | "(" datatype_name type type … ")"               ; type arguments
       | "(" "Ref" type ")"
       | "(" "List" type ")"
       | "(" "Vector" type ")"
       | function_type

primitive_type ::= "I32" | "I64"
                 | "F32" | "F64"
                 | "Bool" | "Char" | "Unit"
                 | "String" | "Bytevector"
                 | "Never" | "Any"

function_type ::= "(" "->" type … type ")"
                | "(" "->" type … "(" "Rest" type ")" type ")"
<!-- ANCHOR_END: types -->
```

## Reading the typing rules

A rule puts its premises above a horizontal line and its conclusion below.
The name at the right of the line identifies the rule. A line with no premises
states an axiom: the conclusion holds directly.

<!-- ANCHOR: typing-notation -->
`Γ` maps available value-binding identities to schemes. `e` is an expression
and `T` a type. `::↑` means *synthesize*: compute a type from the expression,
possibly containing unsolved inference holes. `::↓` means *check*: verify the
expression against an expected type supplied by its context. Either operation
can use unification to solve holes; checking does not require every type to be
concrete before it starts.

```text
Γ ⊢ e ::↑ T ; requirements P    infer type T for e, collecting P
Γ ⊢ e ::↓ T ; requirements P    check e against T, collecting P
```

The suffix names a second output: a set `P` of class requirements. It is
specification notation, not source syntax. `P = ∅` means no requirements;
`P₁ ∪ P₂` combines requirements from two subexpressions. For example, using
`to-hex-string` at an abstract type T can
collect `{(ToHexString T)}`. A generic signature can carry that requirement;
a concrete use must supply the corresponding instance.

A requirement names a class and its type arguments. An *obligation* is a
requirement the checker must discharge, using an assumption from the enclosing
scheme or a checked instance for the concrete types. This checks the availability
and types of operations; it does not prove semantic laws about their behavior.
For example, `ToHexString` does not prove that a returned string contains only
hexadecimal digits.

The relevant AST and checker data can be read as:

```text
requirement = (class binding identity, type arguments)
scheme      = (quantified variables, type, requirements)
judgment    = (inferred type, requirements, source expression, …)
```

Declared requirements belong to a binding's scheme. Inferred requirements are
checker results associated with expressions; they are not extra source forms
attached to every expression. The implementation calls these fields
`constraints`. Equality equations solved by unification are separate from `P`.

Subscripts distinguish related expressions or types. A bar over a variable,
as in `ᾱ`, denotes a sequence. Repeated sequences in a rule have matching
lengths. `?β` denotes a fresh, flexible inference hole; it is not a source type
variable. The algorithm maintains solutions for these holes and follows them
before comparing types. The summary leaves this solver state implicit.
An explicitly quantified variable is rigid while its definition is checked:
unification may solve a hole to that variable, but cannot specialize the variable
itself to a particular type.
<!-- ANCHOR_END: typing-notation -->

## Primitive types

| Type | Values |
| --- | --- |
| I32, I64 | Signed integers of the indicated width |
| F32, F64 | IEEE floating-point numbers of the indicated width |
| Bool | `#t` and `#f` |
| Char | Unicode scalar values, such as `#\a` |
| Unit | One value, constructed by `(unit)` |
| String | Well-formed UTF-8 text, indexed by Unicode scalar value |
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
Γ ⊢ integer ::↑ I32 ; requirements ∅

float fits F64 after rounding
────────────────────────────────── TYPE-F64-INFER
Γ ⊢ float ::↑ F64 ; requirements ∅

W ∈ {I32, I64}     integer ∈ range(W)
──────────────────────────────────────────── TYPE-INT-LITERAL-ANN
Γ ⊢ (ann integer W) ::↑ W ; requirements ∅

W ∈ {F32, F64}     float fits W after rounding
──────────────────────────────────────────── TYPE-FLOAT-LITERAL-ANN
Γ ⊢ (ann float W) ::↑ W ; requirements ∅

────────────────────────────────── TYPE-BOOL-INFER
Γ ⊢ boolean ::↑ Bool ; requirements ∅

────────────────────────────────── TYPE-CHAR-INFER
Γ ⊢ character ::↑ Char ; requirements ∅

────────────────────────────────── TYPE-STRING-INFER
Γ ⊢ string ::↑ String ; requirements ∅

────────────────────────────────── TYPE-BYTEVECTOR-INFER
Γ ⊢ bytevector ::↑ Bytevector ; requirements ∅
```
<!-- ANCHOR_END: literals -->

The literal annotation rules choose a representation before the unannotated
literal is synthesized. Thus `(ann 2147483648 I64)` is valid even though
`2147483648` alone is outside I32's range. A direct numeric literal initializer
with a binding annotation uses the same rule. Other annotated initializers are
checked normally: `(def count I64 (begin 42))` and `(ann (begin 42) I64)` are type
errors. A declared I64 function result also cannot change a bare body literal's
I32 type. Boxing `(def value Any 42)` preserves I32, so `(ann value I64)` fails
its runtime type check. `Unit` is constructed by the ordinary `(unit)` operation with
signature `(-> Unit)`.

An out-of-range literal is a compile-time error. Runtime I32/I64 addition,
subtraction and multiplication wrap modulo 2^32 or 2^64, respectively, with the
result interpreted as a signed integer of the same width. They do not trap on
overflow or widen the type. Thus I32 maximum plus one is I32 minimum, and
subtracting I32 minimum from zero returns I32 minimum. Integer division by zero
and signed minimum divided by minus one trap. Integer remainder by zero traps;
remainder of signed minimum by minus one is zero.

F32/F64 addition, subtraction, multiplication and division use IEEE results,
rounded to the operation's width with nearest rounding and ties to even.
Overflow may produce infinity; underflow may
produce a subnormal or signed zero. Division by zero, invalid domains and
operations with infinity or NaN operands retain their IEEE behavior. NaN payloads
and signs are not prescribed. These contracts apply to direct primitives,
overloads and first-class function values on both Wasm and native execution.

Explicit narrowing conversions remain checked: an out-of-range integer or a
finite float that rounds to infinity traps. Floating-to-integer conversion also
traps for NaN, infinity or a truncated result outside the signed destination
range. These conversion contracts are detailed among the
[implementation extensions](extensions.md). The nominal unbounded `Integer`
library retains exact arithmetic. Explicit overflow-checking arithmetic variants
are future operations; they are not part of the current interface.

Floating literals round once from the source value to the selected IEEE format,
using nearest rounding with ties to even. A finite value just above the largest
finite number is allowed when it rounds back to that number; rounding to infinity
is an error. Underflow rounds to a subnormal or signed zero. Explicit `+inf.0`,
`-inf.0` and signed `nan.0` tokens denote IEEE special values rather than finite
overflow. Rectangular complex and polar spellings are not scalar literals, even
when their mathematical value happens to be real. Bytevector elements must be
exact integers in the byte range before any floating-point rounding.

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
Γ, x₁:T₁, …, xₙ:Tₙ ⊢ body ::↓ R ; requirements P
────────────────────────────────────────────────────── TYPE-LAMBDA-CHECK
Γ ⊢ (lambda (x₁ … xₙ) body) ::↓ (-> T₁ … Tₙ R) ; requirements P

T₁, …, Tₙ fresh     Γ, x₁:T₁, …, xₙ:Tₙ ⊢ body ::↑ R ; requirements P
────────────────────────────────────────────────────── TYPE-LAMBDA-INFER
Γ ⊢ (lambda (x₁ … xₙ) body) ::↑ (-> T₁ … Tₙ R) ; requirements P

Γ ⊢ f ::↑ (-> T₁ … Tₙ R) ; requirements P₀
Γ ⊢ eᵢ ::↓ Tᵢ ; requirements Pᵢ  (1 ≤ i ≤ n)
───────────────────────────────────────────────────────────────── TYPE-CALL-INFER
Γ ⊢ (f e₁ … eₙ) ::↑ R ; requirements P₀ ∪ ⋃ᵢ Pᵢ
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

```text
<!-- ANCHOR: schemes -->
signature ::= type
            | "(" "All" "(" type_variable … ")"
                  ["(" "requires" requirement … ")"] type ")"

requirement ::= "(" class_name type … ")"
<!-- ANCHOR_END: schemes -->
```

`All` binds the type parameters; its optional `requires` clause lists class
assumptions available while checking the definition. The final component is
one ordinary type. The complete signature is a *scheme*, written
`∀ᾱ. T requires P` in the rules. Requirements are part of the scheme, rather
than a separate type form that can appear inside an arrow or container.

```scheme
(def render (All (T) (requires (ToHexString T)) (-> T String))
     (lambda (value) (to-hex-string value)))
```

The clause may contain several requirements, such as
`(requires (Display T) (Serialize T))`. Omitting it is equivalent to writing
`(requires)`. An empty parameter list is also valid: `All ()` quantifies no
variables, while its requirements still need to be satisfied. An ordinary type
used as a signature has neither quantified variables nor declared requirements.

While checking a definition, each `All` parameter becomes a fresh **rigid**
variable. The initializer must work for that arbitrary type using the declared
requirements and any enclosing assumptions. For example, an initializer with
signature `(All (T) (-> T T))` cannot return `42` for every input: unification
cannot equate the rigid `T` with I32. These parameters also scope over annotations
inside the initializer, so a nested `def` can refer to its enclosing definition's
type parameters. They do not escape into sibling definitions.

At each use of a generic binding, quantified variables instead become fresh
**flexible inference holes**. Arguments and an expected result type can solve
those holes. Explicit `inst` supplies the type arguments directly. In both cases,
the substituted requirements must be discharged from enclosing assumptions or
available instances; available instances do not choose the type arguments.

The earlier `(All (T) (=> ((ToHexString T)) (-> T String)))` spelling remains an
input compatibility form. It has the same meaning and checker path. The term
*qualified type* describes the historical requirements-and-type pair; new source
uses the explicit `requires` clause above.

<!-- ANCHOR: instances -->
```text
Γ(x) = ∀ᾱ. T requires P       ?β̄ fresh inference holes       |ᾱ| = |?β̄|
────────────────────────────────────────────── TYPE-NAME-INFER
Γ ⊢ x ::↑ T[ᾱ := ?β̄] ; requirements P[ᾱ := ?β̄]

Γ(x) = ∀ᾱ. T requires P       |ᾱ| = |Ū| ≥ 1
────────────────────────────────────────────── TYPE-INST-INFER
Γ ⊢ (inst x U₁ … Uₙ) ::↑ T[ᾱ := Ū] ; requirements P[ᾱ := Ū]
```
<!-- ANCHOR_END: instances -->

`TYPE-NAME-INFER` instantiates a scheme without choosing concrete type arguments.
For `identity`, it produces `(-> ?β ?β)`. Applying it to `42` later solves
`?β = I32`. Each use gets fresh holes. This is inference with deferred solving;
the name alone does not determine a unique concrete instantiation. Checking
`identity` against `(-> I64 I64)` instantiates the same way, then solves the
hole against the expected type using the checking rule below. Unification is
part of checking; it never changes the rigid variables of a checked definition.
`TYPE-INST-INFER` instead substitutes the supplied types in both the type and
the requirements. Neither rule by itself establishes that those requirements
have an implementation. The checking and generalization rules decide which
requirements must be discharged and which can remain in a scheme.

An expected type does not always determine every parameter. With a signature
`(All (T) (requires (Display T)) (-> String))`, checking a use against
`(-> String)` leaves `T` unknown because it appears only in the requirement.
For a concrete use, `(inst name I32)` supplies that missing choice. The checker
must not select I32 just because a `Display I32` instance happens to be available.

An unannotated `def` or `let` can infer an `All`. Inference generalizes variables
not fixed by the surrounding environment, subject to the *value restriction*:
only literals, names, lambdas, explicit instantiations and static annotations of
these forms can generalize. Applications and allocations stay monomorphic. This
prevents one mutable cell from being used at incompatible element types. An
explicit `All` cannot override this restriction.

An annotation preserves nonexpansiveness when its check is static. A projection
from `Any` that requires a runtime check is expansive, even when its operand is
a name or literal. Its possible initialization failure cannot be skipped by
generalizing the binding.

For typing, resolve each binding's lexical scope, then form dependency groups
from references in its initializer, including references in lambda bodies.
Annotated definitions are checked against their signatures; unannotated ones
get provisional monotypes. Recursive uses within a group are monomorphic, so
type-changing polymorphic recursion is not supported. Solve groups in dependency
order and generalize eligible bindings afterward. This is a checking order,
not a change to initializer execution order. Every body is checked, even if no
caller uses it.

The monomorphic view fixes explicit `inst` arguments as well as the function
type. This includes a quantified parameter absent from the function's argument
and result types: a recursive `inst` cannot change that parameter merely because
the arrow does not mention it. Different declarations in one group keep their
own rigid binders; their recursive views may correspond by consistent renaming,
including a permutation of binders.

## Static definitions and well-formedness

`data`, `typeclass` and `instance` are library-level declarations. Each names
its subject and can introduce related bindings, such as constructors, accessors
or class methods:

```scheme
(data Flag ()
  (off)
  (on))
(typeclass Display (T) (: display-text (-> T String)))
(instance flag-display (Display Flag)
          (display-text (lambda (flag) (match flag ((off) "off") ((on) "on")))))
```

```text
<!-- ANCHOR: static-definitions -->
static_definition ::= data_definition
                    | typeclass_definition
                    | instance_definition
<!-- ANCHOR_END: static-definitions -->
```

These declarations require library scope. A datatype names a type constructor;
a typeclass names a requirement constructor; an instance supplies implementations
for one concrete requirement. Their parameters stand for ordinary types. They
cannot be returned from functions or selected by a runtime `if`.

The compiler still accepts the earlier `(def name [kind] static_former)` syntax
for compatibility, including `(datatype (...) ...)` bodies. Expansion normalizes
the new declarations to that internal representation before ordinary checking.
In that older notation, a *kind* classifies a static declaration: `Type` for a
zero-parameter datatype, `(Kind-> Type … Type)` for a datatype constructor,
`(Kind-> Type … Constraint)` for a class, and `(Evidence (C T …))` for an
instance. These classifications are not runtime value types. New source should
use the explicit declaration forms.

<!-- ANCHOR: well-formedness -->
The first-order type language needs the following well-formedness checks:

- A type variable refers to an enclosing type-parameter binder.
- A datatype application names a visible datatype, has its declared number of
  arguments, and supplies a well-formed type for each argument. A bare datatype
  name denotes a type only when its declaration has zero parameters.
- A class requirement names a visible class and supplies its declared number of
  well-formed type arguments. It appears in a scheme's requirements or an
  instance head, rather than in a field or function parameter's type position.
- A type variable cannot be applied as a constructor: `(F T)` requires a
  datatype declaration for `F`, not an `All` parameter.
- A scheme occurs at the outside of a binding signature. It cannot be nested
  inside an ordinary type.

`arity` reads the parameter count from the resolved declaration. `type-ok` and
`requirement-ok` below use the lexical scope at the application site:

```text
D is a visible datatype     arity(D) = n     |T̄| = n
type-ok(Tᵢ) for every 1 ≤ i ≤ n
──────────────────────────────────────────────────── WF-DATATYPE-APPLY
type-ok(D applied to T̄)

C is a visible class        arity(C) = n     |T̄| = n
type-ok(Tᵢ) for every 1 ≤ i ≤ n
──────────────────────────────────────────────────── WF-CLASS-APPLY
requirement-ok((C T₁ … Tₙ))
```

The datatype conclusion uses `D` when `n = 0` and `(D T₁ … Tₙ)` otherwise.
These rules check that a requirement is well-formed, not that it is satisfied.
Checking an instance requires its head to contain no free type variables and
its methods to implement the class signatures for those types.
<!-- ANCHOR_END: well-formedness -->

## Struct and union types

A struct groups named fields into one value. A closed union selects one of a
fixed set of cases. `data` describes both using constructors: one constructor
for a struct, several for a union. Fields are immutable; a field of type
`(Ref T)` can hold an explicitly mutable cell.

```text
<!-- ANCHOR: data -->
data_definition ::= "(" "data" datatype_name "(" type_variable … ")"
                    constructor_clause constructor_clause … [deriving_clause] ")"

deriving_clause ::= "(" "deriving" name … ")"

constructor_clause ::= "(" value_name field_clause … ")"

field_clause ::= "(" name type [value_name] ")"
<!-- ANCHOR_END: data -->
```

The names in the parameter list bind type variables over the field types.
A constructor clause names a constructor; a field clause gives a field name,
its type and an optional accessor name.

```scheme
(data Tree (T)
  (leaf
   (value T))
  (branch
   (left (Tree T))
   (right (Tree T))))

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

Every `data` declaration creates a distinct nominal type identity.
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
`(All (T) (requires (ToHexString T)) (-> T String))` permits using that method in a
generic body.

```text
<!-- ANCHOR: classes -->
typeclass_definition ::= "(" "typeclass" class_name "(" type_variable … ")"
                         method_signature … ")"

method_signature ::= "(" ":" value_name function_type ")"

instance_definition ::= "(" "instance" instance_name requirement method_implementation … ")"

method_implementation ::= "(" value_name expression ")"
<!-- ANCHOR_END: classes -->
```

A typeclass's parameters scope its method signatures. An instance supplies every
method exactly once; its head has no free type variables. Instance selection
uses the resolved class identity and complete type tuple. The instance's
name identifies the implementation evidence; it is not an ordinary runtime
function binding. Duplicate instances for the same class and type tuple are
errors even if named differently. Importing the same instance through several
paths does not duplicate it.

Available instances do not determine unknown types. Once types are known,
concrete obligations must be discharged, even in unused definitions; generic
obligations can remain in a generalized signature. An instance body's method
expressions still initialize in source order. Static selection never runs their
effects early.

Every [overload alternative](extensions.md#ad-hoc-overload-families) declares an
explicit signature. Its implementation is checked against that signature;
ordinary unannotated definitions retain inference. Overloaded operations are
selected by argument and result constraints together.
Exactly one compatible complete signature must remain. Declaration order and
the availability of an implementation's prerequisites do not rank candidates.
Numeric promotion, where offered, is an explicitly provided operation. Selected
implementations retain their normal initialization and effect ordering.

## Data graph serialization

`(lofi serialization)` provides separate `Serialize` and `Deserialize`
typeclasses. A type opts into either capability with an explicit instance or a
[derive transformer](macros.md#deriving-typeclass-instances). Procedures,
closures, live external resources and arbitrary `Any` values have no supplied
instances. Unsupported fields produce ordinary missing-class-evidence errors.

`serialize` converts a supported typed value to `Sexp`; `deserialize` checks an
`Sexp` and reconstructs the requested type. The result type must be determined
by its use or an annotation. These entry points create private traversal
contexts. Instance methods `serialize-with` and `deserialize-with` receive that
context explicitly, while `serialize-type` and `deserialize-type` identify the
wire type using a `(Witness T)` argument.

```scheme
(import
 (lofi core)
 (lofi serialization))

(data Stock ()
  (stock
   (ore I32 stock-ore))
  (deriving derive-serialize derive-deserialize))

(def saved (sexp->binary (serialize (stock 42))))
(def restored Stock (deserialize (binary->sexp saved)))
(stock-ore restored) ; 42
```

### One value representation, two encodings

```text
data with class instances ↔ S-expression graph ↔ readable text
                                              ↔ compact binary
```

The finite `Sexp` representation contains signed integers, strings, symbols,
bytevectors and lists. Symbols and strings are distinct. `sexp->text` and
`text->sexp` provide its readable representation; `sexp->binary` and
`binary->sexp` encode and decode the same values using a MessagePack-style
binary representation. Binary is encoded directly from the S-expression value,
without a text conversion. It is not a promise that generic MessagePack readers
understand Lofi's symbol representation.

A derived record or union value carries its type, selected constructor, and
named fields. Its schematic readable form is:

```text
(data |(demo inventory):Stock| stock (ore (I32 42)))
```

The type tag combines the declaring library and original type name. Independent
named libraries can define `Stock` without confusing their wire types; import
aliases retain the original instance and tag. A local collision between distinct
type bindings with the same portable name is a compile-time error. Constructor
and field names are checked along with field types and order. These tags are
portable schema names, not process addresses, Wasm references or compiler layout
offsets.

Supplied scalar instances cover `I32`, `I64`, `F32`, `F64`, `Bool`, `Char`,
`Unit`, `String`, `Bytevector`, and `Symbol`. Import `Symbol` and its text
operations directly from `(lofi scalar-text)`, or through `(lofi datum)`, which
reexports the same type. The direct import avoids the dynamic datum and numeric
libraries. Numeric width is explicit in each value's tag. Floats store their
exact IEEE bits as integers, preserving negative zero, infinities and NaN
payloads. The public `f32->bits`,
`bits->f32`, `f64->bits` and `bits->f64` operations expose those representations
without numeric conversion.

### Object graphs and checked reconstruction

One context flows through every generated field operation. Shared strings,
bytevectors, references and vectors receive object numbers. The first encounter
emits `(object id type payload)`; later encounters emit `(link id type)`.
Reference and vector storage is registered before recursively decoding its
contents, so references back to that storage reconstruct cycles. Object numbers
belong to this traversal and have no connection to addresses in the source heap.
Immutable record and list structure is encoded by value; the current language
provides no identity operation for that structure.

The field macros `serialize-field` and `deserialize-field` handle nested `List`,
`Ref` and `Vector` types using typed callbacks and the same context. Every leaf
still requires its class instance. These helpers do not supply blanket generic
container instances: a direct top-level container needs an explicit instance or
use of the corresponding field macro with a context. Reference/vector decoding
requires `Default` evidence for the element type, providing valid initial storage
before its contents are filled. A type without such evidence cannot use that
decoding path.

Decoding rejects malformed shapes, mismatched tags, missing or extra fields,
out-of-range scalar values, duplicate object numbers, unknown or forward links,
and links whose declared type disagrees with their target. Partially filled
storage stays within the private traversal until the complete root succeeds.
Errors use the runtime's checked failure path. Application-specific invariants
still need checking after reconstruction; deriving a decoder does not establish
that a decoded world is a valid game state.

This facility is separate from the existing `(lofi read)`/`(lofi write)` datum
format. It does not add datum-label reading to `(lofi read)`, derive constrained
generic instances, serialize arbitrary values, or migrate incompatible schemas.
The [roadmap](https://github.com/tsnl/snail-scheme/blob/main/doc/roadmap.md#data-graph-serialization) tracks remaining work.

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

Γ ⊢ e ::↑ U ; requirements P       U <: T
────────────────────────────── TYPE-SUBSUME-CHECK
Γ ⊢ e ::↓ T ; requirements P

Γ ⊢ e ::↓ T ; requirements P
────────────────────────────── TYPE-ANN-INFER
Γ ⊢ (ann e T) ::↑ T ; requirements P

Γ ⊢ e ::↑ Any ; requirements P      many(T)
────────────────────────────── TYPE-PROJECT-INFER
Γ ⊢ (ann e T) ::↑ T ; requirements P
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
Γ ⊢ c ::↓ Bool ; requirements P₀
Γ ⊢ a ::↑ A ; requirements P₁    Γ ⊢ b ::↑ B ; requirements P₂    T = join(A,B)
─────────────────────────────────────────────────────────────────────────── TYPE-IF-INFER
Γ ⊢ (if c a b) ::↑ T ; requirements P₀ ∪ P₁ ∪ P₂

Γ ⊢ c ::↓ Bool ; requirements P₀
Γ ⊢ a ::↓ T ; requirements P₁    Γ ⊢ b ::↓ T ; requirements P₂
────────────────────────────────────────────────────────── TYPE-IF-CHECK
Γ ⊢ (if c a b) ::↓ T ; requirements P₀ ∪ P₁ ∪ P₂

join(Never,T) = T; join(T,Never) = T; otherwise unify the two types or report an error.
```
<!-- ANCHOR_END: branches -->

Unification solves inference variables with an occurs check, which rejects a
variable equal to a type containing itself. It never solves rigid quantified
variables. Unknown representations or class operations at specialization are
errors; they do not silently introduce Any, generic runtime code or a JIT.
