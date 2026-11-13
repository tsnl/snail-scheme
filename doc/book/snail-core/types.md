# Types

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` packages an eligible dynamic value, recovered through a checked
conversion ([dynamic values](#dynamic-values)).
`String` is a sequence of Unicode scalars. `(Vector T)` is a mutable, growable
sequence. There is one vector type, with a runtime length: no `Array`,
`MutVector`, fixed-length type parameters, dependent lengths or immutability
checks. Primitives occupy unboxed slots; records, enum cases and nested vectors
occupy reference slots. Records need no special layout or `Unboxed` constraint.
`Bytes` is an alias for `(Vector U8)`, stored packed and mutable like any vector.

`(vector)` constructs an empty vector; `make-vector` and `vector-generate`
construct an initial sequence. `vector-ref` reads an element and `vector-set!`
replaces it. `vector-push!` appends, and `vector-pop!` returns `Some` of the last
element or `None` when empty. Every alias observes writes, growth and removal.
Indices and copy ranges are checked against the current length, not spare capacity.

`vector-copy`, `subvector` and `vector-append` create fresh mutable vectors and
copy their elements shallowly. `vector-set` is the copying replacement operation;
`vector-copy!` overwrites a destination range and supports overlap. None freezes
its result. `vector-for-each` and `vector-fold` check the current length at each
step, so callback mutation can change which elements are visited. `vector-map`
uses the initial length. String/vector conversions copy character storage in both
directions: changing the vector cannot change the string.

A byte vector literal, `#u8(137 80 78 71)`, embeds exactly those bytes.
`(include-bytes "pixel.png")` reads bytes relative to its source file during
reading; macros cannot compute that path. Use [linked files](#linked-files)
for large assets that should be read on demand.

A reusable closure has type `(Fn Param ... → Result)`, with an optional
[effect row](effects.md) after `!`. A consuming closure has type
`(FnOnce Param ... → Result)`. Lowercase `(fn Param ... → Result)` is a
noncapturing code pointer. These are built-in type formers, with the same
spellings in arguments, fields, collections and results; there is no `dyn`,
`impl`, `FnMut` or callable-class hierarchy.
A named function carries its type where it is defined. Every parameter has a
mandatory `(name Type)` annotation, and every named function must state its result
with `(→ Result)`. Optional effect, generic-variable, constraint and
documentation clauses follow the parameter list at the start of the
definition, before its body:

```scheme
(define (map-with (function (Fn A → B ! e)) (values (List A)))
  (→ (List B))
  (! e)
  (∀ A B e)
  (⊨ (Copy A) (Copy B))
  (map function values))
(define (sum (zero T) (values (List T)))
  (→ T)
  (! e)
  (∀ T e)
  (⊨ (Num e T))
  (fold-left + zero values))
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

Local bindings remain monomorphic. Put explicit quantifiers on reusable
generic definitions. A library is checked before its importers, so a use in
another library never determines an exported value's type: `(define key-left 1)`
is `I64`; an `I32` constant needs `(define key-left (→ I32) 1)`.

## Compile-time values

A top-level form declares a function, type, macro, class, effect or other
compile-time definition. Runtime expressions belong in functions. A program
starts by calling its root `main`; importing a library executes no source
initializers. In particular, top-level `set!`, printing, opening a resource
and scheduling work are errors.

A value definition such as `(define size (→ I64) (+ 20 22))` must be
effect-free and fully evaluable by the compiler. Values are forced when
needed, independently of source order. Forcing a value already being forced
reports the cycle. Recursive function definitions remain ordinary code;
recursion is not a constant-forcing cycle.

Each read of an aggregate constant constructs a fresh object graph. Aliases
and mutable cycles *inside* that graph are preserved. Two reads share no
writable state, including through closure captures, vectors, `Rc` or `WeakRc`.
For example, mutating a record obtained from `origin` below does not change
a later read of `origin`:

```scheme
(struct Point
  ((x I64)
   (y I64)))
(define origin (→ Point) (Point 0 0))
```

Effect-free initialization can call pure functions, perform local mutation
inside a justified `unsafe-total`, and handle effects locally. The evaluator
uses the same ownership and cleanup decisions as runtime code. It supports
the compiler's deterministic scalar services, not arbitrary foreign calls or
host I/O. It bounds evaluation at ten million steps and one million heap
cells, reporting a compile error on exhaustion. Emitting a fresh runtime graph
has a separate limit of 512 construction steps: one per object and one per
field or element. Packed byte vectors emit as data segments, so their bytes do
not count as individual construction steps. Larger intermediate values can still
be computed and reduced to a small result. Use an ordinary runtime function to construct a larger
returned graph; runtime vectors have no fixed size. This emission limit protects
recursive compiler passes and is an implementation limit, not a type rule.
Linear top-level values are
rejected; a function can construct a fresh linear owner when called. An
unfinished interpreter resumption cannot escape into a constant.

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

Every struct and every enum case with fields is a heap object. Its fields
are mutable by default; there is no per-field mutation annotation. A struct
`Name` defines its constructor and three operations per field:

| Operation | Result |
| --- | --- |
| `(Name-field-set record value)` | A shallow replacement record; other fields keep their existing object references. |
| `(Name-field-set! record value)` | Updates the existing object and releases the previous field; performs `mut`. |
| `(Name-field-replace! record value)` | Updates the object and returns the previous field; performs `mut`. |

Read struct fields by path: `(● segment from x)`. Each step follows an
ordinary object reference. Reads are pure. `(set! (● segment from x) 3)`
and `(replace! (● segment from x) 3)` use the same resolved slots, evaluating
the receiver and incoming value once. `Rc` transparently exposes its payload's
struct fields. There are no field typeclasses, computed property overloads,
or borrowed receiver types.

Enum cases are constructors, not types, and are always applied: `(Empty)`.
A case provides partial accessors such as `Circle-radius`; selecting the
wrong case traps. `Circle-radius-set!` updates that case's field, and
`Circle-radius-replace!` returns its previous value. These operations also
check the case and perform `mut`. Pattern matching establishes which case
is present. A
field path requires a nominal struct receiver, so it cannot guess an enum
case from a label.

An aggregate containing a linear member is itself linear. A field read may
copy an unrestricted value; taking a linear field out requires consuming the
record by matching it or replacing the field with another owner. See
[ownership](ownership.md) for exact-once use, mutable access through `Rc`, and
compiler-managed finalization.

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
  (: describe (Fn T → String)))

(instance (Describe (List T))
  (⊨ (Describe T))
  (define describe
    (lambda (items) (string-join (map describe items) ", "))))
```

The checker chooses each instance when it checks a use and records that
choice; monomorphization copies the chosen method for each type, so no
dictionary exists at run time. Active instance heads must not overlap on their
input parameters. User-defined classes have
no superclasses: a signature lists every class it needs. Unbound names in an
instance head are its type variables.

### Rows as parameters

A class may take a row as a parameter. A parameter its methods write after
`!` is a row, and the others are types. Each instance writes its row in its
head, so the instances of one class may perform different effects:

```scheme
{{#include ../../../tests/programs/classes-effects.sld:store}}
```

A use performs what its instance's head says. Reading a `Directory`
prints, so `fetch-twice` at a `Directory` performs `output-port`; at a `Table`
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
`(Logged Directory)`, `log` and `output-port`. Ordinary class rows may name control
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

`Repr` is a pure class with one type parameter: `(Repr T)` supplies
`(repr value) → String`. `(snail core io)`'s `write` prints that
representation through `output-port`. Structs and enums can generate instances
with `(deriving Repr)`; see [current ports](libraries.md#current-input-and-output-ports).

### Associated output types

A class can declare ordinary associated types. Each instance defines them:

```scheme
(typeclass (Add e A B)
  (type Output)
  (: add (Fn A B → Output ! e)))

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
in sets, and the compiler's structural `Copy` rule remains unchanged.

### Numeric libraries

Primitive numeric types remain distinct. `(snail shell integer)` supplies
arbitrary-precision integers, and `(snail shell rational)` supplies rationals.
Their constructors and operations are ordinary typed APIs. There is no
standard dynamic numeric tower, implicit widening, or value-dependent switch
between integer and rational result types. Typeclasses and associated
outputs remain available for a library that explicitly needs mixed operands.

## Effects

Every function type has an effect row, the effects calling it may perform,
and a function without `!` is total. [Effects and handlers](effects.md)
covers rows, their inference and polymorphism, local mutation, declaring
and handling effects, control operations with a one-shot `resume`, latent
rows and defaults.

## Functions

`Fn` is reusable and may capture unrestricted values, including mutable
records and `Rc` owners. Copying the closure retains its shared captures;
leaving the last owning scope releases them. Mutation and effects are
independent of how often a closure can be called.

```scheme
(define (twice (function (Fn I64 → I64)) (value I64)) (→ I64)
  (function (function value)))
```

`FnOnce` is linear. Calling it transfers its captures into its body; dropping
it without a call releases those captures. `once` converts a closure to the
corresponding one-shot type without changing its parameters, result or row.
A source once-lambda can move linear captures directly:

```scheme
(struct Job
  ((run (FnOnce I64 → Unit ! output-port))))

(define (greeting (text String)) (→ (FnOnce → Unit ! output-port))
  (once (lambda () (write-line text))))
```

An alias of a reusable closure remains callable after another alias has been
converted with `once` and called or dropped. The wrapper owns that one counted
reference, not every alias of the environment. A handler's `resume` is also a
`FnOnce`; there are no source loans or borrow restrictions on storing it.

### Code pointers

`(fn A → B ! e)` is a noncapturing code pointer. A `fn` expression or a
named top-level function can provide it; a capturing lambda cannot. Its
representation remains separate at storage and foreign boundaries. Wrap a
code pointer in a lambda when a `Fn` closure is needed.

## Foreign functions

`extern` declares a total foreign function; the declaration is the boundary's
unsafe assumption.

A foreign call may take a final `String` or `Bytes` argument. The compiler
copies it into the runtime's staging buffer just before the call. A String
arrives as its Unicode scalar count, with four bytes per scalar in staging.
Bytes arrive as an `i32` address: a little-endian `u32` length followed by
that many packed bytes. The host reads the current memory buffer and copies
any bytes it retains before returning or awaiting; later calls reuse staging.
Imports are leaves and must not call back into Snail Scheme while reading staging.

An exposed function passes scalars directly and managed values as opaque engine
references. JavaScript can retain those references and pass them to synchronous
Wasm constructors/projectors, but cannot inspect their fields or substitute a
JavaScript object, string or typed array. Exposed `String` and `Bytes` are opaque
managed references; the staging convention above applies to calls into foreign imports.
Affine values, including records that contain them, cannot cross this unrestricted
boundary. Exposed signatures remain monomorphic and their effects need host bindings.
A function export may infer its concrete signature. Its effect row stays available
for instance solving rather than being generalized; ordinary value-type variables
still generalize, so an unannotated generic identity function cannot be exposed.
The host must respect the declared Snail Scheme types: Wasm representation checks do not
prove nominal identity or permit treating a `String` as a `Vector Char`.

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
  (: describe (Fn T → String ! e)))

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
`(Store (! output-port dyn-cast) Any)` may dispatch to pure and output-performing
stores; `(Store (! dyn-cast) Any)` cannot dispatch to a store that prints.
Every finite dispatcher needs `dyn-cast` for unsupported payloads. Calls
perform the declared row under the caller's handlers. A payload's type
does not grant permission to perform an undeclared effect.

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

The generator supports binary classes with one row, one associated
output, and methods of type `(Fn A B → Output ! e)`. Independently polymorphic
methods, extra method requirements, and source-instance prerequisites are
rejected. Both listed inputs must be ground, non-`Any` types that can cross
the existing erasure boundary. Heterogeneous results must also support
boxing. It does not convert container elements or wrap functions.

Generated heads follow the ordinary overlap rule. Separate generators for
the same class both produce `(Any, Any)`, so activating both is an error;
the compiler does not merge their domains. No standard numeric tower or
implicit promotion policy is installed. Prefer concrete numeric types and
ordinary typed calls; `Integer` and `Rational` remain explicit libraries.

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
handle or propagate it, and an unhandled effect at a program entrypoint is a
compile error. A handler for some other effect, including a user-defined
`exn`, does not grant this permission. A handler can explicitly translate
`dyn-cast` to another effect.

```scheme
(define (integer (value Any)) (→ I64) (! dyn-cast) value)

(define (example) (→ I64)
  (handle dyn-cast ((conversion-failed (lambda (_) -1)))
    (integer "not an integer")))
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
which additionally reports failures through `output-port`. An interactive
caller can use this explicit boundary once per evaluation and continue
after an `Err`; a script decides its exit status from the result. No host implicitly enables `dyn-cast`; a caller decides where to handle
conversion failure. There is no dynamic Scheme compatibility layer or
interactive evaluator.

A type identity includes fields and cases: changing a struct's fields
changes its identity, even when its name stays the same. A relinked program
cannot interpret an old value as the new type. A proven successful
`T → Any → T` may be optimized away. `Any → T → Any` must preserve the
narrowing check. Optimization never removes `dyn-cast` from an already
checked function's contract.
