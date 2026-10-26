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
- Compiler-owned `Send` and `Sync` evidence for structural data, including
  generic requirements and rejection of unsafe marker instances.
- Reusable `Send + Sync` handler environments, checked again when cached
  code depends on changed helper bodies.
- Type-directed affine `Once` work and concrete aggregates, with ownership
  checks and drops at last use. Generic parameters remain unrestricted.
- One-shot local tasks on shipping JSPI: dispatch, yield, timers, inherited
  ordinary handlers, cancellation and exhaustion accounting. GUI event and
  storage waits use the same scheduler; reload drains the old runtime.
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
  `lofi dev` and `make ide` expose the native project compiler to a browser editor.
- Pinned tools: `shell.nix` takes nixpkgs from an npins pin, and a podman
  devcontainer that CI builds packages the same tools.

## Next

1. Review the [project and development design](https://github.com/tsnl/snail-scheme/blob/design/desktop-ide-tasks-20261024/doc/proposals/desktop-ide.md):
   inert project descriptions, directory outputs and `lofi dev` with one
   shared file watcher, a persistent compiler and an independent editor UI.
   Settled toolchain work is being implemented; the typed-state API remains
   under review.
2. The other open items below. The redesign records the parts of its plan
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
rewrite. Pinned tools, the application main loop and cooperative tasks on
JSPI are done. WebGPU through an effect and the 2D and 3D `graphics`
libraries remain proposed; they do not depend on public `ctl` handlers.
Further runtime work includes:

- [ ] Specify and implement the [mixed memory and continuations
  draft](runtimes/memory-and-continuations.md) in the existing Wasm backend:
  `Gc` and raw `Ptr` representations, grade-polymorphic owners, Box/Arc/Weak,
  resource destruction and representation-aware transfer proofs.
- [ ] Lower public `ctl` and Scheme control into explicit affine and
  reusable continuations, including handler lifetimes and dynamic wind.
  Preserve the required effect evidence through specialization.
- [ ] Move scheduling and task lifecycle policy into Lofi, replacing JSPI
  with foreign completions that enqueue owned continuation invocations.
  Reduce Rust and JavaScript to allocation, foreign services and startup.
- [ ] Execute transferable linear-memory tasks across workers while keeping
  ordinary GC references and their captured continuations local. Shared GC
  references remain dependent on further engine support; the proposed
  linear-memory worker pool does not. Today only independent instances
  execute in parallel.
- [ ] Path-traced lighting over the rasterized G-buffer: a BVH built on the
  CPU first, compute-shader ray queries, and SVGF denoising, as the
  [path tracing primer](graphics/path-tracing.md) describes.

### Development loop

`lofi serve` compiles only the libraries an edit reaches and relinks a
running page from the first changed module, handing over its state, and
`lofi watch` runs a program again after each edit. `lofi dev`/`make ide` run
the separate native project development service and browser editor
([toolchain.md](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md)).
Not implemented:

- [ ] Building `generate-library` recipes in the loop: `lofi serve`,
  `lofi watch` cannot run a producer program yet. Project builds through
  `lofi build` and `lofi dev` support producers; use `make site` for a
  static application with generated libraries.
- [ ] Migrations between Save types, so a reload survives a schema change:
  an application would name a function from its old Save to its new one,
  as the redesign's section 5 proposes.
- [ ] Preserve server application records across code replacement by reopening
  the same database in the new process. This is required by the proposed
  `dev` design; today's `watch` does not supply a database binding or a server
  preservation contract. Arbitrary in-memory state is not saved automatically.
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
  relinking through `save` and `restore` instead of handing them over. The
  proposed durable-table replacement would remove state handover and this
  separate detection path.

### Projects, development and the IDE

`lofi dev PROJECT` and `make ide` run a native project service with a browser
editor: highlighting, Scheme indentation and format-on-save through `(lofi format)`,
full build diagnostics, disk conflict handling, a file browser and split panes.
The browser compiler, project copy and static IDE packaging are removed. The
[replacement design](https://github.com/tsnl/snail-scheme/blob/design/desktop-ide-tasks-20261024/doc/proposals/desktop-ide.md)
authorizes the settled project/IDE work. Its detailed
[state prototype](https://github.com/tsnl/snail-scheme/blob/design/desktop-ide-tasks-20261024/doc/proposals/typed-state.md)
remains under review:

- [x] Delete the integrated preview, its frame transport and application-host
  packaging. Keep editor formatting, diagnostics and split panes.
- [x] Replace browser project/build ownership with `lofi dev` for one project.
  Preserve formatting and splits; subscribe to native file/build updates. Keep
  drafts through conflicting external changes, delayed replies and file deletion.
- [x] Preserve structured compiler source points through the resident boundary,
  including failing artifact dependencies and generated source. The editor opens
  matching project files and marks saved buffers without parsing error prose.
  Full source spans and multiple-error recovery remain separate work.
- [x] Replace application build scripts with inert `project.datum` forms such as
  `build-target` and `run-target`. Every build target produces one output
  directory through `lofi build PROJECT TARGET`. This changes the compiler/CLI
  contract, not just the IDE. Prior completed generations remain until removed.
- [x] Parse project forms on Chibi and Wasm with located diagnostics and typed,
  resolved run references. File access, building and artifacts remain separate.
- [x] Make `compile -o` and `run -o` publish `program.wasm` in an output directory,
  preserving unrelated files and the last successful program on a failed build.
- [x] Resolve named artifact bundles during actual expansion, including
  dependencies from generated application libraries. One server can depend
  on multiple frontend bundles. Native project builds use one serial traversal
  through generated-library producers too; HTTP serving remains library work.
- [x] Implement the artifact macro, typed values and compiler resolver contract.
  Cached expansion re-resolves exact file evidence and invalidates generic
  consumers. Native traversal captures completed generation files for each build.
- [x] Replace stderr work requests with typed request/reply datums. The native
  builder retains artifact replies across retries and shares its target traversal
  through producer compilation. Scratch directories are exclusive.
- [x] Keep compiler sessions alive under `dev`. One shared watcher drives
  compilation from saved files and notifies the editor, including after
  external tools write files. Publish fresh diagnostics for every attempt.
  Omit unsaved build overlays and source-tree snapshot infrastructure.
- [x] Move the existing native incremental loop to one persistent compiler
  worker. HTTP and watches remain responsive during compilation; startup
  installs watches before the first build and shutdown closes owned resources.
  Project sessions, shared subscriptions and fresh attempt diagnostics use this
  execution boundary too.
- [x] Keep generated-library and artifact providers local to each compiler
  invocation. Persistent sessions retain cache evidence without keeping an old
  build's provider closures or captured state alive.
- [x] Expose the resident compiler through parsed native records and opaque
  Session values. Share the request/reply providers with the command-line
  compiler, capture diagnostics per call and retire instances on arbitrary
  traps. Shared project traversal and development use the same boundary.
- [x] Replace the separate Chibi project builder with one native builder for
  cold and incremental output. Keep successful Sessions per target, regenerate
  producers, and return private candidates before publication. Failed parents
  preserve dependency outputs; publication failure retains its completed prefix.
  The persistent worker and shared watcher use this builder too.
- [x] Remove the unused Chibi artifact-resolver binding and its reply state.
  Standalone source compilation retains generated libraries and rejects project
  artifact requests; real project builds use the native target traversal.
- [x] Provide one disk observer with independent subscriptions, metadata
  reconciliation and watch recovery. Explicit exclusions keep output/data
  directories separate; caller policy decides which observed paths need builds.
  Project attempts and editor file updates share its subscriptions. Metadata
  polling detects ordinary local writes, not every change on coarse or unusual
  filesystems.
- [x] Connect project compilation to a persistent native worker and shared
  observer. Retain parsed inputs even after a failed build; reconcile and reject
  observed superseded candidates before publication. Clear diagnostics at each
  attempt, preserve accepted outputs and clean abandoned worker namespaces.
  The native API, CLI and file service are connected. Diagnostics carry severity,
  message and an optional compiler source point. Application launch integration
  remains open.
- [x] Make cold tool builds independent of Chibi 0.12's pipe-descriptor
  finalizers. Native command capture uses private output files and a constant
  redirection script with positional arguments, including in the test runner.
- [x] Add native project text-file reads and atomic saves with client-held
  revision evidence. Reject observed conflicts and keep staging under excluded
  build output; Save neither retains buffers nor calls the compiler.
- [x] Bind the project attempt owner, file service and shared observer in one
  loopback HTTP API. Conditional saves, manual Build and current-status/file-change
  SSE stay responsive during compilation. The native `dev` command and editor use
  this boundary independently of typed-state review.
- [x] Give native suspensions ownership of successful results until delivery.
  Cancellation disposes undelivered resources and unwinds parked Wasm before
  task exhaustion; disposer failures also reject through the parked stack.
- [ ] Add concrete TCP and UDP socket effects and HTTP over TCP. Keep
  ordinary application subprocess controls; retain committed server records
  in concrete databases and derive browser working data through cached views.
  Keep storage identities stable and data writes outside source watching.
- [ ] Review typed tables, write transactions, coherent read snapshots and
  cached views. Replace checkpoint/resume and cross-build heap handover only
  after proving storage, cancellation and cache validity. Views rebuild on
  demand; incompatible durable schemas require explicit migration.
- [ ] Let `dev` subsume `watch`, development serving and the IDE. Reserve
  `serve` for production web applications; keep one-shot `build` and `run`.
- [ ] Prove debugger attachment to the actual Wasm execution agent, then
  source mappings and breakpoints, as separate follow-ups.

The browser-only IDE backend, embedded browser documents, virtual URL
schemes and browser release-build tooling are dropped from the plan. They
are not deferred milestones. Ordinary browser applications remain supported.
Other editor improvements remain open:

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
  empty list of disallowed effects. This language gap remains after removing
  the browser compiler handler that exposed it.

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
