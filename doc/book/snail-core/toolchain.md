# Development toolchain

Snail-Core can link a program statically or link its libraries when it starts.
Static builds compile the whole program, optimize it and merge the Rust runtime
into one module. `--release` increases optimization; it does not select linking
mode. Development builds keep each library as its own module, with the runtime
as a separate instance.

| Command | Build |
| --- | --- |
| `snail build`, `snail run`, `make site`, internal source compile/run | Static; build accepts `--release` for full optimization |
| `snail dev`, `make ide` | Separate development modules |

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
| `build/snail run-wasm PROGRAM ARGUMENT ...` | Runs a compiled program, one linked module, its `.cwasm`, or a per-library `modules.json`, which the engine links (`build/engine/engine.wasm`), as `host/native/run-snail.mjs` does, with the same exit statuses, unless it imports sockets, processes, file modes or watches. The compiled compiler is one such program. |
| `build/snail precompile MODULE OUTPUT` | Writes the module's machine code as a `.cwasm` file, which `run-wasm` loads in place of the module. |
| `build/snail imports PROGRAM` | Lists the modules a program's modules import from, a line each, without compiling them. |

`SNAIL_ENGINE=wasmtime` makes the driver run every compile on it, and
every program that needs no sockets, processes, file modes or watches, and makes
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
editor Save or external writer -> disk -> disk task
                                           |          |
                                      resident     editor reads
                                      builder      saved files
                                           |
                                  candidate + diagnostics
                                           |
                              reconcile and accept or discard
                                           |
                                output links + UI status
                                           |
                              affected wanted run targets
```

Save only writes disk. The disk task triggers compilation regardless of which
application wrote the file. Manual Build also requests an attempt. Unsaved text
never enters compilation. Each attempt starts with fresh diagnostics while
retaining valid compiler caches; an error does not display stale diagnostics
from the preceding attempt.

The cold commands, `snail build` and `snail run`, are a Snail program,
`bootstrap/cli.sld`, which builds with `(snail shell project build)`: the
compiler runs inside it, Binaryen's tools link each program through
`run` (`(snail shell process)`), and Node runs producers. Stage 0 rebuilds the
program when its sources change (`scripts/snail-tool cli-tools`), and is the
only judge of when they have. Starting Chibi and Cargo to find nothing stale
takes most of a second, so `./snail` keeps stage 0's answer in
`build/tools-KIND.txt`, stamped with the time stage 0 began, and uses it again
while every tool it names exists and nothing stage 0's rule reads is newer:
the `.sld` files under `src/`, `bootstrap/`, `host/ide/` and `host/browser/`,
the runtime crate, `rust-toolchain.toml`, and stage 0's driver, which says where
the tools go. The check over-approximates the rule, so a false alarm costs only
stage 0's run, and it takes about 15 ms. `snail run`
publishes the run's program and then becomes it through `exec`, so the
process the caller started is the program's, with its arguments, standard
streams, working directory, status and signals. Development builds with the
same program, as `snail resident PROJECT` in a child process, so synchronous
compilation and tool IO cannot block the HTTP service or disk observation
([the resident builder](compilers.md#the-resident-builder)). The resident
retains a successful compiler Session per target, even through a build that
fails after it; changing its entry or ordered library roots starts a new
Session. Producers run again each attempt, once each. The
[compiler chapter](compilers.md#separate-compilation) explains reuse: a change
to a monomorphic function body recompiles its library; an interface change also
recompiles importers. A cold start has no retained compiler cache.

`snail dev` is the same program's `dev`, whose service is
`(snail shell project service)`. Its tasks each wait on one thing: the owner,
which holds the step below and everything it leaves to its host, and receives
every message; the disk task, which holds the latest inventory; a task writing
the resident's requests and two reading its output; a supervisor for each run
target, which owns that target's process; and a task for each HTTP connection.
No cell holds state: each task threads its own through its loop, and tasks
share only mailboxes. It replaced a service in JavaScript
([#567](https://github.com/tsnl/snail-scheme/issues/567)), whose few cases
tested in process became scenarios of the step's race tests.

### Observation and acceptance

The disk task's inventories ([`(snail shell watch)`](libraries.md)) cover the
project, `src/` and `host/browser/`, without the project's `build` and `.git`
directories or the root's `build`. Exclusions are exact paths, not every folder
named `build`. It takes one when the step asks it to reconcile, when the editor
saves, each second, and on a hint from Node's recursive watch of a root, and
reports the paths whose fingerprints changed since the last complete one. A
file's fingerprint is its size and nanosecond modification time. A directory's
is its kind alone, so writes inside an excluded directory do not invalidate its
parent. A symbolic link is recorded, not followed. A hint names nothing: a
watch can miss a change or be lost, and the next inventory finds what it
missed. The caller decides which observed paths affect compilation.

A path that vanishes while an inventory is taken is left out, as removed. One
that cannot be read otherwise fails the inventory. The task then keeps the last
complete one and reports the failure once, when it begins. It answers a
reconciliation with the failure, so the attempt fails with its message, and
listing files fails rather than returning stale names. The first inventory
that succeeds again reports what changed meanwhile, then the recovery, which
builds. There is no content cache or filesystem snapshot. Metadata polling
catches ordinary local writes but cannot guarantee detection on filesystems
that hide changes behind unchanged or coarse metadata.

The owner runs serialized project attempts and keeps one current status. It
writes the resident's requests a line each, and reads its replies, by epoch.
Each attempt starts with an ID and empty diagnostics. The service
keeps distinct observed paths only for the active attempt, including paths outside
the previous project's public inputs. A reply carries the newly parsed description
even after a later build failure. The service reconciles disk, tests those paths
against the new description, and asks the resident to publish only if no observed
input change, and no Build requested meanwhile, superseded it. Otherwise it discards and
coalesces a successor, so the attempt that answers a Build began after it. Successful
compiler cache entries remain useful in either case; accepted application files
remain available after a failed build.

`(snail shell development)` makes these decisions as a pure step. It is a function from the service and one event to the next
service and the commands its host carries out in order. The events are the
observer's hints and reconciliations, the resident's replies by epoch, the
debounce timer, run controls, the resident's exit and closing. The commands
are building, reconciling, publishing or discarding a candidate, giving up an
attempt's directory, arming the timer, launching a run, reclaiming generations
and notifying.
`tests/programs/development-step.sld` drives it through those races. The
owner feeds it each event, and carries out the commands it answers with, in
order.

The builder also hashes each completed target's sorted relative filenames and
bytes, including the runtime, artifacts and public files; a module file adds only
its name, which is the digest of the text it was assembled from. File boundaries
are length framed; generation directory names and publication bookkeeping are
excluded.
The development owner compares that digest and the run's arguments with its last
issued launch, independently of compiler cache counters. An unchanged child keeps
its earlier generation and build ID; explicit Restart uses the latest accepted
generation. Paths observed through command-line arguments therefore still belong
to the actual run. Native runner/tool changes require restarting the development
service. [Application processes](applications.md#development-run-targets) define
the controls and their interaction with acceptance and shutdown.

Source inputs currently include the project description, `.sld` libraries, declared
entry/public paths, browser runtime assets and the files the latest publication's
programs link, which the resident names with each target. Ordinary data writes do
not request builds. Arbitrary producer file reads are not tracked yet: use manual Build for
those inputs. Unnamed watcher hints do not themselves declare source changes.
The observer and compiler do not claim an atomic filesystem revision.

Before sending work, the owner reserves `build/.snail-attempt-N`, a name that no
entry of the project's build directory has or begins with, and the resident names
the attempt's generations with it. A reply relinquishes that attempt; the
resident's exit relinquishes any unfinished one. This lets the owner remove only
abandoned private generations, including ones a crashed resident never returned.
Publication consumes ownership even when some target links moved before failure,
so those generations must never be swept afterward. The service reclaims the
generations it published once nothing needs them: it keeps the latest
publication and the one before it, which a page may still be loading from, and
an older generation while a run target's process still runs from it, as an
unchanged child does. What was published before the service started, and
what a publication that failed part way linked, are not among its
publications, and stay. Shutdown suppresses
acceptance and closes observation. It ends the resident's input, so the resident
finishes the request it is answering and exits, and kills it if it has not 2 s
later; and it stops each run target's process. Cleanup waits for every exit.
Arbitrary compiler traps retire this development session; there is no automatic
crash loop.

## Project file service

`(snail shell project files)` owns one physical project directory and three
operations: filter the disk task's filenames, read text with a revision, and
save against that revision. Listing awaits a fresh complete inventory; a failed
one rejects the request instead of returning stale names. There is no second
directory traversal. No contents or revisions persist in the service. The editor holds
its unsaved text and the revision of its saved baseline; the disk task
remains the only source of file-change notifications. Save has no compiler call.

The text subset is valid UTF-8 without NUL, up to 8 MiB, preserving BOM, newline
bytes and a missing final newline. Listing selects regular files ending in `.sld`,
`.scm`, `.datum`, `.html`, `.css`, `.js`, `.mjs`, `.json`, `.svg`, `.txt` or `.md`;
reading establishes content validity. Other suffixes and extensionless files are
outside this first editor API. Paths reject traversal and symlinks. `.git` and
the root `build` directory are excluded; `src/build` remains an ordinary source
directory. A pipe cannot block the service while it checks for a regular file.

A revision is the SHA-256 digest of the file's bytes. A read is one version of
the file if the file's length and modification time stay the same. A save writes
its text to a fresh directory under `project/build`, compares the current
revision, preserves ordinary permission bits and renames onto the destination. This
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

A revision names no device or inode, which Rust's standard library gives WASI
only as unstable API. A file replaced by another with the same bytes is the
same revision, and saving over it loses nothing.

WASI preview1 cannot read or set permission bits, so its `modes` effect does,
on Node (`host/native/run-snail.mjs`). `tests/programs/project-files.sld`
drives it.

## Project HTTP service

The service listens on `127.0.0.1`, and prints its editor URL once it does. It
answers each connection's one request in the connection's own task, through
the [Snail HTTP library](http.md). It serves a fixed list of trusted editor
assets, the editor's page, style and program and the browser host's modules
that run it; it never serves project HTML or arbitrary filesystem paths. The
project's browser targets are served on a second listener, the
[applications' origin](applications.md#browser-targets-in-development), whose
URL the service prints after the editor's and whose pages therefore cannot
reach this API.

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
A stream's connection task writes what the owner sends it, and a frame closes a
stream with 16 KiB already sent to it unwritten. An idle blocked stream
stays open until another event or connection closure, within the 64-stream limit.
File operations remain responsive while the real compiler waits on a source pipe
in the resident.

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
than reused. `compiler` identifies the resident builder by its process ID,
`worker`, and is `null` once it has exited. `runs` is the stream's `runs`.

The development loop's tests (`tests/project-http.mjs`,
`tests/project-attempts.mjs`, `tests/development-runs.mjs`, `tests/project-reload.mjs`,
`tests/project-development.mjs`, `tests/project-resources.mjs`,
`tests/browser/ide.mjs` and `tests/browser/ide-runs.mjs`) spawn `snail dev
--port 0` and observe it only through the URL it prints, this snapshot, the
event stream, the files on disk and process IDs, so nothing they check
depends on how the service is written; `tests/development-service.mjs` is
that client. A case about compiler sessions asks for each attempt with
Build, as the editor does, and reads what each target compiled and its digest
from the snapshot. The tests of `snail build` and `snail run` likewise see
only the command's exit status, its output and the build directory. What
must happen within one turn of the session is a transition of the step, and
`tests/programs/development-step.sld` tests it as one.

Request bodies are framed by Content-Length alone, as in the
[Snail HTTP library](http.md): a request naming a Transfer-Encoding is
answered 411 before routing, or 400 if it also gives a Content-Length, so a
body's size is known from its head. Bodies are limited
to 8 MiB and decoded strictly as UTF-8.

The service requires its exact Host authority and rejects a supplied foreign
Origin or fetch context. Mutations require the exact Origin. It provides no CORS
access. This boundary keeps other websites from reading or writing project files;
it is not authentication against other native processes on the same machine.

The step admits run controls using the last accepted
definitions, even while compilation fails. HTTP maps its rejection of unknown
names, and Start/Restart for removed names, to 404. The 204 response
acknowledges applying intent; it contains no process snapshot that could overwrite
a newer SSE observation. A lost response leaves the outcome unknown and must not
cause automatic retries. Closing an HTTP or event connection does not stop an
application. Closing the development service does.

Closing closes the listener, every HTTP connection with any request body still
arriving, and every event stream, then waits for the resident and the run
targets' processes to exit. A body that finishes after shutdown cannot save. A
fatal compiler or service failure closes the session, and `snail dev` exits with
status 1 and its message; failing to listen ends it before anything starts.

## Browser editor

The editor is a Snail program, `host/ide/ide.sld`: a
[document interface](applications.md#document-interfaces) that `snail dev`
serves with the browser host's `ui.mjs`, built by stage 0 with the other
development tools. It has a file browser and split panes. `(snail shell
format)` runs in the same program for Tab/Enter indentation and
format-on-save of Scheme files (`.sld`, `.scm` and `.datum`), and `(snail
shell highlight)` colors them as the [book does](#code-highlighting). Each
pane is one scroller holding its line numbers, its highlighting and its text
field, which is as big as its text, so they scroll together. Other supported files use ordinary text
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
A lost response reports an unknown outcome without retrying; a response that
never comes keeps the controls waiting, as requests have no timeout yet. That
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
disk task. A project listing alone never discards a buffer: lists and reads are
different observations, with independent ordering.

Build status replaces the preceding diagnostic collection at each attempt. The
page shows messages and compiler-provided locations in a separate panel. A
location in an editable project file opens that file. A fresh file read after
the failure binds a one-character squiggle to that observed revision. Later
reads withdraw it until the same revision is confirmed; Save invalidates it.
Drafts and conflicts suppress it. This is an editor observation, not proof of
the compiler's exact filesystem snapshot; the watcher rejects observed
supersession without claiming an atomic filesystem revision. Columns count
Unicode scalars in the original file, as the editor's offsets do, over LF
display text, including CRLF files; the page's `dom` binding converts offsets
to the textarea's UTF-16. Generated scratch and external library
locations remain messages rather than being mapped to another file. These are
source points, not guessed expression ranges or full source spans.
Manual Build requests compilation; Save writes disk and leaves scheduling to the
disk task. Reconnecting the event stream supplies current status and file
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

mdbook runs `scripts/highlight-book` as a preprocessor, which `book.toml`
registers after the `links` preprocessor has included the examples. It is a
Snail program, `bootstrap/highlight-book.sld`, which reads the book as mdbook
writes it, JSON on its standard input, and writes it back. It replaces each fenced block whose language is `scheme` with a
`<pre><code class="nohighlight">` of `tok-` spans, one per token but
whitespace, which `doc/highlight.css` colors for mdbook's light and dark
themes; highlight.js skips code of class `nohighlight`, and still highlights
the book's other blocks. `./scripts/snail-tool book-tools` builds the
program when it is stale, so `mdbook build` works from a fresh checkout that
can build the compiler. `tests/highlight-book.mjs` runs the preprocessor on a small book.
The editor, `host/ide/ide.sld`, draws the same tokens as `tok-` spans for the
lines in view, read from the start of their top-level form.

Proposed: once the book is itself a Snail-Core project, the classifier can run
in a `generate-library` recipe that writes the highlighted pages, and the mdbook
preprocessor goes away.

## Application and networking integration

The native service, HTTP API and editor implement [application run controls](applications.md#development-run-targets)
and replacement after accepted builds, and the service serves each browser
target's builds to pages that reload as each new one is published
([below](applications.md#browser-targets-in-development)). Durable
state remains [proposed work](applications.md#proposed-application-processes).
Production `serve` and package installation still need their own contracts;
neither is a current public command.

The concrete [socket effects](../runtimes/networking.md) provide TCP streams and
UDP datagrams to native CLI programs and replacement handlers for tests. Their
native owners define bounded buffering, cancellation and close behavior. UDP
keeps message boundaries without guaranteeing delivery or order.

The [HTTP library](http.md) provides bounded parsing, response framing and one
complete exchange over TCP, which the project service is written with.
`(snail shell project bundle)` answers for a browser application's
development builds; the project service mounts it for each browser target,
and an application's own server can mount it too.
Wait on the host by ticket, as the runtime's sockets do, and test real sockets as well as
intercepted operations. [Networking work](https://github.com/tsnl/snail-scheme/issues/457)
tracks this boundary. No transport hierarchy or generic provider framework
is needed. TLS, HTTP/2 and deployment infrastructure are separate work.

## Process boundaries and future debugging

| Boundary | Information crossing it |
| --- | --- |
| Editor ↔ development process | File reads/saves, build requests, compiler diagnostics, run controls and current process/output snapshots. |
| Development process ↔ resident builder | Attempt IDs, project descriptions, results, diagnostics, candidate output identities and their files' digests, as JSON lines. Compiler objects and candidates stay in the resident. |
| Development process ↔ application process | Entry, arguments, environment, working directory, standard streams, exit status and OS controls. Each process lifetime names its build and run target. |
| Browser ↔ application server | Ordinary HTTP. In development, each page's build's manifest and the events of the builds after it. |

A future debugger attaches to a run's process and build. Its inspector endpoint
expires with that run. `run-snail.mjs` executes Wasm on the process's main
thread, so attachment reaches the program itself. Debug commands use the inspector
connection rather than compiler requests or parsed stdout. The development
service stays responsive while an application is paused. Source mappings and
breakpoints require a separate compiler/assembler proof; debugger support is
not implemented. [Editor and debugger work](https://github.com/tsnl/snail-scheme/issues/461)
tracks these extensions.

[Build-tooling and package decisions](https://github.com/tsnl/snail-scheme/issues/462)
track cold-cache reuse, producer-input observation and package installation.
