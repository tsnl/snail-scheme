# Application model

`(snail shell application)` defines one ordinary, effect-polymorphic entry
contract:

```scheme
(record (Entry A) ())
(typeclass (Application e A)
  (declare (start (entry (Entry A))) (→ Unit) (! e)))
```

`Entry` is an empty type witness. Selecting an application does not require
constructing its state: `start` creates that state and runs the program. A
console application can implement the class directly, perform `output-port` and task
effects, and return when it is done. Custom handlers and background tasks belong
inside `start`. There is no reset binder or separate declaration of entry effects.

A [project](projects.md) selects an exported concrete type, including an alias:

```scheme
((build-target site
   (browser
    (entry ((apps siegework application) Siegework))
    (library-roots ("src"))
    (public "public"))))
```

The builder generates an ordinary import and a typed `start` call. The compiler's
usual instance resolution checks that the selected type implements `Application`
and determines its effect row. A program target calls `start` directly. A browser
target uses `define-page-entry` from `(snail shell page)` to dispatch it as the
root task and expose the host handover functions. Source-file entries remain
available for scripts and tooling.

Engines express richer contracts as ordinary classes. `Scene State` and
`Interface Model` provide scene and document callbacks; the generic
`SceneApplication State` and `InterfaceApplication Model` adapters implement
`Application`. These are ordinary instances, not a compiler-specific superclass
rule. Each engine calls its class methods directly; it has no second API for
supplying those same methods as callbacks. Both engines use `run-page` for boot,
save and restore, and commit immutable checkpoints through `commit-page`. IPC
remains outside this contract. Typed session protocols are future library work,
expressed through effects rather than additional `Application` methods.

## Scenes

`(snail shell app)` describes a scene with pure methods over immutable state:

| Method | Meaning |
| --- | --- |
| `scene-initialize : seed width height -> State` | The first state. |
| `scene-update : State Input -> State` | Applies a key, pointer, HUD button, screen size, or elapsed milliseconds. |
| `scene-view : State -> Frame` | Drawing data: items, meshes and sprites under a camera and light. |
| `scene-hud : State -> (List Panel)` | Panels of labels, texts, buttons, dials, links and images. |
| `scene-save : State -> Bytes` | Encodes the durable state, often a record of how to rebuild the full state. |
| `scene-restore : Bytes -> State` | Decodes the durable state and reconstructs the running state. |

An application library exports an alias and implements the engine's class:

```scheme
(type GameApplication (SceneApplication Game))
(define-page-state Game)
(instance (Scene Game)
  (define scene-initialize (lambda (seed width height) (new-game seed width height)))
  (define scene-update (lambda (game input) (step game input)))
  (define scene-view (lambda (game) (draw game)))
  (define scene-hud (lambda (game) (panels game)))
  (define scene-save (lambda (game) (serialize (save-game game))))
  (define scene-restore (lambda (bytes) (restore-game (deserialize bytes)))))
```

`define-page-state` supplies ordinary `PageState` evidence for packing and
unpacking this concrete state at the host's opaque `Any` boundary. It preserves
the compiler's checks on reification; it does not permit hidden effectful values
to cross that boundary. Serialization is
chosen explicitly by the application; these examples use `(snail shell wire)`.

The scene engine performs `mut`, `screen`, `events`, `storage` and `tasks`.
`next-event` drains the host queue, then waits by ticket when it is empty.
`FrameEvent` carries elapsed milliseconds; `InputEvent` carries an `Input`.
`Hidden` and `SaveRequested` save without stopping, and `Reload` saves and returns.
A shared five-second host timer supplies `SaveRequested` to either engine, so
saving does not require animation frames. `snail-scheme` rearms it after each save.

Only a complete successful presentation commits the next state. A trap leaves
the preceding checkpoint available through `app_state`. The engine reports
readiness explicitly after its first complete frame. Since elapsed time is
input, the application decides how its simulation advances. Each task keeps its
handlers across waits. Libraries have no runtime initialization;
application state is created by the running entry.

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

[Siegework](https://github.com/tsnl/snail-scheme/tree/main/src/apps/siegework)
is the complete example, and
[Hearsay](https://github.com/tsnl/snail-scheme/tree/main/src/apps/hearsay)'s
prototypes draw their residents as LPC characters on a 2D map.

## Document interfaces

`(snail shell ui)` builds interfaces from a page's document rather than a
canvas, in the shape Elm gave them:

| Function | Meaning |
| --- | --- |
| `view : Model -> (Html M)` | A tree of elements and texts. An element's attributes, typed properties (`StringProperty`, `NumberProperty`, `FlagProperty`) and listeners (`On`) are plain data; a listener holds a function from what its event carried to a message `M`. |
| `update : Model M -> (Pair Model (List (Fn → M ! tasks e)))` | The next model, and the commands the message starts: work run as tasks, each answering a message. |

`run-ui model start update view window commit checkpoint` shows the view in the
document's root through the `dom` effect of `(snail shell dom)`, updates
it with each message in `start`, as when it must ask its server before
anything else happens, then handles one delivery at a time until the
document closes, and answers the last model. The window is no node of the
view's tree, so `window : Model -> (List (Attribute M))` gives its
listeners, for what reaches the whole page, such as a shortcut or the page
going back online, and they are patched as an element's are.
`next-event` delivers a listener's event, a wake, a save request, the page
hidden, or the document closed. `commit` receives each successfully presented
model; `checkpoint` persists it on a save request, hiding, and close.
Only the interface's own task waits on the document,
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
`snail-scheme`, and never a key that ends an input method's composition.
Functions stay in `snail-scheme`: the host sees nodes and listeners only as
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

Browser installation and fullscreen are shared `snail-scheme` capabilities. Any
application using `(snail shell dom)` with the page handler can invoke them. Every browser target
also receives the default manifest and icons during packaging, unless it
supplies its own manifest. An application chooses its own installation button
or command; the packager does not inject controls into it.

The scalar declarations in `(snail runtime browser dom)` define the browser
boundary. `(snail shell dom page)` converts their results into typed values and
task completions; `host/browser/install.mjs` retains the browser's opaque offer
and calls its native APIs. Scheme code owns application behavior, and Chromium
tests cover the browser decisions that the memory DOM cannot make.

The same `dom` effect exposes browser window capabilities. `installation-status`
reports an available installation offer, an installed/standalone app, or no offer.
`install-app` awaits a single-use offer and returns accepted, dismissed,
unavailable, expired activation, failed, or already installed. Acceptance does not
mean the later `appinstalled` event has arrived. The host retains the opaque offer
across application generations; an expired activation leaves it available for a
new explicit click. `fullscreen?` reads the current mode, and `set-fullscreen`
awaits entering or leaving it, returning whether the request succeeded. Both
requests use task tickets, with no suspended Wasm stack. Stopping a generation
releases its wait even if the browser dialog remains open. The memory handler
reports unavailable installation and refuses fullscreen.

`with-memory-dom` from `(snail shell dom memory)` handles `dom` over a
document in memory, delivering a script of cues (events fired at elements
by their `id` or at the window, and the page hidden), and answers the
document it left, as HTML and as a trace of every operation.
`tests/programs/ui-memory.sld`, `tests/programs/ui-patch.sld` and
`tests/programs/ui-commands.sld` run interfaces this way under `make
test`.

`Interface` from `(snail shell ui page)` gives a document application its
ordinary `Application` implementation:

```scheme
(type NotesApplication (InterfaceApplication Notes))
(define-page-state Notes)
(instance (Interface Notes)
  (type Message NoteMessage)
  (define interface-initialize (lambda (seed) (new-notes seed)))
  (define interface-update (lambda (model message) (update model message)))
  (define interface-view (lambda (model) (view model)))
  (define interface-window (lambda (model) (window model)))
  (define interface-messages (lambda (model) (list (Load))))
  (define interface-save (lambda (model) (serialize (save model))))
  (define interface-restore (lambda (bytes) (restore (deserialize bytes)))))
```

`Message` is an associated type of the model's instance. An interface without
window listeners returns `(Nil)` from `interface-window`; one without startup
messages returns `(Nil)` from `interface-messages`. Initialization takes the seed
alone, and update's commands are `(Command Message)`,
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
The shared page lifecycle first adopts a handed-over model of its type, otherwise
restores saved bytes. Only a cold start without a save initializes a fresh model.
The engine runs `run-ui` as the page's root task under `with-page-dom` from
`(snail shell dom page)` and
`with-page-fetch` from `(snail shell fetch page)`. Completed presentations commit
the model and acknowledge startup; the shared saver stores the encoded model.
The page loads `startInterface` from
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

Both `ui.mjs` and the scene's `host.mjs` delegate loading to
`host/browser/application.mjs`. Document applications support development modules
and periodic saves as scenes do.

### Commands and late replies

A command's answer is an ordinary message, so an interface sees a reply
when it arrives and decides then what it still means. Nothing cancels a
command: a reply that is no longer wanted still arrives, and the update
ignores it, telling current replies from stale ones by what the message
carries.

`tests/apps/requests/src/requests/application.sld` is a complete example.
Its `Model` numbers the requests it makes. `Load` starts the next
number's request as a command, which answers `Loaded` with that number
and the reply, and an update shows a reply only if it carries the latest
number. `Cancel` moves the number on, so a reply that arrives after it,
or after a newer `Load`, is ignored; the request itself runs to its end.
Its `Save` contains only display data and a click count. The ordinary
`Application` instance uses `run-page`, installs DOM and fetch handlers,
and calls `run-ui`. Its commit callback calls `commit-page` and
`report-ready`; the checkpoint callback comes from `run-page`.

Only detached `Save` crosses a restart or handover. Mutable fields make
this an application responsibility: a snapshot must not retain mutable
model storage that later updates can change. A command still running
belongs to the old scheduler and never answers the replacement. Restore
decides whether interrupted work should be restarted; the example shows
an interrupted request as such.
A view or update trap leaves the preceding committed Save available to recovery.

`tests/browser/ui-requests.mjs` holds server replies while input
continues, verifies that a canceled request cannot install a late reply,
and refreshes while a request is pending. The replacement restores its
snapshot and can request again. `tests/programs/ui-checkpoint-wait.sld`
runs a command that finishes while a checkpoint waits, over the memory
DOM.

## Task lifetime

The loop is a task of the program's [scheduler](../runtimes/tasks.md).
The host creates a scheduler and a `PageRun` context, then passes both to
`app_main`. It dispatches the entry through `start-page`, which answers its id.
The host turns that scheduler until the root returns or fails. `(snail shell page)`
exposes `app_done` to distinguish a successful return from suspension or an
invalid disappearance, and `app_state` for the optional checkpoint. Normal
return and failure use that same checkpoint; a root that never adopts state
has none. Completion and presentation readiness are independent. A trap in
any task fails the run and closes the scheduler; `tasks:running` identifies
the failing task for the report. Normal root completion after initial presentation
lets children finish: the host turns until no task is live. Root failure
or return before that acceptance boundary closes the scheduler, forgetting
the remaining tasks. Stopping waits for the root's checkpoint
handover before closing it. Repeated stop requests share one handover
result. This is application lifecycle policy; a task finishing does not
stop its children.

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

## Event and save boundaries

`host/browser/runtime.mjs` owns an invocation's queue and storage bindings;
`application.mjs` owns loading and the replacement transaction. `host.mjs` retains
the scene devices, while `ui.mjs` resets the document and fetch devices for each run.
DOM listeners enqueue input rather than calling Wasm. Consecutive moves for the
same pointer and consecutive resizes coalesce without crossing other input.
Consuming a pending frame requests the next animation frame, so slow work does
not accumulate ticks. HUD values update at most every 100 milliseconds and
periodic saves occur every five seconds.

Event waits and complete storage operations wait by ticket on the `snail-scheme`
scheduler. Starting a save copies its byte argument before the
IndexedDB request begins; a failed persistence operation still leaves an
owned snapshot for migration. GPU drawing currently uses synchronous screen
bindings. No import suspends Wasm, so the linear-memory stack of the Rust
scalar services is never left mid-call.

Stopping fences the queue with `Reload`. Its accepted prefix finishes, the root
saves and returns, and the runtime closes the remaining tasks. The engine
explicitly acknowledges its first completed presentation: a scene handles resize
and a zero-time frame, while a document presents its initial model and startup
messages.

After a trap, `app_state` exposes the last complete checkpoint. Serializing it
runs the old entry in handover-only mode: the shared page lifecycle saves it
without entering either engine, avoiding a failing view or replayed startup messages.
The consumed failing event is dropped; unread input remains. A cold first-frame
failure also retains its owner so a source fix can resume it.
A closure kept in the state can retain old code; applications storing functions
must reconstruct them through save/restore when changing their implementation.
There are no global value caches to migrate. Keep state that must survive
a page reload in the application's Save.

<a id="proposed-application-processes"></a>

## Proposed durable state

Durable application data remains
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
