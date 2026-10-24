# Desktop IDE and project engine

**Review draft — proposed, not implemented.** This document starts from
[`12fbcd9a`, the shared actor host in #407](https://github.com/tsnl/snail-scheme/pull/407).
It proposes an implementation sequence for approval; this draft PR contains
only this document. No implementation PRs are being created with it.

One IDE instance works on one folder. A reusable project engine builds the
folder's programs for both the CLI and IDE. Concrete structs and typed
interfaces describe behavior; platform-specific constructors place it in
actors and return channels where communication is needed. The IDE launches
servers on a shared native host. Those servers serve real HTTP responses;
the editor and GUI clients are ordinary web pages.

The browser-local IDE/backend, browser compilation, ServiceWorker and
SharedWorker routing, virtual HTTP mounts and custom URL schemes are
deferred. Ordinary browser GUI actors are included: existing applications
must migrate while preserving their state/view/save/reload behavior.
Native HTTP exercises real server/client behavior without a virtual HTTP
transport. It does not require rebuilding the existing static IDE backend.

## 1. Start with the host that already exists

The [actor host](../../src/app/actors.mjs) and
[(lofi actor)](../../lib/lofi/actor.sld) already provide independent Wasm
instances, typed request/reply mailboxes, dynamic spawn, local immutable
messages and an automatic binary codec path. Startup is reserved before
asynchronous loading; waiting actors count as alive; children can outlive
parents; drain waits for all actors. The
[actor tests](../../tests/actors/check.mjs) already compare the actual GC
objects to prove local identity preservation. Reuse these mechanisms.
Today `createHost({programs})` holds a name-to-loader map and `run(initial)`
accepts a list of initial actors. The proposed single-root bootstrap below
changes that public shape; it is not already implemented.

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
| Actor | An execution context owning private state, a mailbox and a lifetime. |
| Channel/proxy | A caller-owned endpoint value used to communicate with an actor or service; it is not that running actor. |
| Host | The runtime owner of actors, their imports, mailboxes and platform resources. |
| Isolate | An engine instance with its own heap/reference domain. The first desktop host occupies one isolate. |
| Process | The OS container. It is not the unit of application launch. |

The first native provider is Node running Wasm through V8/JSPI. Its
desktop host contains the IDE server actor and multiple user-server
actors on a common event loop. JSPI permits independent waits and
resumptions; Wasm instructions in this isolate do not run in parallel.
Keep the existing promise scheduling, without a second
runnable queue. A host is a runtime abstraction, not another name for an OS
process; an [isolate is an engine/heap boundary](https://v8.dev/docs/embed).

Compatible actors in this host exchange typed, deeply immutable GC objects
directly. There is no dedicated pipe, socket or codec invocation for that
path. The compiler's existing checks exclude nested mutable values,
functions and `Any`; the host and compiler remain trusted. A future host
pool spanning isolates would need a transport across their reference
domains, with derived binary serialization rather than a promise of shared
GC identity. Designing that pool or preemptive scheduling is out of scope.

Compilation is the justified exception to the shared actor loop:
the persistent IDE runs its project engine and compiler sessions in **one
dedicated worker**, so CPU-heavy builds cannot freeze HTTP service and
actors. This is an internal tool host, not one worker per application.
Snapshots and results cross this
boundary as owned bytes/data. Node's
[worker documentation](https://nodejs.org/api/worker_threads.html) identifies
CPU-intensive work as its intended use. The one-shot CLI can call the same
engine directly without starting the IDE or HTTP.

### Structs implement contracts; channels carry calls

Take the ownership pattern from Winit, not its entire platform lifecycle.
[`ApplicationHandler`](https://docs.rs/winit/0.30.13/winit/application/trait.ApplicationHandler.html)
provides callbacks on application-owned state; its
[example](https://raw.githubusercontent.com/rust-windowing/winit/v0.30.13/examples/window.rs)
passes that state to `run_app`.
[`EventLoopProxy`](https://docs.rs/winit/0.30.13/winit/event_loop/struct.EventLoopProxy.html)
is a separate endpoint for posting events and reports a closed event loop.
It does not implement `ApplicationHandler`.

In Lofi, ordinary libraries define concrete state structs, meaningful
type classes and explicit instances. A CLI contract can describe command
execution; a GUI contract can describe resize/input/presentation; a service
contract describes its particular operations. Root, IDE and server are roles
of ordinary actors. There is no `Actor` marker hierarchy, universal
application definition, automatic remote dispatch for every library export,
or universal `send`, `spawn` or `connect` surface API.

Use today's [typeclass syntax and static instance selection](../language.md#typeclasses).
Each method has fixed arity and declared effects. No variadic type
parameters, higher-kinded machinery, superclasses, associated types or
runtime trait dictionaries are needed. Class evidence chooses an
implementation; it neither grants authority nor makes a call remote.

For example, an actor-owned counter handler can use immutable state, while
a channel implements the caller's protocol. This is a **proposed library
API sketch using existing language syntax**, not an implemented new API:

```scheme
(struct CounterState
  ((count I64)))

(typeclass (CounterHandler S)
  (: add-state (-> S I64 (Pair S I64))))

(instance (CounterHandler CounterState)
  (define (add-state state amount)
    (let ((next (+ (CounterState-count state) amount)))
      (Pair (CounterState next) next))))

(enum CounterFailure
  (Unavailable)
  (BadResponse))

(typeclass (CounterClient P)
  (: add-count (-> P I64 (Result I64 CounterFailure) ! actors)))

(struct LocalCounterChannel
  ((endpoint (Actor I64 I64))))

(instance (CounterClient LocalCounterChannel)
  (define (add-count channel amount)
    (counter-request (LocalCounterChannel-endpoint channel) amount)))
```

`counter-request` above is a proposed fixed-signature transport adapter.
It must turn the current `request` operation's rejected JSPI calls into the
declared failure result; that conversion is new work. The service's ordinary
runner receives an immutable amount, applies `add-state` to its private
state and replies with the count. The channel wraps an endpoint, not
`CounterState`; its constructor stays behind the authority-granting API.
Private `Ref`s, handlers and resource handles never become message payloads.
Closing a channel does not stop its target or grant run-management rights.
A transport failure may follow an already-performed operation; it does not
justify automatically retrying a non-idempotent call.

A local object and a proxy may implement the same class when their complete
contracts match. Do not force a state-transition handler and a remote
endpoint into one class when ownership or signatures differ. Effects must
also match: an HTTP implementation cannot silently fit the `actors`-only
method above. Initially keep its HTTP operation/effect explicit and share
the immutable protocol and handler logic. A common endpoint class needs an
agreed common effect/failure contract; it is not automatic transport erasure.

Parent/platform libraries provide ordinary creation functions, such as a
native counter constructor, an HTTP counter connection function, or a
browser GUI attachment function. Their concrete arguments, result types,
capabilities and lifecycle ownership can differ. Construct private state
inside the new actor using immutable initialization data and granted
providers; do not transfer a parent's captured closure or `Ref`.
Underneath, local channels
reuse the landed `Actor<Q,R>` request/reply transport and protocol witness
checks; network channels use explicit HTTP and derived codecs. A small
runner/adaptor can use the existing actor entry machinery internally.
Neither that machinery nor `define-actor` is a new mandatory authoring form.
No compiler-generated universal method-call protocol is required.

### Bootstrap is an actor, not a program registry

Host startup creates **one bootstrap actor** with bounded startup data and
capabilities. Supply context-specific defaults: a server bootstrap selects
native constructors; an ordinary browser GUI bootstrap attaches a client
within its page's host. Users can replace either with their own bootstrap.
A browser-development bootstrap is a possible future context, not a reason
to restore browser-local IDE/backend work here.

The bootstrap owns startup selection. A catalogue, if useful to that
policy, is not a mandatory Host contract or a separately supplied list of
initial actors. Later creation uses the relevant ordinary parent/platform
function, without routing every call through a permanent bootstrap. Root
replacement grants no scheduler privilege or extra filesystem/network
loading authority.

Dynamic launch still needs an explicit boundary: builds produce concrete
typed startup adapters while their structs and instances are statically
known. An artifact contains such an adapter, its frozen code/dependencies
and a small versioned startup contract. The loader verifies that contract
and required platform imports before entering it. Selecting a class name
at runtime cannot manufacture evidence. Keep standalone and linked code
loading; resolve project names/library paths to bounded frozen artifacts
before launch, without a global runtime name registry. Exact adapter ABI
is an open implementation choice, not solved merely by introducing classes.

The host owns instantiation, fresh private state, waits, mailboxes and
lifetime. One actor processes one invocation at a time, including while
suspended in JSPI; callbacks enqueue work instead of reentering its Wasm.
A callback returning does not destroy a passive service. Its runner's
completion or explicit retirement does; a bootstrap may finish without
ending its children. Drain still waits for all live actors. No general
preemption, deadlock detection or handler interleaving is implied.

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
   environment, random or network capability is supplied implicitly.
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

A launch entry selects a built server program and its startup arguments.
The context's bootstrap or IDE launch policy uses its concrete constructor
and checked startup adapter. It starts only that server, not a server/client
pair.
The server calls a native HTTP effect provider to listen and receives
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

Serving a bundle does not produce a typed channel to its running browser
client. That needs an explicit session/handshake and connection lifetime.
A server awaiting a client reference is a later extension; the first proof
uses client-initiated requests, without inventing bidirectional RPC.

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
supervision tree, give actors a flat run-ownership tag. An explicit IDE
launch creates a fresh run scope before reserving its first actor; ordinary
spawns inherit the caller's scope. The bootstrap root's ancestry must not
put every IDE-launched program into the IDE's own run. Run creation and
Stop are management capabilities granted to the IDE, not privileges of
being the first actor. All starts use the same instantiation machinery.
Parent completion still does not cancel children. Explicit Stop applies
to the run's members; unrelated runs in the same host remain alive.

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
is outside this stack. Browser GUI state-preserving reload is already
implemented and must survive the migration below; it does not automatically
solve server migration. No dependency on the separate control-handler
prototype is assumed.

## 5. Migrate GUI applications into the actor model

This migration is required. Today
[`define-application`](../../lib/lofi/app.sld) generates an `app_main` loop,
and [the application runtime](../../src/app/runtime.mjs) enters it separately
from the actor host. The finished stack must not leave a second application
execution model beside actors.

Keep the existing pure initialization, update, view, HUD, save and restore
functions as library helpers. Concrete GUI state structs implement the
needed model/handler contracts. A platform event/presentation adapter owns
the actor and its subscriptions, installs its providers and invokes those
methods. Pure state replacement remains useful; copying Rust's `&mut self`
literally into shared mutable Lofi objects is unnecessary. Where mutable
state or a reset-provided handler context is needed, it remains private to
that GUI actor, including across JSPI suspension.

A compact proposed pure-model contract is:

```scheme
(typeclass (GuiModel S)
  (: update-gui (-> S Input S))
  (: view-gui (-> S Frame)))
```

Resize/input/time become inputs; the adapter performs presentation effects.
HUD and save/restore retain their fixed-signature contracts. Driver
signatures list their required classes explicitly, without superclasses.

Browser DOM events, resize, frame ticks and storage completions must obey
the actor's serialization boundary. One event invocation can suspend; a
second invocation cannot enter its handler globals meanwhile. Prefer
bounded event callbacks rather than a permanently active startup call that
prevents other messages from running. An event commits its immutable
checkpoint only after its update/presentation work succeeds. The GUI
controller retains the last completed checkpoint and unread input for
recovery; it does not publish a partially rendered candidate.

Reload closes admission to the old invocation, settles it, checkpoints,
then starts the new code and transfers input ownership only after successful
initial presentation. Preserve direct handover when the state type is
compatible, save/restore fallback otherwise, and rollback when adoption
fails. The existing opaque handover is a private checked reload boundary;
it does not permit `Any`, mutable cells or closures as ordinary messages.
Frame coalescing, pending storage and handler cleanup remain part of this
contract. A returned callback leaves the GUI actor alive until closed.

Migrate the counter first, then Siegework, Hearsay and application fixtures
to ordinary libraries with structs/instances and concrete constructors.
Retire their dependency on the dedicated `define-application`/`app_main`
entry convention. Internal adapters may bridge the transition, but cannot
become a permanent second runtime. This is execution/framework migration,
not a multiplayer or game-state redesign.

Carry forward the real [browser reload proof](../../tests/browser/reload.mjs):
state survives a body edit; a changed state type uses Save; incompatible
Save or first-view failure preserves the working version; a failing event
is not replayed; unread input survives; suspended startup/storage never
overlaps replacement. First run it through the existing development serving
path with the migrated actor runtime. For project-owned HTTP applications,
any reload advertisement and bundle still come from the actual server;
the IDE cannot inject newer client code into an older frozen server run.
Cold server Restart and possible address changes remain the explicit
contract above.

## 6. The IDE is a client of this model

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

## 7. Proposed implementation sequence

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

4. **Prove typed handlers, channels and bootstrap.** Add a small counter
   library using existing structs/classes, a concrete local channel and
   runner, typed failure conversion, and native startup adapters over the
   landed loader/host. Prove default and custom bootstraps, statically
   checked instances, protocol mismatch rejection and unavailable-channel
   results. Execute real Wasm and retain identity/no-codec/no-socket proofs;
   reject mutable message payloads. Runtime artifact selection must not
   bypass the startup contract. **Depends:** landed actors; fixtures can
   precede 1–3. **Cuts:** universal send/spawn/connect, automatic export RPC,
   runtime trait objects and a mandatory catalogue.

5. **Stop owned runs without stopping the host.** Extend
   `src/app/actors.mjs` and provider ownership with flat run tags and
   cancellation of supported waits. Stop during mailbox wait, pending I/O
   and asynchronous startup. Verify entries settle, handlers/resources
   release, and another run still answers. A bootstrap runner returning or
   retiring its own actor, rather than stopping its whole run, must leave
   children able to create further actors without consulting it;
   a returned callback must not accidentally drain a passive actor.
   **Depends:** 4. **Cuts:** preemption, supervision trees and worker pools.

6. **Serve the built application over native HTTP.** Add the small HTTP
   provider, explicit HTTP channel/operation and counter project. Its server
   bootstrap uses the checked launch entry. In headless Chromium, two
   clients fetch every resource from that server, use derived binary
   messages, keep independent client state and observe shared server state.
   Verify real HTTP errors, transport failure results and Stop isolation
   between two server runs. **Depends:** 3 and 5. **Cuts:** virtual HTTP,
   streaming, universal connection abstractions and game work.

7. **Migrate existing GUI applications.** Adapt `(lofi app)` helpers,
   `src/app/runtime.mjs`, loading and application sources to concrete GUI
   structs/interfaces, a browser bootstrap and actor-owned callbacks. Run
   the existing runtime/reload tests on that path, including pending
   storage, traps, rollback and exactly-once input handover. See Siegework
   and Hearsay running in Chromium; preserve their behavior. The final
   applications must not require the old independent `app_main` runner.
   **Depends:** 4 and 5, plus the existing GUI/reload implementation.
   **Cuts:** game rewrites, browser-local IDE/backend and server migration.

8. **Host the project engine in a native IDE server.** Connect existing
   editing/build behavior to one persistent backend and its compiler
   worker. Expose the small IDE API and implement cold Restart policy.
   Prove exact unsaved revisions, responsive HTTP during builds, failed
   build continuity, artifact retention and Stop/Restart/metadata races.
   CLI and IDE must produce identical artifact diagnostics. Consolidate
   shared watch/build behavior here instead of maintaining two engines.
   **Depends:** 1–7. **Cuts:** multi-workspace management, server migration
   and source-level debugging.

9. **Open applications as Browser documents.** Adapt the current frontend
   and pane layout to the native API and the two document kinds. Verify
   two real clients alongside source, split/pin without reload, independent
   view closure, ordinary external opening, and an unsaved client edit
   reaching the server bundle after a successful build and explicit
   Restart. **Depends:** 8. **Cuts:** a special preview dock, editor-as-URL
   plugins, self-hosted IDE reload and new browser backend infrastructure.

The project proof stays small: two build-linked targets, two clients and
two independent server runs on one host. GUI migration additionally proves
the existing applications and reload behavior survive. Neither requires a
game redesign, package manager, remote scheduler or full IDE platform.

## 8. Choices still to settle

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
- **Startup adapter ABI:** choose the smallest verified artifact contract
  connecting concrete constructors, startup arguments and statically
  selected instances. Runtime class-name lookup is not an implementation.
- **Interface effects:** settle the exact GUI/CLI contracts and endpoint
  failure types. Keep handler ownership distinct from channel authority;
  share a client class across transports only when its declared effects
  and failure semantics actually match. No new type-system feature is
  assumed to make this work.

All-browser IDE/backend placement, custom address schemes, physical actor
parallelism, deployment, server state migration and advanced debugging are explicitly
outside this implementation sequence. Their future designs should reuse
the project engine and host effect boundaries where they fit, without
making this stack implement them in advance.
