# Snail Scheme

**Scheme, but statically typed.** Snail Scheme has S-expressions, hygienic
macros, explicit types and effects, and exact-once ownership. Records are
mutable heap objects; primitive values stay unboxed. `Rc` and `WeakRc`
provide counted resource lifetime without source borrows. Functions use
`Fn` and `FnOnce` type formers with the Unicode `→` separator.

Top-level values initialize lazily at runtime. Their initializers must be
effect-free; each module instance evaluates once and shares the cached result,
including mutable objects. Reentrant initialization panics.

This is one language, with no R7RS compatibility layer, `call/cc` or
`dynamic-wind`. The compiler emits WasmGC and compiles itself; a small Chez
adapter runs its source for the first [bootstrap](bootstrap.md).

The chapters describe implemented behavior and mark proposed toolchain changes:

- [Terms](terms.md): programs, libraries, language forms and toolchain names.
- [Types](types.md): scalars, data, typeclasses, foreign functions, linked
  files and dynamic values.
- [Effects and handlers](effects.md): effect rows, handlers, control
  operations with a one-shot `resume`, and latent rows.
- [Macros and generated libraries](macros.md): hygienic expansion and explicit
  build-time producers.
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
