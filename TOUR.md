# A tour of the compiler

The compiler is a pipeline of five passes. Each pass consumes the previous
pass's output and nothing earlier:

```text
text ──read──▶ located syntax
     ──expand─▶ core program      unique names, resolved types, entity tables
     ──check──▶ typed program     every expression typed, instances chosen
     ──mono───▶ monomorphic program
     ──wasm───▶ WasmGC text ──assemble──▶ module, linked with the Rust runtime
```

Release builds assemble and optimize with Binaryen; debug builds assemble
each library's module with the `wat` crate, in process.

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
  `Instance`, `Effect`), the `Program`, the primitive table, TypeIds for
  wire cases and `Any` values from one FNV-1a hash, and the strongly
  connected components that the checker and the backend share. A `Program`
  is a value: the expander builds it in one cell, and the later passes read
  it without effects.
- **[`expand.sld`](src/lofi/compiler/expand.sld)** is the only pass that
  knows binding forms. It loads libraries, replacing each `include-bytes`
  with the byte vector literal of its file, resolves every identifier through
  environments, and runs `syntax-rules`. Hygiene is renaming: each identifier
  a template introduces gets a mark that is unique to the expansion and, when
  unbound, resolves in the macro's own environment. Top levels expand in two
  passes so definitions may refer to later ones; local bodies are
  sequential. Declarations become entities in the program tables, derived
  wire instances are generated as ordinary instance syntax, and expressions
  become core `Expr`s with unique names. Each library's build key, the text
  of its declarations with its imports' interfaces, lets a session replay
  it.
- **[`check.sld`](src/lofi/compiler/check.sld)** is Hindley-Milner inference
  with effect rows. Unannotated top-level definitions are checked in
  dependency order (core's `strong-components`). Each instantiation records its type
  arguments and an evidence hole per class constraint. While items are
  checked, constraints are only recorded; a group of functions quantifies
  the metavariables nothing else still mentions. Libraries are checked one
  at a time; when a library is checked, its literals default, and each
  class constraint is solved once, filling its hole. Rows unify as sets with open tails. Matches are checked
  with Maranget's usefulness algorithm. A function whose type forbids `mut`
  may mutate storage it allocates; once types are final, nothing it can
  reach from outside, its parameters, result or names it reads, may hold
  mutable storage.
- **[`capabilities.sld`](src/lofi/compiler/capabilities.sld)** establishes
  structural `Send` and `Sync` evidence from types and declared fields.
  The checker resolves these compiler-owned markers; user instances cannot
  override them. Ordinary arrows carry no proof about their captures.
- **[`handlers.sld`](src/lofi/compiler/handlers.sld)** checks that a handler's
  retained environment is reusable and satisfies `Send + Sync`. It follows
  closure aliases, named helpers and selected method evidence to their
  captures and globals, while keeping invocation arguments and fresh local
  storage separate. Unknown callback provenance is rejected.
- **[`mono.sld`](src/lofi/compiler/mono.sld)** starts from the program's
  statements and values and copies each reachable definition once per ground
  instantiation. A method reference becomes the instance method its evidence
  names, and definitions that only rename another, such as
  `(define + i64-add)`, are replaced by their target.
- **[`ownership.sld`](src/lofi/compiler/ownership.sld)** consumes affine
  locals once per path after specialization. Branches fork and intersect
  their live owners; a path drops a value when it has no remaining use.
  Only one-shot closures can own affine captures. Concrete records inherit
  their fields' grade; existing generic parameters remain unrestricted.
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
  other libraries' (doc/toolchain.md, section 3). At the host boundary it
  stages final String and Bytes arguments and wraps exposed `(Option Any)`
  as a nullable opaque handover. Dynamic handler globals are exported so
  the host can restore an entry's context after it settles. Shared-message
  conversions prove deep immutability on concrete types before using the
  opaque boundary, and check the type and GC representation on recovery.
- **[`session.sld`](src/lofi/compiler/session.sld)** keeps the compiler
  running between builds: the expander replays libraries whose declarations
  and imports' interfaces are unchanged, and only libraries whose expansion
  changed are checked, specialized and emitted again. Cached emissions keep
  their monomorphic items so handler capture proofs can be rechecked against
  current helper bodies without regenerating unchanged Wasm text.
- **[`compiler.sld`](src/lofi/compiler.sld)** composes the passes, from a
  program's path to WebAssembly text, or to one module's text per library.

## Around the compiler

The table describes current responsibilities. The
[project and development proposal](doc/proposals/desktop-ide.md) moves
application build recipes into project descriptions and unifies development
under `lofi dev`; those changes are not implemented yet. Use the book's
[terms](doc/book/lofi/terms.md#toolchain-terms) for projects, compiler sessions,
runtimes and application processes.

- **[`src/app/tasks.mjs`](src/app/tasks.mjs)** schedules task starts and
  one-shot JSPI resumptions. One execution permit protects dynamic handler
  bindings; a live-task set accounts for queued work, waits and cleanup.
  I/O adapters own their abortable registrations and settle after cleanup.

| Path | Responsibility |
| --- | --- |
| `lofi`, `scripts/lofi.scm` | The command line: `run`, `compile`, `build`, `wat`, `schema` and `bootstrap`; `-o` publishes a directory's `program.wasm` through `(lofi build)`, and `build` selects one project target. `lofi` hands `serve` and `watch` to `scripts/develop.mjs`. |
| `src/lofi/develop.sld`, `bootstrap/develop.sld` | The development loop behind `lofi serve`, `lofi watch` and the IDE, as a Lofi program: it keeps a session, debounces changes, writes each changed module and a manifest, broadcasts build events, keeps only the latest build's and the previous build's modules, and serves every file in `src/app`, reaching its host only through the `develop` effect's named commands. `bootstrap/develop.sld` exposes its entry points for Node. |
| `src/lofi/project.sld` | Parses inert `project.datum` through the compiler's located reader. Returns typed program/browser builds and resolved program run targets, with lexical path and duplicate checks. It does no file IO, expansion or building. |
| `src/lofi/compiler/inputs.sld` | Parses and prints the two concrete native compiler requests (generated syntax and named artifacts) and artifact-file replies. Missing inputs are recorded in memory; host entries publish requests after unwinding. The native builder supplies them and retries in exclusively owned scratch. Stderr carries only diagnostics. |
| `lib/lofi/artifact.sld` | Ordinary artifact-file/bundle structs and the hygienic `artifact-bundle` macro. The expander consumes immutable file inputs and retains exact evidence for cache reuse. Project builds supply named browser targets. |
| `host/chibi/lofi/project-build.sld` | Parses one project, traverses targets as compiler requests arise, and reuses completed generations within the invocation. It detects active-target cycles through producer compilation, packages browser files, enumerates sorted immutable file paths and atomically publishes each target's output link. Owns the browser-host file list and preserves prior generations. |
| `scripts/develop.mjs` | The native parent owns watchers, timers, HTTP/SSE and application children. It forwards events to one persistent compiler worker and performs its five asynchronous commands. Shutdown closes resources and prevents queued child replacement. |
| `scripts/develop-worker.mjs` | Owns the Wasm development loop, incremental compiler session, assembler and synchronous file helpers. Serial entries preserve the instance across compiler errors. Immediate results remain here; the parent stays responsive during compilation. |
| `host/chibi/lofi/` | The Chibi host: `forms` erases `struct`, `enum`, `match` and signatures; `base`, `table` and `io` implement the compiler's libraries with Chibi's; `build` runs Binaryen and Cargo to assemble, optimize and link a program, gives each compile a private directory, rebuilds the compiled compiler and the development tools under `build/lock` when they are stale, and lends the scripts its file helpers. |
| `src/lofi/compiler/driver.sld`, `bootstrap/compile.sld` | The typed compiler invocation shared by both hosts. The Wasm entry initializes globals and exposes compilation and post-exit request publication separately. |
| `host/chibi/compile.scm`, `scripts/run-compiler.mjs` | Compiler-specific unwind boundaries. Publish pending input requests after a normal compiler exit, distinguish host/publication failure, and preserve resource cleanup. |
| `lib/lofi/` | The standard library, written in Lofi. Chibi never loads it. `(lofi syntax)` is the syntax a `generate-library` recipe returns and the bytes its producer writes. `(lofi sprite)` poses figures from spritebooks. `format.sld` reproduces `scripts/format-scheme`, which the tests check on every Scheme file in the repository, and highlights by the same lexical rules. |
| `lib/lpc/` | Liberated Pixel Cup character art, four packs checked in as they were published (see `ATTRIBUTION.md`), and libraries over them: `layout` (the sheets' grid), `catalog` (bodies, heads, hair and garments, where each is drawn, and which builds wear each garment in which dyes), `wardrobe` (characters dressed from the catalog into the sheets of their layers, composed into pictures and portraits), `skins` (the skin ramps, generated from the pack's palette) and `embed` (helpers for recipes that compile images in as byte literals). |
| `lib/scheme/` | `(scheme base)`, R7RS names over the typed language; `(scheme compiler)`, which translates R7RS programs to Lofi libraries; and `(scheme runtime)`, the standard procedures their code calls. |
| `src/runtime/` | Rust services linked into every program: math, Unicode, float text, console and file I/O, panics. |
| `src/assembler/`, `scripts/assemble.mjs` | The in-process assembler: the `wat` crate built for `wasm32-wasip1`, turning WebAssembly text into a module without Binaryen, under Node or in a browser. `scripts/assemble.mjs` binds it for the loop's hosts; programs never carry it. |
| `scripts/run-lofi.mjs` | Runs a compiled program, or a `modules.json` of linked modules, under Node's WASI, in a worker with a tuned GC heap. It provides `(lofi wasm)` loading and the task scheduler. JSPI stacks remain finite. |
| `src/app/entry.mjs` | Wasm application entries, effect-handler restoration and owned snapshots of foreign byte arguments. |
| `src/app/` | The browser host for `(lofi app)`: input with pointer ids, ticks, a WebGPU renderer (one metallic-roughness shader for meshes and sprites, textures, upright and flat sprites, frame strips, perspective or orthographic, glow, motion between ticks, translucent and revealed batches), `pictures.mjs` (images decoded from the bytes a program sends, composed into textures with color swaps), the keyed HUD with image widgets, and saves. `load.mjs` runs Lofi programs the same way in Node and browsers: a WASI shim, linking a program compiled one library at a time and relinking it from a changed module (`relinkProgram`), the binding of named commands, and the reader of the loop's events and manifests. `runtime.mjs` owns queued application events, asynchronous storage and checkpoint recovery on the shared task scheduler; its stable imports survive library relinks. `host.mjs` owns the page's durable renderer, pictures and HUD, enqueues DOM input, relinks every running application (`relinkAll`) after its old tasks settle, and exports its screen binding for headless tests. `reload.sld` is the reload client, a Lofi program that compares build manifests and decides what a page does; `reload-client.mjs` binds it, and `reload.mjs` adds it to the pages `lofi serve` serves. |
| `src/ide/`, `scripts/build-ide.scm` | The browser IDE. `develop.sld` is the development loop with its files in the worker, through a handler of `fs`, and `toolchain.mjs` the worker; `format.sld` is the formatter as a program; `ide.mjs` lays out the toolbar, docks and files, `panes.mjs` the tree of panes, `editor.mjs` one pane, `project.mjs` keeps project files and directory handles. The editor does not execute the application. `build-ide.scm` packages it as a static site. |
| `apps/siegework/` | The example game: `grid` and `terrain` (the seeded land), `world` (state, wires, power and sight), `colony` (orders and work), `siege` (attacks and combat), `simulation` (`act`, `advance` and the journal), `game` (camera, selection and commands), `view` and `hud`. |
| `apps/hearsay/` | A design for a social simulation game, and browser prototypes that test it: `mill` (stories spreading through a town) and `ledger` (an economy of favors), each with a `-screen` that draws and plays it; `cast` (an LPC character for each person) and `art` (the sheets they wear, embedded); `hud`, the panel pieces both screens share, with the guide that explains each prototype and the empty scene behind a screen; and `shell`, the menu. Its styles are in `public/app.css`. |
| `examples/` | Small programs; the test suite runs them, and the book's tutorials show them. |
| `doc/` | The language guide (`language.md`), the redesign and its history (`redesign.md`), the toolchain design (`toolchain.md`), and how to install the tools (`getting-started.md`). |
| `doc/book/`, `book.toml` | The book published on GitHub Pages; its chapters include the language guide, the redesign and Siegework's guide, and its roadmap tracks open work. |
| `shell.nix`, `npins/`, `rust-toolchain.toml`, `.devcontainer/` | The pinned tools: nixpkgs from an npins pin, the Rust toolchain, and a podman devcontainer with the same tools and Chromium, which CI builds. |
| `scripts/format-scheme`, `scripts/format-scheme.el` | The Scheme formatter, Emacs's scheme-mode with the repository's rules, which `make format` and `make check` run. |
| `tests/` | `run.scm` runs the unit tests, `tests/programs`, Siegework's scenarios, a headless game and `develop.mjs`, which drives `lofi serve` and `lofi watch` over the `tests/apps/counter` fixture, and programs linked one library at a time; `browser/reload.mjs` and `browser/ide.mjs` check hot reload and the IDE in Chromium. |

## Checks and builds

[Getting started](doc/getting-started.md) lists the checks and the tools
each needs. The builds:

```sh
make site       # Each application's site in apps/NAME/build/site
make ide        # the browser editor opening Siegework in build/ide
make pages      # the book, with Siegework at play/siegework/, in build/pages
```

`node tests/browser/page.mjs URL SCREENSHOT` opens a page in headless
Chromium with software WebGPU and saves a screenshot.
