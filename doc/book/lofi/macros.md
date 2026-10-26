# Macros and Scheme libraries

Macros are hygienic `syntax-rules` transformers, defined with
`define-syntax` at the top level or in a local body. Surface forms such as
`let*`, `cond`, `case` and the variadic `list` are macros in `(lofi base)`,
and they expand away before checking, so the checker sees only the core.

A library file may hold a `generate-library` recipe instead of a
`define-library`: the compiler builds and runs that program first, and
compiles the library syntax it returns, which the program writes as bytes
the compiler decodes rather than as text.

Scheme is a library too. `(scheme base)` gives R7RS names (`cons`, `car`,
`vector`, `char=?`, ...) over the typed language, and `(scheme compiler)`
translates R7RS programs into Lofi libraries, run by a `generate-library`
recipe, with `(scheme runtime)` for the standard procedures. The
[Scheme on Lofi](tutorials/scheme.md) tutorial runs a Scheme program.

That compatibility rests on Lofi's core being built so that erasing its typed
forms leaves an R7RS program — which is also how Chibi Scheme runs the
compiler's own source. [Bootstrap and self-hosting](bootstrap.md) sets out the
erasure property and the stages.

**Full Scheme.** `(scheme compiler)` is a Lofi library: a reader plus a
translator from R7RS source to the syntax of a Lofi library. Every Scheme
value is a `Datum`, the type of Scheme data in the dynamic libraries
(`datum`, `number`, `read`, `write`), so matching on one enum replaces
run-time type tests. Scheme code calls no typed Lofi code yet. *Proposed:*
wherever generated code meets typed Lofi code, the translator inserts
`(type-convert e T)`, liberally and without proving it necessary:

- **Upcast.** Converting a typed value to `Any` is checked statically and
  injects the value with its `TypeId`.
- **Downcast.** Converting an `Any` to a specific type checks the `TypeId` at
  run time and traps on a mismatch; `(type-test e T)` asks first, without
  trapping.
- **Redundancy.** The compiler removes conversions it proves redundant, such
  as a downcast of a value just upcast from the same type.

On Chibi, `type-convert` erases to its expression. A `generate-library` recipe
runs the translator:

```scheme
(generate-library (legacy program)
                  (import
                   (lofi base)
                   (lofi io)
                   (scheme compiler))
                  (scheme->lofi-library (list "legacy" "program") (read-file "program.scm")))
```
