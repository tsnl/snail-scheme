# Compiler implementation

This directory contains the Chibi-hosted compiler. Library paths match names:
`infer.sld` declares `(lofi compiler infer)`, for example.

Start at `bootstrap.sld`, which composes library resolution, checking, concrete
demand and Wasm emission. The [repository tour](../../../TOUR.md) lists the passes
in reading order; the [compiler reference](../../../doc/compiler.md) describes
their contracts. Standard libraries remain beside this directory under `lofi/`.

`source-driver.sld` finds `.sld` dependencies and runs `generate-library`
recipes. `execute.mjs` loads compiled Wasm in JavaScript, checks providers and
invokes scalar entries. Chibi build services live in `../host/`; Rust Wasm
scalar services live in `../../runtime/`. The Wasm engine supplies managed
allocation and collection.

Chibi scripts import `(lofi compiler bootstrap)` through the repository's
`bootstrap/` loader view.
