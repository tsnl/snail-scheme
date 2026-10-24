# Desktop IDE and projects

**Design for review; not implemented.** Intended implementation base:
[#421](https://github.com/tsnl/snail-scheme/pull/421), the top of the task-runtime
stack. This replaces the desktop portion parked by
[#412](https://github.com/tsnl/snail-scheme/pull/412), whose
[preserved proposal](https://github.com/tsnl/snail-scheme/blob/be6c41ef76d79d186fc2f405e1c44d28450318bc/doc/proposals/desktop-ide.md)
and preceding discussion informed this draft. Implementation waits for review.

## 1. The shape of the system

One IDE server manages one workspace folder. Its browser frontend edits
files and displays diagnostics, builds and running programs. Applications
open in **external browser windows only**. A project may contain several
applications; a workspace does not become a separate service.

Each launch starts a separate OS process running the existing WasmGC/JSPI
runtime. A compiler worker keeps compilation off the IDE's execution agent.
These are independent Wasm heaps, not shared-heap language multithreading.
The one-shot CLI uses the same project engine without starting an IDE server.

```text
Browser editor -- HTTP --> IDE server -- jobs --> compiler worker
                             |
                             +-- launch --> application process A <-- external browsers
                             +-- launch --> application process B <-- external browsers

lofi build DIRECTORY ------> the same project engine, using disk inputs
```

The browser-only IDE backend, integrated preview, Browser documents,
ServiceWorker routing and virtual schemes (`this-browser://` and its earlier
names) are dropped from the design. They are not future milestones. Keep
ordinary browser applications and the editor's local formatter.

Networking has one concrete TCP socket effect that tests can intercept.
HTTP is a Lofi library over sockets. There is no generic transport typeclass,
portable provider framework, actor channel or in-memory network platform.
Keep the existing concrete filesystem effect for compiler inputs and normal
file operations. There is no executable project metadata to sandbox.

## 2. What we can reuse

| Current boundary | Keep or change |
| --- | --- |
| [Compiler sessions](../../src/lofi/compiler/session.sld) | Keep incremental expansion, checking, specialization and emission; add artifact dependencies to their inputs and cache evidence. |
| [Development loop](../../src/lofi/develop.sld) | Extract its build/session rules into the shared project engine. Watch, serve and restart remain concrete policies around that engine. |
| [Native development commands](../../scripts/develop.mjs) | Reuse watching, assembly, process management and notifications; consolidate their callers instead of adding another build loop. |
| [Build driver](../../host/chibi/lofi/build.sld) | Reuse assembly, linking and generated-library execution. Keep the Chibi bootstrap and file-level compile/run commands. |
| [Task scheduler](../../src/app/tasks.mjs) and [CLI runner](../../scripts/run-lofi.mjs) | Reuse one-shot dispatch, suspension and cleanup inside each launched process. No cross-process continuation or GC reference transfer. |
| [Browser IDE](../../src/ide/ide.mjs) | Keep editor buffers/views, formatting, highlighting, splits and diagnostics presentation; replace local project/build ownership with the server API. |
| [Browser toolchain](../../src/ide/toolchain.mjs), [project storage](../../src/ide/project.mjs), [preview](../../src/ide/preview.mjs) | Delete after their replacement or deliberate feature removal. No fallback browser backend. |

The existing [datum reader](../../lib/lofi/read.sld) can read project data;
no new quotation syntax or executable configuration language is needed.
Compiler sessions expose generated libraries but no project-artifact
resolver. That is the required compiler extension, not existing behavior.

## 3. `project.datum` describes work

The root file contains one **inert datum** with `build` and `launch`
association lists. Names and settings are literal data. There is no `init`
function or project code to evaluate. This supersedes the earlier proposal
for a `project.sld` library exporting three metadata queries.

For example, this is a proposed file schema:

```scheme
((build .
  ((client . (browser
              (entry "client/main.sld")
              (public "client/public")
              (outputs (bundle . bundle))))
   (server . (program
              (entry "server/main.sld")
              (outputs (program . program))))))
 (launch .
  ((dev . (run
           (target server)
           (output program)
           (args "--port" "0"))))))
```

Start with program compilation and browser-bundle assembly, using the
existing builders. A `program` output is a frozen launchable build, including
its required modules/runtime; a `bundle` is an immutable collection of named
files. Output names identify values of these kinds, not arbitrary build paths.
Library roots are project-relative target settings; the toolchain supplies
the standard library. Ordinary imports are discovered by the compiler.

Parse the file once into `ProjectPlan`, targets, outputs and launch commands.
Reject malformed shapes, unknown fields, duplicate names, incompatible
output kinds and invalid launch references. Normalize project-relative paths
at this boundary and reject escapes from the project roots. Downstream code
receives structured values. Reading data never invokes an evaluator, and
the configuration has no callbacks, includes, environment interpolation or
conditional expressions.

This deliberately removes deriving target lists, launch lists or settings
by executing code or reading another file. Explicit targets are sufficient
for this series. Generated application libraries remain supported inside
those targets; they do not generate the project description. No second
configuration mode or constructor library remains to maintain.

### Builds use captured inputs

Capture source bytes and the relevant directory namespace in one immutable
input revision, including `project.datum`, public assets and toolchain inputs.
An IDE revision overlays acknowledged unsaved buffers; a normal CLI invocation
uses disk. The CLI never silently inherits an open IDE's buffers. Later edits
belong to a later revision. Capture is not a claim of atomic transactions
across arbitrary external filesystem writers.

Changing `project.datum`, including an acknowledged unsaved edit, reparses
the plan. Source imports, included bytes, public files and generated libraries
remain compiler/build dependencies. File creation and deletion matter as
well as changed contents. Build staging is outside watched source inputs.

Run existing library producers against the captured project/toolchain tree,
with writes confined to their staging directory. Hearsay's image generator
currently reads paths relative to the repository root; preserve those path
relationships without exposing a changing live tree. Reexecuting a producer
does not by itself make its reads consistent. Test an asset changing during
generation while the current build continues to use its captured bytes.
This needs a concrete build filesystem view, not a portable IO-provider layer
or a new generator framework.

### Artifact names resolve during building

A proposed literal form such as `(artifact-bundle "client" "bundle")`
resolves to a typed bundle value in server code. It neither returns a mutable
build-cache pathname nor performs a runtime name lookup. Unknown names,
wrong output kinds, cycles and failed producers prevent a successful build
of that consumer and therefore prevent its launch.

Let actual compiler expansion request artifacts from the project engine.
Build targets serially with a depth-first traversal: mark a target active
before expansion, record each discovered edge, build its producer, and
return the completed output. Requesting an active ancestor reports the cycle
and source locations. Before reusing a cached consumer, replay its recorded
artifact requests through this traversal for the new revision. An unchanged
consumer A that used B must still detect B's new dependency back on A.
Finished outputs belong to this revision. Include
artifact identities and generated syntax bytes in cached expansion/emission
keys. The current build driver deliberately regenerates producers on each
compile because they can read files outside the recipe's hash. Preserve
that conservative rule until all producer dependencies can be captured;
do not reuse producer output across revisions merely because its code matches.
There is no second source scanner or requirement to predeclare every edge.

This permits generated application libraries, including Hearsay's existing
recipes. Producers may execute before a later graph error is discovered;
their outputs stay in build staging. The promise is failure **before launch**,
not before any producer runs. A selected target validates its reachable
dependencies; a default whole-project build visits every declared target.
Cross-project lookup, package resolution and arbitrary shell recipes are out.

## 4. Sockets, HTTP and application processes

The socket effect exposes concrete listen, accept, connect, read, write and
close operations. Reads/writes have explicit EOF, failure, partial-transfer
and cancellation semantics. Its native implementation uses the current
runtime's suspension bridge; a pending operation owns its bytes and remains
accounted until cleanup settles. Closing a socket disarms its waits. No new
borrow checker or general resource-finalizer system is assumed.

HTTP parsing, framing, routing and bundle serving are ordinary Lofi code.
Start with bounded HTTP/1.1 requests and ordinary finite responses. Preserve
the development tools' event stream through a small SSE writer over socket
writes, without inventing a generic stream or transport hierarchy. Unsupported
framing must fail explicitly. Tests must cover split reads, partial writes,
EOF, malformed/oversized requests and disconnects, as well as actual TCP.
TLS, HTTP/2, WebSockets and deployment are outside the first series.

The IDE and example application use this HTTP library. An application server
serves its own frozen client bundle and API at a real loopback address.
The IDE displays its actual bound address; it does not infer readiness by
scraping logs or manufacture client pages. Add a small runner event for an
explicitly announced HTTP address, sent from the execution worker through
its wrapper and tagged with the run identity. A raw TCP listener does not
announce HTTP readiness. This runner event is a new capability, not something
the existing development host already provides. Launch selects only the server
program. Opening two external browser windows creates two real clients.
Plain console programs use the same launch operation without an address.

A run record needs a launch name, frozen build, process handle, status and
logs. No run-ownership tag is inherited through language tasks. The process
is the Stop/debugging boundary; its runtime still owns cooperative task
cancellation internally. Stop closes admission, requests shutdown and waits
for exit. Add a direct shutdown request through the process wrapper to the
execution worker, which closes its scheduler and drains cooperative cleanup.
The wrapper owns the deadline: a bounded forced process exit handles a
non-yielding program; it is not claimed to run Lofi cleanup or undo side
effects. No other run or the IDE is terminated with it. Shutting down the
IDE explicitly stops its
children; closing an editor or application tab does not stop their servers.

Builds retain their input and plan revisions. A failed build leaves the
running program and its coherent bundle alone. Manual **cold Restart** first
builds successfully, then stops the old process and starts the new one.
State resets; the port may change; clients reload/reconnect. Startup failure
after Stop does not promise rollback. Optional restart-after-success uses
that same completed build. Stop, a newer restart or changed project
configuration invalidates older launch intentions; a stale build cannot
resurrect a stopped run.

## 5. The IDE is a client of the project engine

`lofi ide DIRECTORY` selects one folder at startup. Plain folders can be
edited; build/launch actions require `project.datum`. The native server owns
buffers, disk observations and launch intentions. Its compiler worker runs
the shared engine, owning captured revisions, sessions, dependencies and
artifacts. Only copied requests/results, bytes, artifact identities and
diagnostics cross this boundary; live sessions and WasmGC values do not.
The frontend owns editor selections, scrolling and presentation, with local
unacknowledged edits retained until accepted. It no longer owns filesystem
handles, a compiler worker, application assets or a preview transport.

The API supplies file/buffer state, revision-checked edits and saves, named
build/launch actions, Stop/Restart, and one event stream. An event carries
the input/build/run identity it describes. Reconnection obtains a current
snapshot; it does not require an indefinitely retained event journal.
Saving revision N cannot mark N+1 saved or overwrite an unacknowledged disk
edit. Watch notifications must not silently replace dirty buffers. The
loopback server must reject editing/launch requests from unrelated origins.

One compiler worker serves the IDE's engine jobs. Build completion is a
result tagged with its revision, not permission to replace newer editor
state. CLI and IDE call the same engine; a one-shot CLI build needs neither
HTTP nor an IDE daemon. Project configuration is S-expression data.
Existing loader manifests need not change format merely to introduce it.

Preserve the existing file editor, formatter and split behavior. Remove
folder-picker/localStorage/IndexedDB project ownership as the native backend
takes over. There is no new Browser document, iframe retention protocol,
multi-workspace UI, collaborative editing system or editor plugin platform.

Existing standalone `lofi serve` browser reload remains a separate explicit
development policy using the shared engine and existing reload client.
`lofi watch` likewise becomes an adapter over that engine. Consolidate build
and watch decisions rather than leave a second compiler path. Ordinary
project launches retain frozen bundles; the IDE never pushes new client code
into an old server. Removing the IDE preview does not remove the application's
checkpoint/reload implementation from the runtime stack.

## 6. Global simplification plan

- **One project engine:** CLI, IDE and existing development commands reuse
  plan parsing, dependencies, sessions and publication. No parallel IDE
  builder, HTTP build implementation or mandatory background daemon.
- **One owner per boundary:** the engine owns inputs/builds; the native IDE
  owns buffers and launch intent; each application process owns its runtime
  and sockets; the editor owns view state. Keep identifiers only where they
  reject stale work or associate diagnostics with the correct source.
- **Delete browser development infrastructure:** preview pages/ports/routes,
  compiler/file emulation in browser workers, packaged source snapshots,
  folder handles and project persistence. Keep the formatter and real browser
  application runtime. Delete plans for virtual URLs and embedded browsing.
- **Concrete I/O:** socket and filesystem effects at their real boundaries;
  ordinary HTTP library code above sockets. No shared native/browser provider
  layer, generic channel hierarchy, actor registry or inherited run scopes.
- **Small build vocabulary:** two useful output kinds, ordinary compiler
  import discovery, serial artifact traversal, no plugin recipes or parallel
  graph scheduler. Parse literal configuration once into structured values.
- **Inert project descriptions:** delete the proposed three-query evaluator,
  metadata permission filters and authoring constructors. No executable
  fallback or second configuration format.

Every implementation PR should give an independent behavioral explanation,
identify what it deletes or makes redundant, name the surviving owner, and
test a concrete failure/lifetime boundary. Use Astra Max simplify reviews at
those boundaries and a final whole-series review against this deletion list.
Record production/test/documentation line changes separately; do not promise
net deletion by removing necessary correctness checks.

## 7. Proposed PR sequence

These are plans for review, not implementation PRs. Each builds on the last,
starting from #421. Names describe responsibilities, not a new framework.
Each PR updates its relevant book pages and `TOUR.md`; the final pass removes
any remaining stale descriptions.

| PR | Concrete change and current architecture | Simplification in this PR | Evidence before moving on |
| --- | --- | --- | --- |
| 1. Delete the preview | Remove `src/ide/preview.{mjs,html}`, preview UI and port/routing code in `ide.mjs`/`toolchain.mjs`; trim `scripts/build-ide.scm`. | No replacement preview, Browser document or URL router. The interim browser editor may still compile for diagnostics until PR 10 removes that backend. | Editor formatting, splits and diagnostics still work; preview messages and unused application host assets disappear. |
| 2. Parse project data | Use `(lofi read)` to parse `project.datum` into project-plan types under `src/lofi/`. | No evaluator, constructor library, metadata permissions or quotation extension. | Read actual files; reject duplicate names, unknown fields, bad paths/kinds/references and executable-looking forms outside the schema. |
| 3. Capture build inputs | Add immutable file/directory revisions with optional editor overlays at the existing filesystem boundary. Adapt producer execution to the captured tree. | One concrete view of build inputs; no general provider framework. Keep producer regeneration conservative. | Source and image edits during a build cannot change its inputs; file creation/deletion changes the next revision; generator writes stay in staging. |
| 4. Share the engine and add CLI builds | Extract build/session rules from `src/lofi/develop.sld`; reuse `session.sld` and `host/chibi/lofi/build.sld`. Make `serve`/`watch` callers immediately; add `lofi build DIRECTORY`. | One engine and serial builds using the existing program/bundle builders. No separate IDE build algorithm. | Disk and overlay inputs produce runnable artifacts. Failures retain completed builds. Existing watch/reload behavior survives extraction. |
| 5. Resolve artifact macros | Extend `expand.sld`/`session.sld` with located requests and dependency evidence; the engine resolves them. Carry generated-library support into the shared path. | One serial traversal, including cached dependencies; no scanner, runtime lookup or hardcoded cache paths. | Unknown names/kinds and producer failures reject builds. Cached A→B detects B→A added later. Changed generated bytes invalidate consumers; exercise Hearsay and an embedded client bundle. |
| 6. Add concrete sockets | Add `(lofi socket)` and a thin native TCP implementation using `src/app/tasks.mjs`; integrate socket cleanup with the runner. | Explicit handles and close; no IO-provider layer, worker pool, generic stream hierarchy or new ownership feature. | Real TCP plus intercepted-effect tests for partial transfers, cancellation and late completion; exhaustion/stop releases listeners and buffers. |
| 7. HTTP over sockets | Add bounded HTTP parsing, framing, bundle serving and a small SSE writer. Move native `serve` HTTP/SSE handling out of `scripts/develop.mjs` into this library. | Delete native HTTP provider commands; routing is ordinary Lofi code. | Split/malformed/oversized requests and disconnects over TCP. A fixed test server serves a built bundle and API; external-page reload still works. |
| 8. Process launches | Extend `scripts/run-lofi.mjs` and the existing child-process path with named launches, announced addresses and direct shutdown/drain requests. | One process per launch; no actor catalogue, shared-host run tags or automatic state migration. | Stop one of two servers independently; verify readiness, cold restart, failure continuity, forced exit and stale launch-result races. |
| 9. Native IDE server | Add the IDE API and compiler worker using the engine and HTTP library. Own buffers/saves/watch observations here. | One folder; the server owns editing/launch intent, the worker owns build state. | Exact unsaved revisions, disk conflicts, responsiveness during compilation, reconnection and consistent CLI/IDE artifact errors. |
| 10. Switch frontend and remove browser backend | Adapt `ide.mjs`; delete `project.mjs`, `toolchain.mjs`, browser `develop.sld` and source/sample packaging. Keep editor/panes/formatter; rework `make ide`. | No localStorage project copy, directory-picker permissions, second backend or iframe. | Chromium edits/saves/builds/launches through the server; external windows use the application's origin. Refresh preserves acknowledged unsaved buffers. |
| 11. Examples and series audit | Add representative project files and a multi-client example; audit docs, tests and responsibility changes across the stack. | Remove stale adapters and obsolete plans. No remaining engine migration is deferred to this PR. | CLI and IDE share invalidation; generated libraries and external-page checkpoint reload work. Run compiler suites/bootstrap and inspect the production-code deletion totals. |

## 8. Debugging: a separate, bounded extension

Initial run controls include logs, exit failures, build diagnostics and
Stop/Restart. Those are not a source debugger. Separate processes let a
paused application leave the IDE and other applications responsive.

The next useful proof is attaching to the **actual Wasm execution agent**
through V8's inspector. The present CLI runner starts a Node worker for heap
settings; attaching only to its wrapper process is not enough. Verify the
target and JSPI behavior on the pinned engine before designing IDE controls.
Node documents inspector sessions and cautions against controlling a paused
program from the same execution thread. See the
[Node inspector API](https://nodejs.org/api/inspector.html#support-of-breakpoints).

Source breakpoints require a second proof: preserve Lofi locations through
lowering and assembly to Wasm instruction offsets, then map the inspector's
locations back to the frozen build's source. `Expr` has locations today;
`wasm.sld` and `src/assembler` do not emit the required Lofi source mappings.
Use standard source-map/debug-section conventions where supported; choose
only after an engine experiment. The
[Wasm debugging conventions](https://github.com/WebAssembly/tool-conventions/blob/main/Debugging.md)
describe byte-offset source maps and DWARF sections, not an automatic Lofi
debugger or a guarantee of WasmGC value inspection.

Proposed follow-ups: (D1) attach/pause/resume and traps for one isolated run;
(D2) emitted source locations and line breakpoints for unoptimized builds;
(D3) scalar locals and supported value views after a representation proof.
Do not add a DAP framework, arbitrary evaluation, continuation debugger or
GC-object inspector merely to complete the IDE/project work. Breakpoints
refer to the run's build, never silently to a newer unsaved buffer.

## 9. Review points

Separate launch processes, external browser windows only, no browser IDE
backend, inert `project.datum`, and sockets with HTTP as a library are settled.
Remaining proposals worth challenging are:

- Artifact macros return typed bytes/bundles. They resolve in actual
  expansion, and only the selected build's reachable targets are checked
  unless the user requests the whole project.
- The small program/bundle schema and literal launch settings should be
  proven on two actual project files before adding more target kinds.
- Preserve standalone `serve` reload, while ordinary project launches use
  explicit cold Restart. Full source debugging follows its own proofs.
