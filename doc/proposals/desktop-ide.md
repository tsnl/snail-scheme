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
are removed. The filename remains `project.datum` unless that naming decision
is changed; the format below stays inert either way.

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
   relevant library inputs, excluding build output. Read/reconcile the initial
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

Three operations have distinct meanings:

| Operation | What persists |
| --- | --- |
| Incremental compilation | Compiler caches; no application state is involved. |
| Application restart | The development session and compiler survive; the old process exits and application state starts over. |
| Browser hot reload | The existing `(lofi app)` checkpoint/save/restore contract transfers browser application state while modules are relinked. |

The proposed first server behavior matches today's `lofi watch`: after a
successful accepted build, stop an affected running child, await exit, and
start the new build. Start/Stop/manual Restart also remain available. Run
records identify the launch target, successful build, process and exit status.
Use ordinary process controls and a bounded termination fallback; process
termination does not promise execution of Lofi cleanup. No generic readiness
or graceful-shutdown protocol is required. Logs remain ordinary output.

**Server state preservation remains a review decision.** Restarting a server
is not hot reload under the definition above. Preserving its in-flight work,
listeners and state would require an explicit application handover contract,
which the CLI runner does not implement. Moving the program to a Node worker
would not establish that contract. A browser Service Worker is a different
API with an event-bound, browser-controlled [lifetime](https://www.w3.org/TR/service-workers/#service-worker-lifetime);
it is not the native compiler or application execution worker described here.

Browser hot reload stays in scope. Keep the server origin stable across
restarts. A small HTTP bundle helper serves the files, development manifest
and reload event stream from the same completed build. After a restart, the
browser reconnects and receives that bundle's latest manifest; the existing
reload client performs checkpoint handover/relinking. Pin each relink's
manifest and module identities to the advertised build. The current loader
rereads a mutable manifest URL; it must not choose a relink point from build B
and silently fetch build C. If B becomes unavailable, reconcile with the latest
manifest and retry. Retryable network/supersession failures must also be
distinguished from refused application state migration; the current client
conflates them. Do not signal a browser to adopt a bundle before its server
serves that build. Several bundles have
separate prefixes and manifests. No development reverse proxy, special preview
transport or durable event journal is needed. Production serving omits the
development endpoints. Changing server APIs can still require application
migration; browser code reload does not prove client/server compatibility.

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

- Reuse the existing compiler session and browser checkpoint/reload machinery.
  Delete the competing browser build backend and preview.
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
| 5. Persistent development | Extract the development session from `develop.sld`/`scripts/develop.mjs`, retaining compiler sessions in one Node worker. Share watch reconciliation and publish fresh attempt diagnostics. | Keep old commands until their launch/reload replacements pass in PR 9. Test external edits, rename saves, invalid→valid builds, changes during compilation and unchanged-library reuse. |
| 6. TCP sockets | Add the concrete native TCP effect on `src/app/tasks.mjs` suspension and cleanup. | No provider hierarchy. Exercise real partial transfers, close/cancel and late completion. |
| 7. UDP sockets | Add concrete datagram operations beside TCP. | No stream emulation. Exercise peer addresses, empty/oversized datagrams and cancellation without assuming reliable delivery. |
| 8. HTTP and browser bundles | Implement HTTP over TCP and application asset/reload serving in the bundle helper; reuse `src/app/reload.sld`. Make root-relative reload URLs bundle-relative and relinks use the advertised artifact identity. | Ordinary routing replaces preview transport. Two frontends reload under distinct prefixes. Retry interrupted fetches without treating them as refused state migrations; production exposes no dev endpoints. |
| 9. Launches and reload | Reuse the child-process path and `scripts/run-lofi.mjs` for launch targets, restart ordering and process/build identity. Switch to `dev` and retire old watch/development-serve policies once application serving/reload passes. | No actor catalogue or general run protocol. Test failed-build continuity, Stop versus rebuild, restart during module fetch, stable-origin reconnect and checkpoint retention. Server-state policy must be settled first. |
| 10. File service | Add native file read/save and shared watcher subscriptions to `dev`. | Disk is authoritative; no server buffer database. External writes update clean buffers and surface dirty-buffer conflicts; saves never trigger compilation directly. |
| 11. Editor client | Adapt `ide.mjs`; delete browser `project.mjs`, `toolchain.mjs`, `develop.sld` and source/sample packaging; keep editor/panes/formatter. | The UI consumes the existing dev session. Test it in Chromium alongside an external file edit and a running subprocess. |
| 12. Examples and audit | Migrate example projects and command documentation, remove remaining obsolete scripts/adapters, audit the series. | Verify shared CLI/dev artifacts, generated libraries, saved-file squiggles and browser reload. Run compiler suites/bootstrap and inspect net production-code changes. |

## 9. Remaining review decisions

- The proposed server baseline restarts the subprocess; state-preserving
  server reload needs an explicit contract if required in this series.
- `serve` is reserved for production; confirm whether it should take a built
  output directory or a project/launch name before fixing CLI syntax.
- Keep `project.datum` for inert forms unless the filename is deliberately
  changed. Its role replacing project build scripts is settled.
- Keep frontends as ordinary server dependencies, without restricting the
  language to console applications and web servers.
