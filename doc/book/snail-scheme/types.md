# Types

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` explicitly packages an eligible value; `downcast` attempts to recover its
exact type ([explicit Any](#explicit-any)).
`String` is a sequence of Unicode scalars. `(Array T)` has a fixed runtime
length and mutable elements. Besides it there is only `(ConstantArray T)`, a
table of scalars nothing can write ([below](#constant-arrays)); there is no
`MutArray`, type-level lengths or dependent types.
Primitives occupy unboxed slots; records, enum cases and nested arrays occupy
reference slots. `Bytes` is an alias for `(Array U8)`, stored packed.

`(array)` constructs an empty array; `make-array`, `array-generate` and
`list->array` construct fixed-length arrays. `array-ref` reads an element
and `array-set!` replaces it. Every alias observes writes. Indices and copy
ranges are checked at their full integer width before conversion to Wasm indices.
There are no push, pop, resize or capacity operations.

`array-copy`, `subarray` and `array-append` create fresh mutable arrays and
copy their elements shallowly. `array-set` is the copying replacement operation;
`array-copy!` overwrites a destination range and supports overlap. Iteration
visits the array's fixed extent; callbacks may change its elements.
String/array conversions copy character storage in both directions, so changing
the array cannot change the string. Use lists to accumulate values of an
unknown count, then convert once when indexed access is needed.

A byte array literal, `#u8(137 80 78 71)`, embeds exactly those bytes. Use
[linked files](#linked-files) for external assets. A library producer may read a
linked resource and emit a byte literal when embedding is appropriate; the
reader performs no file inclusion.

A closure has type `(Fn Param ... → Result)`. This is a built-in type
former, with the same spelling in arguments, fields, collections and
results; there is no `dyn`, `impl`, `FnMut` or callable-class hierarchy,
and no annotation for what calling it does: that is in what the function
was made with ([capabilities](capabilities.md#what-a-signature-does-not-say)).
A typed function header carries its type where it is defined. Every parameter has a
mandatory `(name Type)` annotation, and the header must state its result
with `(→ Result)`. Optional generic-variable and constraint clauses follow
the parameter list at the start of the definition, before its body:

```scheme
(define (map-with (function (Fn A → B)) (values (List A)))
  (→ (List B))
  (∀ (A B))
  (map function values))
(define (sum (zero T) (values (List T)))
  (→ T)
  (∀ (T))
  (⊨ (Num T))
  (fold-left + zero values))
```

A lambda takes the same header, and `(define (name parameter ...) clause
... body ...)` is shorthand for defining one:

```scheme
{{#include ../../../tests/programs/typed-lambdas.sld:lambdas}}
```

A lambda either writes the whole header, every parameter as `(name Type)`
and `(→ Result)`, or annotates nothing and has its type inferred from its
use.

A value definition can carry a type in the same header position, for
example `(define zero (→ I64) 0)`.
Class methods use `declare` with the same typed function header and no
body, for example `(declare (describe (value T)) (→ String))`. A colon
signature is not a language form. Type-level callable signatures use the Unicode `→`;
universal quantification and requirements use `∀` and `⊨`. These are the only
spellings: `->`, `All` and `requires` are not aliases.

Integer literals check against any integer or float type and are
range-checked; float literals check against `F32` or `F64`. A literal whose
type nothing determines defaults to `I64` or `F64`. Numeric values never
change numeric type implicitly: use `i64->i32`, `i32->f64` and the other
conversions. Crossing an `Any` boundary checks the payload's type; it
does not change that type. Integer arithmetic wraps.

Local bindings remain monomorphic. Put explicit quantifiers on reusable
generic functions. A library is checked before its importers, so callers do
not decide its exported definitions' types.

### Constant arrays

`(constant-array TYPE (VALUE ...))` is a table of literals of a scalar type,
`U8`, `I32`, `I64`, `Bool` or `Char`, each checked against it
where it is written. Its type is `(ConstantArray TYPE)`, which has no setter,
so the table is built once in its module, when a use first reaches it, and
every use shares it. `constant-array-ref` and `constant-array-length` read
it as `array-ref` and `array-length` read an array, and
`constant-array->array` copies it into an array of its own.

```scheme
(define powers (→ (ConstantArray I32)) (constant-array I32 (1 10 100 1000)))
(constant-array-ref powers 2) ; 100
```

A table is shared as any [top-level value](#top-level-values) is, and
reading it allocates nothing. A table is a data segment of its elements, so it may be as large as
its data. A float table is a table of the floats' bits, an `I64` table read
through `bits->f64`, since only the assembler knows a float literal's bits. The program
`tests/programs/constant-arrays.sld` exercises each element type.

## Top-level values

A top-level `(define name value)` is a cached thunk. Its initializer runs at
most once in a program, the first time something reads `name`, and every
read shares the result: a record or an array defined this way is one object,
and writes to it are seen by every reader. Types, macros, classes, imports
and exports remain declarations, and a program starts by calling its root
`main`; importing or linking a library runs nothing.

```scheme
{{#include ../../../tests/programs/global-values.sld:values}}
```

- **No capability.** An initializer takes nothing, so it holds no
  capability and reaches nothing of the host's. It may read and write
  mutable objects it can name, so a value computed from one depends on
  when it is first read.
  An initializer that [suspends](suspension.md) keeps nothing, and runs
  again on the next read.
- **Order.** Values are read in the order expressions reach them, whatever
  their order in the source, and one that nothing reads never runs. An
  initializer that reads its own value, directly or through another, panics
  with `initialization cycle`.
- **One type.** A value is not generic, since it is one object. What its
  initializer leaves open, as the element type of `(define empty (Nil))`,
  the uses in its library decide together; when they decide nothing, state
  it with `(→ Type)`. Write a generic one as a function of no arguments,
  `(define (empty) (→ (List A)) (∀ (A)) (Nil))`, which makes a fresh value
  at each call.
- **Functions.** A definition whose initializer is a lambda is a function:
  it is code, with nothing to cache, and may be generic, recursive and
  exposed to the host. Any other initializer makes a value, even when the
  value is a function, as `square` above is; calling it reads the value
  first.

To have a fresh object at each use, write a function that constructs one.
Application state that must survive a restart still belongs in an explicit
Save.

## Data

```scheme
(record (Vec3 T)
  ((x T)
   (y T)
   (z T)))

(enum Shape
  (Circle ((radius F64)))
  (Polygon ((points (List (Vec3 F64)))))
  (Empty))
```

Every record and every enum case with fields is a heap object. Its fields
are mutable by default; there is no per-field mutation annotation. A record
`Name` defines its constructor and pure `Name-field-set` operations, which
produce shallow replacement records. It generates no field getters or mutable
setter functions.

Construct a record with `new`, naming every field exactly once:

```scheme
(new Vec3 (z 3.0) (x 1.0) (y 2.0))
```

Fields may appear in any order. Initializers run once each, from left to right
as written; their names select the destination slots. Unknown, repeated and
missing fields are compile errors. Field types and the expected record type
guide inference, including generic records and callback fields. There are no
defaults or spreads. A visible type alias does not grant access to a hidden
constructor.

Record constructors are used only through `new`. Use an ordinary function or
lambda for a factory, such as `(lambda (x y) (new Point (x x) (y y)))`.
Record patterns remain positional: `(match point ((Point x y) ...))`.
Function arguments remain positional; `new` does not add keyword arguments
to `Fn` or change its calling convention.

Read record fields by path: `(● segment from x)`. Each step follows an
ordinary object reference. Reads are pure. `(set! (● segment from x) 3)`
writes the resolved slot, evaluating the receiver and incoming value once.
There are no field typeclasses, computed property overloads,
or borrowed receiver types.

Enum cases are constructors, not types, and are always applied: `(Empty)`.
Use `match` to select an enum case and bind its fields. There are no generated
case getters or mutable setters. A field path requires a nominal record receiver;
for mutable enum payloads, store a record in the case and access its fields after
matching.

A field read shares the value the field holds; see [values](values.md).

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
  (declare (describe (value T)) (→ String)))

(instance (Describe (List T))
  (⊨ (Describe T))
  (define describe
    (lambda (items) (string-join (map describe items) ", "))))
```

The checker chooses each instance when it checks a use and records that
choice; monomorphization copies the chosen method for each type, so no
dictionary exists at run time. Instance heads must not overlap. Classes have
no superclasses: a signature lists every class it needs. Unbound names in an
instance head are its type variables.

Every class parameter is a type, and all of them together choose the
instance. A class has no associated types: a result type that depends on
the instance is a further class parameter.

An instance's requirements are solved where its head matches. A requirement
that leads back to its own goal, or a chain that keeps growing, is refused
as non-terminating; a requirement at a smaller type, as `(Describe T)` for
`(Describe (List T))`, is ordinary.

Arithmetic and comparison are the classes `Num`, `Ord`, `Integral` and
`Fractional`; `Show` converts values to text. Each takes one type, as in
`(Num T)`.

`Repr` is a class with one type parameter: `(Repr T)` supplies
`(repr value) → String`. `(snail core io)`'s `write` prints that
representation to an `OutputPort`. Records and enums can generate instances
with `(deriving Repr)`; see [ports](../libraries/core.md#ports).

## What a call may do

A function's type does not say. A function reaches the host only through
a capability it holds, and suspends only to a prompt it can name:
[capabilities](capabilities.md) covers the first, and what a signature
leaves out, and [suspension](suspension.md) prompts and their one-shot
`resume`.

## Functions

A closure may capture ordinary values, including mutable records, and may be
called any number of times. [Scoped refs](values.md#call-scoped-refs) are
confined to their function.

```scheme
(define (twice (function (Fn I64 → I64)) (value I64)) (→ I64)
  (function (function value)))
```

A `with-prompt`'s `resume` is an `Fn` too, which may be stored like any
other; the frames it holds run at most once
([resuming once](suspension.md#resuming-once)).

## Foreign functions

`extern` declares a foreign function; the declaration is the boundary's
unsafe assumption.

A foreign call may take a final `String` or `Bytes` argument. The compiler
copies it into the runtime's staging buffer just before the call. A String
arrives as its Unicode scalar count, with four bytes per scalar in staging.
Bytes arrive as an `i32` address: a little-endian `u32` length followed by
that many packed bytes. The host reads the current memory buffer and copies
any bytes it retains before returning or awaiting; later calls reuse staging.
Imports are leaves and must not call back into `snail-scheme` while reading staging.

An exposed function passes scalars directly and managed values as opaque engine
references. JavaScript can retain those references and pass them to synchronous
Wasm constructors/projectors, but cannot inspect their fields or substitute a
JavaScript object, string or typed array. Exposed `String` and `Bytes` are opaque
managed references; the staging convention above applies to calls into foreign imports.
Affine values, including records that contain them, cannot cross this unrestricted
boundary. Exposed signatures remain monomorphic; a parameter whose type the
target provides is a capability the build supplies, and the rest are the host's.
A function export may infer its concrete signature, and then asks its
target for nothing; its type variables still generalize, so an unannotated
generic identity function cannot be exposed.
The host must respect the declared `snail-scheme` types: Wasm representation checks do not
prove nominal identity or permit treating a `String` as an `Array Char`.

An exposed `(Option Any)` crosses as `null` for `None` or the opaque `Any`
payload for `Some`. The wrapper converts at the boundary; internal Options
keep their normal enum representation. Plain `Any` remains non-nullable.
This exception applies only to exposed parameters/results; a host import
returning `(Option Any)` still expects its ordinary enum. A host builds no
managed value for a typed host operation: its imports take and answer
scalars, and the library builds the result from them, in the waiting task's
own call ([the native boundary](../runtimes/networking.md#wasm-boundary)).
A task's capabilities are values its saved frames hold, so nothing about
them crosses the host. See
[waiting on the host](../runtimes/tasks.md#waiting-on-the-host).

`unsafe-cast` is unchecked: it turns a `Funcref`, a
function another module exports, into a function of whatever type the
context expects (`(snail shell wasm)`). The engine verifies its WebAssembly
representation; the caller must establish its `snail-scheme` type contract.

## Linked files

`(snail shell resource)` ties a file to a library as one of its dependencies
instead of embedding it, as Python's `importlib.resources` addresses a
package's data, and the library reads it when it needs it:

```scheme
(import
 (snail core base)
 (only (snail shell task) tasks)
 (snail shell resource))


(define (hero) (→ Resource) (link-file "art/hero.png"))


(define (hero-bytes (resources Resources)) (→ Bytes)
  (read-resource resources (hero)))
```

- **Found beside the library.** The path is relative to the file the form is
  written in, or the `generate-library` recipe's directory for a
  producer's own forms, and may not leave its directory: `.`
  and `..` are resolved, and an absolute path, an empty name or a path that
  climbs out is an error. A file that is missing fails the build with the
  library and the path.
- **Shipped by content.** The build places the file as an object of the
  program's store, at `STORE/sha256/AB/DIGEST`, where DIGEST is the
  SHA-256 of its bytes in hex and AB its first two digits, in every build
  that produces one. A program's store
  is `store/` beside its module. The name is
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
  `Resource` is evidence that its file ships. `(read-resource resources r)`
  returns the file's `Bytes`, and `(read-resources resources (list a b))`
  the bytes of each, read
  together: every read starts before the task waits for any. Both take a
  `Resources`, which every target provides, on Node and in the browser. It
  is not `Fs`: a page has no filesystem, and a program with none still
  reads its own files.

**A file is read when the program asks for it.** A host reads nothing a
module links when it instantiates the module. `read-resource` waits for the
host as a task does (`through-host` in `(snail shell task)`), so it runs
in a task. The first read of a file reads it, Node from
the payload's directory and the browser by fetching beside the
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
mismatch. Both evaluate their input exactly once. Downcasting does not panic.
Ordinary checking never inserts a conversion:
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

A closure may be boxed like any other value: its type identity is its
parameters' and its result's.

The type identity includes nominal names, arguments, fields, cases, and nested
function signatures. Changed schemas receive changed identities
across separately linked modules, even if their Wasm layouts match. Downcast also checks the Wasm
representation before reading the payload. Type identities are currently 32-bit
hashes; they are not collision-free structural proofs.
