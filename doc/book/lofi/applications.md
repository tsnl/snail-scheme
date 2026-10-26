# Application model

{{#include ../../language.md:applications}}

<a id="live-reload"></a>

## Hot reload

This section describes the current browser application implementation.
`lofi dev` runs named program targets as subprocesses. The
[proposed durable reload workflow](#proposed-application-processes) requires server
and browser data to survive code replacement through durable records. The browser
handover implementation below has not yet changed.

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
used by `lofi build`, `lofi dev` and `make site` does. Program targets run through
the editor's application controls; browser bundle/reload integration remains in progress.

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

## Native application process owner

`scripts/application-process.mjs` implements ownership of one ordinary OS child
for one run target. The native development service, HTTP API and editor use it.
The public `lofi run` command executes a cold
project build with ordinary shell IO.

The owner accepts a latest launch request `{build, entry, args}` or `null` to stop.
Each non-null request means a fresh attempt. `entry` names the accepted generation
directly, rather than its mutable build-target link: development entries are
`modules.json`, cold entries are `program.wasm`. The owner invokes the existing
runner through `process.execPath` without a shell. It copies arguments and captures
the caller's working directory when constructed; the environment is inherited.
Its stdin is EOF. Interactive execution remains available through `lofi run`.

Replacement first terminates the old child and awaits its `close` event, including
captured streams, then re-reads intent. New requests overwrite pending ones; Stop
can remove a queued replacement while the old child exits. A terminal attempt is
retained and never retried automatically. SIGTERM has two seconds before SIGKILL;
the owner still waits for actual cleanup rather than allowing overlapping children.
Signal failures are reported. OS cleanup or inherited pipes can delay closure;
this is not a wall-clock shutdown guarantee or process-tree supervisor.

Status separates the desired build from the observed attempt's build, PID, phase,
exit code/signal and error. It retains only the latest attempt and the last 64 KiB
of each output stream, decoded for display; truncation can split a UTF-8 character.
There is no history or ordering guarantee between stdout and stderr. Observers
receive current snapshots, may request or close synchronously, and must not throw.
Permanent close prevents late launches, returns one stable cleanup promise and
removes observers after cleanup.

Start/Restart policy and accepted-build decisions belong to the project service.
Applications are assumed not to
spawn additional OS children, and accepted generation files must remain available
for the child's lifetime. The current project publisher retains those directories.

### Development run targets

`developProject` exposes `startRun`, `stopRun` and `restartRun` for names from the
last accepted `project.datum`. Targets begin stopped. Start sets run intent and is
idempotent while that intent remains set, including after exit or failure. Restart
explicitly requests a fresh attempt from the latest accepted build. Stop clears
intent immediately; a compilation already in flight cannot restore it.

Acceptance compares the run's selected build target, literal arguments and complete
output digest against its last issued launch. Changed wanted targets request a
replacement; unchanged targets keep their child and actual build ID. A compiler
cache hit is not this evidence: a discarded build may already have warmed the
cache. Failed or superseded builds do not change accepted launch definitions or
running children. Start remains usable against the last successful build while
the current compilation fails.

Status includes each run's availability, intent, desired build and observed attempt.
Removed names stop and retain their owner and last attempt until session shutdown;
reintroducing a name leaves it stopped. Retaining the owner prevents an old stopping
child from overlapping a new child with the same name. There is no attempt history
or automatic crash retry. Closing the development session waits for all owners as
well as the compiler and file observer.

<a id="proposed-application-processes"></a>

## Proposed durable reload

The process controls above are implemented. Durable application data and browser
reload remain
[application work](https://github.com/tsnl/snail-scheme/issues/458). Process
replacement alone preserves no managed state; killing a process cannot promise
cleanup or a final commit.

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
