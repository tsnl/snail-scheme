# LoFI: Low-Level Functional IR

Lofi is a typed, pure-by-default functional language with Scheme syntax. It
compiles to WasmGC. Its typed forms (structs, enums, signatures, effects
and typeclasses) sit on a Scheme-shaped core: erase them and what remains
is an R7RS program with the same behavior. Languages are libraries: the
compiler is a Lofi program, and Scheme itself is offered as libraries over
the typed language.

The chapters describe what the compiler implements today:

- [Terms](terms.md): programs, libraries and the forms of the language.
- [Types](types.md): scalars, data, typeclasses, effects and dynamic values.
- [Macros and Scheme libraries](macros.md): hygienic macros, generated
  libraries and Scheme on Lofi.
- [Libraries](libraries.md): the standard library and wire types.
- [Compilers as libraries](compilers.md): the compiler's passes, and how it
  bootstraps from Scheme.
- [Application model](applications.md): interactive applications in the
  browser.
- [Notable omissions](omissions.md): what was left out, and why.
- [References](references.md): influences and further reading.
