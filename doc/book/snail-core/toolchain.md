# Development toolchain

Snail-Core can link a program statically or link its libraries when it starts.
Static builds compile the whole program, optimize it and merge the Rust runtime
into one module. `--release` increases optimization; it does not select linking
mode. Development builds keep each library as its own module, with the runtime
as a separate instance.

| Command | Build |
| --- | --- |
| `snail build`, `snail run`, `make site`, internal source compile/run | Static; build accepts `--release` for full optimization |
| `snail dev`, `./scripts/snail-tool serve`, `./scripts/snail-tool watch`, `make ide` | Separate development modules |

The public commands operate on projects. Compiler contributors can use
`./scripts/snail-tool run SOURCE`, `wat SOURCE`, `schema SOURCE` or `bootstrap`.
`./scripts/snail-tool compile -o FILE SOURCE` writes a raw Wasm file and linker
intermediates; it does not provide project publication guarantees.
Source-level `run` uses a private build directory by default and removes it when
the process finishes.

Compiler contributors also have `build/snail`, which Cargo builds from
`crates/snail`: a native executable that embeds wasmtime. Its subcommands
are internal to the driver and the tests:

| Subcommand | Does |
| --- | --- |
| `build/snail run-compiler MODULE ARGUMENT ...` | Runs the compiled compiler as `host/native/run-compiler.mjs` does on Node, with the same exit statuses. |
| `build/snail precompile MODULE OUTPUT` | Writes the module's machine code as a `.cwasm` file, which `run-compiler` loads in place of the module. |
| `build/snail run-wasm PROGRAM ARGUMENT ...` | Runs a compiled program, one linked module or a per-library `modules.json`, as `host/native/run-snail.mjs` does, unless it imports tasks, sockets or processes. |
| `build/snail imports PROGRAM` | Lists the modules a program's modules import from, a line each, without compiling them. |

`SNAIL_ENGINE=wasmtime` makes the driver run every compile on it, and
every program that needs no tasks, sockets or processes, and makes
`make bootstrap` build it first; [the bootstrap](bootstrap.md#the-native-executable)
explains why Node stays the default. The public `./snail` launcher is
unchanged. One native `snail` that replaces it, running the project builder
and programs as well, is proposed in
[#562](https://github.com/tsnl/snail-scheme/issues/562).

The [project chapter](projects.md) defines `project.datum`, named targets,
output directories and artifact bundles.

`snail run PROJECT RUN-TARGET [ARGUMENT ...]` builds the referenced program in
debug mode and runs that exact completed generation. Configured arguments come
first; arguments after the target are passed through unchanged. The application
inherits the caller's working directory, environment and terminal IO.

After compiler and scratch cleanup, the native command replaces itself with the
runtime using [Node's process replacement](https://nodejs.org/api/process.html#processexecvefile-args-env).
Its PID, exit status and signals therefore belong to the application. This uses
the existing Node 26 POSIX host. Compilation and generator execution retain
the cold builder's synchronous behavior.

## From an edit to a build

`snail dev PROJECT` starts one native development process and prints its editor
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
                                           |
                              affected wanted run targets
```

Save only writes disk. The observer triggers compilation regardless of which
application wrote the file. Manual Build also requests an attempt. Unsaved text
never enters compilation. Each attempt starts with fresh diagnostics while
retaining valid compiler caches; an error does not display stale diagnostics
from the preceding attempt.

`host/native/project.mjs` supplies the same serial builder to cold commands and the
resident service. A cold command owns its compiler directly. Development uses
one persistent compiler worker so synchronous compilation and tool IO cannot
block the HTTP service or disk observation. The worker retains a successful
compiler Session per target; changing its entry or ordered library roots starts
a new Session. Producers run again each attempt, once each. The
[compiler chapter](compilers.md#separate-compilation) explains reuse: a change
to a monomorphic function body recompiles its library; an interface change also
recompiles importers. A cold start has no retained compiler cache.

### Observation and acceptance

`host/native/watch.mjs` supplies one disk observer with independent subscriptions.
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
fresh scan after any active one without waiting for global quiet and returns its
regular filenames, detached from the internal inventory. Closing suppresses
later notifications and waits for an active scan to finish. There is no content
cache or filesystem snapshot. Metadata polling catches ordinary local writes but
cannot guarantee detection on filesystems that hide changes behind unchanged or
coarse metadata. The project development parent consumes this observer; the old
commands still use their existing watches until command/application integration.

`host/native/project-develop.mjs` owns serialized project attempts and one current
status, with independent subscriptions. `host/native/project-worker.mjs` owns the
resident builder. Each attempt starts with an ID and empty diagnostics. The parent
keeps distinct observed paths only for the active attempt, including paths outside
the previous project's public inputs. A reply carries the newly parsed description
even after a later build failure. The parent reconciles disk, tests those paths
against the new description, and publishes synchronously only if no observed input
change, and no Build requested meanwhile, superseded it. Otherwise it discards and
coalesces a successor, so the attempt that answers a Build began after it. Successful
compiler cache entries remain useful in either case; accepted application files
remain available after a failed build.

The builder also hashes each completed target's sorted relative filenames and
bytes, including runtime modules, artifacts and public files. File boundaries are
length framed; generation directory names and publication bookkeeping are excluded.
The development owner compares that digest and the run's arguments with its last
issued launch, independently of compiler cache counters. An unchanged child keeps
its earlier generation and build ID; explicit Restart uses the latest accepted
generation. Paths observed through command-line arguments therefore still belong
to the actual run. Native runner/tool changes require restarting the development
service. [Application processes](applications.md#development-run-targets) define
the controls and their interaction with acceptance and shutdown.

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

`host/native/project-files.mjs` owns one physical project directory and three native
operations: filter the shared observer's filenames, read text with a revision,
and save against that revision. Listing awaits a fresh complete reconciliation;
a failed scan rejects the request instead of returning stale names. There is no
second directory traversal. No contents or revisions persist in the service. The editor holds
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

`host/native/project-http.mjs` connects the project attempt owner and file service on
`127.0.0.1`. Its native API returns the URL, development session, completion promise
and an idempotent close operation. `host/native/dev.mjs` supplies the `dev` command.
The same HTTP service serves a fixed list of trusted editor assets and the
formatter; it never serves project HTML or arbitrary filesystem paths.

| Request | Result |
| --- | --- |
| `GET /api/project` | Project name, canonical directory and candidate relative filenames. |
| `GET /api/file?path=...` | `{text, revision}` for one file. |
| `PUT /api/file?path=...` | UTF-8 `text/plain` plus one strong quoted `If-Match` revision; returns the submitted snapshot or a conflict (409). |
| `POST /api/build` | Explicit Build, with an empty body. Save never calls this operation. |
| `POST /api/run/start?target=...` | Start an accepted run target; empty body, 204 acknowledgement. |
| `POST /api/run/stop?target=...` | Stop a retained run target, including a removed name; empty body, 204 acknowledgement. |
| `POST /api/run/restart?target=...` | Fresh attempt for an accepted run target; empty body, 204 acknowledgement. |
| `GET /api/events` | SSE: current compiler `status` (`phase`, attempt `id`, `diagnostics`), current `runs` array, then `files` invalidation; subsequent changes to each. |
| `GET /api/status` | One JSON snapshot of the whole session, below. |

Reconnect obtains both current snapshots and an unconditional file invalidation;
there is no event archive or replay cursor. Each run includes its target, availability,
intent, desired build and observed attempt, with PID, build, phase, exit outcome and
bounded stdout/stderr tails. Compiler and run frames are sent independently when
their respective values change: output does not replay compiler diagnostics.
Each stream holds at most one pending write; a later event
closes a reader whose previous write still needs drain. An idle blocked stream
stays open until another event or connection closure, within the 64-stream limit.
File operations remain responsive while the real compiler waits on a source pipe
in its worker.

The event stream carries what the editor draws. `GET /api/status` answers
with everything else a client can observe of the session, in one value:

```json
{"phase": "succeeded", "id": 4, "diagnostics": [],
 "published": {"id": 4, "targets": [{"name": "main", "directory": "/project/build/.snail-attempt-…", "digest": "…", "compiled": 1}]},
 "compiler": {"worker": 1},
 "runs": [{"target": "dev", "desired": null, "attempt": null, "wanted": false, "available": true}]}
```

`phase`, `id` and `diagnostics` are the stream's `status`: the attempt last
started, numbered by the epoch, and what it reported. `published` is the
build the session last accepted, `null` before the first: its epoch, and for
each target the generation directory its `build/NAME` link names, the digest
of that generation's files, and how many libraries that build compiled rather
than reused. `compiler` identifies the resident compiler, a worker thread
today, and is `null` once it has exited. `runs` is the stream's `runs`.

The development loop's tests (`tests/project-http.mjs`,
`tests/project-attempts.mjs`, `tests/development-runs.mjs`,
`tests/project-development.mjs`, `tests/project-resources.mjs`,
`tests/browser/ide.mjs` and `tests/browser/ide-runs.mjs`) spawn `snail dev
--port 0` and observe it only through the URL it prints, this snapshot, the
event stream, the files on disk and process IDs, so nothing they check
depends on how the service is written; `tests/development-service.mjs` is
that client. A case about compiler sessions asks for each attempt with
Build, as the editor does, and reads what each target compiled and its digest
from the snapshot. The tests of `snail build` and `snail run` likewise see
only the command's exit status, its output and the build directory. The few
cases that must act within one turn of the session, kill its compiler worker,
make one of the builder's removals or renames fail, or read its private
scratch still run it in process and say why.

Request bodies are framed by Content-Length alone, as in the
[Snail HTTP library](http.md): a request naming a Transfer-Encoding is
answered 411 before routing, or 400 by Node's parser if it also gives a
Content-Length, so a body's size is known from its head. Bodies are limited
to 8 MiB and decoded strictly as UTF-8.

The service requires its exact Host authority and rejects a supplied foreign
Origin or fetch context. Mutations require the exact Origin. It provides no CORS
access. This boundary keeps other websites from reading or writing project files;
it is not authentication against other native processes on the same machine.

The native development owner admits run controls using the last accepted
definitions, even while compilation fails. HTTP maps its rejection of unknown
names, and Start/Restart for removed names, to 404. The 204 response
acknowledges applying intent; it contains no process snapshot that could overwrite
a newer SSE observation. A lost response leaves the outcome unknown and must not
cause automatic retries. Closing an HTTP or event connection does not stop an
application. Closing the development service does.

Closing removes subscriptions, closes HTTP connections and pending request bodies,
and awaits the development owner. A body that finishes after shutdown cannot save.
A fatal compiler/service failure closes the session and rejects its completion
promise; a failed bind also disposes the session it created.

## Browser editor

The editor has a file browser and split panes. `(snail shell format)` runs in the page
for Tab/Enter indentation and format-on-save of Scheme files (`.sld`, `.scm`
and `.datum`), and `(snail shell highlight)` colors them as the
[book does](#code-highlighting). Other supported files use ordinary text
editing. Browser textareas use LF in edited text; the native file API
preserves exact bytes until saved.
The browser has no compiler, copied project, directory handles or persistent
project storage. Closing/reloading a page with drafts asks before discarding them.

The Applications panel selects one run target and provides Start, Stop and Restart.
It shows requested and observed builds, PID, exit outcome and separate stdout/stderr
tails. Output is literal text and preserves scroll position; it does not refresh
files, panes or compiler diagnostic evidence. Removed names remain visible and
stoppable. Application pages remain ordinary clients of their own server.

Run snapshots arrive only through the current event connection. One command may
be in flight; its response changes feedback, never the observed process state.
A lost response or timeout reports an unknown outcome without retrying. That
message names its command and target, survives output, selection and reconnect,
and clears on the next deliberate run command. An empty run catalog does not hide
pending command feedback. The controls are not a terminal, log archive or debugger.

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

## Code highlighting

The book and the editor color code with one classifier, `(snail shell highlight)`.
It walks text with the compiler reader's own lexical rules, the "Lexemes"
section of `src/snail/shell/compiler/read.sld`: what starts at an index, where
it ends, and what a token's text is to the reader, a boolean, a number, a name
or an error. The reader is built on the same functions, so a highlighter
cannot disagree with it about where a string, a character such as `#\(`, a
comment or a token ends. The classifier adds what a reader discards, the
comments and whitespace between data, and it never fails: a string the text
ends inside is a string to the end, and a token the reader rejects, such as
`.`, is classed invalid. Its tokens tile the text. The core forms it colors
as keywords are the compiler's own list, `core-keywords` in `core.sld`; the
derived forms and declaration words are listed once in the classifier. It
also marks the name a `define`, `define-syntax` or `:` introduces, and colors
what `#;` comments out as a comment.

mdbook runs `host/native/highlight-book.mjs` as a preprocessor, which
`book.toml` registers after the `links` preprocessor has included the
examples. It replaces each fenced block whose language is `scheme` with a
`<pre><code class="nohighlight">` of `tok-` spans, one per token but
whitespace, which `doc/highlight.css` colors for mdbook's light and dark
themes; highlight.js skips code of class `nohighlight`, and still highlights
the book's other blocks. The classification is `host/native/highlight.sld`,
the library compiled to Wasm, which `./scripts/snail-tool book-tools` builds
when it is stale, so `mdbook build` works from a fresh checkout that can build
the compiler. `tests/highlight-book.mjs` runs the preprocessor on a small book.
The editor's formatter, `host/ide/format.sld`, reduces the same tokens to one
letter per character for its highlight layer.

Proposed: once the book is itself a Snail-Core project, the classifier can run
in a `generate-library` recipe that writes the highlighted pages, and the mdbook
preprocessor goes away.

## Existing application development loop

`dev` currently compiles and edits projects. Application execution and reload
still use `./scripts/snail-tool serve APP-DIRECTORY` and
`./scripts/snail-tool watch SOURCE [ARGUMENT ...]`. Their loop is
`src/snail/shell/develop.sld`, exposed by `bootstrap/develop.sld`; it retains a compiler
session, debounces changes and publishes manifests. It plans each build as the
project builder does, with no project targets: the producers of the
generated libraries the program reaches run first, each compiled one library
at a time into `producers/` beside the build and run to completion by the
worker, and their outputs supply the program's compile. Producers run in
every build, since what they read is not tracked. With no project there is no
target to embed, so the plan runs no discovery expansion, and an
`artifact-bundle` fails in the compile; use project builds for artifacts.
The [application chapter](applications.md#hot-reload) defines current reload behavior.

`host/native/develop.mjs` owns watches, timers, HTTP and application children;
`develop-worker.mjs` owns the compiled loop, the assembler and the synchronous
`produce MANIFEST OUTPUT` command that runs a producer. The loop does its own
file work through the runtime's WASI, as any program does
([files and directories](libraries.md#files-and-directories)): it makes,
lists, renames and removes files, copies linked files, digests files with
`(snail shell sha256)` and times builds with the monotonic clock. Watch,
schedule, serve, broadcast and run commands cross to the parent.
Watches are installed before the first compile. HTML, manifests, module bytes
and linked files are staged beside their destinations and renamed, providing
complete individual files rather than the project builder's generation
publication. Each build copies the files the program links into `resources/`
beside `modules.json`, served at `/resources/`, when their digests changed, and
names each module's file for its text and its linked files' digests, so an
edited file relinks the page from the module that links it. The page's
manifest digests each file of the browser host and of `public/`, leaving out
editors' temporary files, which the watches ignore too. A digest is of what a
read finds: the copy, the server and the digest all follow a symbolic link, so
editing the file a linked or public link names counts as editing the link,
and a link to nothing fails the build, naming the link, before `modules.json`
changes. Only an edit under the watched directories starts a build, so an
edit to a file a link names outside them waits for a build another edit
starts. The loop keeps its latest and previous module sets. Shutdown closes
native resources and the worker and prevents late commands from starting
replacement children.

## Application and networking integration

The native service, HTTP API and editor implement [application run controls](applications.md#development-run-targets)
and replacement after accepted builds. Durable
state and browser reload integration remain [proposed work](applications.md#proposed-application-processes).
Production `serve` and package installation still need their own contracts;
neither is a current public command.

The concrete [socket effects](../runtimes/networking.md) provide TCP streams and
UDP datagrams to native CLI programs and replacement handlers for tests. Their
native owners define bounded buffering, cancellation and close behavior. UDP
keeps message boundaries without guaranteeing delivery or order.

The [HTTP library](http.md) provides bounded parsing, response framing and one
complete exchange over TCP. Routing and bundle/reload serving remain to be added. The project
service currently uses Node HTTP; sharing a Snail-Core HTTP implementation with
applications is future integration.
Wait on the host by ticket, as the runtime's sockets do, and test real sockets as well as
intercepted operations. [Networking work](https://github.com/tsnl/snail-scheme/issues/457)
tracks this boundary. No transport hierarchy or generic provider framework
is needed. TLS, HTTP/2 and deployment infrastructure are separate work.

## Process boundaries and future debugging

| Boundary | Information crossing it |
| --- | --- |
| Editor ↔ development process | File reads/saves, build requests, compiler diagnostics, run controls and current process/output snapshots. |
| Development process ↔ compiler worker | Attempt IDs, project descriptions, results, diagnostics and candidate output identities. Compiler objects and WasmGC references stay in the worker. |
| Development process ↔ application process | Entry, arguments, environment, working directory, standard streams, exit status and OS controls. Each process lifetime names its build and run target. |
| Browser ↔ application server | Ordinary HTTP; build-specific reload delivery is proposed. |

A future debugger attaches to a run's process and build. Its inspector endpoint
expires with that run. `run-snail.mjs` executes Wasm in a Node worker: attachment
must reach that agent, not just its wrapper. Debug commands use the inspector
connection rather than compiler requests or parsed stdout. The development
service stays responsive while an application is paused. Source mappings and
breakpoints require a separate compiler/assembler proof; debugger support is
not implemented. [Editor and debugger work](https://github.com/tsnl/snail-scheme/issues/461)
tracks these extensions.

[Build-tooling and package decisions](https://github.com/tsnl/snail-scheme/issues/462)
track cold-cache reuse, producer-input observation and package installation.
