# Snail Scheme

**Scheme, but statically typed.** Snail Scheme has S-expressions, hygienic
macros, and explicit types and effects. Records are mutable heap objects
that any number of names may share; primitive values stay unboxed, and the
collector reclaims what nothing reaches. Functions use the `Fn` type former
with the Unicode `→` separator.

Top-level definitions bind functions. Construct values inside those functions
and pass shared state explicitly. There are no global value initializers or
implicit caches. Vectors have a fixed length and mutable elements.

This is one language, with no R7RS compatibility layer, `call/cc` or
`dynamic-wind`. The compiler emits WasmGC and compiles itself; a small Chez
adapter runs its source for the first [bootstrap](bootstrap.md).

The chapters describe implemented behavior and mark proposed toolchain changes:

- [Terms](terms.md): programs, libraries, language forms and toolchain names.
- [Types](types.md): scalars, data, typeclasses, foreign functions, linked
  files and dynamic values.
- [Effects and handlers](effects.md): effect rows, handlers, control
  operations with a one-shot `resume`, and latent rows.
- [Values](values.md): sharing, mutable records, closures, resources and
  their representation.
- [Macros and generated libraries](macros.md): hygienic expansion and explicit
  build-time producers.
- [Bootstrap and self-hosting](bootstrap.md): the erasure property, the two
  hosts and the stages that make the compiler compile itself.
- [Libraries](libraries.md): the standard library and wire types.
- [Projects and targets](projects.md): inert descriptions, output directories
  and embedded artifact bundles.
- [Compiler architecture](compilers.md): the passes, bootstrap, linking and
  complete rebuilds.
- [Application model](applications.md): interactive applications in the
  browser.
- [Development toolchain](toolchain.md): building one library at a time,
  hot reload, the native project editor and the proposed application workflow.
- [Proposed typed state](state.md): durable records and disposable cached views;
  an API for review, not implemented functionality.
- [Notable omissions](omissions.md): what was left out, and why.
- [References](references.md): influences and further reading.
