# Roadmap

The [redesign](https://github.com/tsnl/snail-scheme/blob/main/doc/redesign.md)
describes the target language. Completed work lives in git history; this page
outlines what is implemented and lists the work still open. Open items
describe proposed behavior, kept apart from what is implemented.

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
- A development loop: separate compilation of each library, with debug
  builds linked dynamically, so `lofi serve` relinks a running page from the
  first changed module and `lofi watch` reruns a program after each edit.

## Next

1. Grow `(scheme compiler)` toward R7RS, and let Scheme code call typed Lofi
   code through `type-convert`.
2. Notebooks of compiled cells, on the toolchain that
   [toolchain.md](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md)
   describes: separate compilation with dynamic linking in debug builds,
   relinking single modules, the development loop in Lofi, the toolchain in
   a browser, and `(lofi wasm)`.
3. The open items below. The redesign records the parts of its plan that
   were cut, such as the dependent elaborator and the WGSL backend.

## Open items

### Language

- [ ] Complex numbers, mutable pairs and shared-structure labels in the
  dynamic Scheme libraries, which the port left out.
- [ ] Grow `(scheme compiler)` toward R7RS: macros, quasiquote, vectors and
  strings in full, and calls into typed Lofi code through `type-convert`.
- [ ] Literals at a generic numeric type, through the `Num` evidence.
- [ ] Superclasses, so `(Ord T)` can imply an equality class.
- [ ] Explicit overflow-checking arithmetic.
- [ ] Mutually recursive local functions.

### Compiler

- [ ] Decision trees for `match` with many cases, and nullable references for
  `Option`-shaped enums.
- [ ] Source locations in emitted Wasm.

### Runtime and graphics

The [runtime and graphics plan](graphics/plan.md) lists the milestones of the
rewrite: tools, a main loop on JavaScript Promise Integration (JSPI), `ctl`
operations, WebGPU through an effect, and the 2D and 3D `graphics`
libraries. Beyond them:

- [ ] Move `ctl` operations, such as the proposed `wait-event` and
  `read-buffer`, from JSPI to native stack switching. Chrome 156 implements
  core stack switching (`cont.new`, `resume` and `suspend`) only behind
  `--wasm-wasmfx`; once it is on by default, compile `ctl` handlers to
  one-shot continuations and drop the JSPI scheduler. Measured, a perform
  and resume costs about 300 ns on JSPI and 45 ns natively. Tests that use it
  need a Node release with stack switching.
- [ ] Path-traced lighting over the rasterized G-buffer: a BVH built on the
  CPU first, compute-shader ray queries, and SVGF denoising, as the
  [path tracing primer](graphics/path-tracing.md) describes.

### Development loop

`lofi serve` compiles only the libraries an edit reaches and relinks a
running page from the first changed module, handing over its state, and
`lofi watch` runs a program again after each edit; `make ide` runs the same
loop in a browser
([toolchain.md](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md)).
Not implemented:

- [ ] Migrations between Save types, so a reload survives a schema change:
  an application would name a function from its old Save to its new one,
  as the redesign's section 5 proposes.
- [ ] Reloading long-running programs other than pages, such as servers once
  a `net` effect exists, with the same save and restore contract instead
  of a restart.
- [ ] Keeping the build cache on disk, so a cold start does not compile
  everything once.
- [ ] `(lofi wasm)` in browser hosts.

### IDE

`make ide` builds a browser IDE: projects opened from disk, highlighting,
Emacs-style indentation and format-on-save through `(lofi format)`,
squiggles from the compiler's builds, Zed-style docks and split panes, and
the application relinked beside the editor
([toolchain.md](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md),
section 7). Not implemented:

- [ ] Previews inlaid in the editor panes, in place of #368's notebooks:
  each preview compiled as its own module and loaded through `(lofi wasm)`,
  rerun when what it depends on changes, with no manual order.
- [ ] Semantic highlighting: the lexer colors core forms, capitalized names
  and the names definitions introduce; the expander knows what every name
  resolves to (a local, a global, a type, a constructor, a macro), and a
  build could report it for the page to color.
- [ ] Editor plugins: a language server over the compiler's passes, with
  located diagnostics, types on hover from the checker, definitions through
  the expander's resolution, and completion of library exports; then thin
  plugins for Zed, VS Code and Emacs.
- [ ] More than one diagnostic per build, and warnings: the compiler stops
  at its first error and has no warnings yet.
- [ ] Creating, renaming and deleting files in the file browser.
- [ ] One undo history per buffer: each pane keeps the browser's own, so in
  a split, undoing in one pane does not reach an edit made in the other.
- [ ] `lofi format` through `(lofi format)`, so `make format` and `make
  check` need no Emacs.
- [ ] A row-polymorphic handler of a host-bound effect, such as
  `(All (e) (-> (-> Unit ! fs e) Unit ! files e))`, fails to check with an
  empty list of disallowed effects; src/ide/develop.sld spells its rows out.

### Siegework

The pre-rewrite siege, look and HUD are restored on `(lofi app)`, with an
energy network in place of worker drones, journal saves, and seeded land
in four biomes. What remains, none of it implemented:

- [ ] Export and import a journal, and a viewer that plays one back.
- [ ] The original's keyboard cell cursor on the arrow keys; they pan now.
- [ ] Picking tall buildings by their shape; a tap picks the ground cell.
- [ ] Make the siege harder now that the biomes vary the land: playtest
  costs, build times, yields, reach and the pressure of the attacks per
  biome, then tighten the balance program's bound on an undefended hub
  (tick 1000, set by the archipelago's long causeways).
- [ ] Check the HUD at phone sizes in a browser.
- [ ] Loading authored models, if hand-made assets replace the procedural ones.
