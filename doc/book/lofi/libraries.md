# Libraries

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
