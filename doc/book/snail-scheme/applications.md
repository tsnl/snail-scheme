# Application model

An application is a [script](scripts.md): its `main` asks the page for the
capabilities it uses and hands control to an engine's loop. The engine is a
library, in the style of Rust's
[winit](https://github.com/rust-windowing/winit): the script builds a
handler, a record of the application's functions, and calls the engine with
it.

Siegework's script, `src/apps/siegework/main.scm`, is the whole of it:

```scheme
{{#include ../../../src/apps/siegework/main.scm}}
```

```sh
./snail-scheme build --target browser src/apps/siegework/main.scm
```

On the page, the host calls the script's start with a scheduler, as every
host does, and (snail target browser) runs `main` as its first task, with
the page's capabilities ([targets](scripts.md#targets-and-capabilities)).
`main` can wait: `run-scene` waits for the page's events as a task does. There are two engines, `run-scene` for a canvas and `run-interface`
for a document, and both boot and save through `run-page` from
`(snail shell page)`. An application with its own loop calls `run-page`
itself, as `tests/apps/requests` does. IPC remains outside this contract.
Typed session protocols are future library work.

## Scenes

`(snail shell app)`'s `SceneHandler` holds a scene's pure functions over
immutable state, and the two that draw it, which keep a drawing state of
their own:

| Field | Meaning |
| --- | --- |
| `initialize : seed width height -> State` | The first state. |
| `update : State Input -> State` | Applies a key, pointer, HUD button, screen size, or elapsed milliseconds. |
| `start : -> Drawing` | The drawing state of a fresh page or module. |
| `draw : State Drawing -> Drawing` | Draws a frame through `gpu`, and answers what drawing keeps for the next. |
| `hud : State -> (List Panel)` | Panels of labels, texts, buttons, dials, links and images. |
| `image-url : Drawing Key -> String` | The address of the image an `Image` widget names, or `""` until there is one. |
| `save : State -> Bytes` | Encodes the durable state, often a record of how to rebuild the full state. |
| `restore : Bytes -> State` | Decodes the durable state and reconstructs the running state. |

The drawing state is never saved: it holds what drawing keeps between
frames, such as an atlas and the portraits read back from it, and starts
again with each page and each module, as the GPU's objects do.

Serialization is chosen explicitly by the application; these examples use
`(snail shell wire)`.

`run-scene` takes the page's `Dom`, `Events` and `PageStorage` and the
handler, whose `draw` closes over the `Gpu` the script was given; it waits
as a task, and never returns. `next-event` drains the host queue, then waits by ticket when it is
empty. `FrameEvent` carries elapsed milliseconds; `InputEvent` carries an
`Input`. `Hidden` and `SaveRequested` save without stopping. A shared
five-second host timer supplies `SaveRequested` to either engine, so saving
does not require animation frames. The host arms it at boot and after each save.

The engine reports readiness after its first complete frame. Since elapsed
time is input, the application decides how its simulation advances. Each task
keeps what it closed over across waits. Libraries have no runtime initialization;
application state is created by the running script.

For a fixed presentation rate, create a `frame-pacer` with the desired frames
per second and call `pace-frame!` with each `FrameEvent`’s elapsed milliseconds.
It returns `(Some elapsed)` on a display slot and `(None)` between slots. The
first slot reports zero. A long stall skips missed slots. Simulation can still
advance on every refresh. The browser derives elapsed milliseconds from
successive rounded display timestamps so fractional intervals add up.

A scene draws with the [graphics libraries](../graphics/plan.md). Hearsay
composes the pictures it needs into an atlas and draws its map as one run
of quads ([Atlas and quads](../graphics/plan.md#atlas-and-quads)).
`(snail shell sprite)` picks the cell a spritebook of any sheet shows for a
motion, heading and moment, which a quad then draws, and `src/lpc` uses it
for the Liberated Pixel Cup character art.

Siegework builds a 3D `Frame` from batches of mesh items, which
`draw-frame` draws, keeping in its `Frames` each batch's packed instances
until the batch's version changes, so a still scene packs nothing. Each
item also carries where it was, and moves toward where it is as the
frame's motion goes from 0 to 1. Items are matte, lit by the sun and the
ambient light, and glow from 0, lit, to 1, their own color. Batches may be
solid, translucent, or revealed within a growing disc. The camera is
perspective or orthographic.

HUD panels, built from widgets such as those `label` and `button` make,
stack in columns from the screen's corners, appear as dialogs, or sit in a
banner across the top that lets input through but for its links. A widget's
tone can mark it suggested, the control to use next. The HUD is a tree in
the page's document: the scene's loop builds it as `(snail shell ui)`'s
`Html` and changes the document through its `Dom` only where the tree
differs from the one before, so an element keeps its node while its key
stays, and with it hover and focus. A button's listeners make the presses
and hovering the scene's `update` takes as input; a button removed while the
pointer is over it reports the pointer gone. An image shows the image the
scene's `image-url` gives the address of; Hearsay's portraits are regions
of its atlas read back as PNG data URLs. `recognize` turns raw pointer events into points, taps, drags
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
| `update : Model M -> (Pair Model (List (Fn → M)))` | The next model, and the commands the message starts: work run as tasks, each answering a message. |

`run-ui dom model start update view window commit checkpoint` shows the view in the
document's root through `dom`, a `Dom` of `(snail shell dom)`, updates
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
so a command posts its answer to the interface's mailbox and wakes the
document, and the interface drains the mailbox when it is woken; a command
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
application holding the page's `Dom` can invoke them. Every browser target
also receives the default manifest and icons during packaging, unless it
supplies its own manifest. An application chooses its own installation button
or command; the packager does not inject controls into it.

The scalar declarations in `(snail runtime browser dom)` define the browser
boundary. `(snail shell dom page)` converts their results into typed values and
task completions; `host/browser/install.mjs` retains the browser's opaque offer
and calls its native APIs. Scheme code owns application behavior, and Chromium
tests cover the browser decisions that the memory DOM cannot make.

The same `Dom` exposes browser window capabilities. `installation-status`
reports an available installation offer, an installed/standalone app, or no offer.
`install-app` awaits a single-use offer and returns accepted, dismissed,
unavailable, expired activation, failed, or already installed. Acceptance does not
mean the later `appinstalled` event has arrived. The host retains the opaque offer
across application generations; an expired activation leaves it available for a
new explicit click. `fullscreen?` reads the current mode, and `set-fullscreen`
awaits entering or leaving it, returning whether the request succeeded. Both
requests use task tickets, with no suspended Wasm stack. Stopping a generation
releases its wait even if the browser dialog remains open. The memory `Dom`
reports unavailable installation and refuses fullscreen.

`with-memory-dom` from `(snail shell dom memory)` hands its work a `Dom` over a
document in memory, delivering a script of cues (events fired at elements
by their `id` or at the window, and the page hidden), and answers the
document it left, as HTML and as a trace of every operation.
`tests/programs/ui-memory.sld`, `tests/programs/ui-patch.sld` and
`tests/programs/ui-commands.sld` run interfaces this way under `make
test`.

`run-interface` from `(snail shell ui page)` runs a document application
from an `InterfaceHandler`:

```scheme
(run-interface dom fetch events storage
               (new InterfaceHandler
                 (initialize new-notes) (update update) (view view) (window window)
                 (messages (lambda (model) (list (Load))))
                 (save (lambda (model) (serialize (save model))))
                 (restore (lambda (bytes) (restore (deserialize bytes))))))
```

An interface without window listeners returns `(Nil)` from `window`; one
without startup messages returns `(Nil)` from `messages`. Initialization takes
the seed alone, and update's commands are `(Command Message)`, functions
of the page's `Dom` and `Fetch`, which the loop hands each one: a command
may wait as a task, reach the document, and ask the server through the
`Fetch` of `(snail shell fetch)`. `request method url headers
body` answers the server's reply, its status and body, or why there was
none. A stream is the server-sent events of the kinds it names at a URL:
`stream-next` waits for the next, its kind and data, and answers none once
the stream is closed for good. The host connects again when a connection
drops, and a stream that names the kind `error` hears an event each time.
One command waits on a stream at a time, and the update that hears
an event issues the next wait, so a stream needs no machinery beyond
one-shot commands.
The shared page lifecycle restores saved bytes; only a start without a save
initializes a fresh model. The engine runs `run-ui` over the `Dom` it is
handed and gives commands the `Fetch`, which a page's `main` asks its
target for.
A completed presentation acknowledges startup; the shared saver stores the
encoded model.
The page loads `startInterface` from
`ui.mjs`, which a browser build ships, with a container element in place
of the canvas. `host/browser/dom.mjs` keeps the interface's nodes and
listeners in tables by handle and frees a removed node's subtree. A
listener reads what it captures and prevents the default action while
the event is dispatched, then queues the event (kind 14). A `wake` queues
kind 15 from any task. `host/browser/fetch.mjs` runs a request or a stream's next event as a
host operation of the command's own task, and closes every stream when a
program starts. `tests/apps/notes/main.scm` is the example, and
`tests/browser/ui.mjs` drives it in Chromium against a server of its
own.

Both `ui.mjs` and the scene's `host.mjs` delegate loading to
`host/browser/application.mjs`. Document applications support periodic
saves, as scenes do.

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
Its `Save` contains only display data and a click count. Its script calls
`run-requests` with the page's `Dom` and `Fetch`, which runs `run-page` over
the `Save` itself and calls `run-ui`. Its commit callback calls `report-ready`;
the checkpoint callback comes from `run-page`.

Only `Save` crosses a reload. A command still running when the page goes
never answers the next page. Restore decides whether interrupted work should
be restarted; the example shows an interrupted request as such.

`tests/browser/ui-requests.mjs` holds server replies while input
continues, verifies that a canceled request cannot install a late reply,
and saves and reloads while a request is pending. The next page restores
its save and can request again. `tests/programs/ui-checkpoint-wait.sld`
runs a command that finishes while a checkpoint waits, over the memory
DOM.

## Task lifetime

The script is the first task of the program's
[scheduler](../runtimes/tasks.md). The host creates a scheduler, passes it to
the program's `main`, and turns it until no task is live or one fails. A trap
in any task fails the run and closes the scheduler; `tasks:running`
identifies the failing task for the report. An engine's loop never returns,
so a page runs until it is left or traps.

Event waits and storage wait by ticket, as any host operation does
([waiting on the host](../runtimes/tasks.md#waiting-on-the-host)). Their
abort signals belong to the run that began the call, and closing the run
aborts them.

One loop consumes the page's events. The runtime buffers input and
coalesces frames; it does not own an implicitly shared current world. Seed
and canvas dimensions are available to all tasks.

## Event and save boundaries

`host/browser/runtime.mjs` owns a run's queue and storage bindings;
`application.mjs` owns loading and the start without an unreadable save.
`host.mjs` retains the scene devices and gives the HUD the page's overlay as
its document, while `ui.mjs` resets the document and fetch devices for each
run. DOM listeners enqueue input rather than calling
Wasm. Consecutive moves for the same pointer and consecutive resizes coalesce
without crossing other input. Consuming a pending frame requests the next
animation frame, so slow work does not accumulate ticks. HUD values update at
most every 100 milliseconds and periodic saves occur every five seconds.

Event waits and complete storage operations wait by ticket on the
`snail-scheme` scheduler. Starting a save copies its byte argument before the
IndexedDB request begins; a failed save is a warning, and the page keeps
running. GPU drawing waits only to request the device, decode an image or read a
buffer back, by ticket. No import suspends Wasm, so the linear-memory stack of the Rust scalar services is
never left mid-call.

The engine acknowledges its first completed presentation: a scene handles
resize and a zero-time frame, while a document presents its initial model
and startup messages. Input sent before then is delivered after it.

A save the application cannot read traps before the page boots; the page
then starts again without it. A trap after boot ends the page, which keeps
its last save: up to five seconds of work, or what happened since the page
was last hidden, is lost. Keep state that must survive a reload in the
application's Save.

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
