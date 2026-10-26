# Projects, development and the IDE

**Implementation plan; individual state APIs remain under review.** This follows
[#421](https://github.com/tsnl/snail-scheme/pull/421) and replaces the desktop
proposal preserved by [#412](https://github.com/tsnl/snail-scheme/pull/412).
The [earlier document](https://github.com/tsnl/snail-scheme/blob/be6c41ef76d79d186fc2f405e1c44d28450318bc/doc/proposals/desktop-ide.md)
is historical. The settled project/IDE changes are authorized for implementation;
the [typed state prototype](typed-state.md) remains under review.

## 1. Terms and commands

A **project** is one directory containing source files and its project
description. A **workspace** would be a collection of projects; this design
supports one project and needs no workspace object. The book's
[terms](../book/lofi/terms.md#toolchain-terms) distinguish build targets,
launch targets, compiler sessions, runtimes and processes.

`lofi dev` owns a development session: watching files, keeping the incremental
compiler alive, running selected applications and serving the editor UI.
The UI is a client of these services. Closing it does not stop development.
Applications execute as ordinary subprocesses with the same entry point,
arguments, working directory and standard streams as a shell invocation.
A web application's browser windows are clients of its server; opening a
window is not the definition of launching an application.

| Proposed command | Responsibility |
| --- | --- |
| `lofi build PROJECT` | Read the project description and produce target output directories once. No resident development service is required. |
| `lofi dev PROJECT` | Watch saved files, compile incrementally, publish diagnostics and make the editor available. Selected launch targets run here. |
| `lofi run SOURCE [ARGUMENT ...]` | Retain ordinary program execution, using the same compiler and output-directory contract. A server is an ordinary program too. |
| `lofi serve OUTPUT-DIRECTORY [ARGUMENT ...]` | Proposed production entry for a release-built server program. No watcher, editor or development reload endpoint. |

`dev` replaces `watch`, the development role of today's `serve`, and the
separate IDE command/package workflow. Reserve `serve` for production;
its exact command-line spelling remains proposed. The command examples in
the existing guides continue to describe implemented behavior until migration.

## 2. Project descriptions belong to the compiler toolchain

Use an inert `project.datum`: one list of explicit forms, readable and
printable without dotted pairs. These forms describe work; they never execute.
The earlier executable `project.sld` and its `init`/`build`/`launch` queries
are removed. Both the inert format and the `project.datum` filename are settled.
The [format and parser](../project-format.md) are implemented; CLI integration
follows separately. Literal `library-roots` are optional per build target.

```scheme
((build-target client
   (browser
    (entry "client/main.sld")
    (public "client/public")))
 (build-target admin
   (browser
    (entry "admin/main.sld")
    (public "admin/public")))
 (build-target server
   (program
    (entry "server/main.sld")))
 (run-target dev
   (run server
    (args ("--port" "8080")))))
```

Each build target produces **one output directory**, containing any number
of files. There is no second output-name namespace. The compiler driver,
loaders, CLI and IDE consume that same directory contract, including the
manifest identifying its modules or browser bundle when needed. `compile -o`
and `run -o` now publish `DIRECTORY/program.wasm`, a breaking change from the
old filename argument. Single-file builds stage the completed file on the
destination filesystem and rename it atomically; unrelated files remain intact.
Multi-file bundles need a publication boundary for the whole artifact so a
failed attempt cannot expose half a program.
`dev` uses separate debug modules; `build --release` uses the existing release
pipeline. Development bundles carry reload manifests/support; release bundles
omit them.

This replaces project build scripts in general, not just IDE configuration.
`lofi build [--release] PROJECT TARGET` now selects one target and publishes
`PROJECT/build/TARGET` as a link to a completed generation. Program and browser
builds use `program.wasm`; browsers add host files and their public tree,
including `public/index.html` when supplied. Prior generations stay available;
readers resolve the link once to consume a coherent artifact. No extra manifest
is needed for these statically linked builds.

`scripts/project.mjs` now owns traversal and packaging for cold and incremental
builds, replacing the temporary Chibi project builder and `scripts/build-app.scm`.
The Makefile's application recipes use it. The separate
IDE packaging script remains until the editor becomes a development client.
The compiler's bootstrap, linking, assembly and generated-library primitives
remain; descriptions do not replace Chibi's stage-0 role or become an arbitrary
build language.

Parse once into target and launch descriptions. Reject duplicate names,
unknown forms, bad paths and invalid launch references. Library roots and
public directories are literal settings. The toolchain supplies its standard
library. No configuration evaluator, conditions, includes, callbacks or
metadata permission framework is needed.

### Frontends are dependencies of programs

A server source can use `(artifact-bundle "client")` and
`(artifact-bundle "admin")`. Each denotes the complete output of a named
build target as a typed bundle, resolved while compiling. It is not a raw
mutable build-directory path or a lookup performed on the first HTTP request.
Carry the bundle through ordinary/generated libraries, using the existing
`generate-library` machinery where appropriate. Preserve Hearsay's generated
libraries. A bundle's `public` files belong to that bundle.

One server may serve several bundles under different route prefixes. Routes
are ordinary server code, and bundle URLs must respect their mount prefix.
There is no one-server/one-frontend relationship in the project schema. A
frontend is a build dependency, not an independently launched server actor.
Programs without a frontend remain ordinary programs; TCP/UDP servers and
future desktop applications do not need new language-level application kinds.

Artifact requests arise during actual expansion, including generated code.
The parser therefore cannot prove the complete dependency graph acyclic.
Resolve targets serially with a depth-first traversal, detecting an active
ancestor as a cycle. Replay recorded artifact requests before reusing cached
expansion. For example, unchanged A previously used B; B now uses A: the next
attempt must report the cycle. Missing names, wrong kinds and producer errors
fail before a consumer launches. A selected build checks reachable targets;
`dev` initially visits all project build targets for project-wide diagnostics.

## 3. The development loop

```text
Editor save ----------> file service ----> project files <---- other editors/agents
                                             |
                                      shared file watcher
                                      /                 \
                         persistent compiler        editor subscriptions
                                  |
                      attempt diagnostics + completed builds
                           /                         \
                    UI subscriptions           application subprocesses
                                                        |
                                                browser clients, if any
```

1. Load the project description from disk. Start one watcher for project and
   relevant library inputs, excluding build output and application data.
   Read/reconcile the initial
   tree after installing watches so startup changes are not silently lost.
2. Keep one incremental compiler alive, reusing existing `Session` values per
   target. A persistent Node worker runs compilation because the present
   Wasm compiler is synchronous and would block file requests and watch delivery
   on the parent thread. This is an execution boundary, not a compiler daemon
   or a second implementation. Cold `build` invocations need not attach to it.
3. File notifications trigger debounced build attempts. Editor Save only writes
   a file; it does not call Build or send edited contents to the compiler.
   The same watcher notifies the editor of changes made by agents and other
   tools. Explicit initial builds and manual Build are allowed too.
4. Serialize attempts. Changes observed during one attempt mark another needed.
   Do not publish or launch an observed superseded attempt. Coalesce the next
   attempt; never lose a change by clearing the pending work after compiling.
5. Give every attempt an ID and a **fresh diagnostic collection**. Publish
   `building` with that ID and an empty current collection, then its diagnostics
   and success/failure. Superseded results cannot replace the current collection.
   An empty collection while building is not success. Project-wide names the
   attempt's scope, not exhaustive error recovery: the compiler still stops at
   its first error initially.
   Turn its existing located failure into diagnostic data at the compiler
   boundary; the editor need not interpret compiler stdout.
6. Publish completed target directories after success. The launch controller
   and browser reload path consume that result independently of the UI.
   Failed attempts report errors while the last successful application stays
   running. Stop overrides pending automatic restart intentions.

Fast compilation comes from retaining `src/lofi/compiler/session.sld`'s
checked libraries and emitted modules. It does not come from repeatedly
starting `lofi build`. Fresh diagnostics do not require throwing those caches
away. Cache entries must still prove their source/interface/artifact inputs
unchanged; failed or changed sources cannot borrow an old successful result.

Disk is the source of truth. There are no unsaved build overlays or immutable
source-tree snapshots. The promise is convergence after edits settle, not an
atomic filesystem revision. Watch events prompt reconciliation with disk;
renames, creation/deletion, missing filenames and watcher recovery must be
handled. Node documents these [watcher caveats](https://nodejs.org/api/fs.html#caveats).
Generated outputs propagate through compiler dependencies, never back through
the source watcher. Keep conservative producer regeneration until read
tracking justifies reuse: the existing recipe hash does not cover every file
a producer can read. Builds use private output staging, not copied source trees.

## 4. Running and reloading applications

**Server and browser application data must survive code replacement.** The
[typed state prototype](typed-state.md) develops the agreed direction: durable
base tables and disposable, read-only cached views. There are no mutable volatile
tables or application `resume` methods. It supersedes the earlier proposal to
save an application's working state immediately before replacement.

### Facts, views and ordinary startup

Tables hold retained facts as ordinary typed records. Views derive working
values from one consistent database snapshot and explicit parameters. A cache
can be discarded at any time; application code does not manually rebuild or
synchronize it. A new program starts normally, opens the same store, recreates
its sockets/windows and computes views as requested. Committed data survives;
managed objects, closures and suspended computations do not cross code versions.

The prototype specifies typed operations, closed read/write effects, transaction
failure boundaries, coherent snapshots, cache identity, external writers and
schema compatibility. Its syntax, checking rules and storage implementations
remain proposed. The existing browser save/restore implementation remains until
its replacement is reviewed and tested. No new application typeclass is required.

This is a state organization contract, not a promise of zero-cost persistence.
Views cannot reconstruct facts absent from durable inputs. Frequent authoritative
writes still cost database work; coarse cache invalidation and reconstruction
must be measured. Keep data files and journals outside compiler watch inputs
and output directories. Browser applications use distinct stable store names.

### Process replacement

Applications remain ordinary subprocesses. After an accepted build, stop the
affected child, await exit and start the new program against the same store.
Start/Stop/manual Restart and standard streams remain ordinary process controls.
Run records identify launch target, build, process and exit status. Use bounded
termination; killing a process does not promise cleanup or a final commit.
A committed write may survive even when its client never receives a reply.

Transactions finish or abort at their defined commit boundary. Code replacement
discards view caches. If new startup fails, preserve stored records and report
the failure; automatic rollback to the old running loop is not promised.
Reverting code does not undo database writes. Durable schema changes require
explicit migration, while changing a view's result type only invalidates caches.
No database-state transfer IPC is needed.

One concrete server database binding is sufficient. SQLite is a candidate:
the pinned Node 26.8.1 offers `node:sqlite`, and a temporary probe confirmed
committed records survive exit while an open transaction rolls back. This does
not establish a Lofi binding or nonblocking execution; Node's [SQLite API](https://nodejs.org/api/sqlite.html)
is synchronous. Browser storage needs its own transaction/commit proof.

### Build delivery

Keep the server origin stable across restarts. A small HTTP bundle helper
serves files, development manifests and reload events from completed builds.
After reconnecting, the browser receives the latest manifest. Pin replacement
assets to the advertised build: fetching B must not return C's bytes. If B is
unavailable, reconcile with the latest manifest and retry. A network failure is
distinct from incompatible stored data; neither permits silently clearing data.

Do not advertise a bundle before its server serves it. Multiple bundles have
separate prefixes and manifests. Production serving omits development endpoints.
Code compilation does not prove client/server API or data-schema compatibility.

## 5. Concrete networking

Provide concrete **TCP and UDP** socket operations that effect handlers can
intercept for testing. TCP has listen/accept/connect, stream reads/writes and
close; UDP has bind, send/receive datagrams with peer addresses, and close.
Keep their semantics distinct: TCP can split transfers; UDP preserves message
boundaries without promising delivery or ordering. Define buffer limits,
truncation, cancellation and late completion at these boundaries.

Use the existing task suspension bridge for pending native operations. HTTP
is a Lofi library over TCP, with bounded parsing, framing, ordinary routing
and the small bundle/SSE helper. Test real sockets as well as intercepted
operations. No transport hierarchy, actor channel or generic IO-provider
framework is needed. TLS, HTTP/2 and deployment infrastructure remain separate.

## 6. The editor and the IPC boundary

The file service reads/lists files and saves them, checking the last observed
disk version to detect ordinary external-edit conflicts. The editor owns
unsaved buffers, selections and panes. A watcher update reloads a clean buffer;
a dirty buffer offers conflict resolution. Saving acknowledges the bytes
written; watch reconciliation supplies the file-change notification. Do not
promise atomic compare-and-swap against arbitrary external writers.
Bind the local editing/control API to loopback and accept mutations only
from its own origin.
Serve this API and editor subscriptions in the development process using
the same HTTP library; the compiler worker has no HTTP server of its own.

The editor subscribes to file changes, build state and fresh diagnostics. It
can request builds and control launches, but owns no compiler session or
application lifecycle. Squiggles describe saved source; hide them while the
buffer differs. A reconnect fetches current file/build/run state,
not a replay of every event. Keep formatting local. Remove the integrated
preview and the browser compiler/filesystem emulation. Browser windows remain
ordinary application clients, outside the editor's document model.

| Boundary | Information crossing it |
| --- | --- |
| UI ↔ development process | File reads/saves, subscriptions, build/run requests, diagnostics, logs and status. |
| Development process ↔ compiler worker | Project/changed paths and attempt IDs; results, diagnostics and completed output-directory identities. No compiler objects or WasmGC references. |
| Development process ↔ application process | Entry/arguments/environment/working directory; standard streams, exit status and OS process control. Associate each process lifetime with its build. |
| Browser ↔ application server | Ordinary HTTP plus the bundle's development reload stream. |

Debugging is future implementation work, but this boundary should leave one
clear place to attach it: a run's process identity and successful build identify
the debug target and source. A future optional inspector endpoint belongs to
that run and expires with it. The current runner executes Wasm in a Node worker;
attachment must reach that execution agent, not just its wrapper. Debug commands
travel on the inspector connection, not through compiler requests or stdout
parsing. The dev process remains responsive while an application is paused.
Source mapping and breakpoints need a separate compiler/assembler proof; no
DAP framework or GC-object inspector is required for this series.

## 7. Global simplification plan

- Reuse the compiler session. Replace application checkpoint/resume policy
  with durable facts and disposable views after the state prototype is reviewed. Delete the competing browser build
  backend and preview.
- Use one disk-change path for the compiler and editor. Delete unsaved compiler
  overlays, server-owned buffer histories and source snapshot machinery.
- Make project files the shared compiler/CLI build description. Delete redundant
  application build scripts and the old development-command split.
- Give each target one output directory. Keep serial artifact resolution;
  omit extra output names, recipe plugins and a second dependency scanner.
- Keep process control ordinary. Omit custom readiness/shutdown protocols,
  runtime actor registries, embedded browser documents and virtual URL schemes.
- Use concrete socket effects and HTTP library code. Keep debugger work outside
  this stack while preserving process/build identity for later attachment.
- Keep durable facts in typed tables and derive working state through views.
  Use one concrete server database binding; omit manual cache rebuilding,
  automatic heap snapshots, a database engine of our own and state-transfer IPC.

Each implementation PR must name what it deletes and the surviving owner,
update its book pages and `TOUR.md`, and test one meaningful behavior or failure
boundary. Record production, test and documentation line changes separately.
Astra Max simplify reviews should challenge retained behavior, not merely
validate the machinery chosen to preserve it.

## 8. Proposed PR sequence

These are implementation cuts above #421. Settled project/IDE work is authorized;
state-library integration waits for prototype review. The anchors refer to the
current code. Each state-library cut will be split further once its API is settled.

| PR | Change grounded in current architecture | Simplification and evidence |
| --- | --- | --- |
| 1. Delete the preview | Remove `src/ide/preview.{mjs,html}`, iframe/ports and preview packaging. | Keep editor formatting, panes and diagnostics; no replacement preview protocol. |
| 2. Project forms | Parse explicit target/launch forms in `(lofi project)` with the compiler's located reader, shared by Chibi and Wasm. | No evaluator or metadata sandbox. Check duplicate/invalid forms, resolved launch types and round-trip printing. |
| 3a. Output directories | Change `scripts/lofi.scm` and `host/chibi/lofi/build.sld` callers to the directory contract. | Keep linker primitives; publish only completed `program.wasm`. Execute output and prove failed builds preserve it and unrelated files. |
| 3b. CLI project builds | Consume parsed project descriptions, introduce project builds and replace application packaging scripts. | One compiler build path; inspect browser output files and preserve generated libraries. |
| 4a. Artifact compiler contract | Extend `expand.sld`/`session.sld` with a concrete file resolver, exact cached evidence and ordinary typed bundle values. Existing hosts reject requests until connected. | No new backend representation; test hygienic/generated uses, replay failures, changed bytes and generic importers through executed Wasm. |
| 4b. Native compiler inputs | Replace stderr work requests with typed request/reply datums. Keep an artifact resolver bound through nested producer compiles. | One request file per exclusive compile scratch directory, no compatibility path. Test stale/malformed/repeated requests, resolver scope, generated libraries and binary embedding. |
| 4c. Project artifact traversal | Bind the project builder's serial target traversal to compiler artifact requests. Keep completed generations stable throughout the build. | No scanner or runtime lookup. Test missing targets, cycles through producers, repeated targets, multiple bundles and Hearsay generation. |
| 5a. Native compiler worker | Move the existing Wasm loop into one persistent worker; the native parent owns HTTP, watches, timers and children. Replace published files atomically while HTTP reads concurrently. | Immediate helpers stay local, five existing commands cross the boundary. Test HTTP while a real compiler read is blocked, staged publication, an edit during compilation, error recovery, incremental reuse and live-child shutdown. |
| 5b. Session input lifetime | Pass generated-library and artifact providers to each `build-session` invocation. Sessions keep directories and compiler evidence only. | Delete stored callbacks; verify fresh providers preserve reuse, invalidate changed artifacts and propagate failures. |
| 5c. Native compiler facade | Expose project parsing, opaque compiler sessions and typed input requests from one Wasm compiler instance. Keep input retries outside active Wasm frames. | Reuse the existing request/reply format and effects; no native reentry or second project parser. |
| 5d. Shared project builder | Retain sessions per parsed target and use one native traversal/packager for cold and development builds. Stage completed candidates before publication. | Delete the separate Chibi project builder and hardcoded application layout; preserve producer and artifact semantics. Keep old commands until PR 11. |
| 5e. Watch reconciliation and attempts | Share one disk watcher and publish fresh attempt diagnostics. Stage results until the parent accepts a nonsuperseded attempt. | One source of disk changes; no editor-triggered builds or unsaved overlays. Test external writes, rename saves, invalid→valid builds and edits during compilation. |
| 6. TCP sockets | Add the concrete native TCP effect on `src/app/tasks.mjs` suspension and cleanup. | No provider hierarchy. Exercise real partial transfers, close/cancel and late completion. |
| 7. UDP sockets | Add concrete datagram operations beside TCP. | No stream emulation. Exercise peer addresses, empty/oversized datagrams and cancellation without assuming reliable delivery. |
| 8. Typed state (review pending) | Follow the [prototype](typed-state.md): typed table operations, transactions, coherent read snapshots and disposable views, grounded in existing effects, wire types and task suspension. | Replace checkpoint/resume and cross-build heap handover. Split schema/checking, platform storage and view caching into separate PRs after review; prove commit/cancel and snapshot/cache boundaries. |
| 9. HTTP and browser bundles | Implement HTTP over TCP and application asset/reload serving in the bundle helper; adapt `src/app/reload.sld` to the agreed replacement path. Make root-relative reload URLs bundle-relative and fetch the advertised artifact identity. | Ordinary routing replaces preview transport. Two frontends reload under distinct prefixes and retain independent stores. Retry interrupted fetches without resetting saved data; production exposes no dev endpoints. |
| 10. Server persistence | Bind one concrete database through effects in the Node runtime; keep its data outside build output and watch inputs. Exercise a server using committed application records. | No provider hierarchy or automatic heap persistence. Test a fresh process recovers committed data, an unfinished transaction is rolled back, and storage failures are reported. Verify the binding's blocking/cancellation behavior. |
| 11. Launches and reload | Reuse the child-process path and `scripts/run-lofi.mjs` for launch targets, restart ordering and process/build identity. Switch to `dev` and retire old watch/development-serve policies once application serving/reload passes. | No actor catalogue or database-state transfer protocol. Test failed-build continuity, Stop versus rebuild, server record retention, database-write watcher exclusion, restart during bundle fetch and browser data retention. |
| 12. File service | Add native file read/save and shared watcher subscriptions to `dev`. | Disk is authoritative; no server buffer database. External writes update clean buffers and surface dirty-buffer conflicts; saves never trigger compilation directly. |
| 13. Editor client | Adapt `ide.mjs`; delete browser `project.mjs`, `toolchain.mjs`, `develop.sld` and source/sample packaging; keep editor/panes/formatter. | The UI consumes the existing dev session. Test it in Chromium alongside an external file edit and a running subprocess. |
| 14. Examples and audit | Migrate example projects and command documentation, remove remaining obsolete scripts/adapters, audit the series. | Verify shared CLI/dev artifacts, generated libraries, saved-file squiggles and server/browser data preservation. Run compiler suites/bootstrap and inspect net production-code changes. |

## 9. Remaining review decisions

- Review the concrete [typed state prototype](typed-state.md), including its
  structural data/capture checks, transaction errors and cache policy. Durable
  tables, derived views and removal of `resume` are settled directions.
- Select the concrete server database binding and browser transaction strategy;
  measure write rates, cache invalidation and first-view latency after reload.
- `serve` is reserved for production; settle its output-directory versus
  project/launch argument before fixing CLI syntax.
