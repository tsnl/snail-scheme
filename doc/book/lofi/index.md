# LoFI: Low-Level Functional IR

Lofi is a typed, pure-by-default functional language with Scheme syntax. It
compiles to WasmGC. Its typed forms (structs, enums, signatures, effects
and typeclasses) sit on a Scheme-shaped core: erase them and what remains
is an R7RS program with the same behavior. Languages are libraries: the
compiler is a Lofi program, and Scheme itself is offered as libraries over
the typed language.

The chapters describe implemented behavior and mark proposed toolchain changes:

- [Terms](terms.md): programs, libraries, language forms and toolchain names.
- [Types](types.md): scalars, data, typeclasses, effects and dynamic values.
- [Macros and Scheme libraries](macros.md): hygienic macros, generated
  libraries and Scheme on Lofi.
- [Bootstrap and self-hosting](bootstrap.md): the erasure property, the two
  hosts and the stages that make the compiler compile itself.
- [Libraries](libraries.md): the standard library and wire types.
- [Projects and targets](projects.md): inert descriptions, output directories
  and embedded artifact bundles.
- [Compiler architecture](compilers.md): the passes, bootstrap, linking and
  incremental compilation.
- [Application model](applications.md): interactive applications in the
  browser.
- [Development toolchain](toolchain.md): building one library at a time,
  hot reload, the native project editor and the proposed application workflow.
- [Proposed typed state](state.md): durable records and disposable cached views;
  an API for review, not implemented functionality.
- [Notable omissions](omissions.md): what was left out, and why.
- [References](references.md): influences and further reading.
