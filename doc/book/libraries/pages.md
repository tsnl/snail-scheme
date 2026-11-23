# Pages, documents and interfaces

A page's program is either a **scene**, drawn on a canvas each frame with a
HUD of document panels beside it (`(snail shell app)`), or a **document
interface**, a tree of elements kept equal to a view of its model
(`(snail shell ui)`). Both run on `(snail shell page)`, which owns the
page's events and its save. The [application model](../snail-scheme/applications.md)
describes both in full.

The capabilities a page offers each come in two or three libraries: one
declares the capability, a `page` library makes it over the browser host,
and for the document a `memory` library makes one with no page at all, for
tests.

## `(snail shell page)`

What every page program shares: `Events`, the host's queue of input and
lifecycle events (`host-events`); `PageStorage`, the page's one save
(`host-storage`, `load-save`); and `run-page`, which boots from that save,
or fresh, and saves on request. An event is a kind and fields of `I32`; the
kinds a display frame, the page hidden and a save's timer are the host's
own (`hidden-kind`, `save-kind`), and each program numbers the rest. A trap
ends the page, which keeps its last save.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/page.sld)

## `(snail shell app)`

Canvas applications. An application is pure functions over its state:
`init`, `update` over each `Input`, `save` and `restore`, and `start` and
`draw` with a drawing state of their own, which holds what drawing keeps
between frames, such as an atlas, and is never saved. `hud` answers the
`Panel`s of document widgets beside the canvas. A `SceneHandler` holds the
eight, and `run-scene` runs one. Time is an input, so the state decides how
its simulation advances, and a save may be much smaller than the state: a
record of how to rebuild it.

A scene draws through its `Gpu`, itself or as a 3D `Frame` of mesh `Item`s
in batches, which `draw-frame` rasterizes and lights
(`(snail shell graphics raster)`), as Siegework does; a 2D scene draws
pictures as quads from an atlas, as Hearsay does. `recognize` turns pointer
events into `Gesture`s (tap, drag, pinch), and `pointer-ray`,
`screen-axes` and `ground-point` map the pointer into the scene. The HUD is
changed through the page's document only where it differs after each input,
and after time at most ten times a second
([scenes](../snail-scheme/applications.md#scenes)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/app.sld)

## `(snail shell ui)`

Document interfaces in the shape Elm gave them: a model, a `view` from it to
a tree of `Html`, and an `update` from the model and a message to the next
model and the commands it starts. `run-ui` shows the tree through a `Dom`,
and after each update changes only what differs, so a node keeps its
identity, and the focus, selection and scroll the page gave it, as long as
the view keeps it. A listener holds a function from what its event carried
to a message, which stays in `snail-scheme`; the host sees only the
listener's id. A command is work run as a task, whose answer is a message
posted to the interface's mailbox. The window's listeners are a list the
model gives, since the window is no node of the tree.

A program with a loop of its own, as a scene's HUD has, shows trees itself:
`patch-children` keeps a node's children equal to a list of trees, and
`listener-table` finds the function of a listener that fired
([document interfaces](../snail-scheme/applications.md#document-interfaces)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/ui.sld)

## `(snail shell ui page)`

`InterfaceHandler` and `run-interface`, a document application's loop on
the page: it makes the page's document and fetch, runs `run-ui` over them,
and hands them to each `Command`.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/ui/page.sld)

## `(snail shell dom)`

A document as the capability `Dom`: the primitives an interface needs to
build and change it. A `Node` is a handle the host keeps in a table, so no
host object crosses into `snail-scheme` and no closure crosses out. A
listener says when it is made what its events carry (`Capture`) and when the
host prevents their default action (`Prevent`), since the host decides both
synchronously, while the event is dispatched; a listener with `Chords`
hears only those keys. Commands find nodes by `id` to focus, select, insert
text undoably and `measure`; on a node the view has removed they do
nothing, as on a page. `next-event` waits for the next `Delivery`: a
listener `Fired`, `Woken` by another task's `wake`, a `SaveRequested`, the
page `Hidden`, or the document `Closed`.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/dom.sld)

## `(snail shell dom page)`

`page-dom` makes the page's `Dom` from a `Host`, bound to the browser host's
document (`host/browser/dom.mjs`), which keeps the interface's nodes and
listeners by handle under the container the page gives it. A page's
document never closes.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/dom/page.sld)

## `(snail shell dom memory)`

`with-memory-dom` hands its work a `Dom` over a document in memory, which
delivers a script of `Cue`s (`Fire`, `FireWindow` and `Hide`), and answers
the work's value with the document it left: `document->html` prints its
tree, and `document-trace` lists every operation. It is strict where a page
would forgive: a removed node or listener used again, a node inserted into
itself, or a key fired at a listener that does not hear it is a panic, so
an interface's tests catch what a page would hide. As a page delivers only
between tasks, each delivery waits until every other ready task has run.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/dom/memory.sld)

## `(snail shell fetch)`

Requests to a server and the events it streams, as the capability `Fetch`,
so an interface's commands can ask and a test can answer for the server:
`request` answers a `Reply` or why there was none, `fetch-bytes` a GET's
body, and a stream of server-sent events is opened, read event by event as
`StreamEvent`s, and closed.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/fetch.sld)

## `(snail shell fetch page)`

`page-fetch` makes the page's `Fetch` over its `fetch` and `EventSource`
(`host/browser/fetch.mjs`). A request or a stream's next event waits in the
task that asked, so a command's request never holds up the interface.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/fetch/page.sld)

## `(snail shell files)`

Files the user hands the program, dropped on the page or chosen with its
pickers, as the capability `FilePicker`: each file is its path within what
was `Chosen` and an address a `Fetch` reads its bytes from. The user
chooses and the program only asks, so a program reads no file it was not
given. `open-picker` asks for `SomeFiles` or a `Folder` and returns at
once; a choice arrives as an event (`FilesEvent` in `(snail shell app)`),
and `chosen-files` lists it. A link dropped on the page is a file whose
path is its address.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/files.sld)

## `(snail shell files page)`

`page-file-picker` makes the page's `FilePicker` over its pickers and drops
(`host/browser/files.mjs`).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/files/page.sld)

## `(snail shell png)`

`rgba->png` writes RGBA pixels as a PNG file, and `png-data-url` as a data
URL an `img` element shows, as a HUD shows a portrait the program drew. The
pixels are stored in zlib's stored blocks, uncompressed: they need no
search, and the images written are small.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/png.sld)

## `(snail shell sprite)`

Spritebooks: animations on a picture of equal cells, by motion and heading.
`heading` picks the heading a viewer should see, and `cell-at` the cell a
`Strip` shows at a moment, which a quad then draws. Nothing here knows a
particular sheet: a sheet's own library, such as `(lpc layout)`, says which
cells each motion uses and in which order the sheet draws its headings.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/sprite.sld)
