# Compiler implementation

The public `(lofi compiler)` API remains in `../compiler.sld`. This directory
contains its implementation and adapters. Library paths match names:
`infer.sld` declares `(lofi compiler infer)`, for example.

Start at `bootstrap.sld`, which composes library resolution, checking, concrete
demand and Wasm emission. The [repository tour](../../../TOUR.md) lists the passes
in reading order; the [compiler reference](../../../doc/compiler.md) describes
their contracts. Standard libraries remain beside this directory under `lofi/`.

`builder.sld` implements the public library-builder data and transfer API.
`service.mjs`, `builder.mjs` and `execute.mjs` host those services for Wasm.
`native.sld` translates the artifact's checked entry metadata at the explicit
boundary to `(native)`. It does not change the compiler's Wasm output contract.

Chibi scripts import `(lofi compiler bootstrap)` through the repository's
`bootstrap/` loader view. Product programs import `(lofi compiler)`. The compiler
implementation is still hosted by Chibi.
