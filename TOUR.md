# A tour of the compiler

The compiler is a pipeline of five passes. Each pass consumes the previous
pass's output and nothing earlier:

```text
text ──read──▶ located syntax
     ──expand─▶ core program      unique names, resolved types, entity tables
     ──check──▶ typed program     every expression typed, instances chosen
     ──mono───▶ monomorphic program
     ──wasm───▶ WasmGC text ──Binaryen──▶ module, linked with the Rust runtime
```

Read [`examples/fibonacci.sld`](examples/fibonacci.sld), run
`./lofi wat examples/fibonacci.sld` to see the WebAssembly it becomes, then
read the passes in order. The [language guide](doc/language.md) describes the
surface they implement.

## The passes

All compiler modules live in `src/lofi/compiler/` and are written in typed
Lofi: they import only `(lofi base)`, `(lofi table)` and `(lofi io)`, so the
compiler can compile itself. Chibi Scheme runs the same source through
`host/chibi/`, which implements those three libraries and erases the typed
forms. `(lofi table)` is an immutable table, so a pass threads its tables
as values where their scope is clear, such as the checker's local types,
and keeps state that grows over a whole pass in a `Ref`.

- **[`read.sld`](src/lofi/compiler/read.sld)** turns text into `Syntax`:
  atoms, identifiers and forms, each with a `Loc`. It is a recursive descent
  over a vector of characters; a line table recovers line and column only
  when a location is needed. It also decodes the bytes a `generate-library`
  producer writes, the encoding `(lofi syntax)` defines, straight into
  `Syntax`. `compile-error` reports every diagnostic.
- **[`core.sld`](src/lofi/compiler/core.sld)** defines the data the later
  passes share: `Type` (with effect rows), `Scheme`, class `Evidence`, the
  `Expr` tree, `Pattern`s, declared entities (`DataType`, `Class`,
  `Instance`, `Effect`), the `Program`, the primitive table, and TypeId
  hashing for wire types. A `Program` is a value: the expander builds it in
  one cell, and the later passes read it without effects.
- **[`expand.sld`](src/lofi/compiler/expand.sld)** is the only pass that
  knows binding forms. It loads libraries, replacing each `include-bytes`
  with the byte vector literal of its file, resolves every identifier through
  environments, and runs `syntax-rules`. Hygiene is renaming: each identifier
  a template introduces gets a mark that is unique to the expansion and, when
  unbound, resolves in the macro's own environment. Top levels expand in two
  passes so definitions may refer to later ones; local bodies are
  sequential. Declarations become entities in the program tables, derived
  wire instances are generated as ordinary instance syntax, and expressions
  become core `Expr`s with unique names.
- **[`check.sld`](src/lofi/compiler/check.sld)** is Hindley-Milner inference
  with effect rows. Unannotated top-level definitions are checked in
  dependency order (Tarjan's algorithm). Each instantiation records its type
  arguments and an evidence hole per class constraint. While items are
  checked, constraints are only recorded; a group of functions quantifies
  the metavariables nothing else still mentions. When the whole program is
  checked, literals default, and each class constraint is solved once,
  filling its hole. Rows unify as sets with open tails. Matches are checked
  with Maranget's usefulness algorithm. A function whose type forbids `mut`
  may mutate storage it allocates; once types are final, nothing it can
  reach from outside, its parameters, result or names it reads, may hold
  mutable storage.
- **[`mono.sld`](src/lofi/compiler/mono.sld)** starts from the program's
  statements and values and copies each reachable definition once per ground
  instantiation. A method reference becomes the instance method its evidence
  names, and definitions that only rename another, such as
  `(define + i64-add)`, are replaced by their target.
- **[`wasm.sld`](src/lofi/compiler/wasm.sld)** chooses representations and
  emits WebAssembly text. Scalars are Wasm numbers. An enum whose cases have
  no fields is an `i32`; other data are GC structs, and enum cases are final
  subtypes of a base holding the tag. Sequences are GC arrays. Functions are
  closures: a struct whose first field is a typed function reference, with
  captured variables in a subtype. Tail calls become `return_call`. Each
  effect has a global handler stack. Each GC type sits in the smallest
  recursion group it can, ordered by name, so modules that declare the same
  type declare the same group. Compiled one library at a time, a module
  exports its monomorphic definitions under their global names and imports
  other libraries' (doc/toolchain.md, section 3).
- **[`session.sld`](src/lofi/compiler/session.sld)** keeps the compiler
  running between builds: the expander replays libraries whose declarations
  and imports' interfaces are unchanged, and only libraries whose expansion
  changed are checked, specialized and emitted again.
- **[`compiler.sld`](src/lofi/compiler.sld)** composes the passes, from a
  program's path to WebAssembly text, or to one module's text per library.

## Around the compiler

| Path | Responsibility |
| --- | --- |
| `lofi`, `scripts/lofi.scm` | The command line: `run`, `compile`, `wat`, `serve` and `watch`. |
| `src/lofi/develop.sld`, `bootstrap/develop.sld` | The development loop behind `lofi serve`, `lofi watch` and the IDE, as a Lofi program: it keeps a session, debounces changes, writes each changed module and a manifest, and broadcasts build events, reaching its host only through the `develop` effect's commands. |
| `scripts/develop.mjs` | The loop's Node host: file watching, timers, HTTP with server-sent events, and running programs. |
| `host/chibi/lofi/` | The Chibi host: `forms` erases `struct`, `enum`, `match` and signatures; `base`, `table` and `io` implement the compiler's libraries with Chibi's; `build` runs Binaryen and Cargo to assemble, optimize and link a program. |
| `bootstrap/compile.sld` | The compiler's entry program when it runs as Wasm. |
| `lib/lofi/` | The standard library, written in Lofi. Chibi never loads it. `(lofi syntax)` is the syntax a `generate-library` recipe returns and the bytes its producer writes. |
| `lib/lpc/` | Liberated Pixel Cup character art, four packs checked in as they were published (see `ATTRIBUTION.md`), and libraries over them: `layout` (the sheets' grid), `catalog` (bodies, heads, hair and garments, and where each is drawn), `wardrobe` (characters dressed from the catalog, as layered pictures, spritebooks and portraits), `skins` (the skin ramps, generated from the pack's palette) and `embed` (helpers for recipes that compile images in as byte literals). |
| `lib/scheme/` | `(scheme compiler)`, which translates R7RS programs to Lofi libraries, and `(scheme runtime)`, their standard procedures. |
| `src/runtime/` | Rust services linked into every program: math, Unicode, float text, console and file I/O, panics; `files.rs` keeps files in memory for a host without a file system. |
| `src/assembler/`, `scripts/assemble.mjs` | The in-process assembler: the `wat` crate built for `wasm32-wasip1`, turning WebAssembly text into a module without Binaryen, under Node or in a browser. `scripts/assemble.mjs` drives it; programs never carry it. |
| `scripts/run-lofi.mjs` | Runs a compiled program, or a `modules.json` of linked modules, under Node's WASI, in a worker with room for deep recursion; it provides `(lofi wasm)`'s loading. |
| `src/app/` | The browser host for `(lofi app)`: input with pointer ids, ticks, a WebGPU renderer (one metallic-roughness shader for meshes and sprites, textures, upright sprites and frame strips, perspective or orthographic, glow, motion between ticks, translucent and revealed batches), `pictures.mjs` (images decoded from the bytes a program sends, composed into textures with color swaps), the keyed HUD with image widgets, and saves. `load.mjs` links a program compiled one library at a time; `host.mjs` relinks it from a changed module, handing over the state. `reload.sld` is the reload client, a Lofi program that compares build manifests and decides what a page does; `reload-client.mjs` binds it, and `reload.mjs` adds it to the pages `lofi serve` serves. |
| `src/ide/`, `scripts/build-ide.scm` | The browser IDE: an editor and the application on one page, and the development loop in a worker with the runtime's memory files. `build-ide.scm` packages it as a static site. |
| `scripts/build-app.scm` | Packages an application, with its `public/` files, as a static site. |
| `apps/siegework/` | The example game: `grid` and `terrain` (the seeded land), `world` (state, wires, power and sight), `colony` (orders and work), `siege` (attacks and combat), `simulation` (`act`, `advance` and the journal), `game` (camera, selection and commands), `view` and `hud`. |
| `apps/hearsay/` | A design for a social simulation game, and browser prototypes that test it: `mill` (stories spreading through a town) and `ledger` (an economy of favors), each with a `-screen` that draws and plays it; `cast` (an LPC character for each person) and `art` (the sheets they wear, embedded); and `shell`, the menu. |
| `examples/` | Small programs; the test suite runs them, and the book's tutorials show them. |
| `doc/book/`, `book.toml` | The book published on GitHub Pages; its chapters include the language guide, the redesign and Siegework's guide. |
| `tests/` | `run.scm` runs the unit tests, `tests/programs`, Siegework's scenarios, a headless game and `develop.mjs`, which drives `lofi serve` and `lofi watch` over the `tests/apps/counter` fixture, and programs linked one library at a time; `browser/reload.mjs` and `browser/ide.mjs` check live reload and the IDE in Chromium. |

## Checks

```sh
make test       # unit tests, programs, examples and Siegework
make check      # formatting
cargo test --manifest-path src/runtime/Cargo.toml --offline
cargo test --manifest-path src/assembler/Cargo.toml --offline
make site       # Siegework and Hearsay in build/siegework and build/hearsay
make ide        # the browser IDE around Siegework in build/ide
make test-browser  # live reload and the IDE in headless Chromium; CHROMIUM names it
make pages      # the book, with Siegework at play/siegework/, in build/pages
```

`node tests/browser/page.mjs URL SCREENSHOT` opens a page in headless
Chromium with software WebGPU and saves a screenshot.
