# TODO

Completed work lives in git history. Keep this list to open items, and keep
proposed language changes separate from implemented behavior.

## Language

- [ ] Complex numbers, mutable pairs and shared-structure labels in the
  dynamic Scheme libraries, which the port left out.
- [ ] Grow `(scheme compiler)` toward R7RS: macros, quasiquote, vectors and
  strings in full, and calls into typed Lofi code through `type-convert`.
- [ ] Literals at a generic numeric type, through the `Num` evidence.
- [ ] Superclasses, so `(Ord T)` can imply an equality class.
- [ ] Explicit overflow-checking arithmetic.
- [ ] Mutually recursive local functions.

## Compiler

- [ ] Decision trees for `match` with many cases, and nullable references for
  `Option`-shaped enums.
- [ ] Source locations in emitted Wasm.

## Development loop

`lofi serve` compiles only the libraries an edit reaches and relinks a
running page from the first changed module, handing over its state, and
`lofi watch` runs a program again after each edit; `make ide` runs the same
loop in a browser (doc/toolchain.md). Not implemented:

- [ ] Migrations between Save types, so a reload survives a schema change:
  an application would name a function from its old Save to its new one,
  as the redesign's section 5 proposes.
- [ ] Reloading long-running programs other than pages, such as servers once
  a `net` effect exists, with the same save and restore contract instead
  of a restart.
- [ ] Keeping the build cache on disk, so a cold start does not compile
  everything once.
- [ ] `(lofi wasm)` in browser hosts, and notebooks of compiled cells on it.

## Siegework

The pre-rewrite siege, look and HUD are restored on `(lofi app)`, with an
energy network in place of worker drones, journal saves, and seeded land
in four biomes. What
remains, none of it implemented:

- [ ] Export and import a journal, and a viewer that plays one back.
- [ ] The original's keyboard cell cursor on the arrow keys; they pan now.
- [ ] Picking tall buildings by their shape; a tap picks the ground cell.
- [ ] Make the siege harder now that the biomes vary the land: playtest
  costs, build times, yields, reach and the pressure of the attacks per
  biome, then tighten the balance program's bound on an undefended hub
  (tick 1000, set by the archipelago's long causeways).
- [ ] Check the HUD at phone sizes in a browser.
- [ ] Loading authored models, if hand-made assets replace the procedural ones.
