# Snail-Core

Snail-Core is a typed, pure-by-default functional language with Scheme syntax. It
compiles to WasmGC. Scheme does not compile directly: its macros and
libraries expand it into Snail-Core, and checking, specialization and code
generation all happen there, so Scheme ships as libraries over the typed
language. The compiler is a Snail-Core program and compiles itself. Erasing
Snail-Core's typed forms leaves an R7RS program with the same behavior, which is
how stage 0 runs that source; [Bootstrap](bootstrap.md) explains it.

The chapters describe implemented behavior and mark proposed toolchain changes:

- [Terms](terms.md): programs, libraries, language forms and toolchain names.
- [Types](types.md): scalars, data, typeclasses, effects and dynamic values.
- [Macros and Scheme libraries](macros.md): hygienic macros, generated
  libraries and Scheme on Snail-Core.
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
