# The Lofi language

Lofi is a typed, pure-by-default functional language with Scheme syntax. It
compiles to WasmGC. This guide describes what the compiler implements today;
[the redesign](redesign.md) describes where the language is going.

<!-- ANCHOR: terms -->
## Programs and libraries

A program is a file of `import` forms followed by definitions and expressions,
which run in order. A library is an R7RS `define-library` with `import`,
`export` and `begin` sections, stored at a path that matches its name:
`(sample geometry)` lives in `sample/geometry.sld` under a search directory.
Import sets may use `only`, `except`, `prefix` and `rename`.

```scheme
(import
 (lofi base)
 (lofi io))

(: fibonacci (-> I64 I64))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 30))
(newline)
```

`src/` is always on the search path. `./scripts/lofi-tool run -I DIR program.sld` adds more.

A library file may instead hold a `generate-library` recipe: a program whose
value is the library's `define-library` form, as a `Syntax` from
`(lofi syntax)`. The compiler builds and runs it first:

```scheme
(generate-library (sample table)
  (import
   (lofi base)
   (lofi syntax))
  (library-syntax (list "sample" "table")
                  (list "squares")
                  (list (list "lofi" "base"))
                  (list (form "define" (list (SymbolSyntax "squares")
                                             (form "list" (map (lambda (i) (IntegerSyntax (* i i))) (iota 6))))))))
```

The program writes the syntax as bytes that the compiler decodes, so no text
is printed or parsed in between, and a `BytesSyntax` reaches the compiler
as the bytes it holds. `datum->syntax` from `(lofi datum)` turns a Scheme
datum into syntax. Every generated form is located at the recipe.

## Forms

| Form | Meaning |
| --- | --- |
| `(define name value)`, `(define (name param ...) body ...)` | Definition. |
| `(lambda (param ...) body ...)` | Function with a fixed number of parameters. |
| `(if test then [else])` | `test` is `Bool`; without `else` the result is `Unit`. |
| `(begin form ...)` | A body: definitions and expressions in order. |
| `(let ((name value) ...) body ...)`, `(let loop ((name value) ...) body ...)` | Local bindings and loops. |
| `(match value (pattern body ...) ...)` | Pattern matching, checked for exhaustiveness and unreachable clauses. |
| `(: name type)` | Signature for the following definition. |
| `(ann expression type)` | Static type annotation. |
| `(type-convert expression type)` | Converts to or from `Any`; a downcast is checked at run time. |
| `(type-test expression type)` | Whether an `Any` holds a value of `type`, without trapping. |
| `(struct (Name param ...) ((field type) ...))` | Record type. |
| `(enum (Name param ...) (Case [((field type) ...)]) ...)` | Tagged sum. |
| `(type (Name param ...) type)` | Transparent alias. |
| `(typeclass (Class param ...) (: method type) ...)` | Class of types with methods. |
| `(instance (Class type ...) [(requires constraint ...)] (define ...) ...)` | Instance. |
| `(effect Name ((operation type) ...) [(host "module" ((operation "symbol") ...))])` | Effect with operations and optional host defaults. |
| `(handle Name ((operation implementation) ...) body ...)` | Handles an effect for the extent of `body`. |
| `(extern name "module" "symbol" type)` | Wasm import, asserted total. |
| `(expose name "symbol")` | Exports a monomorphic top-level function to the host; its arguments and result must be unrestricted. |
| `(define-syntax name (syntax-rules (literal ...) (pattern template) ...))` | Hygienic macro. |

`(lofi base)` adds `let*`, `letrec`, `cond`, `case`, `when`, `unless`, `and`,
`or`, `do`, `list`, `string` and a variadic `string-append` as macros.

### Bodies and scope

Library and program top levels see all of their definitions, so top-level
functions may be mutually recursive. A local body is sequential: a definition
is visible to the forms after it, and a local function is also visible to
itself. Write mutually recursive helpers at the top level.

Functions have fixed arity. Where Scheme uses variadic procedures, Lofi
uses macros (`list`, `string-append`) or lists.
<!-- ANCHOR_END: terms -->

<!-- ANCHOR: types -->
## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` is a value of any type, used with `type-convert`.
`String` is an immutable sequence of Unicode scalars. `(Vector T)` is an
immutable sequence and `(Array T)` a mutable one; `(Ref T)` is a mutable
cell. `Bytes` is `(Vector U8)`, stored packed. A byte vector literal,
`#u8(137 80 78 71)`, compiles to a data segment of exactly its bytes, so a
program can carry large binary data, such as images; it cannot be a
pattern. `(include-bytes "pixel.png")` is another spelling of the literal
holding a file's bytes, with the path relative to the file it is written
in. It is replaced when the source is read, so a macro cannot compute the
path, and nothing else may be named `include-bytes`.

A function type is `(-> Param ... Result)`, optionally followed by an effect
row: `(-> String Unit ! console)`. A polymorphic signature quantifies type
and row variables and lists its class requirements:

```scheme
(: map (All (A B e) (-> (-> A B ! e) (List A) (List B) ! e)))
(: sum (All (T) (requires (Num T)) (-> (List T) T T)))
```

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
replacements `Name-field-set`. An enum defines a constructor and accessors per
case. Cases are constructors, not types, and are always applied: `(Empty)`.

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
`Fractional`; `Show` converts values to text.

### Transfer and sharing

`(Send T)` permits transferring ownership of a value between threads;
`(Sync T)` permits shared access across threads. Both are compiler-owned
marker typeclasses from `(lofi base)`. Write them as ordinary requirements:

```scheme
(: transferable (All (T) (requires (Send T)) (-> T T)))
(define (transferable value) value)
```

The compiler derives evidence for scalars, text, immutable vectors and
declared data whose arguments and fields satisfy the same requirement.
Recursive data is checked structurally. Aliased `Ref` and `Array`, opaque
`Any`, raw `Funcref`, and ordinary function arrows do not satisfy either
marker. A procedure's arrow does not describe its captures. Generic fields
need the corresponding evidence in the enclosing signature.

There are no user-defined instances for these two markers. Their meanings
differ even though this initial set of representations has the same proofs
for both. No data is serialized or copied by a marker constraint. These
checks apply on today's single-threaded runtime as part of the language's
multithreaded contract.

## Effects

Ordinary handler implementations must be reusable and satisfy `Send + Sync`,
including their captures and the globals reachable through helper functions.
The compiler checks concrete handler installations after specialization.
Capturing an immutable value or a known safe procedure is allowed. Capturing
a mutable cell, an alias of a procedure that reaches one, or an opaque
callback whose environment is unknown is rejected. The handler may allocate
fresh mutable storage on each invocation and operate on its arguments.
An arrow alone is not a certificate for an unknown callback; higher-order
handler factories may need to construct their implementation at the binding
site so its environment remains visible to the compiler.
Incremental builds recheck cached handler code against current helper bodies;
an unchanged function signature does not preserve a proof about captures.

Every function type has an effect row: the effects calling it may perform.
A function without `!` is total. `mut` covers reading and writing `Ref` and
`Array`; every other effect is declared with operations:

```scheme
(effect Log
  ((log (-> String Unit))))

(: quietly (All (A e) (-> (-> A ! Log e) A ! e)))
(define (quietly action)
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))
```

Rows are inferred by unification, Koka-style. A call requires its callee's
effects to fit the current row. With a shared quantified tail, `e` fits
`console e`, and `fs e` fits `console fs e`; the reverse inclusion does not
hold. This permission check does not change equality of function types.
A handler removes its effect. Handler
implementations return to the operation's caller exactly once, and they run
in the handler's outer context, so an operation they perform goes to the
next handler out. A handler names operations within its effect, so they need
not be imported. Effects with host defaults, such as `console` and `fs` from
`(lofi io)`, need no handler at the top level of a program, and a test can
handle `fs` to serve files from memory.

`extern` declares a total foreign function; the declaration is the boundary's
unsafe assumption.

A foreign call may take a final `String` or `Bytes` argument. The compiler
copies it into the runtime's staging buffer just before the call. A String
arrives as its Unicode scalar count, with four bytes per scalar in staging.
Bytes arrive as an `i32` address: a little-endian `u32` length followed by
that many packed bytes. The host reads the current memory buffer and copies
any bytes it retains before returning or awaiting; later calls reuse staging.
Imports are leaves and must not call back into Lofi while reading staging.

An exposed function passes scalars directly and managed values as opaque engine
references. JavaScript can retain those references and pass them to synchronous
Wasm constructors/projectors, but cannot inspect their fields or substitute a
JavaScript object, string or typed array. Exposed `String` and `Bytes` are managed
arrays; the staging convention above applies to calls into foreign imports.
Affine values, including records that contain them, cannot cross this unrestricted
boundary. Exposed signatures remain monomorphic and their effects need host bindings.
The host must respect the declared Lofi types: Wasm representation checks do not
prove nominal identity or permit treating immutable `Bytes` as a mutable `Array`.

An exposed `(Option Any)` crosses as `null` for `None` or the opaque `Any`
payload for `Some`. The wrapper converts at the boundary; internal Options
keep their normal enum representation. Plain `Any` remains non-nullable.
This exception applies only to exposed parameters/results; a host import
returning `(Option Any)` still expects its ordinary enum. Constructors for a
typed host operation should return its whole result, such as `(Result Bytes E)`.
Resolve helpers from their library instance in separate builds and the combined
instance in static builds. After a wait, the runtime must reacquire the execution
permit before invoking a constructor or returning to Wasm. Programs export their
dynamic handler globals as `handler.NAME`; the scheduler preserves each task's
bindings across suspension. See [scheduling](https://tsnl.github.io/snail-scheme/runtimes/scheduling.html).

A function whose signature has no `mut` may still mutate storage that it
allocates and that nothing keeps after it returns:

```scheme
(: sum (-> (List I64) I64))
(define (sum items)
  (let ((total (ref 0)))
    (for-each (lambda (item) (ref-set! total (+ (ref-get total) item))) items)
    (ref-get total)))
```

The checker accepts such a body when nothing the function can reach from
outside can hold mutable storage: not its parameters, not its result, and
not any name it reads, including effect operations. Holding storage means
being a `Ref`, an `Array` or an `Any`, data with such a field, or a function
that performs `mut`. Primitives, constructors and field operations are always
allowed. A helper defined elsewhere that mutates its argument is therefore
rejected even when the argument is local; define it inside the function.
`unsafe-total` runs a thunk and discards all its effects without a check, for
the cases this rule rejects; each use says in a comment why nothing escapes.
`unsafe-cast` is the other unchecked primitive: it turns a `Funcref`, a
function another module exports, into a function of whatever type the
context expects (`(lofi wasm)`).

Traps and non-termination are not tracked.

## Dynamic values

`Any` holds an unrestricted value together with its type's identity.
Affine values cannot cross this boundary.
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
<!-- ANCHOR_END: types -->

<!-- ANCHOR: wire -->
## Wire types

`(deriving Serialize Deserialize)` at the end of a struct or enum generates
instances of `(lofi wire)`'s classes. `serialize` writes a value as bytes and
`deserialize` reads it back:

```scheme
(struct Point
  ((x I64)
   (y I64))
  (deriving Serialize Deserialize))

(ann (deserialize (serialize (Point 1 2))) Point)
```

Each struct and enum case has a 32-bit TypeId hashed from its library, name
and field schema. Every struct or enum value is written as its case's TypeId
followed by its fields, so reading data written for another schema fails at
the first changed type instead of misreading it.
<!-- ANCHOR_END: wire -->

## Applications

<!-- ANCHOR: applications -->
`(lofi app)` defines interactive browser applications as total functions over
a state:

| Function | Meaning |
| --- | --- |
| `init : seed width height -> State` | The first state. |
| `update : State Input -> State` | Applies one input: a key, a pointer, a HUD button, the screen's size, or the milliseconds since the last display frame. |
| `view : State -> Frame` | A frame of items, meshes and sprites, under a camera and a light, with the pictures their textures use. |
| `hud : State -> (List Panel)` | The HUD's panels of labels, texts, buttons, dials, links and images, shown again after each update. |
| `save : State -> Save` | What to store, with a wire encoding; it may be a record of how to rebuild the state. |
| `restore : Save -> State` | The state again. |

These functions operate on immutable state. `define-application`
runs them inside one loop and the binder returned by `reset`:

```scheme
(define-application Game
  (reset: default-reset)
  (init: new-game)
  (update: step)
  (view: draw)
  (hud: panels)
  (save: save-game)
  (restore: restore-game))
```

`default-reset` simply runs its argument. A custom reset returns a binder
that installs effect handlers around startup and the whole loop; its result
and effect row are quantified on the reset function, so the returned binder
is monomorphic. The loop exports `app_main : (Option Any) -> (Option Any)`.
The task scheduler calls it through `WebAssembly.promising`; `next-event`
drains the host queue and suspends through `WebAssembly.Suspending` when it
is empty. `FrameEvent` carries elapsed milliseconds, `InputEvent` carries an
`Input`, `Hidden` saves without stopping, and `Reload` saves and returns the
state. The `Frame` type continues to describe drawing data.

DOM listeners enqueue input. The host keeps at most one pending display
frame and coalesces consecutive pointer moves and resizes without crossing
other input. Storage suspends for a whole load or store, copying save bytes
before awaiting the browser. The loop saves every five seconds and when the
page becomes hidden. Only a complete successful event commits its state;
a trap leaves the preceding checkpoint available through `app_state`.
Because time is input, an application decides how time passes and can stop
it at any frame. Browser applications and headless tests need JSPI; the
pinned Node 26 runs both packaging modes.

The loop and locally dispatched work share one runtime. The reset binder
may dispatch background tasks; the root admits the `tasks` effect as well
as `mut`, `screen`, `events` and `storage`. Suspensions preserve each
task's handlers. Reload lets the loop save and return, then cancels and
drains remaining work before relinking. Module globals still initialize
synchronously; dispatch application work from the reset binder or the
running entry. See [runtimes](https://tsnl.github.io/snail-scheme/runtimes/index.html).

Frames are built from batches of items. The host keeps a batch until its
version changes, so a still scene costs nothing to send; each item also
carries where it was, and the host moves it toward where it is as the
frame's motion goes from 0 to 1. Batches may be solid, translucent, or
revealed within a growing disc. The camera is perspective or orthographic.

Meshes and sprites are both items, drawn by one shader in the
metallic-roughness model: a `Material` gives an optional texture, the albedo
of a dielectric or the specular color of a metal, with metalness and
roughness defaulting to 0 and 1. Textures are regions of `Picture`s, which
the host composes from layers of encoded image files the program carries,
recoloring each by swapping colors, and keeps until their version changes.
A sprite is a textured quad, standing upright toward the camera in a 2.5D
scene or lying flat under an orthographic camera looking straight down in
a 2D one, and a texture region can be a strip of frames the host steps
through by the clock. `(lofi sprite)` poses figures from spritebooks of any
sheet, and `src/lpc` uses it for the Liberated Pixel Cup character art.

HUD panels, built from widgets such as those `label` and `button` make,
stack in columns from the screen's corners, appear as dialogs, or sit in a
banner across the top that lets input through but for its links. A widget's
tone can mark it suggested, the control to use next. The host keeps elements
by key, so hover and focus survive updates, and reports presses and hovering
back as input. `recognize` turns raw pointer events into points, taps, drags
and pinches.

[Siegework](https://github.com/tsnl/snail-scheme/tree/main/apps/siegework)
is the complete example, and
[Hearsay](https://github.com/tsnl/snail-scheme/tree/main/apps/hearsay)'s
prototypes draw their residents as LPC characters on a 2D map.
<!-- ANCHOR_END: applications -->

## Ownership and runtimes

`Once` wraps a zero-argument procedure returning `Unit`. Construct one with
`once` and consume it with `call-once`. It has grade `1` (at most once);
ordinary procedures have grade `omega` (reusable). Concrete records and
enums containing affine fields are affine too. Use `match` to consume
their fields. Moves invalidate the previous binding, and unused owners
are dropped at their last use on each path.

The [runtime chapter](book/runtimes/index.md) explains the ownership subset,
effect-handler requirements, single-threaded implementation and future
parallel execution. Generic type parameters currently range over
unrestricted types; there is no borrow checker or user-defined destructor.

<!-- ANCHOR: libraries -->
## Standard library

| Library | Contents |
| --- | --- |
| `(lofi base)` | Forms, numeric classes, `Option`, `Result`, `Pair`, lists, vectors, arrays, strings, `Show`. |
| `(lofi io)` | The `console` and `fs` effects: text output, lines of input, and files as text or bytes. |
| `(lofi task)` | One-shot local dispatch, cooperative yield and timer waits through the runtime-owned `tasks` effect. |
| `(lofi table)` | Immutable tables from strings to values. |
| `(lofi math)` | Elementary functions on `F64`. |
| `(lofi text)` | Unicode character properties and case mapping. |
| `(lofi random)` | A deterministic generator as a value. |
| `(lofi wire)` | `Serialize`, `Deserialize` and the byte encoding. |
| `(lofi app)` | Applications, frames, pictures, materials and sprites, and the `screen` effect. |
| `(lofi wasm)` | Loading WebAssembly modules while a program runs, and `unsafe-cast`. |
| `(lofi sprite)` | Spritebooks: animations on sheets of equal cells, posed as sprites facing the camera. |
| `(lofi format)` | Indenting and formatting Lisp source as `scripts/format-scheme` does. |
| `(lofi integer)`, `(lofi rational)`, `(lofi number)` | Exact integers of any size, rationals, and Scheme numbers. |
| `(lofi datum)`, `(lofi read)`, `(lofi write)` | Scheme data and its external representation. |
| `(lofi syntax)` | The syntax a `generate-library` recipe returns, and the bytes its producer writes. |
| `(lofi explore)` | Bounded model checking of a total state machine's invariant. |
| `(scheme base)` | R7RS names (`cons`, `car`, `vector`, `char=?` ...) over the typed language. |
| `(scheme compiler)`, `(scheme runtime)` | The R7RS translator, and the standard procedures its output calls. |
<!-- ANCHOR_END: libraries -->
