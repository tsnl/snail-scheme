# Types

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
path, and nothing else may be named `include-bytes`. A large file is better
linked than included: see [linked files](#linked-files).

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
marker typeclasses from `(snail-core base)`. Write them as ordinary requirements:

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
A signature may not claim more than its body does either: a top-level
definition whose signature names an effect, or a tail variable such as `e`,
that no call in its body performs is an error at the signature, so
`(: double (-> I64 I64 ! mut))` over a body that never mutates is rejected.
An instance method keeps its class method's row, which one instance may need
less of than another; `extern` declarations, class method signatures and
definitions whose value is not a lambda have no body to compare. A signature
a macro writes is held to each expansion, so a macro that cannot know a row,
as `define-application` cannot know what its reset binder performs, takes
the effects as an argument.
A handler removes its effect. Handler
implementations return to the operation's caller exactly once, and they run
in the handler's outer context, so an operation they perform goes to the
next handler out. A handler names operations within its effect, so they need
not be imported. Effects with host defaults, such as `console` and `fs` from
`(snail-core io)`, need no handler at the top level of a program, and a test can
handle `fs` to serve files from memory.

**Proposed: control operations.** An effect may declare an operation with
`ctl`, as in `(effect Gen ((ctl next (-> I64 Unit))))`. Its implementation
receives one more argument, `resume`, the rest of the handled body: calling
`(resume answer)` runs it, under the handler again, to the handler's result,
which the implementation returns. `resume` is a `Once`, so the checker
rejects calling it twice, and it may be stored and called later. A control
operation has no host default, since the host cannot be handed the rest of a
computation. The checker accepts all of this today; the backend reports
"control operations are not compiled yet" until the translation lands.

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
context expects (`(snail-core wasm)`).

Traps and non-termination are not tracked.

## Linked files

`(snail-core resource)` links a file to a library instead of embedding it, as
Python's `importlib.resources` addresses a package's data:

```scheme
(import
 (snail-core base)
 (snail-core resource))

(: hero Resource)
(define hero (link-bytes "art/hero.png"))

(: hero-bytes (-> Bytes ! resource))
(define (hero-bytes)
  (read-resource hero))
```

- **Addressed by the library.** The path is relative to the file the form is
  written in, as `include-bytes`'s is, and may not leave its directory: `.`
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
  links: `link-bytes` becomes a call to an import from `snail.link` named for
  the file, so a host cannot instantiate the module without supplying it.
- **A handle, not the bytes.** `link-bytes` evaluates to a `Resource`, which
  names bytes and nothing more. The type is exported without its constructor,
  so a program cannot make one from a string: holding a `Resource` is evidence
  that its file ships. `(read-resource r)` returns the file's `Bytes` and
  performs `resource`, an effect with host defaults on Node and in the
  browser. It is not `fs`: a page has no filesystem, and a program with none
  still reads its own files.

**Resources are loaded before the program starts.** Each host reads every
file a module links before it instantiates the module, Node from the
payload's directory and the browser by fetching beside the page's module, so
`read-resource` is a synchronous lookup on both hosts and never suspends. A
payload whose files are absent fails to load, not when one is first read.
A module linked again reads its files again; a module kept linked keeps the
bytes it was linked with. Loading on demand waits for tasks to become effects.

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
