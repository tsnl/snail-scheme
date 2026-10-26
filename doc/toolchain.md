# Toolchain: linking, hot reload and development

> **Status: implemented**, except where a section says *proposed*. The book's
> [roadmap](book/roadmap.md) tracks what is left.
>
> The [project and development proposal](proposals/desktop-ide.md) puts project
> builds, a shared file watcher and persistent compilation under `lofi dev`.
> The editor subscribes independently; applications run as ordinary
> subprocesses, preserving durable facts and deriving working state through
> disposable views. The [state prototype](proposals/typed-state.md) remains
> under review while independent IDE/project work proceeds. The commands and relink
> behavior below describe the current implementation; browser-only IDE and
> integrated preview work is dropped from the replacement plan.

This document describes how Lofi programs are built, linked, reloaded and
loaded during development, so that a rebuild costs as much as the edit
that caused it. The compiler and assembler run as Wasm; native code owns project
traversal and processes. The older browser toolchain remains until the IDE becomes
a native service's client. C is the reference model: programs can link statically
or by library, and code loaded at run time is reached through an explicit,
unchecked cast.

## 1. Goals

1. Rebuild and reload in proportion to the edit, not to the program.
2. Hot reload at the granularity of a module, keeping the application's
   state.
3. Load compiled code while a program runs, including `generate-library`
   producers.
4. Keep compiler decisions in Lofi and native project/process ownership explicit.
5. The current implementation runs the whole debug toolchain in a browser.
   The proposed `dev` keeps a native incremental compiler alive and gives
   the editor file/build subscriptions.

## 2. Where a rebuild's time goes

Before this work, a rebuild of Siegework through `lofi serve` took about
1.4 seconds, half of it work a debug build need not do:

| Step | Time |
| --- | --- |
| Starting Chibi and loading the driver, `(lofi build)` | 345 ms |
| Compiling every library to WebAssembly text with the compiled compiler | 463 ms |
| Optimizing twice with `wasm-opt` | 170 ms |
| Assembling with `wasm-as` and merging the runtime with `wasm-merge` | 170 ms |
| Starting Node | 26 ms |

Now the development loop is a long-lived Lofi program that compiles one
library at a time, keeps what it compiled in memory, and assembles
without Binaryen:

| Build | Desktop | Browser worker |
| --- | --- | --- |
| Siegework, first build, 14 modules | about 450 ms | about 550 ms |
| Siegework, an edit to one function body, 1 or 2 modules | 70 to 110 ms | 50 to 100 ms |
| The counter of `tests/apps/counter`, an edit | 25 to 50 ms | about 30 ms |

## 3. Linking, after C

| Build | Linking |
| --- | --- |
| Static | The whole program is compiled at once, optimized and tree-shaken, and the Rust runtime is merged in. `lofi compile`, `lofi run`, `lofi build` and `make site` build this way; `--release` increases optimization. |
| Development | Each library is compiled to its own module, and the modules are linked when the program is instantiated. The Rust runtime is a separate instance, like a shared C library. Nothing is optimized or tree-shaken. `lofi serve`, `lofi watch` and the browser IDE build this way. |
| Either | Code loaded while the program runs, through `(lofi wasm)` (section 3.3). |

### 3.1 Separate compilation

The unit of compilation is a library (`compile->modules` in
`src/lofi/compiler.sld`). In its module:

- each monomorphic definition is exported under its global name, as in
  `lofi.base:map`;
- each generic definition and alias the library uses is copied in,
  specialized at the library's own types, as C++ instantiates a template in
  every translation unit that uses it;
- each monomorphic definition of another library is imported from that
  library's module;
- each effect's stack of handlers is a global that the declaring library's
  module exports and the others import.

The checker settles each library's types before it checks the libraries
that import it, so a definition's type comes from its own library and not
from how an importer happens to use it.

A **session** (`src/lofi/compiler/session.sld`) compiles a program again
and again, as the development loop does, keeping everything in memory:

- The expander replays a library, adding what it added before, when its
  declarations read the same and its imports show the same interfaces.
- A library's **interface** is what importers depend on: its imports and
  exports, every declaration except the bodies of definitions whose
  signatures are monomorphic, and its imports' interfaces, since its
  generic code carries theirs into importers. It is hashed, as GHC uses
  interface hashes to avoid recompilation.
- Each library's checked items, type schemes and module text are kept
  under the expansion they came from. A build checks, specializes and
  emits only the libraries whose expansion changed.

`make-session` fixes its library directories. `build-session` receives the
generated-library provider and artifact snapshots for that invocation. A
returned session keeps only compilation evidence. Cached artifact uses must
still match the current snapshots before expansion is reused. A failed build returns no
replacement session.

`bootstrap/compiler.sld` exposes this compiler to a resident native caller.
`scripts/compiler.mjs` owns one Wasm instance and returns parsed project and
input-request records, static text, or modular text with a successor Session.
JavaScript retains a Session as an opaque `Any`; it cannot inspect it and must
keep it with its originating compiler instance. Each operation consumes its staged arguments
before doing work, and projected records become visible only on success.

The compiler records missing inputs in memory. After a trusted diagnostic exit
unwinds, the resident boundary projects the pending request into the returned
`CompilerFailure`; it needs no request file. Each invocation resets this state.
Generated syntax and artifact replies belong to a logical compilation's private
scratch. The resident boundary constructs artifact replies through Lofi's
printer and loads their snapshots before expansion. Native code needs no datum
parser or string-escaping implementation. Its caller handles requests after
Wasm unwinds; the boundary itself neither retries nor traverses projects.

Each native call starts with empty diagnostic storage. The trusted compiler's
code-1 diagnostic exits follow resource cleanup and allow another call with
the last successful Session. Arbitrary Wasm or imported-function traps retire
the instance. This distinction comes from the runtime exit path, not from
finding a familiar string in stderr. These operations are implemented and
tested. `scripts/project.mjs` now calls them for cold and resident project builds;
the shared watcher and replacement development loop are the next integration step.

The native builder owns serial target traversal, producer execution and packaging.
Each attempt creates private generations and discovers dependencies only through
compiler requests. Successful Sessions advance independently of output acceptance;
they retain evidence, not backing-file lifetimes. Static output uses the existing
linker through `scripts/link.scm`, with intermediates kept in scratch. Development
output assembles all returned modules into a fresh self-contained directory.
Only the compiler cache persists; there is no second native binary cache.

A completed attempt returns a candidate. `scripts/build.mjs` accepts it immediately;
a future watcher parent can reject superseded work. Publication and discard consume
the candidate. If one of several link renames fails, publication preserves its
completed prefix and removes the remaining generations; it is not a project-wide
transaction. Failed compilation or packaging publishes nothing.

So an edit to a function body with a signature recompiles one library. An
edit to an interface recompiles the libraries that import it too. The
loop assembles each changed module into a file named after a hash of its
text, so a page fetches a module again only when it changed. Nothing is
kept on disk; a cold start compiles everything once.

### 3.2 Dynamic linking

A module imports each function of another library by the library's name,
and the loader (`src/app/load.mjs`) instantiates the runtime, then the
modules in program order, so every module comes after those it imports
from. Calls across libraries are direct calls to imported functions.

WebAssembly treats two GC types as the same only when their whole
recursion groups match. The backend therefore puts each type in the
smallest recursion group it can have: the strongly connected component of
the graph of references between types, ordered by name, with the groups it
refers to emitted first. Every module that uses a type declares the
identical group, and the engine's canonicalization makes them one type
across modules. A case of an enum without fields declares no type of its
own, since only the modules that build or match it would declare one.

Lofi types are checked at compile time, each library against the
interfaces it imports. Nothing checks them at load time: every module of a
link comes from one build of one session, which recompiles importers
whenever an interface changes. The engine still checks the WebAssembly
type of every import, and a value that crosses as `Any` keeps its own
check at `type-convert`.

Replacing a library's module means linking it and every module after it
in program order again (`relinkProgram` in `load.mjs`); the modules before
it cannot import from it. That
costs the instantiation of a few modules, and keeps debug code free of the
indirection that a table of mutable globals, like ELF's global offset
table, would add to every call across libraries.

### 3.3 Loading modules at run time

`(lofi wasm)` is `dlopen` and `dlsym`. It loads a module from a file,
linked against the runtime, the program's own modules and the modules
loaded before it, by name. A function the module exports comes out as a
`Funcref`, and `unsafe-cast` makes it a function of the type the context expects:

```scheme
(let* ((cell (load-module "cell" "build/cell.wasm"))
       (run (ann (unsafe-cast (module-export cell "cell:run")) (-> I64 I64))))
  (run 41))
```

`unsafe-cast` is a primitive. It wraps the reference in a closure whose
code casts it to the WebAssembly type of a function of the expected type
and calls it. The cast is the only check: the engine traps when the
WebAssembly types differ, and nothing compares Lofi types, so the unsafe
assumption is visible where it is made. `tests/programs/wasm.sld` loads a
module it writes itself.

The Node runner provides the `wasm` effect for both builds. A statically
linked program exports nothing of its runtime, so what it loads can link
only against the host. Browser hosts do not provide it yet: loading is
synchronous, and a page reads files asynchronously.

## 4. Hot reload

### 4.1 Relinking from a module

Each build's event carries a manifest of what a page runs: every file with
a digest, and the modules in program order with the files they live in.
The page's reload client compares it with the manifest of the build the
page runs, and relinks the program from the first module whose file
changed. A changed style sheet is fetched again; any other changed file
reloads the page.

**Module globals are ephemeral.** A relinked module runs its top level
again, and whatever its globals held is rebuilt from nothing. The one value
that survives is the application's immutable state. The host queues
`Reload`; the application loop saves and returns an opaque state from
`app_main`. Only after that JSPI entry settles does the host relink modules
and start the new `app_main` with the handover. The state crosses even when
the module that defines its type is relinked:

- as it is, when `type-test` finds its type unchanged: an `Any` carries a
  structural TypeId, a hash of its type's name, fields and cases, so the
  new code accepts the old value;
- through `save` and `restore`, the contract a page reload uses, when the
  type differs;
- not at all, when the save cannot be restored either. The old program
  keeps running and the page offers to start the new one over.

Treating globals as ephemeral, rather than requiring modules without
state, is deliberate. `(scheme compiler)` translates every top-level Scheme
variable into a cell, so a Scheme library is stateful by construction. A
relinked Scheme library simply runs again, as it would when first loaded.

| Edit | Rebuilt | Relinked | State |
| --- | --- | --- | --- |
| A function body | That library | That module and those after it | Kept as is |
| An interface, with the state's types unchanged | That library and its importers | From the first of them | Kept as is |
| A type the state holds | That library and every user of the type | From the first of them | Through `save` and `restore` |
| The state and the save | As above | Nothing, until the developer starts over | Started over |
| The host's scripts or page | Nothing | The page reloads | Through `save` and `restore` |

Three hazards remain:

- A closure stored in the state keeps running the code it was made from
  until the state is rebuilt. An application that stores functions in its
  state should relink through `save` and `restore`.
- A relink waits for the old loop to save and return, then cancels and
  drains remaining tasks and I/O cleanup from that invocation.
  Input arriving during the transition waits for the new run. No two entry
  invocations overlap. The scheduler saves handler bindings on suspension
  and restores them before resumption; idle globals contain runtime defaults.
- A trap leaves the state from the last complete event. The host reads
  `app_state` only after the entry rejects. If saving that checkpoint is
  needed, the old entry runs with `Reload` as its first event, so a failing
  update or view is not repeated. A rejected candidate restarts the old
  program; a cold first-frame trap also remains available for a source fix.
- Startup is accepted after Resize and the first display frame succeed.
  Until then the old program and its state remain available for rollback.
  A live migration never silently starts fresh; only cold startup may
  discard an incompatible saved value and retry without it.

### 4.2 Builds as events

The reload client relinks one build at a time. An event that arrives while
a relink is in flight waits for it, and only the latest waits. The client
records a build as the page's only once its relink succeeds, so a page
that missed events, even across a restart of the server, catches up from
the next one, and a refused build is not tried again until the developer
starts over.

## 5. The development loop in Lofi

The loop is a Lofi program: `(lofi develop)` in `src/lofi/develop.sld`,
exposed and started by `bootstrap/develop.sld`, or by `src/ide/develop.sld`
in the IDE. It keeps a session, debounces changes, builds, writes modules
and manifests, broadcasts events, and decides which module files stay: the
latest build's and the one before, which pages may still be relinking
from. It reaches its host only through a `develop` effect of named
commands: watch a path, schedule a timer, assemble a module, serve routes,
broadcast an event, run a program, digest a file, read the clock, list
and make directories, and remove a file. Hosts deliver three events back: a file changed, the timer
fired, and a call into the loop panicked, with the panic's message. The
loop cannot build a `generate-library` recipe yet, so an application with
one, such as Hearsay, is built with `make site`.

| Host | Where |
| --- | --- |
| Node: HTTP with server-sent events, file watching, timers, child processes | `scripts/develop.mjs`, for `lofi serve` and `lofi watch` |
| Node compiler worker: one Wasm instance, its assembler and immediate filesystem helpers | `scripts/develop-worker.mjs` |
| A browser worker: the files it holds, timers, messages to the IDE | `src/ide/toolchain.mjs`, running `src/ide/develop.sld` |

The native parent remains responsive during synchronous compilation. The worker
receives file/timer events and forwards only watch, schedule, serve, broadcast
and run commands. Immediate helper results stay in the worker; no request/reply
service or second compiler coordinator is introduced. Startup sends watch
commands before a zero-delay timer, so watches are installed before the first
compile. Recoverable compiler panics report through the existing loop; fatal
worker or host failures close the native host.

Because HTTP now runs during compilation, published HTML and manifests are
written to neighboring staging files and renamed into place. A synchronous
rename command also works as a map move in the temporary browser backend.
Assembled module binaries use the same replacement rule; a failed write cannot
leave a partial module that a later build mistakes for a cached file. This
provides complete individual files; project-level attempt acceptance and
generation publication remain the next development-session changes.

Each host owns private diagnostic storage and removes it after worker exit.
Node [tracks filesystem descriptors opened by a worker](https://nodejs.org/api/worker_threads.html#new-workerfilename-options)
and closes them on exit. Shutdown marks the host stopped before closing watches,
timers and connections, stopping its application child, and terminating the
compiler worker. Late commands cannot start a replacement child. This is one
isolated compiler runtime, not shared-memory Lofi execution.

The reload client is a Lofi program too, `src/app/reload.sld`, whose
`page` effect asks the page to show a notice, restyle, relink or reload.
`src/app/reload-client.mjs` binds it for the pages `lofi serve` serves.
*Proposed:* checking the loop and the client with
`(lofi explore)`, for example that a page never applies an older build
after a newer one.

## 6. Scheme

A Scheme program becomes a Lofi library through `(scheme compiler)`, so it
is compiled separately, linked and relinked like any other library. Every
Scheme variable is a cell, and a relinked Scheme library runs its top level
again. *Proposed:* a Scheme REPL, which expects that redefining a procedure
changes what every caller calls, would relink every library after the
redefinition, as an edit does.

## 7. The toolchain in a browser

`make ide` packages the browser IDE as a static site in `build/ide`
(`scripts/build-ide.scm`), with Siegework as the project it opens until the
developer opens a project directory. The page is laid out as Zed is: a narrow toolbar
along the top, a file browser docked on the left, a binary tree of editor
panes. The editor compiles for diagnostics but does not run the application.

| Piece | In a browser |
| --- | --- |
| Compiler and loop | `src/ide/develop.sld`, the loop of `bootstrap/develop.sld` compiled one library at a time and linked in a worker. |
| Files | The worker holds them: the standard library, the project as the editor has it, unsaved edits included, and what builds write. The program handles `(lofi io)`'s `fs` effect with a `files` effect that the worker implements, so the compiler opens files as it does from a disk. The loop keeps only the modules of the latest build and the one before. |
| Projects | Text files by relative path in local storage, from a project directory opened from disk. Where the browser offers the File System Access API, saving writes back to that directory, whose handle survives a reload in IndexedDB. |
| Assembler | The `wat` crate compiled to WebAssembly (`src/assembler`), which the desktop loop uses too, instead of `wasm-as`. |
| Formatter | `(lofi format)`, which reproduces `scripts/format-scheme` on every file in the repository, compiled to its own module (`src/ide/format.sld`) and run on the page's thread. Tab and Enter indent as Emacs does; saving formats the file. Its lexer also classes each character for highlighting, of the lines in view only, read from the start of their top-level form. |
| Diagnostics | A failed build's message starts with the place the compiler means; the IDE puts a squiggle under the expression there. |
| Linker | The loader of section 3.2. |
| Runtime | The prebuilt `snail_runtime.wasm`, an instance for the development loop. |
| Optimizer | None. |

Section 2 gives the worker's build times; text crosses to the worker a
character at a time, which makes its first build slower than the desktop's.
`tests/browser/ide.mjs` packages `tests/apps/counter` and, in headless
Chromium, checks failed-build recovery, a squiggle, Tab and
format-on-save, splits a pane, and opens a project directory.

## 8. What is left

The book's [terms](book/lofi/terms.md#toolchain-terms) distinguish a project
from a workspace, and incremental compilation from restart and hot reload.
The [roadmap](book/roadmap.md) lists the open work: the build cache
on disk, interfaces as generated headers, `(lofi wasm)` in browsers,
a native host for the loop, closures in the state, and the proposed
[project and development workflow](proposals/desktop-ide.md). Integrated and
inlaid previews, virtual browser routing and a browser-only development
backend are not part of that plan.
