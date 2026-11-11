# Types

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` packages an eligible dynamic value, recovered through a checked
conversion ([dynamic values](#dynamic-values)).
`String` is an immutable sequence of Unicode scalars. `(Vector T)` is an
immutable sequence and `(Array T)` a mutable one whose elements are unboxed,
`(Unboxed T)`: a scalar, a reference or a struct of one unboxed field, each one
Wasm slot, so an array of points is refused and a struct of arrays stands in
for it, as typed arrays do in JavaScript; `(MutVector T)` grows at its end over
such an array. `(Ref T)` is a mutable cell, the one struct with a mutable
field, which `(snail core base)` declares ([data](#data)). `Bytes` is `(Vector U8)`, stored packed. A byte vector literal,
`#u8(137 80 78 71)`, compiles to a data segment of exactly its bytes, so a
program can carry large binary data, such as images; it cannot be a
pattern. `(include-bytes "pixel.png")` is another spelling of the literal
holding a file's bytes, with the path relative to the file it is written
in. It is replaced when the source is read, so a macro cannot compute the
path, and nothing else may be named `include-bytes`. A large file is better
linked than included: see [linked files](#linked-files).

A callable contract is `(impl (Fn Param ... → Result))`, with an optional
[effect row](effects.md) after `!`. `FnMut` selects exclusive access and
`FnOnce` selects a consuming call. `dyn` names callable storage, while
`(fn Param ... → Result)` names noncapturing code. The
[callable classes](#callable-classes) section describes these distinctions.
A named function carries its type where it is defined. Every parameter has a
mandatory `(name Type)` annotation, and every named function must state its result
with `(→ Result)`. Optional effect, generic-variable, constraint and
documentation clauses follow the parameter list at the start of the
definition, before its body:

```scheme
(define (map-with (function F) (values (List A)))
  (→ (List B))
  (! e)
  (∀ A B e F)
  (⊨ (Copy F) (Fn F A → B ! e))
  (map function values))
(define (sum (values (List T)))
  (→ T)
  (! e)
  (∀ T e)
  (⊨ (Num e T))
  (fold-left + 0 values))
```

Ordinary value definitions retain their initializer form and can put an
explicit type, quantifiers or constraints in the same leading header position,
for example `(define zero (→ I64) 0)`. Existing separate `(: name type)`
declarations remain for class, effect and foreign signatures, which have no
implementation body. Type-level callable signatures use the Unicode `→`;
universal quantification and requirements use `∀` and `⊨`. These are the only
spellings: `->`, `All` and `requires` are not aliases.

A type variable is linear unless the signature requires `(Copy T)`, which
a body needs to use a `T` twice or to discard one
([ownership](ownership.md)).

Integer literals check against any integer or float type and are
range-checked; float literals check against `F32` or `F64`. A literal whose
type nothing determines defaults to `I64` or `F64`. Numeric values never
change numeric type implicitly: use `i64->i32`, `i32->f64` and the other
conversions. Crossing an `Any` boundary checks the payload's type; it
does not change that type. Integer arithmetic wraps.

Local bindings remain monomorphic; place explicitly quantified definitions at
the top level. Unannotated top-level functions are generalized over the type variables no
constraint mentions. Other unannotated definitions, and functions whose
types involve a class constraint, keep one type, which later uses in the
same library may decide. A library is checked before the libraries that
import it, so their uses never decide its types: `(define key-left 1)` is an
`I64` wherever it is imported, and a value meant as an `I32` elsewhere needs
the inline signature `(define key-left (→ I32) 1)`. Polymorphic definitions with constraints,
and polymorphic values that are not functions, need signatures.

## Data

```scheme
(struct (Vec3 T)
  ((x T)
   (y T)
   (z T)))

(enum Shape
  (Circle ((radius F64)))
  (Polygon ((points (List (Vec3 F64)))))
  (Empty))
```

A struct `Name` defines the constructor `Name` and pure replacements
`Name-field-set`; its fields are read by path, `(::field s)`, below. A
struct is a value: its fields are immutable,
and a program that changes one holds it in a cell, `(Ref Name)`, and writes a
*place*, the cell's content or a field read from it, with `set!` or
`replace!`: `(set! (::count (ref-get r)) 1)`. Reading or writing a cell
performs `mut`. `Ref` is the one struct with a mutable field, and a pattern can
only skip its content, with `_` ([ownership](ownership.md)). An enum defines a
constructor and partial accessors `Case-field` per case, and its fields are
immutable. Cases are constructors, not types, and are always applied:
`(Empty)`.

A field is read by its label alone: `(::label s)` reads the field `label`
of whatever struct `s` is, and `(::from::x s)` reads `x` of what `from`
holds. Each label is a typeclass, `(::label R T)`, over the record
type and the field's type, with the one method `::label`; a struct without
mutable fields has an instance per field, and the record's type decides
the field's, so a path needs no annotation where the record's type is
known. A library may declare an instance for a type that computes the
field. A generic function that reads the field of any record with that label
needs `(⊨ (::label R String))`. Names beginning
with `::` are reserved for paths.

```scheme
{{#include ../../../tests/programs/field-paths.sld:paths}}
```

Patterns are `_`, variables, literals (numbers, characters, strings,
booleans) and constructor patterns, nested freely. `(List T)` is an ordinary
enum with cases `Nil` and `Cons`.

## Annotations

A separate type declaration (`:`), `struct`, `enum`, `type`, `typeclass`,
`effect`, `extern`, a struct or enum field, an enum case, a typeclass member
or an effect operation can end with an optional
`(annotations ...)` list. Omitting it and writing an empty list both leave
the declaration undocumented. Each entry is an annotation application;
its own parser establishes its argument types and meaning.

```scheme
{{#include ../../../tests/programs/annotations.sld:annotations}}
```

The first supported annotation is `(doc "text")`. Its argument must be a
literal string. Repeated `doc` entries retain their source order and are
joined with a newline when displayed. Comments are not documentation
metadata, and annotation arguments are not evaluated. Unknown names and
malformed arguments are compile errors; adding another annotation requires
an argument parser, allowed targets and a consumer. Library-defined annotation
kinds and executable attribute macros are not implemented.

Metadata belongs to the canonical declaration; import prefixes and renames
do not change its owner. A field belongs to its declaring constructor and
field name, independently of the generated replacement functions. Those
functions already carry their field origin, which tooling can follow for
documentation. Metadata is retained when a library is reused by an
incremental build and does not contribute to type identity, wire schemas,
ownership, field order or runtime layout.

Function and value documentation belongs in the definition's leading header,
after its type clauses and before its initializer or body. For example,
`(define count (→ I64) (annotations (doc "A count.")) 3)` puts metadata
before the initializer. A macro can emit that annotated definition. For
no-body declarations such as class methods and foreign functions, metadata
stays on their separate declaration. Raw macro arguments and ordinary
expressions are not annotation slots: a function named `annotations` remains
an ordinary function. In a leading definition header, `(annotations)` or a
list of annotation applications is metadata. Wrap a call of that same shape
in `begin` to use it as the first body expression or initializer. The reader is unchanged; `:` is an identifier bound to
the signature form, not special punctuation. In an enum's final clause,
`annotations` is reserved for its metadata container, like `deriving` is
reserved for derived instances.

## Typeclasses

A typeclass declares methods over its parameters; instances may be generic
and may require other instances:

```scheme
(typeclass (Describe T)
  (: describe (impl (Fn T → String))))

(instance (Describe (List T))
  (⊨ (Describe T))
  (define describe
    (lambda (items) (string-join (map describe items) ", "))))
```

The checker chooses each instance when it checks a use and records that
choice; monomorphization copies the chosen method for each type, so no
dictionary exists at run time. Active instance heads must not overlap on their
input parameters. User-defined classes have
no superclasses: a signature lists every class it needs. The compiler-derived
callable classes have the implications described below. Unbound names in an
instance head are its type variables.

### Rows as parameters

A class may take a row as a parameter. A parameter its methods write after
`!` is a row, and the others are types. Each instance writes its row in its
head, so the instances of one class may perform different effects:

```scheme
{{#include ../../../tests/programs/classes-effects.sld:store}}
```

A use performs what its instance's head says. Reading a `Directory`
prints, so `fetch-twice` at a `Directory` performs `console`; at a `Table`
it is total, and a total function may call it. The row is found from the
types, not matched: the types choose the instance, which must be the only
one for them whatever rows the others write, and its row is charged to the
call, as a call is charged what its callee performs. A generic function
that requires `(Store e S)` performs `e`, which its signature names, and
each caller is charged what its own type's instance performs. A
requirement may give a closed row instead, as `(Store (!) S)`, which admits
only the types whose instance performs no more.

An instance's row is closed, or ends with a row variable that its
requirements of row classes give theirs, which the types they are given
decide:

```scheme
{{#include ../../../tests/programs/classes-effects.sld:logged}}
```

Fetching from a `(Logged Table)` performs `log`, and from a
`(Logged Directory)`, `log` and `console`. Ordinary class rows may name control
effects; specialization and control lowering preserve them. `Drop` and `Clone` are classes over a row too
([releasing](ownership.md#releasing)), whose rows are found from a type's
structure where it has no instance. These lifecycle classes still prohibit
control effects, since cleanup must finish.

Arithmetic and comparison are the classes `Num`, `Ord`, `Integral` and
`Fractional`; `Show` converts values to text. These classes all take a
row followed by a value type, as in `(Num e T)`. Concrete numeric
instances use `(!)`, so static arithmetic remains pure; a dynamic
instance can instead declare `(! dyn-cast)`. `Drop` releases values
([ownership](ownership.md#releasing)).

### Associated output types

A class can declare ordinary associated types. Each instance defines them:

```scheme
(typeclass (Add e A B)
  (type Output)
  (: add (impl (Fn A B → Output ! e))))

(instance (Add (!) I64 F64)
  (type Output F64)
  (define add (lambda (a b) (+ (i64->f64 a) b))))


(define (sum (a A) (b B))
  (→ (Add.Output e A B))
  (! e)
  (∀ A B e)
  (⊨ (Add e A B))
  (add a b))
```

`A` and `B` select the instance. Its `Output` and row are learned after
selection; neither an expected result nor permitted effects can select a
different instance. Thus `sum` at `I64` and `F64` infers `F64`, while an
annotation demanding `String` fails. Instances with identical inputs and
different outputs or rows overlap.

Inside a class, `Output` names its own member. Outside, `Add.Output` projects
from the matching enclosing `⊨` constraint. Write the same class arguments
as that constraint. A projection needs a unique requirement;
two requirements with the same input types cannot be distinguished by
outputs or rows. Export the projection binding explicitly, alongside the
class and its methods, when a library's clients need it.

A requirement can constrain an output with an equality:

```scheme
(define (twice (a A))
  (→ A)
  (! e)
  (∀ A e)
  (⊨ (Copy A) (Add e A A (type Output A)))
  (add a a))
```

The equality checks the selected instance. Merely naming an output or
requiring an instance does not call a method, inspect an `Any`, or perform
the method's effects. An unknown generic output has the same ownership
restrictions as another abstract type parameter.

Every instance must define each member exactly once. Definitions can use
input variables and projections from earlier prerequisites. Prerequisites
are resolved in written order: an earlier output may supply a later input,
but an expected result cannot supply a prerequisite's otherwise unknown
input. Recursive resolution rejects repeated input goals and bounds growing
chains. Ordinary decreasing recursive instances remain possible.

Members have kind `Type`. Associated parameters, defaults, effect-row
members, and higher-kinded members are not supported. A concrete projection
without an enclosing requirement is also currently rejected; this is not
a general type-function evaluator.

### Named instance sets

```scheme
(define-instance-set mixed-addition
  (instance (Add (!) I64 F64)
    (type Output F64)
    (define add (lambda (a b) (+ (i64->f64 a) b)))))

(with-instances (mixed-addition)
  (add (ann 1 I64) 2.5))
```

A set is an importable, exportable syntax binding. Importing it does not
activate its instances. `with-instances` activates sets for its expression
body or top-level declaration group. Activation adds to the enclosing
scope; it does not shadow instances. Repeating the same set is harmless.
Distinct active heads that overlap on inputs are errors, even if their
outputs or rows differ. Inactive alternatives may coexist. A set's methods see their containing set
and any surrounding active sets.

Unnamed instances remain available as before and cannot be overridden by
a set. A matching generic requirement supplies its existing evidence.
Concrete choices in a checked definition, including a returned closure,
remain fixed when callers activate another set; generic requirements
receive the evidence chosen by each caller. Activation itself performs no
effects and grants no effect permission. `Drop` and `Clone` cannot be placed
in sets, and the compiler's `Copy` and `Unboxed` rules remain unchanged.

### Asymmetric arithmetic

`(snail shell arithmetic)` supplies separate binary classes `Add`, `Sub`,
`Mul`, and `Div`, with methods `add`, `subtract`, `multiply`, and `divide`.
Each has an effect row, two operand types, and an associated `Output`.
They coexist with Core's existing numeric operators.

Its `arithmetic-base` set supports all ordered pairs of `Integer` and
`Rational`, and `F64` with `F64`. Exact addition, subtraction and
multiplication of integers return `Integer`; exact division returns
`Rational`. Operations involving a rational return `Rational`.
`inexact-promotion` adds both orders of `Integer`/`F64` and
`Rational`/`F64`, returning `F64`. These explicit conversions can round;
there is no conversion-chain search outside the selected operation.

`Integer` is the existing arbitrary-precision integer type. Results never
switch types because of their values. Core literals retain their existing
`I64`/`F64` defaults; construct exact values with `integer-from-i64` or
`string->integer`, and rationals with `make-rational`. Arithmetic errors
retain the underlying libraries' behavior; they are separate from `dyn-cast`.
Scheme uses these policies with native numeric payloads in `Any`; see
[dynamic Scheme](macros.md). Comparison policy remains separate work.

## Effects

Every function type has an effect row, the effects calling it may perform,
and a function without `!` is total. [Effects and handlers](effects.md)
covers rows, their inference and polymorphism, local mutation, declaring
and handling effects, control operations with a one-shot `resume`, latent
rows and defaults.

## Callable classes

`Fn`, `FnMut`, and `FnOnce` describe how a value can be called. They are
compiler-derived typeclasses, independent of `Copy` and of effects. Each
callable type puts `→` before its one result and `!` before its effect row:

```scheme
(define (square (n I64)) (→ I64)
  (* n n))
```

A definition's `impl` contract keeps its concrete implementation type.
Anonymous lambdas also have distinct concrete types, including the types
of their captures. Specialization retains that identity. Captured runtime
values do not create different specializations of the same closure type.
`define`, `lambda`, and the existing definition macros keep their meanings.

| Contract | Receiver access |
| --- | --- |
| `Fn` | Shared access; the owner can call it again. |
| `FnMut` | Exclusive access for the invocation; the owner can call it again. |
| `FnOnce` | Ownership passes to the invocation; call or drop it once. |

An `Fn` satisfies `FnMut` and `FnOnce`; an `FnMut` satisfies `FnOnce`.
The reverse implications do not hold. No callable class implies `Copy`.
A pure callable can be one-shot, and a repeatable callable can perform
console, mutation, or control effects. A consuming call of a shared owned
closure releases its environment when the call finishes; abandoning it
releases the captures without calling its body.

Argument-position `impl` introduces a fresh caller-chosen type with a
callability requirement. The consumer is generic over that type:

```scheme
(define (run-once (function (impl (FnOnce I64 → I64))) (value I64)) (→ I64)
  (function value))
```

An explicit type variable is useful when other requirements concern the
same owner. The receiver type comes before the signature in a constraint:

```scheme
(define (twice (function F) (value I64))
  (→ I64)
  (∀ F)
  (⊨ (Fn F I64 → I64) (Drop (!) F))
  (let ((answer (function (function value))))
    (drop function)
    answer))
```

This function borrows its argument for each call, then releases it. Add
`(Copy F)` explicitly when a consumer must duplicate or freely retain `F`.
The standard list and vector combinators use these callable constraints,
with an explicit `Copy` requirement on their callback. This preserves their
existing ability to suspend under an arbitrary effect row. The compiler
derives callable evidence for functions, lambdas, erased closures and code
pointers. User-defined instances of these three classes
are not supported.

### Explicit callable storage

Use `dyn` for fields, collections and returned values that can hold
different implementations of the same calling contract:

```scheme
(struct Job
  ((run (dyn (FnOnce I64 → Unit ! console)))))


(define (greeting (text String)) (→ (dyn (FnOnce → Unit ! console)))
  (once (lambda () (write-line text))))
```

`(dyn (Fn Args ... → Result))` preserves the existing unrestricted closure representation
and requires `Copy` captures. `(dyn (FnMut Args ... → Result))` and
`(dyn (FnOnce Args ... → Result))`
are owned storage. Their capture droppers run when they are released.
This explicit storage keeps heterogeneous jobs, future reducers, task
queues and saved resumptions possible. The checker inserts erasure at the
stated boundary; it does not erase every callable argument.

The current `impl` forms cover definitions, lambda annotations and direct
argument contracts. General opaque return types, nested quantified `impl`
contracts and generic associated implementation families are not
implemented. Use explicit `dyn` for those storage boundaries.

`once` accepts any argument count and preserves the complete signature.
An `impl FnOnce` lambda can move its captures into its body. A concrete
`Fn` or `FnMut` lambda can own non-`Copy` captures, but its repeatable body
may borrow them only; moving one requires a consuming contract. Ordinary
mutable storage and its `! mut` effect remain separate from receiver access.

### Receiver lifetimes and suspension

A call of a non-`Copy` `Fn` borrows a named local owner or immutable field
path. `FnMut` additionally requires exclusive receiver access through
argument evaluation and the call. The owner remains available afterward
and must eventually be consumed or dropped.

These loans use the existing lexical lifetime rules. A borrowed receiver
or its borrowed captures cannot remain live across a control operation;
an unknown effect-row tail also requires that conservative check. Moving
or capturing a borrowed owner is rejected. Mutable and lifetime-polymorphic
borrow types are not implemented. Consuming adaptation from an owned
shared or exclusive callable obeys this same limit; owning the adapter
does not extend its receiver loan's lifetime.

Existing `Copy` closures can still suspend, and consuming `FnOnce` values
can still own captures across suspension. Saved resumptions remain one-shot
and may be stored in `dyn FnOnce` values. Callability does not imply purity,
`Copy`, or the ability to keep a receiver loan across suspension.

### Code pointers

`(fn A → B ! e)` is the noncapturing code-pointer representation. A `fn`
expression or a top-level function can provide it; a capturing lambda
cannot. Code pointers satisfy the callable contracts, but retain their
separate representation at storage and foreign boundaries. Wrap a code
pointer in a lambda when an unrestricted `dyn Fn` closure is required.

The older prefix arrow and code-pointer `Fn` spellings are rejected with
migration diagnostics. Provider specialization, scoped capability changes
and effect-transition types remain proposals in their own chapters; this
migration preserves the current evidence-passing effect runtime.

## Proposed places and locators

**Design for review, not implemented.** A place is a concrete type; `Ref`
is the capability implemented by places that select a value of a given
type. Generic consumers accept `impl Ref T` and preserve the concrete
place type for specialization. There is no conversion to a single
concrete `Ref T`, runtime path descriptor or accessor-function dictionary.
The names below are proposed; the implemented `Ref` above is still the
current cell type.

### Concrete places

Write the internal shape schematically as `Place<Base, Path>`. `Base`
identifies the root storage representation and `Path` describes the
access steps at the type level. Allocating mutable storage for a `Point`
returns a root place with an empty path. The backing storage is always
allocated on the GC heap, including when bound to a local variable.

Projection composes paths. If `p` is a root place selecting a record,
`p.position.x` produces a concrete place type whose path identifies both
fields. It does not first copy `position` into a temporary. The root and
field path determine the selected type; neither the caller nor inference
can choose a different target type for the same place type. A computed
getter does not establish storage, and writable-field evidence must obey
the defining library's access rules.

For managed roots and paths consisting only of inline fields, the runtime
value is just the root managed reference. All path steps are erased by specialization;
projection allocates no locator object and installs no runtime dispatch.
The emitted accesses use fixed field indices, as WasmGC requires
([instruction syntax](https://webassembly.github.io/spec/core/text/instructions.html)).
The place keeps its root alive through that reference. Replacing the root's
content leaves a retained place selecting the same field in the new value.

### Reference capability and argument sugar

`Ref T` describes access to storage containing `T`. Internally its evidence
relates a concrete place type `P` to its unique selected type `T`; write
that relation as `(Ref P T)`. The compiler derives it from valid place
construction and projection. User instances cannot assert arbitrary
storage layouts. The argument-position `impl` form introduces a fresh type
variable and its class obligation directly on this function:

```scheme
(define (zero! (target (impl (Ref I64)))) (→ Unit) (! mut)
  (ref-set! target 0))
```

The compiler checks it with a fresh type variable `P`, constrained by
`(Ref P I64)`, and the caller chooses `P`. Calling `zero!` on two different field paths
specializes it for their distinct place types; both write an `I64` without
boxing or converting either place. Each argument-position `impl` introduces
an independent type variable. A named `P` expresses that two arguments, or
an argument and a result, must have the same concrete place type.

The capability admits reading, writing and swapping with `mut` recorded.
Reading must satisfy the existing copying rules for the selected value.
Managed place handles are unrestricted even though their contents have a
separate type: duplicating a handle preserves aliasing and does not copy the
stored object. The compiler can derive `(Copy P)` from its place evidence;
this implication must be explicit in checking, since current user classes
have no superclasses. Existing restrictions on shared cell contents remain:
linear values cannot be stored there without a separate ownership and
finalization design. This proposal does not permit moving a linear value
out of aliased storage or silently dropping one on replacement.

`impl Ref T` in an argument is static polymorphism, not an existential
container. Different place types cannot be put in one homogeneous list or
returned from different branches merely because they select the same `T`.
Such code must keep its alternatives explicit or invoke the generic
consumer within each branch. Returned or stored opaque `impl` types need
a separate language rule; this proposal introduces no automatic erasure.
The same principle applies to the [callable class](#callable-classes).

### GC-heap storage for local variables

All place-backed storage is allocated on the WasmGC heap, including
storage for local variables. A local allocation returns the same concrete
root place as any other allocation. Field projection composes the same
static paths, and generic consumers use the same `impl Ref T` capability.
Source scope does not select a different storage representation.

There are no stack allocations, stack-place types or stack-borrow
lifetimes in this design. The compiler must not replace this storage with
Wasm locals as an allocation-elimination strategy. A Wasm local can hold
the managed root reference; the referenced storage remains a GC object.
Every alias retains that same root.

The managed root remains valid when retained by a closure or saved
continuation: GC follows the reference when control lowering unwinds the
Wasm activation. Existing restrictions on storing linear values in shared
cells still apply; managed lifetime alone is not a resource-finalization
policy.

Exact allocation syntax and automatic versus explicit reads remain open.
Tests must establish GC-backed storage for local allocations, two aliases
observing writes across a call, and a place retained across a suspension.
The Place/Ref distinction is identical in each case.

### Array element places

A dynamic array index is runtime data. The static path records an indexing
step, but not the index's value: `array[i]` and `array[j]` have the same
concrete place type when their array types agree. They carry different
indices. An indexed place therefore contains the selected array reference
and index, while its path description still disappears during
specialization. No specialization is generated for each numeric index.

There is at most one dynamic index per place, and its indexing step is
the leaf. Native array elements cannot contain inline struct fields, so a
place cannot continue through fields inside an array element. Reaching
through an element that holds an explicit reference reads that reference
and establishes a new root. For an array of arrays, selecting `a[i][j]`
first reads the inner array at `i`; the resulting element place retains
only the inner array and `j`. This is a property of each resulting place,
not a limit on the number of indexing expressions in source code. Reads
used to obtain a new root still perform their declared effects.

Evaluate the receiver and index once, check bounds when constructing the
place, and retain the selected fixed-length array. Later reads and writes
use that reference and index; bounds checks may be removed only when their
validity is proved. No unchecked truncation of a source integer to a Wasm
index is permitted. A reference stored in an element is a value: reaching
through it requires a dereference step whose construction retains the
selected target. Updating that element later does not retarget an already
constructed place into the old target.

Growable containers need a separate invalidation or stable-storage rule;
a saved element place must not silently follow a reallocated buffer.
Enum payload projection also needs a case-validity rule. Neither extension
is implied by ordinary struct projection or fixed-array indexing.

### Native array layout contract

Arrays admit only element types explicitly supported by the native Wasm
array representation. Arrays of struct values are compile-time errors,
including single-field structs; this deliberately tightens today's
`Unboxed` exception for a one-slot struct. The compiler must not silently
box elements, transpose a record into several arrays, or pack heterogeneous
fields into bytes to make such an array compile.

Scalar and packed element types use their declared native storage mapping.
Explicit managed-reference elements remain possible, with their indirection
visible in the source type. A reference capability is not itself an element
representation: an array of `impl Ref T` cannot erase heterogeneous place
types. A concrete place may be an element only when its representation is
one supported native reference; an array-element place carrying both a root
and an index does not qualify. Source struct values remain rejected even
when an implementation could box them into references.

This guarantees the representation category and absence of hidden element
boxing or layout conversion. Physical GC object headers, byte offsets and
alignment are still engine choices; native WasmGC storage does not expose a
C-compatible memory layout. Future inline aggregates would require an
explicit extension of the array contract, not a silent change in layout.

The WasmGC [post-MVP nested-data design](https://github.com/WebAssembly/gc/blob/main/proposals/gc/Post-MVP.md#nested-data-structures)
sketches inline arrays of structs and interior references. At the time of
this review it is not listed as an active staged proposal in the
[proposal tracker](https://github.com/WebAssembly/proposals); the design
must not depend on a delivery date. The active
[Multibyte Array Access proposal](https://github.com/WebAssembly/multibyte-array-access/blob/main/proposals/multibyte-array-access/Overview.md)
addresses wider accesses through numeric arrays, not arbitrary inline
aggregates containing managed references.

### Implementation evidence

Checking must produce structured path evidence and preserve the concrete
place type through substitution, interfaces and monomorphization. Lowering
must consume that evidence instead of recovering writable storage from the
syntax of a getter call. Keep root and dynamic-index evaluation order,
GC liveness and aliasing rules beside the code that implements them.

Acceptance tests must pass a root place and distinct field places to one
generic consumer, retain a place across root replacement, and read and
write checked array-element places with runtime indices. Rejections must
cover computed getters used as storage, inconsistent target types,
implicit place erasure, linear cell contents, every struct-array shape
and indexed places used as native array elements. Execute linked Wasm and
inspect the relevant lowering to establish that field-only places retain
only a root and that access uses static field indices. Bootstrap and
compiled execution must agree.

## Foreign functions

`extern` declares a total foreign function; the declaration is the boundary's
unsafe assumption.

A foreign call may take a final `String` or `Bytes` argument. The compiler
copies it into the runtime's staging buffer just before the call. A String
arrives as its Unicode scalar count, with four bytes per scalar in staging.
Bytes arrive as an `i32` address: a little-endian `u32` length followed by
that many packed bytes. The host reads the current memory buffer and copies
any bytes it retains before returning or awaiting; later calls reuse staging.
Imports are leaves and must not call back into Snail-Core while reading staging.

An exposed function passes scalars directly and managed values as opaque engine
references. JavaScript can retain those references and pass them to synchronous
Wasm constructors/projectors, but cannot inspect their fields or substitute a
JavaScript object, string or typed array. Exposed `String` and `Bytes` are managed
arrays; the staging convention above applies to calls into foreign imports.
Affine values, including records that contain them, cannot cross this unrestricted
boundary. Exposed signatures remain monomorphic and their effects need host bindings.
A function export may infer its concrete signature. Its effect row stays available
for instance solving rather than being generalized; ordinary value-type variables
still generalize, so an unannotated generic identity function cannot be exposed.
The host must respect the declared Snail-Core types: Wasm representation checks do not
prove nominal identity or permit treating immutable `Bytes` as a mutable `Array`.

An exposed `(Option Any)` crosses as `null` for `None` or the opaque `Any`
payload for `Some`. The wrapper converts at the boundary; internal Options
keep their normal enum representation. Plain `Any` remains non-nullable.
This exception applies only to exposed parameters/results; a host import
returning `(Option Any)` still expects its ordinary enum. A host builds no
managed value for a typed host operation: its imports take and answer
scalars, and the library builds the result from them, in the waiting task's
own call ([the native boundary](../runtimes/networking.md#wasm-boundary)).
A task's handlers are evidence its saved frames hold, so nothing about them
crosses the host. See
[waiting on the host](../runtimes/tasks.md#waiting-on-the-host).

`unsafe-cast` is unchecked, like `unsafe-total`
([local mutation](effects.md#local-mutation)): it turns a `Funcref`, a
function another module exports, into a function of whatever type the
context expects (`(snail shell wasm)`). `dynamic-cast` is its checked
counterpart, for a function a plugin exposes with `dynamic`: it makes the
function only if the policy it is given accepts the signature of the
expected type ([plugins](compilers.md#plugins)).

## Linked files

`(snail shell resource)` ties a file to a library as one of its dependencies
instead of embedding it, as Python's `importlib.resources` addresses a
package's data, and the library reads it when it needs it:

```scheme
(import
 (snail core base)
 (only (snail shell task) tasks)
 (snail shell resource))


(define hero (→ Resource) (link-file "art/hero.png"))


(define (hero-bytes) (→ Bytes) (! resource tasks)
  (read-resource hero))
```

- **Found beside the library.** The path is relative to the file the form is
  written in, as `include-bytes`'s is, a `generate-library` recipe's for a
  producer's own forms, and may not leave its directory: `.`
  and `..` are resolved, and an absolute path, an empty name or a path that
  climbs out is an error. A file that is missing fails the build with the
  library and the path.
- **Shipped by content.** The build places the file as an object of the
  program's store, at `STORE/sha256/DIGEST`, where DIGEST is the SHA-256
  of its bytes in hex, in every build that produces one: project program
  and browser targets, `scripts/snail-tool run` and `compile`, and the
  development loop. A linked program's store is `store/` beside
  `program.wasm`; a per-library build's `modules.json` names its store,
  relative to itself, and lists each object with its size. The name is
  never a path or a library's: libraries that link the same bytes ship one
  object, an object is written once and never rewritten, and a file's name
  changes exactly when its bytes do. The module itself records what it
  links: `link-file` becomes a call to an import from `snail.runtime.link`
  named for the digest, which answers the file's handle. Editing a linked
  file therefore compiles again the library that links it, and its
  importers, whose modules name the new digest.
- **A handle, not the bytes.** `link-file` evaluates to a `Resource`, which
  names a file and nothing more. The type is exported without its
  constructor, so a program cannot make one from a string: holding a
  `Resource` is evidence that its file ships. `(read-resource r)` returns the
  file's `Bytes` and performs `resource`, an effect with host defaults on
  Node, in the browser and on wasmtime. It is not `fs`: a page has no
  filesystem, and a program with none still reads its own files.

**A file is read when the program asks for it.** A host reads nothing a
module links when it instantiates the module. `read-resource` waits for the
host as a task does (`through-host` in `(snail shell task)`), so it performs
`tasks` and runs in a task. The first read of a file reads it, Node and
wasmtime from the payload's directory and the browser by fetching beside the
page's module, and later reads of it from the same module return the same
bytes. A file the program never reads is never fetched, so a library may link
far more than any one program uses. A file that cannot be read traps the task
that reads it. The bytes under a digest never change, so a host keeps what it
has read by digest: a module linked again reads a file it still links without
fetching it, and an edited file, under its new digest, is read anew. For the
same reason a server may let a browser cache the store for good, as the
development server does.

## Dynamic values

### Inferred boundaries and dynamic instances

Typed libraries should retain their signatures when called from dynamic
code. A dynamic caller need not repeat a callee's parameter types or use a
special application form. At an expected-type boundary the checker inserts
the same `type-convert` that a programmer could write:

| Expected | Actual | Checked program |
| --- | --- | --- |
| `T` | `T` | The value itself. |
| `Any` | An eligible concrete `T` | Package the value. |
| A concrete `T` | `Any` | Check the payload at run time; requires `dyn-cast`. |
| A concrete `T` | A different concrete `U` | A compile error. |
| An inference variable | Any type | Ordinary unification, without inventing a cast. |

These boundaries are arguments, annotated expressions and definitions,
Boolean conditions, type-test operands, and results checked against
function or handler signatures. Constructors use the argument rule for
their fields. Structural unification is unchanged:
`List Any` does not become `List I64`, and function types do not acquire
adapters. Branches of an unannotated conditional must still agree.

Concrete arguments constrain shared parameter variables before `Any`
arguments are fitted, without changing evaluation order. If `choose`
takes two arguments of one type, both `(choose boxed 1)` and
`(choose 1 boxed)` select that type as `I64` and check `boxed`. With only
`Any` arguments the type remains `Any`. A result annotation checks the
result; it does not retroactively choose the callee's instantiation.
Numeric literals retain their numeric constraints across a conversion:
an integer packaged into `Any` defaults to `I64`, never to `Any`, unless
another use gives that literal a concrete numeric type.

No failed constraint silently becomes `Any`. An unresolved inference
variable, a quantified parameter and a runtime package remain different
things. The existing restrictions on erasing linear values, function
references and effectful functions apply to inserted conversions too.

A class at `Any` needs an instance just as a class at any other type does.
An explicit finite dispatcher supplies one:

```scheme
(typeclass (Describe e T)
  (: describe (impl (Fn T → String ! e))))

;; Declare pure instances (Describe (!) I64) and (Describe (!) String) first.
(instance (Describe (! dyn-cast) Any)
  (dispatch I64 String))
```

The compiler builds each method from type tests, checked conversions and
ordinary typed calls. The first argument of the erased class type selects
a concrete branch. All arguments of that class type are checked against
the same concrete type, and a result of that type is packaged back into
`Any`. An unsupported payload or mixed argument types fail through the
usual conversion check; there is no numeric promotion. The selected
branch carries the ordinary static instance evidence. No global registry,
runtime specialization or hidden host dependency is introduced.

The dispatcher is an ordinary method: its caller evaluates the arguments
before entering it. Its internal checks run in that method's body.

The constraint `Describe (! dyn-cast) Any` is solved at compile time to this adapter;
the payload is checked when a method is called. A generic function that
never calls a method does not inspect its argument merely because it has
a `Describe` requirement. This is an instance for `Any`, not implicit
unpacking of an existential concrete type at every constrained call.

The list is explicit and belongs to the declaring library. Adding another
instance elsewhere does not change it. Compound ground types, such as
`(List I64)`, may be listed if their ordinary instances exist. The normal
overlap rule still applies: an explicit `Describe (! dyn-cast) Any` and a dispatched
one cannot coexist.

For this first version, the instance head has exactly one `Any` argument;
other types and effect rows are closed. Each method needs a direct input
of the erased class type, and that type may occur only as a whole
parameter or result. Independently polymorphic methods and extra method
constraints need explicit implementations. These restrictions avoid
inventing higher-order wrappers, container traversals, or result-directed
runtime selection. `Drop` and `Clone` use their existing ownership rules,
not dynamic dispatch.

Effects are checked over every branch. For example, an instance
`(Store (! console dyn-cast) Any)` may dispatch to pure and console-performing
stores; `(Store (! dyn-cast) Any)` cannot dispatch to a store that prints.
Every finite dispatcher needs `dyn-cast` for unsupported payloads. Calls
perform the declared row under the caller's handlers. A payload's type
does not grant permission to perform an undeclared effect.

The Scheme translator now uses these boundaries through `Any` and a nominal
procedure wrapper with a fixed effect signature ([dynamic Scheme](macros.md)).
This does not generalize local bindings or permit direct erasure of effectful
function types.
Catchable conversion failure uses the same ownership cleanup as other
abortive effects ([cleanup](ownership.md#drops-that-may-run)).

### Finite asymmetric adapters

A named set can generate adapters for an explicitly listed relation of
concrete operand types:

```scheme
(with-instances (arithmetic-base inexact-promotion)
  (define-instance-set dynamic-addition
    (dynamic-instances Add
      (Integer Integer)
      (Integer F64)
      (F64 Integer)
      (F64 F64))))
```

Source instances must already be declared and active at the generator's
definition. The generator records their implementations. Later declarations
and callers' policies cannot change its branches. Duplicate or missing
pairs fail at compile time. The relation need not be a Cartesian product:
listing `(Integer F64)` and `(F64 Integer)` does not admit `(F64 F64)`.

For each fixed right operand it generates `(Any, Right)`, for each fixed
left operand `(Left, Any)`, and one `(Any, Any)` instance. Each head's output
is the common branch output when all agree, otherwise `Any`. In the example,
`(Any, F64)` and `(F64, Any)` return `F64`; the other generated heads return
`Any`. The caller never boxes arguments just to find an instance.

Both arguments finish evaluating, once and in source order, before the
adapter tests their type identities. Only the selected branch converts
values and calls its recorded implementation. Unsupported payloads or
unlisted pairs perform catchable `dyn-cast`. Source-method effects propagate
normally and do not trigger another branch attempt. Every generated head's
row contains `dyn-cast` plus the union of its eligible source rows; handlers
or signatures must account for that whole row.

The initial generator supports binary classes with one row, one associated
output, and methods of type `(dyn (Fn A B → Output ! e))`. Independently polymorphic
methods, extra method requirements, and source-instance prerequisites are
rejected. Both listed inputs must be ground, non-`Any` types that can cross
the existing erasure boundary. Heterogeneous results must also support
boxing. It does not convert container elements or wrap functions.

Generated heads follow the ordinary overlap rule. Separate generators for
the same class both produce `(Any, Any)`, so activating both is an error;
the compiler does not merge their domains. `(snail shell arithmetic dynamic)`
exports `dynamic-arithmetic`, generated from the complete nine-pair relation
over `Integer`, `Rational`, and `F64` for all four arithmetic classes.
Importing that library still requires explicit activation of its set.

### Explicit dynamic values

`Any` holds an unrestricted value together with its type's identity.
Linear values cannot cross this boundary. Nor can a function that performs
effects, wherever it sits in the value's type, or a rigid type variable
that might stand for one: type identities do not record effect rows.
This restriction applies to `type-convert`, `try-convert` and `type-test`.
It also excludes a bare `fn` code reference; a pure closure can be packaged.

`(type-convert e Any)` packages a value. Conversion to the same type,
including `Any` to `Any`, preserves it. Neither operation needs `dyn-cast`.
An unconstrained inference variable still unifies normally: casting an
unannotated parameter to `I64` infers an `I64` parameter. Annotate the
input `Any` when a runtime conversion is intended.

Extracting a concrete `T` from `Any` checks its identity and representation.
A mismatch performs the abortive operation
`(conversion-failed error)` of `dyn-cast`; it does not panic.
The rule is identical for explicit syntax and compiler-inserted checks.
At a call's concrete parameter boundaries, inserted checks run left to
right, before evaluating the following argument.

The ordinary effect rules apply. An inferred function acquires `dyn-cast`;
a closed signature must declare it or handle it inside the body. A function
may declare it without being defined inside a handler. Its callers must
handle or propagate it, and an unhandled effect at a Core entrypoint is a
compile error. A handler for some other effect, including a user-defined
`exn`, does not grant this permission. A handler can explicitly translate
`dyn-cast` to another effect.

```scheme
(define (integer (value Any)) (→ I64) (! dyn-cast) value)

(handle dyn-cast ((conversion-failed (lambda (_) -1)))
  (integer "not an integer"))
```

The handler returns a fallback for the whole handled computation; it
receives no resumption. Earlier effects remain visible. Cleanup of
abandoned owners completes before the handler runs.

`(try-convert value T)` is nonthrowing inspection. It returns
`(Result T CastError)`, with the already checked value in `Ok`, and does
not require `dyn-cast`. The target must be eligible and reifiable where the
form is written. Unlike a Boolean `type-test`, its successful result needs
no second cast. The effects of evaluating `value` still apply.

`CastError` carries `reason`, `expected` (readable target types),
`actual` (the existing numeric type identity), and `origin` (source
location). A dispatch failure also supplies `method` and a zero-based
`argument` index; ordinary conversion uses an empty method and `-1`.
Reasons are `TypeMismatch`, `UnsupportedInstance`, and `ArgumentMismatch`.
A single-parameter dispatcher reports its complete domain. A binary adapter
reports accepted types for the failed operand; when its left type is known,
that restricts the expected right types. Dispatch origins
name the adapter declaration; ordinary checks name the source boundary.
Errors do not retain the payload for diagnostics.

`(snail core dynamic)` provides `try-dynamic`, which handles a thunk's
`dyn-cast` failures as a `Result`, `cast-error->string`, and `run-dynamic`,
which additionally reports failures through `console`. An interactive
caller can use this explicit boundary once per evaluation and continue
after an `Err`; a script decides its exit status from the result. No host
implicitly enables `dyn-cast`. Generated Scheme scripts explicitly wrap each
top-level evaluation with `scheme-evaluate`, which reports a failure as a
script error. Direct runtime calls remain catchable by their caller; there
is no interactive evaluator yet.

A type identity includes fields and cases: changing a struct's fields
changes its identity, even when its name stays the same. A relinked program
cannot interpret an old value as the new type. A proven successful
`T → Any → T` may be optimized away. `Any → T → Any` must preserve the
narrowing check. Optimization never removes `dyn-cast` from an already
checked function's contract.
