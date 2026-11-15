# Development toolchain

Snail Scheme can link a program statically or link its libraries when it starts.
Static builds compile the whole program and link the Rust runtime into one
module. `--release` remains a build mode but runs no function-body optimizer. Development builds keep each library as its own module, with the runtime
as a separate instance.

| Command | Build |
| --- | --- |
| `snail build`, `snail run`, `make site`, internal source compile/run | Static; `--release` does not invoke an optimizer |
| `snail dev`, `make dev`, `snail lsp` | Separate development modules |

The public commands operate on projects. Compiler contributors can use
`./scripts/snail-tool run SOURCE`, `wat SOURCE`, `schema SOURCE` or `bootstrap`.
`./scripts/snail-tool compile -o FILE SOURCE` writes a runnable Wasm file and its
compiler-generated WAT; it does not provide project publication guarantees.
Source-level `run` uses a private build directory by default and removes it when
the process finishes.

Compiler contributors also have `build/snail`, which Cargo builds from
`crates/snail`: a native executable that embeds wasmtime. Its subcommands
are internal to the driver and the tests:

| Subcommand | Does |
| --- | --- |
| `build/snail run-wasm PROGRAM ARGUMENT ...` | Runs a compiled program, one linked module, its `.cwasm`, or a per-library `modules.json`, which the engine links (`build/engine/engine.wasm`), as `host/native/run-snail.mjs` does, with the same exit statuses, unless it imports sockets, processes, file modes or watches. The compiled compiler is one such program. |
| `build/snail precompile MODULE OUTPUT` | Writes the module's machine code as a `.cwasm` file, which `run-wasm` loads in place of the module. |
| `build/snail assemble INPUT.wat OUTPUT.wasm` | Assembles text with `wat`. |
| `build/snail link INPUT.wat RUNTIME.wasm OUTPUT.wasm` | Assembles and statically links with `wasm-fuse`, using the same Rust backend as compiled tools. |
| `build/snail imports PROGRAM` | Lists the modules a program's modules import from, a line each, without compiling them. |

`SNAIL_ENGINE=wasmtime` makes the driver run every compile on it, and
every program that needs no sockets, processes, file modes or watches. The
[bootstrap chapter](bootstrap.md#the-native-executable) explains why Node stays
the default. Stage 0 uses the native executable for assembly and linking on
both engines. The public `./snail` launcher is
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

## Contributor checks

`make test` runs the compiler and project unit tests, program fixtures, host
and development-service checks, and static and linked application checks.
Each fixture owns its output files and each compile has private scratch, so
the compiled compiler's fixture checks compile, link and run in the test
runner's eight child processes. Linked-module cases use the same worker
limit. `make test-chez` keeps source compilation serial because each Chez
compiler needs a large heap; its static programs still link and run in parallel.
Stage 0 places Wasm modules in the object store using the shared SHA-256 implementation,
with parity tests against the compiler's portable hash. Hashing these large
binary artifacts stays in the host; the self-hosted compiler keeps its own
portable implementation.

CI reports formatting, both Rust crates, tool building and the Snail suite
as separate steps under the required `Complete correctness checks` job. It
caches Cargo's test targets and the driver's native and WASI target
directories; Cargo checks their freshness on every build. Test debug symbols
and incremental compilation are disabled there to keep these caches small.
The bootstrapped compiler has a separate exact cache key covering its source,
bootstrap hosts, Rust runtime and pinned tools. On an exact hit, CI refreshes
its timestamp to account for checkout's new source timestamps. A changed
input rebuilds the bootstrap, and test outputs are rebuilt on every run.

## Assembly, linking and optional optimization

`(snail shell assembler)` offers `assemble` for an independent module and
`link` for a standalone program, taking program text and runtime bytes and
returning a `Result` of bytes or an error message. The toolchain runtime's
`assembler` feature provides `wat` and `wasm-fuse`; plain program runtimes
carry neither. Stage 0 calls the same Rust functions through `build/snail`.
No Binaryen installation is required.

Linking resolves the program, runtime and diagnostics/cleanup adapter before
removing `snail:*` and `diagnostics/*` exports. All other exports survive,
including GC globals and dynamic functions. A second `wasm-fuse` pass prunes
unreachable definitions and remaps debug names. Function bodies are not
optimized. Debug and release use this same backend; the internal source
driver also continues to accept `--release`.

Optimization can be a separate user-owned step, with Binaryen installed
independently:

```sh
wasm-opt program.wasm -o program.optimized.wasm -O3 \
  --enable-gc --enable-reference-types --enable-tail-call --enable-bulk-memory \
  --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals \
  --always-inline-max-function-size=40 --converge
```

Optimize a copy, outside a published generation and its cache. Avoid
`--closed-world`: hosts and separately linked libraries can retain function
references and access each other's GC values.

## From an edit to a build

`snail dev PROJECT` starts one native development process, which prints its
URL and serves each browser target at `/NAME/` on it. `--port PORT` selects a
port (8000 by default; 0 chooses a free one). `make dev` runs `snail dev .`
for the whole repository, whose root `project.datum` names the `siegework`
and `hearsay` browser targets. Any editor writes the files; the service owns
observation and compilation, and the pages relink into each accepted build.

```text
editor or other writer -> disk -> disk task
                                     |
                                resident builder
                                     |
                            candidate + diagnostics
                                     |
                        reconcile and accept or discard
                                     |
                      output links + status + page reloads
```

Saving only writes disk. The disk task triggers compilation regardless of which
program wrote the file. A POST to `/.snail/build` also requests an attempt.
Unsaved text never enters compilation. Each attempt starts with fresh
compilation and diagnostics; an error does not display stale diagnostics from
the preceding attempt.

The cold commands, `snail build` and `snail run`, are a Snail program,
`bootstrap/cli.sld`, which builds with `(snail shell project build)`: the
compiler and linker run inside it through `(snail shell assembler)`, and
Node runs producers. Stage 0 rebuilds the
program when its sources change (`scripts/snail-tool cli-tools`), and is the
only judge of when they have. Starting Chez and Cargo to find nothing stale
takes most of a second, so `./snail` keeps stage 0's answer in
`build/tools-KIND.txt`, stamped with the time stage 0 began, and uses it again
while every tool it names exists and nothing stage 0's rule reads is newer:
the `.sld` files under `src/`, `bootstrap/` and `host/browser/`,
the runtime crate, `rust-toolchain.toml`, and stage 0's driver, which says where
the tools go. The check over-approximates the rule, so a false alarm costs only
stage 0's run, and it takes about 15 ms. `snail run`
publishes the run's program and then becomes it through `exec`, so the
process the caller started is the program's, with its arguments, standard
streams, working directory, status and signals. Development builds with the
same program, as `snail resident PROJECT` in a child process, so synchronous
compilation and tool IO cannot block the HTTP service or disk observation
([the resident builder](compilers.md#the-resident-builder)). The resident
rebuilds all configured targets on every attempt. Producers run again, once
each within the attempt, and every library is checked, emitted and assembled.
The [compiler chapter](compilers.md#separate-compilation) describes this full
build. The previously published generation remains usable until a successful
candidate is accepted.

`snail dev` is the same program's `dev`, whose service is
`(snail shell project service)`. Its tasks each wait on one thing: the owner,
which holds the step below and everything it leaves to its host, and receives
every message; the disk task, which holds the latest inventory; a task writing
the resident's requests and two reading its output; and a task for each HTTP
connection. No cell holds state: each task threads its own through its loop,
and tasks share only mailboxes. It replaced a service in JavaScript
([#567](https://github.com/tsnl/snail-scheme/issues/567)), whose few cases
tested in process became scenarios of the step's race tests.

### Observation and acceptance

The disk task's inventories ([`(snail shell watch)`](libraries.md)) cover the
project, `src/` and `host/browser/`, without the project's `build` and `.git`
directories or the root's `build`. Exclusions are exact paths, not every folder
named `build`. It takes one when the step asks it to reconcile, each second,
and on a hint from Node's recursive watch of a root, and
reports the paths whose fingerprints changed since the last complete one. A
file's fingerprint is its size and nanosecond modification time. A directory's
is its kind alone, so writes inside an excluded directory do not invalidate its
parent. A symbolic link is recorded, not followed. A hint names nothing: a
watch can miss a change or be lost, and the next inventory finds what it
missed. The caller decides which observed paths affect compilation.

A path that vanishes while an inventory is taken is left out, as removed. One
that cannot be read otherwise fails the inventory. The task then keeps the last
complete one and reports the failure once, when it begins. It answers a
reconciliation with the failure, so the attempt fails with its message. The
first inventory that succeeds again reports what changed meanwhile, then the
recovery, which builds. There is no content cache or filesystem snapshot.
Metadata polling catches ordinary local writes but cannot guarantee detection
on filesystems that hide changes behind unchanged or coarse metadata.

The owner runs serialized project attempts and keeps one current status. It
writes the resident's requests a line each, and reads its replies, by epoch.
Each attempt starts with an ID and empty diagnostics. The service
keeps distinct observed paths only for the active attempt, including paths outside
the previous project's public inputs. A reply carries the newly parsed description
even after a later build failure. The service reconciles disk, tests those paths
against the new description, and asks the resident to publish only if no observed
input change, and no build requested meanwhile, superseded it. Otherwise it discards and
coalesces a successor, so the attempt that answers a build request began after it.
Accepted application files remain available after a failed or discarded build.

`(snail shell development)` makes these decisions as a pure step. It is a function from the service and one event to the next
service and the commands its host carries out in order. The events are the
observer's hints and reconciliations, the resident's replies by epoch, the
debounce timer, build requests, the resident's exit and closing. The commands
are building, reconciling, publishing or discarding a candidate, giving up an
attempt's directory, arming the timer, reclaiming generations and notifying.
`tests/programs/development-step.sld` drives it through those races. The
owner feeds it each event, and carries out the commands it answers with, in
order.

Source inputs currently include the project description, `.sld` libraries, declared
entry/public paths, browser runtime assets and the files the latest publication's
programs link, which the resident names with each target. Ordinary data writes do
not request builds. Arbitrary producer file reads are not tracked yet: ask for
a build for those inputs. Unnamed watcher hints do not themselves declare source changes.
The observer and compiler do not claim an atomic filesystem revision.

Before sending work, the owner reserves `build/.snail-attempt-N`, a name that no
entry of the project's build directory has or begins with, and the resident names
the attempt's generations with it. A reply relinquishes that attempt; the
resident's exit relinquishes any unfinished one. This lets the owner remove only
abandoned private generations, including ones a crashed resident never returned.
Publication consumes ownership even when some target links moved before failure,
so those generations must never be swept afterward. The service reclaims the
generations it published once nothing needs them: it keeps the latest
publication and the one before it, which a page may still be loading from.
What was published before the service started, and what a publication that
failed part way linked, are not among its publications, and stay. Shutdown
suppresses acceptance and closes observation. It ends the resident's input, so
the resident finishes the request it is answering and exits, and kills it if it
has not 2 s later. Cleanup waits for its exit. Arbitrary compiler traps retire
this development session; there is no automatic crash loop.

## Project HTTP service

The service listens on `127.0.0.1` and prints its URL once it does. It
answers each connection's one request in the connection's own task, through
the [Snail HTTP library](http.md). Its own paths are under `/.snail/`; every
other path is a browser target's
([browser targets in development](applications.md#browser-targets-in-development)),
and `/` lists them.

| Request | Result |
| --- | --- |
| `POST /.snail/build` | Asks for an attempt, with an empty body; 202 with the status. |
| `GET /.snail/status` | The session's status, below. |
| `GET /.snail/events` | SSE: a `status` event with the status on connection and on each change of it. |
| `GET /NAME/...` | Browser target `NAME`'s latest build, its pinned builds and its page events. |

```json
{"phase": "succeeded", "id": 4, "diagnostics": [],
 "published": {"id": 4, "targets": [{"name": "main", "directory": "/project/build/.snail-attempt-…", "digest": "…", "compiled": 1}]},
 "compiler": {"worker": 1}}
```

`phase`, `id` and `diagnostics` are the attempt last started, numbered by the
epoch, and what it reported; each diagnostic has a `message` and a `source`
point, `{file, line, column}`, or `null`. `published` is the build the session
last accepted, `null` before the first: its epoch, and for each target the
generation directory its `build/NAME` link names, the digest of that
generation's files, and how many library modules that build compiled, with a
browser target's `url`. The digest hashes the target's sorted relative
filenames and bytes, including the runtime, artifacts and public files, but a
module file adds only its name, which is the digest of the text it was
assembled from; generation names are excluded, so an unchanged build has the
digest of the last. `compiler` identifies the
resident builder by its process ID, `worker`, and is `null` once it has exited.

A stream's connection task writes what the owner sends it, and a frame closes a
stream with 16 KiB already sent to it unwritten. An idle blocked stream
stays open until another event or connection closure, within the 64-stream
limit. There is no event archive or replay cursor: a reconnect gets the
current status.

The development loop's tests (`tests/project-attempts.mjs`,
`tests/project-reload.mjs`, `tests/project-development.mjs`,
`tests/project-resources.mjs`, `tests/project-bundles.mjs` and
`tests/browser/reload.mjs`) spawn `snail dev --port 0` and observe it only
through the URL it prints, the status, the event stream, the files on disk
and process IDs, so nothing they check depends on how the service is written;
`tests/development-service.mjs` is that client. A complete-rebuild case asks
for each attempt and reads what each target compiled, and its digest, from
the status. The
tests of `snail build` and `snail run` likewise see only the command's exit
status, its output and the build directory. What must happen within one turn
of the session is a transition of the step, and
`tests/programs/development-step.sld` tests it as one.

Requests are framed by Content-Length alone, as in the
[Snail HTTP library](http.md): a request naming a Transfer-Encoding is
answered 411 before routing, or 400 if it also gives a Content-Length. Bodies
are limited to 8 MiB, and a build request takes none. The service requires
its exact Host authority, so a page of another site that rebinds a name to
this address reaches nothing, and answers only reads but for the build
request. It provides no CORS access. This is not authentication against other
native processes on the same machine.

Closing closes the listener, every HTTP connection and every event stream,
then waits for the resident to exit. A fatal compiler or service failure
closes the session, and `snail dev` exits with status 1 and its message;
failing to listen ends it before anything starts.

## Editors

Snail Scheme has no editor of its own. An editor gets what it needs from two
pieces in the repository: a [tree-sitter](https://tree-sitter.github.io/)
grammar for what it can tell from the text alone, and `snail lsp`, a
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
server, for what takes the compiler. `editors/zed` is the extension that puts
them together for [Zed](https://zed.dev/).

### The grammar

`editors/tree-sitter-snail` parses the reader's data: lists in `()` or `[]`,
`#u8(` byte vectors, quotes, strings, and the comments the reader discards,
`;` lines, nested `#| |#` blocks and `#;` datum comments. Its external scanner,
`src/scanner.c`, reads every other token to a delimiter and classifies it as
`token-kind` in `src/snail/shell/compiler/read.sld` does: a boolean, a number,
a character or a symbol. A token the reader rejects, such as `.` or `#x1F`, is
a symbol to the grammar, so Chez's own files still parse. The grammar is for
editors alone; the compiler keeps its reader. The generated parser is
committed, and `tests/tree-sitter.mjs` (in `make test`) checks that
`grammar.js` still generates it, runs its corpus and highlight tests, parses
every tracked Scheme file without an error, and checks that the keywords Zed
colors are `(snail shell highlight)`'s.

The queries live with the extension, under `editors/zed/languages/snail/`:
`highlights.scm` colors the core forms, the derived forms and declaration
words, capitalized type names and the name a definition introduces;
`brackets.scm`, `indents.scm` and `outline.scm`, which lists a library by
its name and then its definitions.

### The language server

`snail lsp` is the command line's `lsp`, `(snail shell lsp)`. It reads
Content-Length framed JSON-RPC on standard input, answers on standard output,
and serves the project at the root folder the editor opens. It offers:

- **Diagnostics.** Once the editor is ready, and on each save, it builds the
  project as `snail dev` would, in development mode with scratch under
  `build/snail-run/`, and discards the candidate, publishing nothing. Each
  failure is reported on its file, over the range `(snail shell highlight)`
  derives for its point: the token there, or the datum that starts there. A
  file is cleared once it builds. A failure with no point, or in a file that
  does not exist, is reported on `project.datum`. Like `snail dev`'s, a build
  reads the disk, so diagnostics follow what was saved.
- **Formatting.** The open text, formatted by `(snail shell format)`, as one
  edit of the whole document.
- **Hover and definition.** The last build's checked libraries give each
  variable's use its type and the binding that introduces it: a top-level
  definition, perhaps in an imported library, a `let` binding or a lambda's
  parameter. Hover shows the name, its type and the library it comes from;
  definition goes to the name in its binding form.

Positions are counted in UTF-16 code units, as the protocol's default
encoding is. `tests/lsp.mjs` (in `make test`) drives the server through
each of these on a project of its own.

### Zed

`editors/zed` is a Zed extension: `extension.toml` names the grammar, by
repository and revision, and the language server, and `languages/snail/`
holds the language's configuration and queries. Zed runs extensions in a
wasmtime without its garbage-collection feature and loads only Rust, so the
extension is a small Rust crate, `src/snail.rs`, compiled to
`wasm32-wasip2`. It only finds the command: the `snail` binary path the
user's settings give under `lsp.snail`, then a `snail` on the worktree's
`PATH`, then the repository's own `./snail` launcher. To try it, choose
**Install Dev Extension** in Zed's extensions page and pick `editors/zed`.

### The formatter

The command-line formatter, `scripts/format-scheme`, runs the same library as
the language server. Stage 0 builds and caches its small Snail program on first
use and rebuilds it when its sources change. With no arguments it formats
stdin to stdout; optional `--width COLUMNS` selects a positive width instead of
100. `--check FILE ...` reports every file needing formatting on stderr and
exits with status 1; `--write FILE ...` updates only changed files.
`make check`, `make format` and `snail lsp` all use this implementation.

Binding forms are recognized by name: `let`, `let*`, and any name ending in
`-let` or `-let*`. A user-defined `result-let*` or `retry-let` needs no formatter
registration. Bindings align with each other, and the body is indented two
spaces from the form's opening parenthesis. Forms ending in `-let` also use
named-let layout when a loop name precedes the bindings. This is a formatting
convention; the formatter does not expand macros or inspect their definitions.

## Browser packaging

Packaging has three steps: copy host and project assets, generate the default
manifest only when the project has none, and add typed page metadata. The
manifest is a normal bundled file. `(snail shell project web-app)` renders
metadata constructors with HTML attribute escaping and inserts them at the
page's head boundary, preserving the supplied HTML, head attributes, comments
and doctype. The reload client's Snail datum text travels in a `meta` element's
`content` attribute; browser decoding precedes datum parsing. Scheme fixtures
cover this encoding and page construction; Chromium checks the browser's
resolved URLs and standards mode.

Browser bundles expose a web-app manifest by default. The
manifest gives a standalone window, the application name, theme colors, and
192/512-pixel icons. A browser target can provide `public/manifest.webmanifest`
to replace the default entirely, including its icons and display mode; it is
served unchanged. The builder links the manifest from UTF-8 `index.html` pages.

During development, the page's scripts remain pinned to their build, while its
web manifest is linked at `/TARGET/manifest.webmanifest`. Its relative
`start_url` and `scope` resolve at the stable target mount, and the default identity
is that resolved start URL (no explicit `id` is emitted), so installing it
never pins the launch URL to a reclaimed generation. Static bundles use a
relative manifest link and work under a deployment subdirectory. Keep the same
host and port for a local installed app. HTTPS or a loopback origin is needed
for browser installation; the development server must remain running. These
manifests do not add offline caching or a service worker.

## Code highlighting

The book colors code with `(snail shell highlight)`, and editors with the
[grammar](#the-grammar), which agrees with it.
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

Proposed: once the book is itself a Snail Scheme project, the classifier can run
in a `generate-library` recipe that writes the highlighted pages, and the mdbook
preprocessor goes away.

## Application and networking integration

The native service serves each browser target's builds to pages that reload
as each new one is published
([browser targets in development](applications.md#browser-targets-in-development)).
A program target runs with `snail run`, outside the service. Durable
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
| Editor ↔ language server | LSP over standard streams: open text, saves, diagnostics, formatting edits, hovers and definitions. |
| Development process ↔ resident builder | Attempt IDs, project descriptions, results, diagnostics and candidate output identities, as JSON lines. Compiler objects and candidates stay in the resident. |
| Browser ↔ application server | Ordinary HTTP. In development, each page's build's manifest and the events of the builds after it. |

A future debugger attaches to a program's process and build. Its inspector
endpoint expires with that process. `run-snail.mjs` executes Wasm on the process's main
thread, so attachment reaches the program itself. Debug commands use the inspector
connection rather than compiler requests or parsed stdout. The editor
stays responsive while an application is paused. Source mappings and
breakpoints require a separate compiler/assembler proof; debugger support is
not implemented. [Editor and debugger work](https://github.com/tsnl/snail-scheme/issues/461)
tracks these extensions.

[Build-tooling and package decisions](https://github.com/tsnl/snail-scheme/issues/462)
track complete rebuilds, producer-input observation and package installation.
