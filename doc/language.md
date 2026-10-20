# The Lofi language

Lofi is a typed, pure-by-default functional language with Scheme syntax. It
compiles to WasmGC. This guide describes what the compiler implements today;
[the redesign](redesign.md) describes where the language is going.

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

`lib/` is always on the search path. `./lofi run -I DIR program.sld` adds more.

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
| `(struct (Name param ...) ((field type) ...))` | Record type. |
| `(enum (Name param ...) (Case [((field type) ...)]) ...)` | Tagged sum. |
| `(type (Name param ...) type)` | Transparent alias. |
| `(typeclass (Class param ...) (: method type) ...)` | Class of types with methods. |
| `(instance (Class type ...) [(requires constraint ...)] (define ...) ...)` | Instance. |
| `(effect Name ((operation type) ...) [(host "module" ((operation "symbol") ...))])` | Effect with operations and optional host defaults. |
| `(handle Name ((operation implementation) ...) body ...)` | Handles an effect for the extent of `body`. |
| `(extern name "module" "symbol" type)` | Wasm import, asserted total. |
| `(expose name "symbol")` | Exports a top-level function to the host. |
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

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`String` is an immutable sequence of Unicode scalars. `(Vector T)` is an
immutable sequence and `(Array T)` a mutable one; `(Ref T)` is a mutable
cell. `Bytes` is `(Vector U8)`, stored packed.

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

Unannotated top-level functions are generalized. Other unannotated
definitions are monomorphic, and their types may be decided by later uses.
Polymorphic definitions that are not functions need signatures.

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

## Effects

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

Rows are inferred by unification, Koka-style. A call adds its callee's
effects to the current row, and a handler removes its effect. Handler
implementations return to the operation's caller exactly once, and they run
in the handler's outer context, so an operation they perform goes to the
next handler out. Effects with host defaults, such as `console` from
`(lofi io)`, need no handler at the top level of a program.

`extern` declares a total foreign function; the declaration is the boundary's
unsafe assumption. `unsafe-total` runs a thunk and discards its effects. The
standard library uses it where a function mutates only storage it allocates.

Traps and non-termination are not tracked.

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

## Applications

`(lofi app)` defines interactive applications as three total functions:
`init` makes the state from a seed and the screen size, `update` applies one
`Input`, and `view` describes a `Frame` of mesh instances and HUD panels.
`define-application` exposes them to the browser host in `src/app`, along
with saving and restoring the state through its wire encoding.
[Siegework](../apps/siegework) is the complete example.

## Standard library

| Library | Contents |
| --- | --- |
| `(lofi base)` | Forms, numeric classes, `Option`, `Result`, `Pair`, lists, vectors, arrays, strings, `Show`. |
| `(lofi io)` | The `console` effect and text output. |
| `(lofi math)` | Elementary functions on `F64`. |
| `(lofi text)` | Unicode character properties and case mapping. |
| `(lofi random)` | A deterministic generator as a value. |
| `(lofi wire)` | `Serialize`, `Deserialize` and the byte encoding. |
| `(lofi app)` | Applications, frames and the `screen` effect. |
