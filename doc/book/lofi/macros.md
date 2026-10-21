# Macros and Scheme libraries

Macros are hygienic `syntax-rules` transformers, defined with
`define-syntax` at the top level or in a local body. Surface forms such as
`let*`, `cond`, `case` and the variadic `list` are macros in `(lofi base)`,
and they expand away before checking, so the checker sees only the core.

A library file may hold a `generate-library` recipe instead of a
`define-library`: the compiler builds and runs that program first, and
compiles the library text it prints.

Scheme is a library too. `(scheme base)` gives R7RS names (`cons`, `car`,
`vector`, `char=?`, ...) over the typed language, and `(scheme compiler)`
translates R7RS programs into Lofi libraries, run by a `generate-library`
recipe, with `(scheme runtime)` for the standard procedures. The
[Scheme on Lofi](tutorials/scheme.md) tutorial runs a Scheme program.

The rest of this chapter is the design of that compatibility: Lofi's core is
built so that erasing its typed forms leaves an R7RS program, which is also
how Chibi Scheme runs the compiler's own source.

{{#include ../../redesign.md:bootstrap}}
