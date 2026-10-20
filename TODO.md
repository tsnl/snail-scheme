# TODO

Completed work lives in git history. Keep this list to open items, and keep
proposed language changes separate from implemented behavior.

## Language

- [ ] Port the dynamic Scheme libraries (`datum`, `read`, `write`, `number`,
  with exact integers and rationals) from the previous compiler's history to
  `lib/`.
- [ ] `generate-library`: build a library from the text a Lofi program prints.
- [ ] A Scheme surface: `(scheme base)` over `(lofi base)`, then the
  `(scheme compiler)` translator of the redesign's section 6.
- [ ] `type-convert` and `Any` for the boundary between typed and dynamic code.
- [ ] Literals at a generic numeric type, through the `Num` evidence.
- [ ] Superclasses, so `(Ord T)` can imply an equality class.
- [ ] Explicit overflow-checking arithmetic.
- [ ] Mutually recursive local functions.

## Compiler

- [ ] Compile the compiler with itself; the shim already gives Chibi the forms
  it uses. The compiler still uses `#f` for absent values and host hash tables.
- [ ] Separate checking: serialize each library's checked interface.
- [ ] Decision trees for `match` with many cases, and nullable references for
  `Option`-shaped enums.
- [ ] Source locations in emitted Wasm.

## Siegework

- [ ] Towers and guns as the original's rail network, artillery and upgrades
  were before the rewrite, if the game needs them.
- [ ] Hot reload of the module while keeping the running state.
