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

## Kernels

What `(lofi kernel)`, the REPL and the notebook do not do yet; none of it is
implemented.

- [ ] Typed cells: compile a cell as Lofi on a development server, check it
  against the kernel's libraries, and rebuild the kernel with it.
- [ ] Rich output: inline SVG, tables, or an application's frames drawn by
  the renderer in `src/app`, from a cell's value.
- [ ] Field access for opaque structs, so Scheme can read a typed value
  without a bound accessor per field.
- [ ] Track the effects of bound functions, so a kernel can bind `fs` and
  other host effects safely.
- [ ] A fixnum case for `Number`: interpreted and translated Scheme spend
  most of a counting loop in exact rational arithmetic.
- [ ] Quasiquote and `syntax-rules` in `(scheme eval)`, shared with
  `(scheme compiler)`.
- [ ] Save notebook files through a development server, not only by export.

## Editing

Lofi is edited as Scheme today: editors highlight it with their Scheme
modes, `scripts/format-scheme` formats it, and notebook cells are plain
text areas. None of the following is implemented. It could grow into a
browser-based IDE around the notebook, which is not planned yet.

- [ ] Syntax highlighting of Lofi's own forms (`struct`, `enum`, `match`,
  `:`, signatures and effect rows) in notebook cells, from the reader's
  tokens, so the page and the compiler agree on what a form is.
- [ ] Editor plugins: a language server over the compiler's passes, with
  located diagnostics, types on hover from the checker, definitions through
  the expander's resolution, and completion of library exports; then thin
  plugins for Zed, VS Code and Emacs.
- [ ] The notebook as a client of the same server: diagnostics and types in
  cells, and completion beyond the REPL's names.

## Compiler

- [ ] Decision trees for `match` with many cases, and nullable references for
  `Option`-shaped enums.
- [ ] Source locations in emitted Wasm.

## Siegework

- [ ] Towers and guns as the original's rail network, artillery and upgrades
  were before the rewrite, if the game needs them.
- [ ] Hot reload of the module while keeping the running state.
