# Development toolchain

Lofi can link a program statically or link its libraries when it starts.
Static builds compile the whole program, optimize it and merge the Rust runtime
into one module. `--release` increases optimization; it does not select linking
mode. Development builds keep each library as its own module, with the runtime
as a separate instance.

| Command | Build |
| --- | --- |
| `lofi build`, `lofi run`, `make site`, internal source compile/run | Static; build accepts `--release` for full optimization |
| `lofi dev`, `./scripts/lofi-tool serve`, `./scripts/lofi-tool watch`, `make ide` | Separate development modules |

The public commands operate on projects. Compiler contributors can use
`./scripts/lofi-tool run SOURCE`, `wat SOURCE`, `schema SOURCE` or `bootstrap`.
`./scripts/lofi-tool compile -o FILE SOURCE` writes a raw Wasm file and linker
intermediates; it does not provide project publication guarantees.
Source-level `run` uses a private build directory by default and removes it when
the process finishes.

The [project chapter](projects.md) defines `project.datum`, named targets,
output directories and artifact bundles.

`lofi run PROJECT RUN-TARGET [ARGUMENT ...]` builds the referenced program in
debug mode and runs that exact completed generation. Configured arguments come
first; arguments after the target are passed through unchanged. The application
inherits the caller's working directory, environment and terminal IO.

After compiler and scratch cleanup, the native command replaces itself with the
runtime using [Node's process replacement](https://nodejs.org/api/process.html#processexecvefile-args-env).
Its PID, exit status and signals therefore belong to the application. This uses
the existing Node 26 POSIX host. Compilation and generator execution retain
the cold builder's synchronous behavior.

`lofi check PROJECT` checks every declared build entry using the same expansion,
type/effect checking, specialization and ownership passes as a static debug build.
It does not emit or execute those entries. Specialization still matters: selected
typeclass methods can reveal unsafe handler captures or affine uses. Checking
does not invent specializations for unused generic definitions.

Generated-library producers execute normally. An artifact reference requires a
real temporary build, including browser packaging, even if that target's code
was checked earlier. The same traversal detects cycles through checked roots.
All temporary artifact generations are discarded when checking ends, including
on failure; check never publishes them. A root-only check creates no project
output directory. Artifact dependencies can leave an empty `build` directory.
The command stops at the first failure and is silent on success.

## From an edit to a build

`lofi dev PROJECT` starts one native development process and prints its editor
URL. `--port PORT` selects a port (8000 by default; 0 chooses a free one).
`make ide` runs it for Siegework. The browser owns open buffers and drafts;
the native service owns disk files, observation and compilation.

```text
editor Save or external writer -> disk -> shared observer
                                           |          |
                                      compiler     editor reads
                                      worker       saved files
                                           |
                                  candidate + diagnostics
                                           |
                              reconcile and accept or discard
                                           |
                                output links + UI status
```

Save only writes disk. The observer triggers compilation regardless of which
application wrote the file. Manual Build also requests an attempt. Unsaved text
never enters compilation. Each attempt starts with fresh diagnostics while
retaining valid compiler caches; an error does not display stale diagnostics
from the preceding attempt.

`scripts/project.mjs` supplies the same serial builder to cold commands and the
resident service. A cold command owns its compiler directly. Development uses
one persistent compiler worker so synchronous compilation and tool IO cannot
block the HTTP service or disk observation. The worker retains a successful
compiler Session per target; changing its entry or ordered library roots starts
a new Session. Producers run again each attempt. The
[compiler chapter](compilers.md#separate-compilation) explains reuse: a change
to a monomorphic function body recompiles its library; an interface change also
recompiles importers. A cold start has no retained compiler cache.

### Observation and acceptance

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

## Project file service

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

## Project HTTP service

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
| `GET /api/events` | SSE: current `status` (`phase`, attempt `id`, `diagnostics`), then `files` invalidation; subsequent status and shared-observer changes. |

Reconnect obtains current status and an unconditional file invalidation; there is
no event archive or replay cursor. Build directories and worker identity stay in
the native session. Each stream holds at most one pending write; a later event
closes a reader whose previous write still needs drain. An idle blocked stream
stays open until another event or connection closure, within the 64-stream limit. Request
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

## Browser editor

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

## Existing application development loop

`dev` currently compiles and edits projects. Application execution and reload
still use `./scripts/lofi-tool serve APP-DIRECTORY` and
`./scripts/lofi-tool watch SOURCE [ARGUMENT ...]`. Their loop is
`src/lofi/develop.sld`, exposed by `bootstrap/develop.sld`; it retains a compiler
session, debounces changes and publishes manifests. It cannot run generated-library
producers or resolve project artifacts. Use project builds for those inputs.
The [application chapter](applications.md#hot-reload) defines current reload behavior.

`scripts/develop.mjs` owns watches, timers, HTTP and application children;
`develop-worker.mjs` owns the compiled loop, assembler and immediate filesystem
helpers. Watch, schedule, serve, broadcast and run commands cross to the parent.
Watches are installed before the first compile. HTML, manifests and module bytes
are staged beside their destinations and renamed, providing complete individual
files rather than the project builder's generation publication. The loop keeps
its latest and previous module sets. Shutdown closes native resources and the
worker and prevents late commands from starting replacement children.

## Proposed application and networking integration

The [application process design](applications.md#proposed-application-processes)
moves run controls and reload under `dev`. It is not implemented by the editor
service described above. Production `serve` and package installation still need
their own contracts; neither is a current public command.

Provide concrete TCP and UDP socket effects that tests can intercept. TCP needs
listen/accept/connect, stream reads/writes and close; UDP needs bind, datagram
send/receive with peer addresses, and close. TCP can split transfers. UDP keeps
message boundaries without guaranteeing delivery or order. Define buffer limits,
truncation, cancellation and late-result ownership at each operation.

HTTP is proposed as a Lofi library over TCP, with bounded parsing, framing,
routing and bundle/reload serving. The project service currently uses Node HTTP;
sharing a Lofi HTTP implementation with applications is future integration.
Use the existing runtime suspension bridge and test real sockets as well as
intercepted operations. [Networking work](https://github.com/tsnl/snail-scheme/issues/457)
tracks this boundary. No transport hierarchy or generic provider framework
is needed. TLS, HTTP/2 and deployment infrastructure are separate work.

## Process boundaries and future debugging

| Boundary | Information crossing it |
| --- | --- |
| Editor ↔ development process | File reads/saves, build requests, current status and diagnostics. Run controls/logs are proposed. |
| Development process ↔ compiler worker | Attempt IDs, project descriptions, results, diagnostics and candidate output identities. Compiler objects and WasmGC references stay in the worker. |
| Development process ↔ application process (proposed) | Entry, arguments, environment, working directory, standard streams, exit status and OS controls. Each process lifetime names its build and run target. |
| Browser ↔ application server | Ordinary HTTP; build-specific reload delivery is proposed. |

A future debugger attaches to a run's process and build. Its inspector endpoint
expires with that run. `run-lofi.mjs` executes Wasm in a Node worker: attachment
must reach that agent, not just its wrapper. Debug commands use the inspector
connection rather than compiler requests or parsed stdout. The development
service stays responsive while an application is paused. Source mappings and
breakpoints require a separate compiler/assembler proof; debugger support is
not implemented. [Editor and debugger work](https://github.com/tsnl/snail-scheme/issues/461)
tracks these extensions.

[Build-tooling and package decisions](https://github.com/tsnl/snail-scheme/issues/462)
track cold-cache reuse, producer-input observation and package installation.
