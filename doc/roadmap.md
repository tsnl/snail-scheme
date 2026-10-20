# Roadmap

The [redesign](redesign.md) describes the target language. Its first
milestones are implemented; open items are tracked in [TODO.md](../TODO.md).

## Implemented

- A five-pass compiler: reader, expander, checker, monomorphizer and WasmGC
  emitter, written with Lofi's own data forms and hosted by Chibi.
- Structs, enums and nested pattern matching with exhaustiveness and
  redundancy checks.
- Typeclasses with generic instances and requirements; instances are chosen
  once, during checking.
- Effect rows with tail-resumptive handlers and host defaults.
- Wire types: derived `Serialize` and `Deserialize` with per-case TypeIds.
- `(lofi app)` applications with a browser host, and Siegework on top of it.
- Exact integers and rationals, Scheme data with `read` and `write`, and
  `generate-library`.

## Next

1. Grow a Scheme surface on `(lofi base)`, then the Scheme translator that
   `generate-library` and the dynamic libraries were ported for.
2. Compile the compiler with itself, and retire Chibi as the only host.
3. The dependent elaborator, WGSL backend and checked interfaces of the
   redesign's phases 4 and 5.
