# Types

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` is a value of any type, used with `type-convert`.
`String` is an immutable sequence of Unicode scalars. `(Vector T)` is an
immutable sequence and `(Array T)` a mutable one; `(Ref T)` is a mutable
cell, a struct with one [mutable field](#data) that `(snail core base)`
declares. `Bytes` is `(Vector U8)`, stored packed. A byte vector literal,
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
replacements `Name-field-set`. A struct's field may be mutable, written
`(count mut I64)`: it is read and written where the struct is, by
`Name-count`, `Name-count-set!` and `Name-count-replace!`, which stores a new
value and returns the old one, and each performs `mut`. A struct with a mutable
field has identity, so it has no pure replacements and derives no instances,
and a pattern can only skip a mutable field, with `_`
([ownership](ownership.md)). An enum defines a constructor and accessors per
case, and its fields are immutable. Cases are constructors, not types, and are
always applied: `(Empty)`.

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

Arithmetic and comparison are the classes `Num`, `Ord`, `Integral` and
`Fractional`; `Show` converts values to text, and `Drop` releases them
([ownership](ownership.md#releasing)).

## Effects

Every function type has an effect row, the effects calling it may perform,
and a function without `!` is total. [Effects and handlers](effects.md)
covers rows, their inference and polymorphism, local mutation, declaring
and handling effects, control operations with a one-shot `resume`, latent
rows and defaults.

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

- **Addressed by the library.** The path is relative to the file the form is
  written in, as `include-bytes`'s is, a `generate-library` recipe's for a
  producer's own forms, and may not leave its directory: `.`
  and `..` are resolved, and an absolute path, an empty name or a path that
  climbs out is an error. The file ships under a name made from the library
  and the canonical path, `assets.sprites/art/hero.png` for `(assets sprites)`,
  or `main/...` for a program's own body. The name is the same on every host
  and in every build; it is never a filesystem path.
- **Guaranteed to ship.** The build places the file at `resources/NAME`
  beside the payload, `program.wasm` or `modules.json`, in every build that
  produces one: project program and browser targets, `scripts/snail-tool run`
  and `compile`, and the development loop. A file that is missing fails the
  build with the library and the path. The module itself records what it
  links: `link-file` becomes a call to an import from `snail.runtime.link`
  named for the file, which answers its handle.
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
that reads it. A module linked again gets new handles, so it reads its files
as they are then.

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
