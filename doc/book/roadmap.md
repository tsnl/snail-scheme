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
- `(lofi app)` applications own a JSPI loop with queued events, suspending
  storage, a reset binder and checkpoint handovers on reload. Their browser
  host retains meshes and sprites drawn by
  one metallic-roughness shader, textures composed from embedded image
  files, and 2D scenes seen straight down. Siegework and Hearsay's
  prototypes run on it; Hearsay's people are dressed from the checked-in
  LPC art (`lib/lpc`).
- Exact integers and rationals, Scheme data with `read` and `write`, and
  `(scheme compiler)`, which translates R7RS programs into Lofi libraries.
- Byte vector literals and `include-bytes`, and `generate-library`
  recipes that return syntax through `(lofi syntax)`, so an embedded file
  reaches the compiler as its bytes.
- A structural TypeId for `Any`, and `type-test`, which asks what an `Any`
  holds without trapping.
- Wire schema export (`lofi schema`) and bounded model checking of total
  state machines (`(lofi explore)`).
- A development loop: separate compilation of each library, with debug
  builds linked dynamically, so `lofi serve` relinks a running page from the
  first changed module and `lofi watch` reruns a program after each edit;
  `make ide` runs the same loop in a browser IDE.
- Pinned tools: `shell.nix` takes nixpkgs from an npins pin, and a podman
  devcontainer that CI builds packages the same tools.

## Next

1. The runtime and graphics rewrite, from milestone 3 of its
   [plan](graphics/plan.md): `ctl` operations, then WebGPU through an effect
   and the 2D and 3D graphics libraries.
2. Previews inlaid in the IDE's editor panes (below).
3. The other open items below. The redesign records the parts of its plan
   that were cut, such as the dependent elaborator.

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
- [ ] The same text from both hosts. The backend numbers closures, strings
  and lambdas as it emits them, some while evaluating a call's arguments,
  which Chibi evaluates right to left; so Chibi's stage 1 text numbers them
  differently from the Wasm compiler's. The two mean the same, and
  `make bootstrap` compares only the Wasm stages. The character classes differ too: Chibi's
  `char-numeric?`, `char-whitespace?` and `char-alphabetic?` accept Unicode,
  and Lofi's only ASCII.

### Runtime and graphics

The [runtime and graphics plan](graphics/plan.md) lists the milestones of the
rewrite. Pinned tools and the application main loop on JSPI are done;
`ctl` operations, WebGPU through an effect, and the 2D and 3D `graphics`
libraries remain proposed. Beyond them:

- [ ] Replace the removed actor API with one-shot tasks, runtime-owned
  event waits and cancellation. Keep the language ready for multithreading
  while the shipping WasmGC implementation uses one execution agent.

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

- [ ] Building `generate-library` recipes in the loop: `lofi serve`,
  `lofi watch` and the IDE cannot run a producer program yet, so an
  application with a generated library, such as Hearsay with its art, is
  built with `make site` instead.
- [ ] Migrations between Save types, so a reload survives a schema change:
  an application would name a function from its old Save to its new one,
  as the redesign's section 5 proposes.
- [ ] Reloading long-running programs other than pages, such as servers once
  a `net` effect exists, with the same save and restore contract instead
  of a restart.
- [ ] Keeping the build cache on disk, so a cold start does not compile
  everything once: entries keyed by content hashes and written atomically,
  validated on a cold start by hashing sources, as Bazel and Nix do.
- [ ] Interfaces as generated headers: each library's interface printed as
  a declaration-only library of S-expressions, whose text hash is the
  interface hash, as C++ modules, OCaml, GHC and Rust keep interface files.
- [ ] `(lofi wasm)` in browser hosts, with imports given by the caller.
- [ ] A native host for the loop in place of Node: Rust embedding wasmtime,
  once its support for WebAssembly GC matures.
- [ ] Closures in the state: detecting them from the state's type, and
  relinking through `save` and `restore` instead of handing them over.
- [ ] Release builds in a browser, with Binaryen compiled to WebAssembly if
  its threads and exceptions can be tamed.

### IDE

`make ide` builds a browser IDE: projects opened from disk, highlighting,
Emacs-style indentation and format-on-save through `(lofi format)`,
squiggles from the compiler's builds, Zed-style docks and split panes, and
the application relinked beside the editor
([toolchain.md](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md),
section 7). Not implemented:

- [ ] Previews inlaid in the editor panes: each preview compiled as its own
  module and loaded through `(lofi wasm)`, rerun when what it depends on
  changes, with no manual order.
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

### Hearsay

The rumor mill and the favor ledger, the first two of
[Hearsay's prototypes](https://github.com/tsnl/snail-scheme/blob/main/apps/hearsay/prototypes.md),
run in a browser. Not implemented:

- [ ] The third prototype, which waits until the first two hold up.
