# Types

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` is a value of any type, used with `type-convert`.
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

A function type is `(-> Param ... Result)`, optionally followed by an
[effect row](effects.md): `(-> String Unit ! console)`. Two other arrows
are written the same way: `(FnOnce Param ... Result)` is called at most
once, and `(Fn Param ... Result)` has no environment, a reference to code
alone ([ownership](ownership.md#closures-without-an-environment)). A
polymorphic signature quantifies type and row variables and lists its
class requirements:

```scheme
(: map (All (A B e) (-> (-> A B ! e) (List A) (List B) ! e)))
(: sum (All (T) (requires (Num T)) (-> (List T) T T)))
```

A type variable is linear unless the signature requires `(Copy T)`, which
a body needs to use a `T` twice or to discard one
([ownership](ownership.md)).

Integer literals check against any integer or float type and are
range-checked; float literals check against `F32` or `F64`. A literal whose
type nothing determines defaults to `I64` or `F64`. Values never convert
implicitly: use `i64->i32`, `i32->f64` and the other conversions. Integer
arithmetic wraps.

Unannotated top-level functions are generalized over the type variables no
constraint mentions. Other unannotated definitions, and functions whose
types involve a class constraint, keep one type, which later uses in the
same library may decide. A library is checked before the libraries that
import it, so their uses never decide its types: `(define key-left 1)` is an
`I64` wherever it is imported, and a value meant as an `I32` elsewhere needs
the signature `(: key-left I32)`. Polymorphic definitions with constraints,
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

A struct `Name` defines the constructor `Name`, accessors `Name-field` and pure
replacements `Name-field-set`. A struct is a value: its fields are immutable,
and a program that changes one holds it in a cell, `(Ref Name)`, and writes a
*place*, the cell's content or a field read from it, with `set!` or
`replace!`: `(set! (::count (ref-get r)) 1)`. Reading or writing a cell
performs `mut`. `Ref` is the one struct with a mutable field, and a pattern can
only skip its content, with `_` ([ownership](ownership.md)). An enum defines a
constructor and accessors per case, and its fields are immutable. Cases are constructors, not types, and are
always applied: `(Empty)`.

A field is also read by its label alone: `(::label s)` reads the field
`label` of whatever struct `s` is, and `(::from::x s)` reads `x` of what
`from` holds. Each label is a typeclass, `(::label R T)`, over the record
type and the field's type, with the one method `::label`; a struct without
mutable fields has an instance per field, and the record's type decides
the field's, so a path needs no annotation where the record's type is
known. A library may declare an instance for a type that computes the
field, and a generic function requires one, `(requires (::label R
String))`, to read the field of any record that has it. Names beginning
with `::` are reserved for paths.

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
  (: describe (-> T String)))

(instance (Describe (List T))
  (requires (Describe T))
  (define (describe items)
    (string-join (map describe items) ", ")))
```

The checker chooses each instance when it checks a use and records that
choice; monomorphization copies the chosen method for each type, so no
dictionary exists at run time. Instance heads must not overlap. Classes have
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
`(Logged Directory)`, `log` and `console`. A head's row names no control
effect. `Drop` and `Clone` are classes over a row too
([releasing](ownership.md#releasing)), whose rows are found from a type's
structure where it has no instance.

Arithmetic and comparison are the classes `Num`, `Ord`, `Integral` and
`Fractional`; `Show` converts values to text, and `Drop` releases them
([ownership](ownership.md#releasing)).

## Effects

Every function type has an effect row, the effects calling it may perform,
and a function without `!` is total. [Effects and handlers](effects.md)
covers rows, their inference and polymorphism, local mutation, declaring
and handling effects, control operations with a one-shot `resume`, latent
rows and defaults.

## Proposed callable typeclass

**Design for review, not implemented.** The syntax and typeclass in this
section describe a proposed replacement for function arrows. The earlier
sections describe the compiler today; their examples still use `->`.

Use `fun` in signatures and for named function definitions:

```scheme
(: square (fun I64 I64))
(fun (square n)
  (* n n))
```

`define` continues to bind values. A `fun` signature describes a callable
contract: argument types, result type and effects. It does not require one
universal closure representation. Generic consumers accept a concrete type
through a callable typeclass, provisionally named `Callable`. Ordinary
functions and effect operations both satisfy it. A `ctl` operation is not a
subclass of ordinary functions; its declaration supplies a different way
to perform the same calling interface
([parameterized effects](effects.md#proposed-parameterized-effects)).

The class must carry four pieces of evidence:

| Contract | What the checker must establish |
| --- | --- |
| Argument types | Each call supplies the required arguments. |
| Result type | Continuing the call produces a value of this type. |
| Effect row | The caller permits every effect that calling may perform. |
| Call multiplicity | The consumer calls or releases the value as its ownership permits. |

For example, a generic `map` needs a concrete callable `F` from `A` to `B`
with row `e`, callable repeatedly. A consumer that invokes its argument
once can accept a one-shot callable under the appropriate ownership rule.
A repeatable callable may be invoked once too; the obligation to release
its captures still follows its ownership. `Copy` alone does not establish
callability. A one-shot continuation must not satisfy the repeated-call
requirement. The current rule for `FnOnce` remains the baseline: consume it
by calling or dropping it exactly once, including any effects of dropping
its captures ([ownership](ownership.md)).

The exact `Callable` parameter syntax, argument-list representation and
multiplicity spelling remain open. The intended elaboration of a generic
callable parameter introduces a concrete type variable and its class
requirement; it does not erase that type into a common closure. How a `fun`
signature expresses a stored or returned callable needs a separate rule
for representation and quantification. This proposal does not silently
give those positions an existential package or a higher-rank type.

The compiler supplies callable evidence for functions, closures and effect
operations. Whether user-defined data may implement this class is a
separate extension. During monomorphization the concrete callable type
allows the compiler to choose a direct call, a closure call or an effect
operation dispatch. Its effect row determines whether the surrounding
computation must support yielding: an ordinary function can call a `ctl`
operation internally. A repeatable callable can yield, and a one-shot
callable can be total; multiplicity and control behavior are independent.

Specialization must not depend on the installed handler's identity.
Operations still select their handler through the evidence in scope, so
one compiled consumer can run under different implementations of an
effect. This preserves the compiler's existing handler-dispatch contract.

Replacing `->` with `fun` is the proposed surface direction. The migration
must cover signatures, function definitions, bootstrap forms, macros,
formatting, highlighting and diagnostics together. The spelling of `Fn`
and `FnOnce`, compatibility with old forms, and anonymous-function syntax
need decisions before implementation. This section proposes no new
working syntax in the current compiler.

## Proposed places and locators

**Design for review, not implemented.** A first-class place separates
storage selection from reading, writing or swapping its value. Its surface
syntax should serve [everyday use](terms.md#proposed-surface-design), with
no requirement to spell the flattened layout or an accessor's typeclass.

Conceptually, a place contains a root reference and a locator. For a root
`a`, the expression `a.b.c` would compose the field locators `b` and `c`
and bind them to `a`. Dot notation here describes the intended selection;
the reader syntax is undecided. Constructing the place does not read or
copy the selected value. Reading, writing and swapping are separate
operations with their own ownership requirements and effects. A computed
getter is not automatically a locator for storage.

Writable-field evidence must preserve the defining library's field-access
rules. Replacing an owned field retains the existing requirements for
releasing its old value, including any cleanup effects. Whole-cell writes
through `ref-set!` and pure replacements such as `Counter-count-set` have
different contracts and remain distinct operations. A direct field setter
such as `(::count! counter 3)` is an alternative surface spelling under
review, not a requirement of the locator design. Whether `set!` remains
and how selection composes with reading still need decisions.

For a statically known path through inline struct fields, a distinct
concrete locator type can preserve the root type, selected type and field
path. Generic code constrains that locator through its access contract
and retains its concrete type for specialization, as with callables.
The compiler can then represent a bound place by its root reference
alone: the selected path lives in generated code, with no runtime list of
field names or offsets. This is a proposed lowering, not a guarantee made
by the current compiler. An explicit wrapper may still be needed at a
boundary that does not preserve its representation.

WasmGC `struct.get` and `struct.set` encode their field indices in the
instructions ([instruction syntax](https://webassembly.github.io/spec/core/text/instructions.html)).
That constrains each generated access, but does not prohibit runtime
selection of a locator. An erased place could retain a root and generated
access functions, or dispatch on a finite choice of locators; every access
function or branch would still use fixed field indices. Such erasure has
a representation and dispatch cost. A runtime integer offset alone cannot
index an arbitrary WasmGC struct. Static knowledge can also come from
inlining or constant propagation; preserving it in the concrete locator
type provides a contract across generic function boundaries.

The first design should cover paths through inline struct fields rooted
in a stable cell. A retained place keeps that root alive through a managed
reference, not an interior address. Replacing the cell's value leaves the
place referring to the same field path in its new value. Extending paths
through a replaceable reference needs a choice between following its new
target and retaining its old target. Selecting an enum payload requires
evidence that its case remains valid, or a checked access that can fail.
Neither behavior should be hidden in punctuation.

Aliased places must not let a read move a linear value out of shared
storage. Reads require the same copying evidence as field access today;
writes and swaps retain the existing release and replacement rules.
The remaining design work is the locator class's precise contract,
composition, explicit erasure, and the syntax distinguishing a place from
the value read through it. This replaces the assumption that a separate
setter name must be the final field API.

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

(: hero Resource)
(define hero (link-file "art/hero.png"))

(: hero-bytes (-> Bytes ! resource tasks))
(define (hero-bytes)
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

`Any` holds an unrestricted value together with its type's identity.
Affine values cannot cross this boundary. Nor can a function that performs
effects, wherever it sits in the value's type, or a value of a type
variable, which may be one: a type's identity has no effect rows, so such a
function could come back out claiming to perform nothing, and run where
nothing handles what it does (`tests/programs/error-any-control-function.sld`).
`type-convert` and `type-test` refuse these types when they are written, so
an `Any` never holds a function with effects.
`(type-convert e Any)` wraps a value; `(type-convert e T)` unwraps an `Any`,
panicking if it does not hold a `T`, and `(type-test e T)` asks whether it
does. A type's identity describes its structure, its fields and cases, so a
struct whose fields change, even under the same name, is another type: a
program relinked with that change cannot take an old value for a new one.
Converting a value to the type it already has does nothing, and a value
converted to `Any` and straight back is never wrapped, so conversions can be
inserted liberally where typed code meets dynamic code.

```scheme
(define items (list (type-convert 42 Any) (type-convert "text" Any)))
(+ 1 (type-convert (car items) I64))
```
