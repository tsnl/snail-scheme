# Application model

`(snail shell app)` defines interactive browser applications as total functions over
a state:

| Function | Meaning |
| --- | --- |
| `init : seed width height -> State` | The first state. |
| `update : State Input -> State` | Applies one input: a key, a pointer, a HUD button, the screen's size, or the milliseconds since the last display frame. |
| `view : State -> Frame` | A frame of items, meshes and sprites, under a camera and a light, with the pictures their textures use. |
| `hud : State -> (List Panel)` | The HUD's panels of labels, texts, buttons, dials, links and images, shown again after each update. |
| `save : State -> Save` | What to store, with a wire encoding; it may be a record of how to rebuild the state. |
| `restore : Save -> State` | The state again. |

These functions operate on immutable state. `define-application`
runs them inside one loop and the binder returned by `reset`:

```scheme
(define-application Game
  (reset: default-reset)
  (init: new-game)
  (update: step)
  (view: draw)
  (hud: panels)
  (save: save-game)
  (restore: restore-game))
```

`default-reset` simply runs its argument. A custom reset returns a binder
that installs effect handlers around startup and the whole loop; its result
and effect row are quantified on the reset function, so the returned binder
is monomorphic. The application exports `app_main : (Option Any) -> I64`,
which starts the loop as a task and answers its id; the host turns the
scheduler until the loop answers ([task lifetime](#task-lifetime)).
`next-event` drains the host queue and, when it is empty, waits for the
next event by ticket
([waiting on the host](../runtimes/tasks.md#waiting-on-the-host)). `FrameEvent` carries elapsed milliseconds, `InputEvent` carries an
`Input`, `Hidden` saves without stopping, and `Reload` saves and returns the
state. The `Frame` type continues to describe drawing data.

DOM listeners enqueue input. The host keeps at most one pending display
frame and coalesces consecutive pointer moves and resizes without crossing
other input. Storage waits for a whole load or store, copying save bytes
before the browser's work begins. The loop saves every five seconds and when the
page becomes hidden. Only a complete successful event commits its state;
a trap leaves the preceding checkpoint available through `app_state`.
Because time is input, an application decides how time passes and can stop
it at any frame. Headless tests run on the pinned Node 26, in both
packaging modes.

The loop and locally dispatched work share one runtime. The root performs
`mut`, `screen`, `events`, `storage` and `tasks`, since it waits for events
and saves by ticket; a reset binder that performs more, such as one that
installs a handler with effects of its own, names those effects with
`(effects: ...)`, since a signature may not claim effects its body never
performs. Each task keeps its handlers across its waits. Reload lets the
loop save and return, then closes the remaining tasks before relinking. Module globals still initialize
synchronously; dispatch application work from the reset binder or the
running entry. See [runtimes](https://tsnl.github.io/snail-scheme/runtimes/index.html).

Frames are built from batches of items. The host keeps a batch until its
version changes, so a still scene costs nothing to send; each item also
carries where it was, and the host moves it toward where it is as the
frame's motion goes from 0 to 1. Batches may be solid, translucent, or
revealed within a growing disc. The camera is perspective or orthographic.

Meshes and sprites are both items, drawn by one shader in the
metallic-roughness model: a `Material` gives an optional texture, the albedo
of a dielectric or the specular color of a metal, with metalness and
roughness defaulting to 0 and 1. Textures are regions of `Picture`s, which
the host composes from layers of encoded image files the program carries,
recoloring each by swapping colors, and keeps until their version changes.
A sprite is a textured quad, standing upright toward the camera in a 2.5D
scene or lying flat under an orthographic camera looking straight down in
a 2D one, and a texture region can be a strip of frames the host steps
through by the clock. `(snail shell sprite)` poses figures from spritebooks of any
sheet, and `src/lpc` uses it for the Liberated Pixel Cup character art.

HUD panels, built from widgets such as those `label` and `button` make,
stack in columns from the screen's corners, appear as dialogs, or sit in a
banner across the top that lets input through but for its links. A widget's
tone can mark it suggested, the control to use next. The host keeps elements
by key, so hover and focus survive updates, and reports presses and hovering
back as input. `recognize` turns raw pointer events into points, taps, drags
and pinches.

[Siegework](https://github.com/tsnl/snail-scheme/tree/main/apps/siegework)
is the complete example, and
[Hearsay](https://github.com/tsnl/snail-scheme/tree/main/apps/hearsay)'s
prototypes draw their residents as LPC characters on a 2D map.

## Document interfaces

`(snail shell ui)` builds interfaces from a page's document rather than a
canvas, in the shape Elm gave them:

| Function | Meaning |
| --- | --- |
| `view : Model -> (Html M)` | A tree of elements and texts. An element's attributes, typed properties (`StringProperty`, `NumberProperty`, `FlagProperty`) and listeners (`On`) are plain data; a listener holds a function from what its event carried to a message `M`. |
| `update : Model M -> (Pair Model (List (FnOnce M ! tasks e)))` | The next model, and the commands the message starts: one-shot work, run as tasks, each answering a message. |

`run-ui model start update view window checkpoint` shows the view in the
document's root through the `dom` effect of `(snail shell dom)`, updates
it with each message in `start`, as when it must ask its server before
anything else happens, then handles one delivery at a time until the
document closes, and answers the last model. The window is no node of the
view's tree, so `window : Model -> (List (Attribute M))` gives its
listeners, for what reaches the whole page, such as a shortcut or the page
going back online, and they are patched as an element's are.
`next-event` delivers a listener's event, a wake, the page hidden, or the
document closed; `checkpoint` is given the model when the page is hidden
and when it closes. Only the interface's own task waits on the document,
so a command posts its answer to the interface's mailbox and performs
`wake`, and the interface drains the mailbox when it is woken; a command
still running when the document closes never answers. After each update
the interface changes only what differs from the tree it showed before. An element keeps its node while its tag and key stay the
same, so the page keeps its focus, selection and scroll; a child with a
`Keyed` attribute is matched by key and one without by its place among the
others without one. Attributes and properties the view leaves out are
cleared, and a listener is made again only when its captures or its
prevention change. Since the host decides both while an event is
dispatched, a listener declares them when it is made: the fields its events
carry (`Capture`) and when the host prevents their default action
(`Prevent`, never, always, or for listed key chords). A listener with
chords hears only them, so the keys it leaves alone never cross into
Snail-Core, and never a key that ends an input method's composition.
Functions stay in Snail-Core: the host sees nodes and listeners only as
handles. A selection's offsets count scalars, as a String's indices do,
though the page counts UTF-16 code units.

A command does what a view cannot say by finding a node by its `id`
attribute with `element-by-id`. It can then focus it, scroll it through
its scroll properties, select a range of it or read its selection
(`selection-range`), insert text into it as typing
would (`insert-text`, which the page can undo and which fires the field's
`input` event, and which answers whether the field took the text), and
`measure` it. A command can run after the view has removed its node, so on
a removed node these do nothing, and reads of it answer "" or 0. `confirm`
asks the person a question and answers whether they agreed. When the view
gives a field a new value, as when another view of its text changed it,
the field keeps its selection and scroll as far as the new text reaches.

`with-memory-dom` from `(snail shell dom memory)` handles `dom` over a
document in memory, delivering a script of cues (events fired at elements
by their `id` or at the window, and the page hidden), and answers the
document it left, as HTML and as a trace of every operation.
`tests/programs/ui-memory.sld`, `tests/programs/ui-patch.sld` and
`tests/programs/ui-commands.sld` run interfaces this way under `make
test`.

`define-ui` from `(snail shell ui page)` hosts an interface in a page as
`define-application` hosts a scene:

```scheme
(define-ui Notes Message
  (init: start)
  (update: update)
  (view: view)
  (window: window)
  (start: (list (Load)))
  (save: save)
  (restore: restore))
```

An interface without window listeners gives `(window: (lambda (model)
(Nil)))`, as an Elm program without subscriptions gives `Sub.none`, and
one without messages to start with gives `(start: (Nil))`. `init` takes
the seed alone, and `update`'s commands are `(Command Msg)`,
which may wait on tasks, reach the document, and ask the server through
the `fetch` effect of `(snail shell fetch)`. `request method url headers
body` answers the server's reply, its status and body, or why there was
none. A stream is the server-sent events of the kinds it names at a URL:
`stream-next` waits for the next, its kind and data, and answers none once
the stream is closed for good. The host connects again when a connection
drops, and a stream that names the kind `error` hears an event each time.
One command waits on a stream at a time, and the update that hears
an event issues the next wait, so a stream needs no machinery beyond
one-shot commands.
The interface boots as an application does, from a handed-over model of
its type, else the stored save, else `init`. It runs `run-ui` as the
page's root task under `with-page-dom` from `(snail shell dom page)` and
`with-page-fetch` from `(snail shell fetch page)`, whose `checkpoint`
stores the save. The page loads `startInterface` from
`ui.mjs`, which a browser build ships, with a container element in place
of the canvas. `host/browser/dom.mjs` keeps the interface's nodes and
listeners in tables by handle and frees a removed node's subtree. A
listener reads what it captures and prevents the default action while
the event is dispatched, then queues the event (kind 14). A `wake` queues
kind 15 from any task. `host/browser/fetch.mjs` runs a request or a stream's next event as a
host operation of the command's own task, and closes every stream when a
program starts. `tests/apps/notes` is the example, and
`tests/browser/ui.mjs` drives it in Chromium against a server of its
own.

*Proposed* ([#514](https://github.com/tsnl/snail-scheme/issues/514)):
periodic saves, and live reload of an interface's page. Today `ui.mjs` loads a release build's
`program.wasm`, and the interface saves only when the page is hidden or
reloads.

<a id="live-reload"></a>

## Hot reload

This section describes the current browser handover. The
[proposed durable reload workflow](#proposed-application-processes) would
carry server and browser data across code replacement through durable
records instead.

`snail dev PROJECT` builds each browser target one library at a time, and
builds it again whenever the project, the standard library or the browser
host changes, compiling only the libraries the change reaches. Each page it
serves ([below](#browser-targets-in-development)) relinks the modules that
changed, and those after them, without reloading. Their globals start over;
the application's state crosses to the new program:

- as it is, when `type-test` finds its type unchanged;
- through `save` and `restore` when its layout changed. That is the
  contract a page reload already relies on, so an application whose save
  is a journal, as Siegework's is, replays the journal under the new code;
- not at all when the save cannot be restored either: the old program
  keeps running, and the page offers to start the new one over.

A failed build is shown over the page, and the old program keeps running.
A changed [linked file](types.md#linked-files) compiles again the library
that links it, whose module names the new bytes' digest, so the page relinks
from that module and reads the new file; a file whose digest is unchanged is
not fetched again. An edit to the file builds again once a published build
links it. A changed
stylesheet is fetched again; a changed page or host script reloads the page
after saving. A public tree holds only regular files and directories
([projects](projects.md)). The
[event and reload boundaries](#event-and-reload-boundaries) below define
checkpoint recovery, acceptance and manifest reconciliation.

Each build runs the producers of generated-library recipes first and
resolves artifact bundles, as every project build does. A program is a
[run target](#development-run-targets), run again from each accepted build.
[The development toolchain](toolchain.md) describes how builds stay this
fast, and the browser editor that subscribes to the same service.

## Task lifetime

The loop is a task of the program's [scheduler](../runtimes/tasks.md).
`app-main` dispatches it through `app-start`, which answers its id, and
the host turns the scheduler until the loop answers: `app-start` records
the answer in a cell of `(snail shell page)`, which the host reads through
the `app_outcome` and `app_handover` exports. A trap whose task is the
loop's, by `tasks:running`, is the loop's failure; any other is a child's,
reported and survived. Normal root completion after initial presentation
lets children finish: the host turns until no task is live. Root failure
or return before that acceptance boundary closes the scheduler, dropping
the remaining tasks. Explicit reload waits for the root's checkpoint
handover before closing it. Repeated stop requests share one handover
result. This is application lifecycle policy; ordinary task completion
does not cancel its children.

Event waits and storage wait by ticket, as any host operation does
([waiting on the host](../runtimes/tasks.md#waiting-on-the-host)). Their
abort signals belong to the run that began the call, and closing the run
aborts them. Non-abortable storage may delay teardown until it finishes.
An old completion wakes nothing in a replacement run.

Only one loop consumes application events. The runtime buffers input and
coalesces frames; it does not own an implicitly shared current world.
The root task owns event consumption, boot acknowledgement and checkpoint
storage. Calling these operations from a detached task fails before any
input or saved bytes change. A child can use task waits and separately bound
I/O, but cannot replace the application's checkpoint while its loop saves.
Read-only seed and canvas dimensions remain available to all tasks.

## Event and reload boundaries

`host/browser/runtime.mjs` owns an invocation's queue and storage bindings;
`host.mjs` retains the canvas, renderer, pictures and HUD across invocations.
DOM listeners enqueue input rather than calling Wasm. Consecutive moves for the
same pointer and consecutive resizes coalesce without crossing other input.
Consuming a pending frame requests the next animation frame, so slow work does
not accumulate ticks. HUD values update at most every 100 milliseconds and
periodic saves occur every five seconds.

Event waits and complete storage operations wait by ticket on the Snail-Core
scheduler. Starting a save copies its borrowed byte argument before the
IndexedDB request begins; a failed persistence operation still leaves an
owned snapshot for migration. GPU drawing currently uses synchronous screen
bindings. No import suspends Wasm, so the linear-memory stack of the Rust
scalar services is never left mid-call.

Reload fences the old queue with `Reload`. Its accepted prefix finishes, the root
saves and returns, and the runtime closes the remaining tasks. New input
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

The reload client (`host/browser/reload.sld`, bound by `reload-client.mjs`) compares
manifests and relinks from the first changed module. It serializes relinks and
keeps only the latest waiting build. A build becomes the page's current build
only after acceptance. Missed events reconcile against the next complete
manifest; a refused build is not retried automatically until the developer
starts over.

## Native application process owner

A supervisor task in `(snail shell project service)` owns one ordinary OS child
for one run target. The development service's HTTP API and editor use it.
The public `snail run` command executes a cold
project build with ordinary shell IO.

The owner accepts a latest launch request `{build, entry, args}` or `null` to stop.
Each non-null request means a fresh attempt. `entry` names the accepted generation
directly, rather than its mutable build-target link: development entries are
`modules.json`, cold entries are `program.wasm`. The owner invokes the existing
runner through `process.execPath` without a shell. It copies arguments and captures
the caller's working directory when constructed; the environment is inherited.
Its stdin is EOF. Interactive execution remains available through `snail run`.

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

### Browser targets in development

`snail dev` serves the project's browser targets on a listener of their
own, the applications' origin: the port after the editor's when `--port`
names one and it is free, otherwise any. The service prints its URL after
the editor's, and the status names each published browser target's `url`.
`/` lists the targets, and `/NAME/` mounts one with
`(snail shell project bundle)`:

| Request | Result |
| --- | --- |
| `/NAME/` | The latest build's `index.html`, with `<base href="/NAME/.snail/builds/EPOCH/">` first, or after its doctype, then the build's manifest and the reload client. |
| `/NAME/.snail/builds/EPOCH/PATH` | `PATH` of that build's generation, while it is retained; 404 after. |
| `/NAME/.snail/builds/.snail-store/sha256/DIGEST` | An object of the store the builds share, where a manifest's `../.snail-store/` resolves; cached for good. |
| `/NAME/.snail/events` | An event stream that tells the target's pages of its builds. |
| `/NAME/.snail/reload.mjs`, `reload.wasm` | The reload client, from the browser host and the development tools. |
| `/NAME/PATH` | `PATH` of the latest build's generation. |

The base pins a page to its build: its scripts, styles and `modules.json`
resolve under that build, and the modules that names in the store beside
the builds, by digest, so a page never links one build's manifest with
another's modules, and loading `/NAME/` again gives the newest build. A
build's files never change. The service keeps
the latest publication and the one before it, so a page loading as a build
lands still finds its own. Everything the server adds lives under
`.snail/`, which a public tree does not use. The origin answers only GET
and HEAD for its own Host, so a page of another site that rebinds a name to
the address reads nothing; it is apart from the editor's, so no project
page can reach the editor's API.

A page served this way reloads as [above](#hot-reload). Its manifest is
`(base BASE) (files (FILE DIGEST) ...) (modules (LIBRARY DIGEST) ...)`: the
build's base, the digest of each of its files but `modules.json`, and each
module, in program order, with the digest of its bytes, which names the
object holding it. The events stream carries `(building M)` while an
attempt is under way, `(built MILLISECONDS M)` when one is published and
`(failed MESSAGE M)` when one fails, each with the manifest `M` of the
target's latest published build; a stream's first event is the current
one, so a page that reconnects hears of the build it missed. The client,
`host/browser/reload.sld`, compares each manifest with the one its page
was built from: it relinks the program from the first module that changed,
reading the new build's `modules.json` under its base, so the program's
later reads come from that build too; it fetches a changed stylesheet again
from the new base; and it reloads the page, after saving, for any other
changed file, which gives the newest build's page.

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

The HTTP bundle helper, `(snail shell project bundle)`, serves a build's files
and pins a page's assets to its build: a request for B never returns C's bytes
([above](#browser-targets-in-development)), and gives each page its build's
manifest; the service's events give a page that reconnects the latest one.
Proposed: keep the server origin stable across restarts, and when B is
unavailable, reconcile and retry using the latest manifest. Network failures and
incompatible stored data are distinct; neither permits clearing data silently.

Advertise a bundle only after its server can serve it, as the service names a
browser target's `url` only once a build of it is published. Multiple
frontends use separate prefixes and manifests. Production serving omits development endpoints.
Compilation does not prove client/server API or durable-schema compatibility.
The editor remains an independent client of development services; application
browser windows are ordinary clients of their server.
