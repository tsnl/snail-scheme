# `snail-scheme`

**`snail-scheme` is a statically-typed Scheme successor.** It has S-expressions, hygienic
macros, explicit types, and capabilities passed as values. Records are mutable heap objects
that any number of names may share; primitive values stay unboxed, and the
collector reclaims what nothing reaches. Functions use the `Fn` type former
with the Unicode `→` separator.

A top-level definition is a value: its initializer runs at most once, on the
first read, changes nothing, and every read shares the result. A function
definition is shorthand for defining a lambda. Arrays have a fixed length
and mutable elements.

This is one language, with no R7RS compatibility layer, `call/cc` or
`dynamic-wind`. The compiler emits WasmGC and compiles itself; a small Chez
adapter runs its source for the first [bootstrap](bootstrap.md).

These chapters describe the language:

- [Terms](terms.md): programs, libraries, language forms and toolchain names.
- [Types](types.md): scalars, data, typeclasses, foreign functions, linked
  files and dynamic values.
- [Capabilities](capabilities.md): capabilities as values, how `main`
  asks its target for them, and what a signature does not say.
- [Suspension](suspension.md): prompts, exceptions, generators and a
  one-shot `resume`.
- [Values](values.md): sharing, mutable records, closures, resources and
  their representation.
- [Macros and generated libraries](macros.md): hygienic expansion and explicit
  build-time producers.
- [Notable omissions](omissions.md): what was left out, and why.
- [References](references.md): influences and further reading.

[Building programs](applications.md) covers applications, workspaces,
builds, the toolchain and the compiler; the [library reference](../libraries/index.md)
lists every library; and [proposed typed state](state.md) is an API for
review, not implemented functionality.
