# Projects, development and the IDE

**Design for review; not implemented.** This follows
[#421](https://github.com/tsnl/snail-scheme/pull/421) and replaces the desktop
proposal preserved by [#412](https://github.com/tsnl/snail-scheme/pull/412).
The [earlier document](https://github.com/tsnl/snail-scheme/blob/be6c41ef76d79d186fc2f405e1c44d28450318bc/doc/proposals/desktop-ide.md)
is historical. Implementation waits for review.

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
 (launch-target dev
   (run server
    (args "--port" "8080"))))
```

Each build target produces **one output directory**, containing any number
of files. There is no second output-name namespace. The compiler driver,
loaders, CLI and IDE consume that same directory contract, including the
manifest identifying its program/modules or browser bundle. Changing
`compile -o` from a file to a directory is an acceptable breaking change;
migrate callers and tests together. Publish completed directories from build
staging so a failed attempt cannot expose half a program.
`dev` uses separate debug modules; `build --release` uses the existing release
pipeline. Development bundles carry reload manifests/support; release bundles
omit them.

This replaces project build scripts in general, not just IDE configuration.
In this checkout the concrete paths are `scripts/build-app.scm`,
`scripts/build-ide.scm`, the Makefile's application recipes and
`host/chibi/lofi/build.sld`. Move application selection and packaging into the
shared project build path and delete superseded scripts. Keep the compiler's
bootstrap, linking and assembly primitives; the description does not replace
Chibi's stage-0 role or pretend to be an arbitrary build language.

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

**Preserving server and browser application data across reload is required
in this series.** Storage is accessed through effects and outlives replacement
code: an actual database for server records, and a database-like store for
the browser. This does not require every state access to go through storage.

### Working state and persisted data

| State | During execution | Across replacement |
| --- | --- | --- |
| Server application records | Application operations read and commit database transactions; working sets and derived caches may stay in RAM. | The new process reopens the same database. It need not rewrite or eagerly load every record. |
| Browser working state | Updates and rendering use RAM. The application chooses its saved representation. | Proposed: a planned reload commits a checkpoint and restores it under the new code. IndexedDB already supplies the browser's checkpoint store. |
| Transient resources | Connections, suspended tasks, render caches and intermediate calculations belong to the running instance. | They are closed, interrupted or reconstructed; they are not serialized as application data. |

Storage lifetime and access frequency are separate choices. Siegework already
keeps a `Game` in memory and saves a `Save` containing its journal, tick, view
and preferences. Its current browser loop saves periodically and on reload,
not on each frame. A smaller saved representation can still be expensive to
restore: replaying a growing journal costs work. Persisting a whole simulation
on every interaction is not the proposed contract.

RAM-only authoritative state needs an explicit checkpoint if it is promised
to survive replacement. A database connection does not flush that state
automatically. For servers, the first implementation preserves committed
application records; the application must commit any additional state before
replacement if it requires that state to survive. There is no generic server
heap checkpoint or shutdown-save guarantee. The first server fixture must
demonstrate this boundary with a real database, not an in-memory stand-in.

Keep database paths and browser storage keys stable across build IDs.
Independent applications use distinct checkpoint keys, including frontends
sharing an origin, unless they deliberately share data. Database files,
journals and WAL files belong outside output directories and watched
source inputs; a database write must not trigger compilation. Read errors,
incompatible data and a missing record are different outcomes. Initialize only
missing data; never silently replace an unreadable or incompatible save. Data
migration belongs to the application. Reverting code does not undo database
writes, and browser and server commits are independent.

### Browser replacement: proposed simplification

Propose replacing the browser's Wasm application instance from its saved
representation, removing opaque `Any` state transfers and cross-build heap
rollback. Keep the page host where useful. This simplifies the existing
`app-boot`, `relinkApplication` and module-relink lifecycle, but remains a design
choice for review. Measure checkpoint, startup and restoration costs with
representative Siegework state before deleting the existing relink path.
Compilation and state restoration have separate costs.

For planned replacement, pause updates at a coherent event boundary, finish
earlier writes, commit the latest checkpoint, then dispose the old instance
and restore the new one. Await the IndexedDB transaction's completion, not
just the write request. If saving fails, report it and leave the old loop
usable. The current `loadSave` treats read errors as absence, `store` can warn
and continue after failure, and `startCold` may discard incompatible data;
these behaviors must change before storage becomes the reload boundary.

Keep periodic saves for recovery after an unexpected exit. A planned reload
checkpoint and crash recovery are different guarantees: uncommitted RAM can
be lost on a crash. A new version that cannot restore must report an error
without resetting the saved data. Full restoration preserves what `save`
encodes; selection, focus or other interaction state survives only if included
or explicitly retained by the page host. Retain the same-version trap
checkpoint only for its existing failed-event recovery role.
The proposal also drops automatic recovery to the old loop if the replacement
fails to restore or present its first frame after disposal. Saved data remains
intact, but the page reports the error and awaits a corrected build or retry.
That loss of running continuity is part of the replacement choice under review.

### Server replacement and build delivery

After a successful accepted build, stop an affected running child, await exit,
and start the new build against the same database. Start/Stop/manual Restart
remain ordinary process operations. A process restart and data-preserving
reload are compatible: the heap is new while committed records survive.
Run records identify the launch target, successful build, process and exit
status. Use bounded termination; exiting does not promise Lofi cleanup or a
final database commit. Interrupted requests may have committed without their
clients receiving a reply; do not promise automatic replay or exactly-once
execution. No database-state transfer IPC is needed. Logs remain ordinary output.

One concrete database binding is enough to establish this contract. SQLite
is a candidate, not a generic provider framework: the pinned Node 26.8.1 has
`node:sqlite`, and a local probe confirmed committed records survive process
exit while an open transaction rolls back. That probe does not establish a
Lofi binding or nonblocking execution. Node's [SQLite API](https://nodejs.org/api/sqlite.html)
is synchronous; wrapping it in a Promise does not remove blocking.

Keep the server origin stable across restarts. A small HTTP bundle helper
serves the files, development manifest and reload event stream from completed
builds. After reconnecting, the browser receives the latest manifest. Pin each
replacement's manifest and module identities to its advertised build; fetching
build B must not return build C's bytes. If B is unavailable, reconcile with
the latest manifest and retry. A network failure is distinct from incompatible
saved data. Do not signal a browser to adopt a bundle before its server serves
that build. Several bundles have separate prefixes and manifests. No development
reverse proxy, preview transport or durable event journal is needed. Production
serving omits the development endpoints. Code compilation does not prove
client/server API or data-schema compatibility.

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

- Reuse the compiler session and browser save/restore representation. Propose
  deleting cross-build heap handover in favor of checkpoint restoration,
  subject to the reload-cost review above. Delete the competing browser build
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
- Keep working state in RAM and persist application-defined data. Use one
  concrete server database binding; omit automatic heap snapshots, transparent
  caching, a database abstraction hierarchy and database-state transfer IPC.

Each implementation PR must name what it deletes and the surviving owner,
update its book pages and `TOUR.md`, and test one meaningful behavior or failure
boundary. Record production, test and documentation line changes separately.
Astra Max simplify reviews should challenge retained behavior, not merely
validate the machinery chosen to preserve it.

## 8. Proposed PR sequence

These are reviewable implementation cuts above #421, not changes authorized
by this design PR. The anchors below refer to the current code.

| PR | Change grounded in current architecture | Simplification and evidence |
| --- | --- | --- |
| 1. Delete the preview | Remove `src/ide/preview.{mjs,html}`, iframe/ports and preview packaging. | Keep editor formatting, panes and diagnostics; no replacement preview protocol. |
| 2. Project forms | Parse explicit target/launch forms with `(lofi read)` into structured descriptions. | No evaluator or metadata sandbox. Check duplicate/invalid forms and round-trip printing. |
| 3. Output directories and CLI builds | Change `scripts/lofi.scm` and `host/chibi/lofi/build.sld` callers to the directory contract; introduce project builds and replace application packaging scripts. | One compiler build path; migrate `compile -o`, runner and build tests together. Execute built programs and inspect browser output files. |
| 4. Artifact dependencies | Extend `expand.sld`/`session.sld` and generated-library execution with named target resolution. | One serial traversal; no scanner or runtime lookup. Test missing targets, cached dependency cycles, producer changes and Hearsay generation. |
| 5. Persistent development | Extract the development session from `develop.sld`/`scripts/develop.mjs`, retaining compiler sessions in one Node worker. Share watch reconciliation and publish fresh attempt diagnostics. | Keep old commands until their launch/reload replacements pass in PR 11. Test external edits, rename saves, invalid→valid builds, changes during compilation and unchanged-library reuse. |
| 6. TCP sockets | Add the concrete native TCP effect on `src/app/tasks.mjs` suspension and cleanup. | No provider hierarchy. Exercise real partial transfers, close/cancel and late completion. |
| 7. UDP sockets | Add concrete datagram operations beside TCP. | No stream emulation. Exercise peer addresses, empty/oversized datagrams and cancellation without assuming reliable delivery. |
| 8. Browser checkpoints | Make storage outcomes explicit in `storage.mjs`, `runtime.mjs` and `(lofi app)`. Prove and measure committed checkpoint restoration in `host.mjs` before adopting it in place of relinking. | Proposed deletion of cross-build `Any` handover and rollback. Test commit failure leaves the old loop usable, replacement startup failure retains saved data, late writes cannot replace the final checkpoint, and saved interaction state survives. |
| 9. HTTP and browser bundles | Implement HTTP over TCP and application asset/reload serving in the bundle helper; adapt `src/app/reload.sld` to the agreed replacement path. Make root-relative reload URLs bundle-relative and fetch the advertised artifact identity. | Ordinary routing replaces preview transport. Two frontends reload under distinct prefixes and retain independent checkpoints. Retry interrupted fetches without resetting saved data; production exposes no dev endpoints. |
| 10. Server persistence | Bind one concrete database through effects in the Node runtime; keep its data outside build output and watch inputs. Exercise a server using committed application records. | No provider hierarchy or automatic heap persistence. Test a fresh process recovers committed data, an unfinished transaction is rolled back, and storage failures are reported. Verify the binding's blocking/cancellation behavior. |
| 11. Launches and reload | Reuse the child-process path and `scripts/run-lofi.mjs` for launch targets, restart ordering and process/build identity. Switch to `dev` and retire old watch/development-serve policies once application serving/reload passes. | No actor catalogue or database-state transfer protocol. Test failed-build continuity, Stop versus rebuild, server record retention, database-write watcher exclusion, restart during bundle fetch and browser checkpoint retention. |
| 12. File service | Add native file read/save and shared watcher subscriptions to `dev`. | Disk is authoritative; no server buffer database. External writes update clean buffers and surface dirty-buffer conflicts; saves never trigger compilation directly. |
| 13. Editor client | Adapt `ide.mjs`; delete browser `project.mjs`, `toolchain.mjs`, `develop.sld` and source/sample packaging; keep editor/panes/formatter. | The UI consumes the existing dev session. Test it in Chromium alongside an external file edit and a running subprocess. |
| 14. Examples and audit | Migrate example projects and command documentation, remove remaining obsolete scripts/adapters, audit the series. | Verify shared CLI/dev artifacts, generated libraries, saved-file squiggles and server/browser data preservation. Run compiler suites/bootstrap and inspect net production-code changes. |

## 9. Remaining review decisions

- Review fresh browser instance restoration against measured checkpoint and
  restore costs before deleting the current relink path. Keeping working state
  in RAM is settled; making every update a database operation is not proposed.
- Select the concrete server database binding. Preservation of committed
  records is required; automatic preservation of arbitrary RAM is not supplied.
- `serve` is reserved for production; confirm whether it should take a built
  output directory or a project/launch name before fixing CLI syntax.
- Keep frontends as ordinary server dependencies, without restricting the
  language to console applications and web servers.
