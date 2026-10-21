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

## Siegework

The pre-rewrite world, siege, look and HUD are restored on `(lofi app)`,
with an energy network in place of worker drones and journal saves. What
remains, none of it implemented:

- [ ] Hot reload: load a changed module in place and replay the journal
  into it, keeping the camera, rather than reloading the page.
- [ ] Export and import a journal, and a viewer that plays one back.
- [ ] The original's keyboard cell cursor on the arrow keys; they pan now.
- [ ] Picking tall buildings by their shape; a tap picks the ground cell.
- [ ] Playtest the balance: costs, build times, yields, reach and the
  pressure of the attacks. The balance program guards the extremes.
- [ ] Check the HUD at phone sizes in a browser.
- [ ] Loading authored models, if hand-made assets replace the procedural ones.
