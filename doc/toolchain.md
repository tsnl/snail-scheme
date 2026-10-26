# Toolchain: linking, hot reload and development

> **Status: implemented**, except where a section says *proposed*. The book's
> [roadmap](book/roadmap.md) tracks what is left.
>
> The [project and development proposal](proposals/desktop-ide.md) puts project
> builds, a shared file watcher and persistent compilation under `lofi dev`.
> The editor subscribes independently; applications run as ordinary
> subprocesses, preserving durable facts and deriving working state through
> disposable views. The [state prototype](proposals/typed-state.md) remains
> under review. `lofi dev` now owns native compilation and the editor; application
> launch/reload integration remains. The older `serve`/`watch` relink behavior
> below is still implemented. Browser-only development and integrated previews
> have been removed.

This document describes how Lofi programs are built, linked, reloaded and
loaded during development, so that a rebuild costs as much as the edit
that caused it. The compiler and assembler run as Wasm; native code owns project
traversal and processes. The browser editor is a client of the native project
service; its only Wasm tool is the formatter. C is the reference model: programs can link statically
or by library, and code loaded at run time is reached through an explicit,
unchecked cast.

Native Chibi tooling captures each command's stdout and stderr in a private
`TMPDIR` directory (or `/tmp`). A constant POSIX shell script owns redirection;
paths and arguments are positional data, never interpolated into shell source.
The parent waits for the direct child, reads both files, then removes the
directory. This avoids a Chibi 0.12 pipe-descriptor finalizer bug that could
truncate compiler output on a cold tool build, and allows large stderr output
without a pipe-draining deadlock. This synchronous capture supplies EOF on stdin;
it is not the application launch or supervision service. Tool names must be
nonempty and cannot begin with a dash; use a path for such executables.

## 1. Goals

1. Rebuild and reload in proportion to the edit, not to the program.
2. Hot reload at the granularity of a module, keeping the application's
   state.
3. Load compiled code while a program runs, including `generate-library`
   producers.
4. Keep compiler decisions in Lofi and native project/process ownership explicit.
5. Keep the compiler in a persistent native worker. Give the independent editor
   file/build subscriptions and keep unsaved buffers out of compilation.

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

| Build | Native loop |
| --- | --- |
| Siegework, first build, 14 modules | about 450 ms |
| Siegework, an edit to one function body, 1 or 2 modules | 70 to 110 ms |
| The counter of `tests/apps/counter`, an edit | 25 to 50 ms |

## 3. Linking, after C

| Build | Linking |
| --- | --- |
| Static | The whole program is compiled at once, optimized and tree-shaken, and the Rust runtime is merged in. `lofi compile`, `lofi run`, `lofi build` and `make site` build this way; `--release` increases optimization. |
| Development | Each library is compiled to its own module, and the modules are linked when the program is instantiated. The Rust runtime is a separate instance, like a shared C library. Nothing is optimized or tree-shaken. `lofi dev`, `lofi serve` and `lofi watch` build this way. |
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
finding a familiar string or a diagnostic record. Failure to read diagnostic
storage is terminal too: the worker cannot reuse a retired compiler.
`compile-error` keeps its
`Loc` and message in a compiler-private cell before the existing terminal panic.
This explicitly unsafe bridge avoids adding an abort effect to every compiler
pass; it does not prove the mutation pure. The serial native caller resets the
request and diagnostic cells before entry, then takes and projects each after a
trusted exit, before compiling a producer. Reset/projection traps retire
the instance too. Module initialization precedes the first reset.

Native failures carry `{severity, message, source}`; `source` is null or
`{file, line, column}`. Lines and Unicode scalar columns start at one. IO and
producer-input requests have no source record; internal no-location sentinels
are unlocated. An artifact wrapper preserves a failing child's origin. Printed
producer programs report their actual scratch source, while decoded generated
syntax retains the recipe location already established by expansion. No source
mapping is invented. CLI panic text is unchanged, and the compiler still stops
at its first error. These operations are implemented and tested.

`scripts/project.mjs` calls this boundary for cold and resident project builds.
Its `describe()` parses once; `build(description, ...)` consumes that parsed
description, allowing a development caller to retain inputs even after failure.

The native builder owns serial target traversal, producer execution and packaging.
Each attempt creates private generations and discovers dependencies only through
compiler requests. Successful Sessions advance independently of output acceptance;
they retain evidence, not backing-file lifetimes. Static output uses the existing
linker through `scripts/link.scm`, with intermediates kept in scratch. Development
output assembles all returned modules into a fresh self-contained directory.
Only the compiler cache persists; there is no second native binary cache.

A completed attempt returns a candidate. `scripts/build.mjs` accepts it immediately;
the project development parent can reject superseded work. Publication and discard consume
the candidate. If one of several link renames fails, publication preserves its
completed prefix and removes the remaining generations; it is not a project-wide
transaction. Failed compilation or packaging publishes nothing.

`scripts/watch.mjs` supplies one disk observer with independent subscriptions.
Construction installs recursive watches before the first inventory read; callers
subscribe and then await `reconcile()`. Named native notifications are hints.
Periodic inventories compare file identity, size and nanosecond modification/change
times, recording symlinks without following them. Directory identity omits child
timestamps so writes inside explicitly excluded output/data directories do not
invalidate their parents. Exclusions are exact paths, not every folder named `build`.

Missing names and lost watches report uncertainty; they do not by themselves mean
source code changed. The caller decides which observed paths affect compilation.
Missing roots are checked again, and replaced roots get new watches. A scan stops
at the first unreadable root and retains the previous complete inventory. It
reports one uncertainty for the failure episode, then one recovery after a complete
scan succeeds; failures moving between roots do not publish partial inventories.
`reconcile()` requests a
fresh scan after any active one without waiting for global quiet; closing suppresses
later notifications and waits for an active scan to finish. There is no content
cache or filesystem snapshot. Metadata polling catches ordinary local writes but
cannot guarantee detection on filesystems that hide changes behind unchanged or
coarse metadata. The project development parent consumes this observer; the old
commands still use their existing watches until command/application integration.

`scripts/project-develop.mjs` owns serialized project attempts and one current
status, with independent subscriptions. `scripts/project-worker.mjs` owns the
resident builder. Each attempt starts with an ID and empty diagnostics. The parent
keeps distinct observed paths only for the active attempt, including paths outside
the previous project's public inputs. A reply carries the newly parsed description
even after a later build failure. The parent reconciles disk, tests those paths
against the new description, and publishes synchronously only if no observed input
change superseded it. Otherwise it discards and coalesces a successor. Successful
compiler cache entries remain useful in either case; accepted application files
remain available after a failed build.

Source inputs currently include the project description, `.sld` libraries, declared
entry/public paths and browser runtime assets. Ordinary data writes do not request
builds. Arbitrary producer file reads are not tracked yet: use manual Build for
those inputs. Unnamed watcher hints do not themselves declare source changes.
The observer and compiler do not claim an atomic filesystem revision.

Before sending work, the parent reserves a private generation-name prefix under
the project's build directory. A worker result relinquishes that attempt; exit
relinquishes any unfinished one. This lets the parent remove only abandoned private
generations, including ones a crashed worker never returned. Publication consumes
ownership even when some target links moved before failure, so those generations
must never be swept afterward. Shutdown suppresses acceptance, closes observation
and requests graceful worker exit, then termination. Synchronous native operations
can delay actual exit; cleanup waits for it. Arbitrary compiler traps retire this
development session; there is no automatic crash loop.

This native API is implemented and tested, including a producer blocked on an input
pipe while a newly configured public file changes. The native file service and
HTTP API and editor are connected through `lofi dev`; application launch
integration follows. Diagnostic records carry source points from the compiler;
the editor never parses locations from error prose. Full source spans and
multiple-error recovery remain separate work.

So an edit to a function body with a signature recompiles one library. An
edit to an interface recompiles the libraries that import it too. The
loop assembles each changed module into a file named after a hash of its
text, so a page fetches a module again only when it changed. Compiler Sessions live in memory; a cold start compiles everything once.
Accepted project output generations remain on disk.

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

## 5. The existing application development loop

The older `serve`/`watch` loop is a Lofi program: `(lofi develop)` in
`src/lofi/develop.sld`, exposed by `bootstrap/develop.sld`. It remains until
application launching and reloads move to the project development service. It keeps a session, debounces changes, builds, writes modules
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

The native parent remains responsive during synchronous compilation. The worker
receives file/timer events and forwards only watch, schedule, serve, broadcast
and run commands. Immediate helper results stay in the worker; no request/reply
service or second compiler coordinator is introduced. Startup sends watch
commands before a zero-delay timer, so watches are installed before the first
compile. Recoverable compiler panics report through the existing loop; fatal
worker or host failures close the native host.

Because HTTP now runs during compilation, published HTML and manifests are
written to neighboring staging files and renamed into place.
Assembled module binaries use the same replacement rule; a failed write cannot
leave a partial module that a later build mistakes for a cached file. This
provides complete individual files. The newer `dev` service instead uses
project-level attempt acceptance and completed output generations.

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

### Project file service

`scripts/project-files.mjs` owns one physical project directory and three native
operations: list candidate filenames, read text with a revision, and save against
that revision. No contents or revisions persist in the service. The editor holds
its unsaved text and the revision of its saved baseline; the shared disk observer
remains the only source of file-change notifications. Save has no compiler call.

The text subset is valid UTF-8 without NUL, up to 8 MiB, preserving BOM, newline
bytes and a missing final newline. Listing selects regular files ending in `.sld`,
`.scm`, `.datum`, `.html`, `.css`, `.js`, `.mjs`, `.json`, `.svg`, `.txt` or `.md`;
reading establishes content validity. Other suffixes and extensionless files are
outside this first editor API. Paths reject traversal and symlinks. `.git` and
the root `build` directory are excluded; `src/build` remains an ordinary source
directory. A pipe cannot block the service while it checks for a regular file.

Revisions describe file identity and exact bytes. A save compares the current
revision, writes an exclusive temporary file under `project/build`, compares
again, preserves ordinary permission bits and renames onto the destination. This
keeps temporary writes out of source/public trees and compiler inputs. It returns
evidence for the submitted bytes, even if another writer subsequently changes the
file. Failed writes or rename leave the old destination intact; saves across a
nested filesystem mount fail with `EXDEV` instead of copying over the destination.

Reads/saves are bounded synchronous operations, so this service's saves cannot
interleave. Rename is atomic; comparison plus rename is not. An external writer
can still race after the final comparison, and pathname checks do not constitute
a sandbox against a hostile local process. This API makes no crash-durability,
ACL, extended-attribute or hardlink-preservation promise. It edits existing files;
creation, rename, deletion, merging and automatic conflict retry are omitted.

### Project HTTP service

`scripts/project-http.mjs` connects the project attempt owner and file service on
`127.0.0.1`. Its native API returns the URL, development session, completion promise
and an idempotent close operation. `scripts/dev.mjs` supplies the `dev` command.
The same HTTP service serves a fixed list of trusted editor assets and the
formatter; it never serves project HTML or arbitrary filesystem paths.

| Request | Result |
| --- | --- |
| `GET /api/project` | Project name, canonical directory and candidate relative filenames. |
| `GET /api/file?path=...` | `{text, revision}` for one file. |
| `PUT /api/file?path=...` | UTF-8 `text/plain` plus one strong quoted `If-Match` revision; returns the submitted snapshot or a conflict (409). |
| `POST /api/build` | Explicit Build, with an empty body. Save never calls this operation. |
| `GET /api/events` | SSE: full current `status`, then `files` invalidation; subsequent status and shared-observer changes. |

Reconnect obtains current status and an unconditional file invalidation; there is
no event archive or replay cursor. Each stream holds at most one pending write;
a later event or five-second drain deadline closes a blocked reader. Request
bodies are limited to 8 MiB and decoded strictly as UTF-8. File operations remain
responsive while the real compiler waits on a source pipe in its worker.

The service requires its exact Host authority and rejects a supplied foreign
Origin or fetch context. Mutations require the exact Origin. It provides no CORS
access. This boundary keeps other websites from reading or writing project files;
it is not authentication against other native processes on the same machine.

Closing removes subscriptions, closes HTTP connections and pending request bodies,
and awaits the development owner. A body that finishes after shutdown cannot save.
A fatal compiler/service failure closes the session and rejects its completion
promise; a failed bind also disposes the session it created.

## 6. Scheme

A Scheme program becomes a Lofi library through `(scheme compiler)`, so it
is compiled separately, linked and relinked like any other library. Every
Scheme variable is a cell, and a relinked Scheme library runs its top level
again. *Proposed:* a Scheme REPL, which expects that redefining a procedure
changes what every caller calls, would relink every library after the
redefinition, as an edit does.

## 7. The native project editor

`lofi dev [--port PORT] PROJECT` reads `project.datum`, keeps the shared project
builder alive and serves the editor on loopback. Port 8000 is the default; port 0
chooses a free port. `make ide` runs this command for Siegework. SIGINT/SIGTERM
close the HTTP service, shared observer and compiler worker. Existing `serve` and
`watch` still provide application execution/reload until that part of `dev` lands.

The editor has a file browser and split panes. `(lofi format)` runs in the page
for Scheme highlighting, Tab/Enter indentation and format-on-save (`.sld`, `.scm`
and `.datum`). Other supported files use ordinary text editing. Browser textareas
use LF in edited text; the native file API preserves exact bytes until saved.
The browser has no compiler, copied project, directory handles or persistent
project storage. Closing/reloading a page with drafts asks before discarding them.

Each open buffer owns its draft and saved `{text, revision}` baseline. A file read
updates a clean buffer; a dirty buffer keeps its draft and reports a changed disk
revision. Saving sends the baseline revision and one captured string. Success
advances the baseline without replacing later typing; an older in-flight read
cannot overwrite that evidence. Every completed save refreshes from disk,
including failures whose writes might have reached the server. There is one save
in flight per buffer, with no autosave or queued retries. A formatting failure
still permits saving the original draft, including incomplete code. Explicit
operation failures remain visible through background reads until the next
Save, Format or Reload action; reading successfully does not prove saving succeeded.

Reload discards a confirmed draft immediately to its saved baseline, then reads
disk. A failed read leaves that baseline and an error; later typing is a new draft
and survives the read. A current file read returning 404 clears a clean/loading buffer;
a dirty deleted file remains selectable with its text. Saves cannot recreate it.
The UI handles an empty project and later discovers files through the same
observer. A project listing alone never discards a buffer: lists and reads are
different observations, with independent ordering.

Build status replaces the preceding diagnostic collection at each attempt. The
page shows messages and compiler-provided locations in a separate panel. A
location in an editable project file opens that file. A fresh file read after
the failure binds a one-character squiggle to that observed revision. Later
reads withdraw it until the same revision is confirmed; Save invalidates it.
Drafts and conflicts suppress it. This is an editor observation, not proof of
the compiler's exact filesystem snapshot; the watcher rejects observed
supersession without claiming an atomic filesystem revision. Columns count
Unicode scalars in the original file, converted to textarea UTF-16 offsets and
LF display text, including CRLF files. Generated scratch and external library
locations remain messages rather than being mapped to another file. These are
source points, not guessed expression ranges or full source spans.
Manual Build requests compilation; Save writes disk and leaves scheduling to the
shared observer. Reconnecting the event stream supplies current status and file
invalidation without a replay log. An exact repeat of the retained status keeps
its diagnostic observations, including invalidation by Save or a changed read.
It still restores status presentation and refreshes files. Going back online replaces the stream too,
covering file reads that failed while an existing event connection survived.

`tests/browser/ide.mjs` drives the actual native service with Chromium: disk saves,
compiler recovery, clean external updates, dirty conflicts, delayed save/read
replies, deleted drafts, empty projects, reconnection, split panes and command
shutdown. Application launch/reload tests will follow that integration.

## 8. What is left

The book's [terms](book/lofi/terms.md#toolchain-terms) distinguish a project
from a workspace, and incremental compilation from restart and hot reload.
The [roadmap](book/roadmap.md) lists the open work: the build cache
on disk, interfaces as generated headers, `(lofi wasm)` in browsers,
a native host for the loop, closures in the state, and the proposed
[project and development workflow](proposals/desktop-ide.md). Integrated and
inlaid previews, virtual browser routing and a browser-only development
backend are not part of that plan.
