# Application model

{{#include ../../language.md:applications}}

<a id="live-reload"></a>

## Hot reload

This section describes the current browser application implementation.
The [proposed process workflow](#proposed-application-processes) moves application
execution into `lofi dev` and requires server and browser data to survive code
replacement through durable records. The handover implementation below has not
yet changed.

`./scripts/lofi-tool serve APP-DIRECTORY` builds an application one library at a time,
serves it at `http://127.0.0.1:8000/`, and builds it again whenever the
application's directory, the standard library or the browser host
changes, compiling only the libraries the change reaches. Each page it
serves relinks the modules that changed, and those after them, without
reloading. Their globals start over; the application's state crosses to
the new program:

- as it is, when `type-test` finds its type unchanged;
- through `save` and `restore` when its layout changed. That is the
  contract a page reload already relies on, so an application whose save
  is a journal, as Siegework's is, replays the journal under the new code;
- not at all when the save cannot be restored either: the old program
  keeps running, and the page offers to start the new one over.

A failed build is shown over the page, and the old program keeps running.
A changed stylesheet is fetched again; a changed page or host script reloads
the page after saving. The [event and reload boundaries](#event-and-reload-boundaries)
below define checkpoint recovery, acceptance and manifest reconciliation.

`./scripts/lofi-tool serve` does not build generated-library recipes. The project builder
used by `lofi build`, `lofi dev` and `make site` does; application launch/reload
integration into `dev` remains in progress.

`./scripts/lofi-tool watch SOURCE` is the same loop for a program: it builds and runs the
program again whenever its sources change, stopping a run still in
progress once a new build succeeds. [The development
toolchain](toolchain.md) describes how builds stay this fast, and the
browser editor that subscribes to the native project development service.

## Task lifetime

Each invocation owns a [task runtime](../runtimes/scheduling.md). Normal
root completion after initial presentation lets children finish. Root
failure or return before that acceptance boundary closes the runtime.
Explicit reload waits for the root's
checkpoint handover before closing it. Repeated stop requests share one
handover result. This is application lifecycle policy; ordinary task
completion does not cancel its children.

Event waits and storage use the same suspension bridge as task waits.
Their cancellation signals belong to the invocation that began the call.
Non-abortable storage may delay teardown until it finishes. An old
completion cannot write into a replacement invocation.

Only one loop consumes application events. The runtime buffers input and
coalesces frames; it does not own an implicitly shared current world.
The root task owns event consumption, boot acknowledgement and checkpoint
storage. Calling these operations from a detached task fails before any
input or saved bytes change. A child can use task waits and separately bound
I/O, but cannot replace the application's checkpoint while its loop saves.
Read-only seed and canvas dimensions remain available to all tasks.

## Event and reload boundaries

`src/app/runtime.mjs` owns an invocation's queue and storage bindings;
`host.mjs` retains the canvas, renderer, pictures and HUD across invocations.
DOM listeners enqueue input rather than calling Wasm. Consecutive moves for the
same pointer and consecutive resizes coalesce without crossing other input.
Consuming a pending frame requests the next animation frame, so slow work does
not accumulate ticks. HUD values update at most every 100 milliseconds and
periodic saves occur every five seconds.

Event waits and complete storage operations suspend through JSPI. Save imports
copy borrowed byte arguments before awaiting IndexedDB; a failed persistence
operation still leaves an owned snapshot for migration. GPU drawing currently
uses synchronous screen bindings. Only Lofi calls suspending imports: the Rust
scalar services keep a linear-memory stack that JSPI does not switch.

Reload fences the old queue with `Reload`. Its accepted prefix finishes, the root
saves and returns, and the runtime cancels and drains remaining tasks. New input
waits for the replacement. Resize and an initial zero-time frame must finish before
its first presentation is accepted; until then the old program and handover
remain available for rollback. Cold startup, including a retry, finishes before
a relink may stop it. A live migration never silently discards incompatible
state; only a cold start may retry without an incompatible saved value.

After a trap, `app_state` exposes the last complete checkpoint. Serializing it
runs the old entry with `Reload` first, avoiding the failing update or view.
The consumed failing event is dropped; unread input remains. A cold first-frame
failure also retains its owner so a source fix can resume it.
A closure kept in the state can retain old code; applications storing functions
must reconstruct them through save/restore when changing their implementation.
Relinked module globals, including Scheme's top-level variable cells, start over.

The reload client (`src/app/reload.sld`, bound by `reload-client.mjs`) compares
manifests and relinks from the first changed module. It serializes relinks and
keeps only the latest waiting build. A build becomes the page's current build
only after acceptance. Missed events reconcile against the next complete
manifest; a refused build is not retried automatically until the developer
starts over.

## Proposed application processes

**Not yet implemented.** [Application integration](https://github.com/tsnl/snail-scheme/issues/458)
will move ordinary process controls and reload under `lofi dev`. After an accepted
build, stop the affected child, await exit and start its replacement. Each run
records its run target, build, process and exit status. Start/Stop/Restart and
standard streams remain OS process operations, with bounded termination; killing
a process cannot promise cleanup or a final commit.
Stop overrides a pending automatic restart: stopping during compilation must
not let the completed build start a new child.

The [typed state prototype](state.md) proposes durable base tables and disposable,
read-only cached views. Ordinary entry startup opens the same store, recreates
sockets/windows and requests views. There is no application `resume` method,
heap snapshot or state-transfer IPC. Managed objects, closures and suspended
computations never cross code versions. This API remains under review.

Failed startup retains stored records and reports the failure, without automatic
rollback to the old running loop. Reverting code does not undo data writes.
The state chapter defines transaction outcomes, explicit schema migration and
cache validity; process replacement supplies none of those guarantees by itself.

Keep storage identities stable, database files/journals outside source watching
and output directories, and independent browser stores separately named. One
concrete server database binding is sufficient; browser storage needs its own
transaction and commit proof. The existing save/restore implementation remains
until the replacement is reviewed and tested.

### Delivering new browser code

The proposed HTTP bundle helper keeps the server origin stable across restarts
and serves files, development manifests and reload events. Reconnect supplies
the latest manifest. Pin assets to that manifest's build: a request for B must
not silently return C's bytes. If B is unavailable, reconcile and retry using the
latest manifest. Network failures and incompatible stored data are distinct;
neither permits clearing data silently.

Advertise a bundle only after its server can serve it. Multiple frontends use
separate prefixes and manifests. Production serving omits development endpoints.
Compilation does not prove client/server API or durable-schema compatibility.
The editor remains an independent client of development services; application
browser windows are ordinary clients of their server.
