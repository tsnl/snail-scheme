# Desktop IDE and project engine

**Review draft — proposed, not implemented.** This document starts from
[`12fbcd9a`, the shared actor host in #407](https://github.com/tsnl/snail-scheme/pull/407).
It proposes an implementation sequence for approval; this draft PR contains
only this document. No implementation PRs are being created with it.

One IDE instance works on one folder. A reusable project engine builds the
folder's programs for both the CLI and IDE. The IDE launches server actors
on a shared native host; those servers serve their actual applications over
HTTP. The editor and application clients are ordinary web pages.

The major simplification is to defer the entire browser-local backend:
browser compilation/hosting, ServiceWorker and SharedWorker routing, virtual
HTTP mounts and custom URL schemes. This proposal neither removes the
existing static IDE nor extends it. Native HTTP lets the first example
exercise real server/client behavior without a browser transport emulation
layer. Browser placement can be a separate proposal after this model works.

## 1. Start with the host that already exists

The [actor host](../../src/app/actors.mjs) and
[(lofi actor)](../../lib/lofi/actor.sld) already provide independent Wasm
instances, typed request/reply mailboxes, dynamic spawn, local immutable
messages and an automatic binary codec path. Startup is reserved before
asynchronous loading; waiting actors count as alive; children can outlive
parents; drain waits for all actors. The
[actor tests](../../tests/actors/check.mjs) already compare the actual GC
objects to prove local identity preservation. Reuse these mechanisms.

The current host has **no explicit Stop, owned network listeners, worker
pool or network actor transport**. Its binary path is tested within one
host, not across a network. The [existing development loop](../../src/lofi/develop.sld)
reuses compiler sessions for one entry. `lofi serve` preserves a browser
application's state during relink; `lofi watch` restarts a child process.
Neither implements the server lifecycle proposed here. The current IDE
also serves preview build files itself rather than launching an application
server.

| Term | Meaning in this proposal |
| --- | --- |
| Workspace | The single folder being edited. It is not a service. |
| Project | A folder with a root `project.sld`; it can contain several applications and build targets. |
| IDE instance | The running IDE server and its frontend, managing one workspace. |
| Actor | A running Wasm program with its own mutable state, mailbox and lifetime. |
| Host | The runtime owner of actors, their imports, mailboxes and platform resources. |
| Isolate | An engine instance with its own heap/reference domain. The first application host occupies one isolate. |
| Process | The OS container. It is not the unit of application launch. |

The first native provider is Node running Wasm through V8/JSPI. Its
application host contains the IDE server actor and multiple user-server
actors on a common event loop. JSPI permits independent waits and
resumptions; Wasm instructions in this isolate do not
run in parallel. Keep the existing promise scheduling, without a second
runnable queue. A host is a runtime abstraction, not another name for an OS
process; an [isolate is an engine/heap boundary](https://v8.dev/docs/embed).

Compatible actors in this host exchange typed, deeply immutable GC objects
directly. There is no dedicated pipe, socket or codec invocation for that
path. The compiler's existing checks exclude nested mutable values,
functions and `Any`; the host and compiler remain trusted. A future host
pool spanning isolates would need a transport across their reference
domains, with derived binary serialization rather than a promise of shared
GC identity. Designing that pool or preemptive scheduling is out of scope.

Compilation is the justified exception to the shared application loop:
the persistent IDE runs its project engine and compiler sessions in **one
dedicated worker**, so CPU-heavy builds cannot freeze HTTP service and
application actors. This is an internal tool host, not one worker per
application or another public service. Snapshots and results cross this
boundary as owned bytes/data. Node's
[worker documentation](https://nodejs.org/api/worker_threads.html) identifies
CPU-intensive work as its intended use. The one-shot CLI can call the same
engine directly without starting the IDE or HTTP.

## 2. One project description, one reusable engine

`project.sld` is the common project entry for CLI and IDE. The recommended
form is a Lofi library exporting three functions; exact signatures and
data spelling remain review choices.

| Export | Returns | Does not do |
| --- | --- | --- |
| `inputs` | Declared read patterns for description queries. | Read files or grant ambient authority. |
| `build` | Datum describing targets, recipes, named outputs and declared dependencies. | Compile targets or write outputs. |
| `launch` | Datum describing named server launches, their targets, arguments and options. | Start actors or choose a client for the IDE to load. |

The engine compiles and loads this description, queries it, then parses and
links the returned data into an immutable `ProjectPlan`. Construction
establishes unique names, valid output kinds, valid references and an
acyclic declared graph. Procedure values and malformed data are errors;
there is no repeated interpretation of raw Datum downstream. New project
metadata uses S-expressions, not JSON. A plain data file would use `.datum`;
`project.sld` is executable metadata. A second mandatory configuration file,
such as `launch.datum`, adds nothing here.

The smallest recipe set should compile Lofi targets and assemble the
client bundle needed by the example. Arbitrary shell hooks, package
resolution, deployment plans and a general build DSL are not prerequisites.
Each target names its entry and library roots; the compiler discovers
library imports. Project authors do not repeat those imports as manual
graph edges.

The project engine is a library under `src/lofi/`, separate from IDE UI and
HTTP. It owns plan parsing, target dependencies and build sessions; host
providers own filesystem access, watching, assembly and output storage.
Reuse [compiler sessions](../../src/lofi/compiler/session.sld) and useful
development-loop operations. Do not create parallel CLI and IDE build
implementations. Proposed `lofi build DIRECTORY` loads
`DIRECTORY/project.sld` and builds its graph through this engine. Existing
file-level compilation remains available. Plain folders can still be
edited; project build/launch operations require the marker.

### Query authority and invalidation

The host supplies the filesystem implementation. A project does not write
its own handler to decide what it may access.

1. Capture one input revision for description code, query inputs and target
   builds. Compile the description and its imports under fixed, bounded
   project and toolchain roots. These trusted compiler reads are distinct
   from reads performed by the description itself.
2. Instantiate/initialize fresh modules for this evaluation and call
   `inputs` with filesystem access closed. Neither initialization nor the
   declaration query gets to read before the policy exists. No time,
   environment, random or
   network capability is supplied implicitly.
3. Parse the patterns once, bounded by host-granted roots. Use the same
   matcher for read access and metadata watch scope. Run `build` and
   `launch` against one frozen, read-only input view. Out-of-pattern reads,
   including existence checks, and all writes fail with a query/path
   diagnostic. Publish the new plan only when both queries and parsing
   succeed. Compiled code may be cached; mutable module globals cannot
   become hidden inputs carried from a previous evaluation.

Start with project-relative paths and reject traversal and symlinks rather
than relying on a string-prefix check. The snapshot provider must own its
bytes and namespace, including absence. Source changes during capture are
reconciled into a subsequent revision; one build never mixes later live
reads into its captured view. External roots would require an explicit host
grant, not an absolute path supplied by project code.

The existing [`fs` effect](../../lib/lofi/io.sld) includes writes. A
restricted snapshot handler is new work, not a type-level path proof.
Enforcement must cover low-level defaults and foreign imports during module
initialization too; installing a convenient Lofi handler over an ambient
writable runtime is insufficient. Unsupported foreign escapes must be
rejected. This is a capability boundary for supported compiled Lofi, not a
claim to sandbox arbitrary native plugins.

Use declared patterns conservatively as dependencies. Watch the relevant
directories so a newly matching file, deletion, or previously missing path
invalidates the plan; watching only today's matched files is wrong. Changes
to `project.sld`, its imports or matching metadata inputs requery the
description. Other edits reuse the plan and update the affected target
sessions. If a pattern includes an ordinary source file, editing that file
**does** requery metadata. Fine-grained observation tracing is unnecessary
for the first version. Generated outputs belong to the artifact graph,
outside source watch inputs, to avoid build feedback loops.

Invalidation immediately removes the old plan's eligibility for new
launches or restarts. A failed or stale query cannot authorize execution
using the retained plan; only a successful current evaluation can.
Existing runs and their frozen artifacts remain usable.

### Artifacts are build dependencies

One project can declare `client` and `server` targets. A literal artifact
form in the server source names the client target and its named `bundle`
output. The macro spelling is undecided; its required behavior is not:

- Resolve the names and expected output kind during expansion/build.
  Record a real dependency before requesting the producer's output.
- Build that producer and bind the resulting artifact/read-only bundle
  into the server build. A change to the output invalidates its consumer.
- Fail the dependent build for an unknown target/output, wrong kind,
  dependency cycle or failed producer. No server with an unresolved
  artifact can launch; no first HTTP request performs a name lookup.

`ProjectPlan` holds the metadata catalogue and declared edges. A target's
build session also records library and artifact edges discovered by
expansion. These belong to that build revision; they do not mutate the
cached metadata description. Cycle checking includes discovered edges,
and the completed build freezes the resolved graph and outputs together.
The compiler interface exposing these dependencies is part of the work,
not an existing public session API.

This is entirely **intra-project**. There is no cross-project registry,
package feature, hardcoded build-cache path or runtime artifact-name
service. Generated artifacts arrive through explicit graph edges, not by
letting metadata read the build directory. CLI and IDE report the same
build-time failures.

## 3. Launch a server; let it serve the application

A launch entry starts only a server actor, with arguments bound to that
actor. The server calls a native HTTP effect provider to listen and receives
its actual `http://127.0.0.1:PORT/` address. The IDE reports
“Application running at …” and offers the link. One ordinary loopback
listener/origin per server is sufficient initially; root-relative paths
then resolve naturally. No application is mounted beneath an IDE path.

The provider handles network I/O and HTTP framing; the actor decides the
response. Start with complete request/response bodies: method, path,
headers and bytes, and status, headers and bytes. HTML, JS, Wasm, assets,
typed binary POST messages and errors all come from the actual server.
Streaming, WebSockets and remote deployment are later extensions.
Listeners and pending operations belong to the actor that created them.

The server holds its frozen client bundle from the build graph. The IDE
does not select a client binary or manufacture application pages. Multiple
browser views reach the same server; each has its own client state. Typed
application messages crossing HTTP use the derived binary codecs; HTTP
itself is the network protocol. This transport is new work, distinct from
the already-landed local actor path. Native actors talking to each other
continue to use that direct local path, not loopback HTTP.

The first complete example is one project containing a client target that
produces a bundle and a counter/ping server target. Two real browser clients
load HTML, relative and root-relative JS/Wasm/assets from that server and use
its protocol. A second independent server run demonstrates shared-host
lifetime isolation. Siegework's authoritative simulation/client-state split
and multiplayer semantics are separate game work.

## 4. Own runs, resources and revisions explicitly

The IDE owns buffers, input revisions, build requests, diagnostics and run
records. A `Run` identifies a selected launch entry, one frozen build and
the actors/resources started for it. To make Stop meaningful without a
supervision tree, give actors a flat run-ownership tag: a root receives it
at reservation, and its spawns inherit it. Parent completion still does not
cancel children. Explicit Stop applies to the run's members; unrelated
runs in the same host remain alive.

This is a proposed addition to the host, including its current name-only
platform-import construction. The lifecycle is small but real:

1. Close the run to new actors and new I/O before awaiting anything. Startup
   reservations and pending loads already belong to that run.
2. Close its listeners; reject queued/current mailbox requests and cancel
   its host-owned pending I/O. Each operation settles once. Late completions
   cannot enter a retired actor or resurrect its run. Callers in other runs
   receive a failed request; unrelated actors are not terminated.
3. Let suspended JSPI entries unwind and settle. Existing `runEntry` then
   restores handler globals; the host releases the actor record and
   remaining resources. Stop completes after all owned entries have settled.

This is **cooperative cancellation**, limited to waits the host can cancel.
A non-yielding Wasm computation blocks the shared event loop; Stop cannot
forcibly interrupt it while preserving other actors. Killing the isolate
is a whole-host failure action, not implementation of per-run Stop. CPU
budgets, preemption, restarts after crashes and general supervision are
deferred. Closing an application view ends that client, not its server.
Closing the editor tab does not kill the native IDE server. Shutting down
the IDE server explicitly stops its owned runs and tool worker. Stop does
not roll back I/O already performed.

Builds consume immutable snapshots of disk files plus unsaved buffers.
Edits advance the input revision; diagnostics identify the revision they
describe. Save writes a named buffer revision and must not overwrite a
newer buffer or an unacknowledged external edit. Watching disk must not
silently replace an unsaved buffer. The IDE's initial file/buffer snapshot
and subsequent changes use the same revision model.

Each completed build identifies its input revision and plan generation.
Keep last-good artifacts while a build session or live run references them.
A failed build reports diagnostics and leaves the current run serving its
old coherent bundle. Never mix a new client bundle into an old server run.

Manual **cold Restart** is the default. It prepares a successful build,
stops the previous run, then starts a fresh run with reset state. Optional
restart-after-success consumes that same completed build; it does not
trigger another build. Stop, a newer Restart or changed launch metadata
supersedes old pending completions. A late successful build cannot restart
a stopped run. If startup fails after the old run has stopped, report the
failure; rollback is not promised. The actual address may change and
clients must reload/reconnect. Transparent client migration is later work.

State-preserving server replacement would additionally need quiescence,
checkpoint/restore and protocol compatibility. It is not cold Restart and
is outside this stack. Existing browser application relinking remains
available through the current path; this proposal neither removes it nor
claims it already solves actor-server migration. No dependency on the
separate control-handler prototype is assumed.

## 5. The IDE is a client of this model

The native IDE server serves its frontend and exposes one IDE API: initial
file/buffer state, edit/save, build, launch/restart/stop, and a single event
channel for changes, diagnostics, run status and logs. Notifications carry
the relevant input revision, build ID and run ID. Compiler workers are
internal. One IDE owns one folder; there is no workspace manager or
multi-root switching layer.

Reuse the editor's existing pane/split model with two document kinds:
**File** and **Browser**. A Browser document is an ordinary HTTP(S) iframe
with an address bar. Palette actions launch a server, open its address,
open another client, split and pin documents. Moving or splitting a view
must preserve its live iframe/document instance; blindly reusing
[`replaceChildren` in the editor layout](../../src/ide/panes.mjs) would
disconnect it. Only an explicit navigation/reload replaces the client.

Applications may restrict embedding through
[`frame-ancestors`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/frame-ancestors).
Our example permits the IDE origin; Open externally remains available.
The IDE is not a replacement browser, a universal editor-plugin host or a
special preview that knows application build paths. Initial observability
is logs, failures and run status. Source locations, stepping, breakpoints
and GC-value inspection require separate compiler/debugger work.

## 6. Proposed implementation sequence

These are review-sized increments, not published implementation PRs.
Each extends the preceding proof; exact filenames are suggestions rather
than a prescribed framework.

1. **Query a project safely.** Add the project-description library boundary,
   snapshot FS provider and typed plan parser under `src/lofi/` with a thin
   native loader. Execute compiled Lofi fixtures proving allowed reads,
   denied reads/writes, closed initialization/`inputs`, malformed patterns
   and invalid plan references. Creation/deletion of matching inputs must
   invalidate queries. **Depends:** landed loader/compiler. **Cuts:** build
   execution, IDE UI, fine-grained tracing and arbitrary recipe plugins.

2. **Build projects from the CLI.** Add the shared project executor around
   compiler sessions and expose `lofi build DIRECTORY`. Give targets named,
   typed outputs and own their output storage. Prove several targets build,
   ordinary source edits reuse metadata, matching metadata changes requery,
   and failed builds preserve last-good outputs. Include unsaved-overlay
   snapshots through the library API even before an IDE uses them.
   **Depends:** 1. **Cuts:** application launch, HTTP and artifact macros.

3. **Resolve artifact references during builds.** Add the literal expansion
   boundary and discovered target edges, then build client source into a
   bundle bound into a server target. Prove changed producer output rebuilds
   the consumer and unknown names, wrong kinds, cycles and producer failures
   fail before any launch in both engine callers. **Depends:** 2.
   **Cuts:** cross-project references, runtime lookup and generic packaging.

4. **Stop owned actors without stopping the host.** Extend
   `src/app/actors.mjs` and native import ownership with flat run tags and
   cancellation of supported waits. Execute linked Wasm: stop during
   mailbox wait, pending host I/O and asynchronous startup; include a child
   that outlives its parent. Verify every owned entry settles, handlers and
   resources release, and another run still answers. Retain the existing
   actual-object identity proof; assert local traffic invokes no codec or
   socket path. **Depends:** landed actors, independent of 1–3.
   **Cuts:** preemption, supervision trees and worker pools.

5. **Serve the built application over native HTTP.** Add the small standard
   HTTP effect/provider and the counter project. A native launch harness
   uses its parsed launch entry. In headless Chromium, two clients fetch
   every resource from the server actor, exchange derived binary messages,
   observe shared server state and independent client state, and receive
   real error responses. Stop one run, verify its pending requests settle
   and the second server survives. **Depends:** 3 and 4.
   **Cuts:** IDE integration, browser-local hosting, streaming and game work.

6. **Host the project engine in a native IDE server.** Connect existing
   editing/build behavior to one persistent backend and its compiler
   worker. Expose the small IDE API and implement cold Restart policy.
   Prove exact unsaved revisions, responsive HTTP during builds, failed
   build continuity, artifact retention and Stop/Restart/metadata races.
   CLI and IDE must produce identical artifact diagnostics. Consolidate
   shared watch/build behavior here instead of maintaining two engines.
   **Depends:** 1–5. **Cuts:** multi-workspace management, server migration
   and source-level debugging.

7. **Open applications as Browser documents.** Adapt the current frontend
   and pane layout to the native API and the two document kinds. Verify
   two real clients alongside source, split/pin without reload, independent
   view closure, ordinary external opening, and an unsaved client edit
   reaching the server bundle after a successful build and explicit
   Restart. **Depends:** 6. **Cuts:** a special preview dock, editor-as-URL
   plugins, self-hosted IDE reload and new browser backend infrastructure.

The final proof is deliberately small: one project, two build-linked
targets, two clients, and two independent server runs on one host. It tests
the architectural boundaries without requiring a game rewrite, package
manager, remote scheduler or full IDE platform.

## 7. Choices still to settle

- **Description syntax:** confirm the library form, export signatures and
  minimal Datum grammar. The ownership and query rules above are fixed;
  an executable build script is not an alternative interpretation.
- **Initial pattern/recipe vocabulary:** choose the smallest documented
  glob grammar and compiler/bundle recipes sufficient for the example.
  Recommendation: project-relative patterns, rejected symlinks, no ambient
  external roots or shell hooks.
- **Artifact syntax:** choose the literal form and named output kinds.
  Build-time resolution, real dependency edges and identical CLI/IDE
  failures are requirements regardless of spelling.

All-browser placement, custom address schemes, physical actor parallelism,
deployment, server state migration and advanced debugging are explicitly
outside this implementation sequence. Their future designs should reuse
the project engine and host effect boundaries where they fit, without
making this stack implement them in advance.
