# Roadmap

The [redesign](redesign.md) describes the target language. Its first
milestones are implemented; open items are tracked in [TODO.md](../TODO.md).

## Implemented

- A five-pass compiler: reader, expander, checker, monomorphizer and WasmGC
  emitter, written in typed Lofi. It compiles itself; Chibi runs its source
  to start the first bootstrap.
- Structs, enums and nested pattern matching with exhaustiveness and
  redundancy checks.
- Typeclasses with generic instances and requirements; instances are chosen
  once, during checking.
- Effect rows with tail-resumptive handlers and host defaults.
- Wire types: derived `Serialize` and `Deserialize` with per-case TypeIds.
- `(lofi app)` applications with a browser host, and Siegework on top of it.
- Exact integers and rationals, Scheme data with `read` and `write`,
  `generate-library`, and `(scheme compiler)`, which translates R7RS
  programs into Lofi libraries.
- Wire schema export (`lofi schema`) and bounded model checking of total
  state machines (`(lofi explore)`).

## Next

1. Grow `(scheme compiler)` toward R7RS, and let Scheme code call typed Lofi
   code through `type-convert`.
2. Notebooks of compiled cells, on the toolchain that
   [toolchain.md](toolchain.md) describes: separate compilation with dynamic
   linking in debug builds, relinking single modules, the development loop
   in Lofi, the toolchain in a browser, and `(lofi wasm)`.
3. Open items in [TODO.md](../TODO.md). The redesign records the parts of
   its plan that were cut, such as the dependent elaborator and the WGSL
   backend.
