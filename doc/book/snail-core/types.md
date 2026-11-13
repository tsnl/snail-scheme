# Types

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` explicitly packages an eligible value; `downcast` attempts to recover its
exact type ([explicit Any](#explicit-any)).
`String` is a sequence of Unicode scalars. `(Vector T)` has a fixed runtime
length and mutable elements. There is one vector type, with no `Array`,
`MutVector`, type-level lengths, dependent types or immutability checks.
Primitives occupy unboxed slots; records, enum cases and nested vectors occupy
reference slots. `Bytes` is an alias for `(Vector U8)`, stored packed.

`(vector)` constructs an empty vector; `make-vector`, `vector-generate` and
`list->vector` construct fixed-length vectors. `vector-ref` reads an element
and `vector-set!` replaces it. Every alias observes writes. Indices and copy
ranges are checked at their full integer width before conversion to Wasm indices.
There are no push, pop, resize or capacity operations.

`vector-copy`, `subvector` and `vector-append` create fresh mutable vectors and
copy their elements shallowly. `vector-set` is the copying replacement operation;
`vector-copy!` overwrites a destination range and supports overlap. Iteration
visits the vector's fixed extent; callbacks may change its elements.
String/vector conversions copy character storage in both directions, so changing
the vector cannot change the string. Use lists to accumulate values of an
unknown count, then convert once when indexed access is needed.

A byte vector literal, `#u8(137 80 78 71)`, embeds exactly those bytes. Use
[linked files](#linked-files) for external assets. A library producer may read a
linked resource and emit a byte literal when embedding is appropriate; the
reader performs no file inclusion.

A reusable closure has type `(Fn Param ... → Result)`, with an optional
[effect row](effects.md) after `!`. A consuming closure has type
`(FnOnce Param ... → Result)`. Lowercase `(fn Param ... → Result)` is a
noncapturing code pointer. These are built-in type formers, with the same
spellings in arguments, fields, collections and results; there is no `dyn`,
`impl`, `FnMut` or callable-class hierarchy.
A named function carries its type where it is defined. Every parameter has a
mandatory `(name Type)` annotation, and every named function must state its result
with `(→ Result)`. Optional effect, generic-variable and constraint clauses follow the parameter list at the start of the
definition, before its body:

```scheme
(define (map-with (function (Fn A → B ! e)) (values (List A)))
  (→ (List B))
  (! e)
  (∀ (A B e))
  (⊨ (Copy A) (Copy B))
  (map function values))
(define (sum (zero T) (values (List T)))
  (→ T)
  (! e)
  (∀ (T e))
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

## Lazy runtime values

A top-level form declares a function, type, macro, class, effect or value.
Top-level statements such as `set!`, printing and scheduling work are errors;
a program starts by calling its root `main`. Importing or linking a library
runs no source initializer.

A value definition such as `(define size (→ I64) (+ 20 22))` must have an
empty effect row. Its ordinary compiled initializer runs on the first read,
independently of source order. The defining module instance caches the result
and every later read returns that same value. Reentering an initializer before
it finishes panics with the binding's name. An unused cycle never runs.
Recursive function definitions remain ordinary code, outside this guard.

Records, vectors and closure captures are shared across reads. For example,
changing `origin` below changes the object observed by every later read:

```scheme
(struct Point
  ((x I64)
   (y I64)))
(define origin (→ Point) (Point 0 0))
```

Initializers may call pure functions and handle effects locally. Private
mutation can be hidden inside a justified `unsafe-total`; that assertion does
not make mutation of a shared global pure. Runtime work with an observable
effect belongs in a function with its effect row declared. There is no separate
interpreter, freezing step or constant-evaluation budget.

Linear globals are rejected. A cache may own an `Rc`, including one wrapping
a linear resource. Each read retains its own credit; dropping that credit
does not release the cache's owner. Replacing a counted field releases its
previous value normally. Cache roots last for the module instance's lifetime.
WasmGC collection and module replacement do not run source finalizers; host
resource cleanup still runs at the owning run's teardown. An old closure kept
across a relink may keep accessing its original cache. A new module instance
starts with empty caches, so persistent application state belongs in Save.
These WasmGC values are not shared between threads, so guards need no mutex.

Polymorphic functions and their aliases remain supported. A quantified value
may also be a scalar/string literal or a nullary enum template, such as
`(define empty (→ (List A)) (∀ (A)) (Nil))`. These have no mutable state to share.
Other polymorphic values are rejected: specializing an allocating value in
each importer would give separate compilation different sharing semantics.
Use a zero-argument generic function for fresh values, or concrete monomorphic
value definitions for shared state. Byte vectors and empty growable vectors
are mutable objects, not stateless templates.

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
`Name` defines its constructor and pure `Name-field-set` operations, which
produce shallow replacement records. It generates no field getters or mutable
setter functions.

Read struct fields by path: `(● segment from x)`. Each step follows an
ordinary object reference. Reads are pure. `(set! (● segment from x) 3)`
and `(replace! (● segment from x) 3)` use the same resolved slots, evaluating
the receiver and incoming value once. `Rc` transparently exposes its payload's
struct fields. There are no field typeclasses, computed property overloads,
or borrowed receiver types.

Enum cases are constructors, not types, and are always applied: `(Empty)`.
Use `match` to select an enum case and bind its fields. There are no generated
case getters or mutable setters. A field path requires a nominal struct receiver;
for mutable enum payloads, store a struct in the case and access its fields after
matching.

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
effects; specialization and control lowering preserve them. `Drop` is also a class over a row
([releasing](ownership.md#releasing)), derived from the type's structure when
it has no instance. Cleanup must finish, so its row cannot contain control effects.

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
  (∀ (A B e))
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
  (∀ (A e))
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
  written in, or the `generate-library` recipe's directory for a
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

## Explicit Any

`(Any value)` boxes a value with its concrete type identity. `(downcast T boxed)`
returns `(Option T)`: `Some` holds the recovered value, and `None` reports a
mismatch. Both evaluate their input exactly once. Downcasting does not panic or
perform a conversion effect. Ordinary checking never inserts a conversion:
arguments, results, branches and annotations must agree on their types.

```scheme
(define (read-count (boxed Any)) (→ I64)
  (match (downcast I64 boxed)
    ((Some count) count)
    ((None) 0)))

(define (example) (→ I64)
  (read-count (Any 42)))
```

Boxing preserves the exact input type. `(Any (Any 42))` holds an `Any`, whereas
`(Any 42)` holds an `I64`. Downcasting never converts numbers, container elements,
or function signatures. There are no `type-convert`, `try-convert`, `type-test`,
`dyn-cast`, dynamic instance dispatch, or `(snail core dynamic)` APIs.

A payload must be non-linear and its disposal must be known to be effect-free.
An effectful function, or a generic type that could hide one, cannot cross the
erasure boundary. This also prevents hiding effectful resource finalization.
Pure closures may be boxed; the box owns their counted reference. A successful
downcast retains the recovered payload before releasing its input owner, and a
failed downcast releases the input owner normally.

The type identity includes nominal names, arguments, fields, cases, and nested
function signatures and effect rows. Changed schemas receive changed identities
across relinks, even if their Wasm layouts match. Downcast also checks the Wasm
representation before reading the payload. Type identities are currently 32-bit
hashes; they are not collision-free structural proofs.
