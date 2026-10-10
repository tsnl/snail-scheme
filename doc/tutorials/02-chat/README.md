# A chat application in two places

Build a chat room with persistent history and two browser clients. Posting in one
tab updates the other. The server runs native Scheme, the browser runs Scheme
compiled to WASM, and a database service retains the messages. Package the whole
application as a library another project can configure and build.

**Status: project specification, not a runnable tutorial yet.** Proposed names
illustrate the [actor model](../../why-snail-scheme.md); the
[acceptance criteria](requirements.md) are the completion contract. The existing
[Chibi workbook](../../ui.md) is a useful first checkpoint, but it executes the
application on the server and does not satisfy browser execution here.

## 1. Describe the conversation with types

Define records for a draft, an accepted post, and room events. Give them stable
type identities and typed fields: a draft has a client operation ID, room ID,
and text; an accepted post adds a server sequence and author. Derive S-expression
codecs from these definitions and derive method interfaces from their argument,
result, and stream-item types.

The declarations below describe required interfaces, not a second source schema:

| Actor | Exposed method | Input and result |
| --- | --- | --- |
| Chat server | `post-message` | A `draft` becomes an accepted `post`, or a service error. |
| Chat server | `watch-room` | A room/cursor request becomes a stream of `room-event` records. |
| Chat store | `append` | An authenticated draft becomes a durably accepted post. |
| Chat store | `watch` | A room/cursor request becomes an ordered stream with replay. |
| Browser | Host input and room-event handlers | Typed events update a local model and DOM. |

These are ordinary exported functions. A `room-event` variant definition can
group posts and membership changes; the same metadata drives matching and codec
generation. R7RS's `define-record-type` supplies neither typed fields nor that
union facility by itself. The extension's syntax remains to be designed, but
there must be no hand-maintained encoder schema alongside the records.

**Checkpoint C01:** round-trip every message and result over local and WebSocket
connectors. Reject an unknown type/version, malformed value, or excessive payload
before handler dispatch. The decoder parses data; it never evaluates it.

## 2. Make a page from a model

Keep the application model, reducer, and view as ordinary Scheme. A browser-local
draft and the current room snapshot can live in the browser actor; persisted chat
history belongs to the store. Components are functions that return trees, without
`use-state` slots or component-owned lifecycle machinery.

```scheme
;; Proposed chat view, using the existing element/fragment composition direction.
(define (post-view post)
  (element 'li '()
           (element 'strong '() (post-author post))
           (post-text post)))

(define (room-view model)
  (element 'main '()
           (element 'h1 '() (room-title model))
           (apply fragment (map post-view (room-posts model)))
           (composer (room-draft model))))
```

The composer turns input into typed reducer messages. Treat user text as text,
not trusted HTML. Evaluate the view once for a static archive or initial HTML;
evaluate it after updates for an interactive page. The DOM adapter performs
updates while retaining input focus and selection. Generic tree composition
remains useful for other backends.

**Checkpoint C02:** render the same snapshot statically under Chibi and
interactively in a browser. First establish this functional API without a custom
reader. Keep its reusable library separately readable from the application.

## 3. Author both sides together, ship them separately

An authoring source can contain explicit server and browser library definitions.
The build selects each root and its imports; server dependencies cannot leak into
the browser through source adjacency. This multi-library source container is
planned loader/staging work. Separate `.sld` files remain an equivalent option.

```scheme
;; chat.scm -- proposed multi-target authoring sketch.
(define-library (chat server)
  (export started post-message watch-room)
  (import (scheme base) (snail actors) (chat server-support))
  (begin
    (define store #f)
    (define (started dependencies)
      (set! store (connect (dependency dependencies 'history)
                           'chat-store/v1)))
    (define (post-message draft)
      (invoke store 'append (authenticate-draft draft)))
    (define (watch-room request)
      (invoke store 'watch (authorize-room request)))))

(define-library (chat browser)
  (export mounted submit received)
  (import (scheme base) (snail actors) (chat browser-support))
  (begin
    (define server #f)
    (define (mounted configuration)
      (set! server (connect (chat-address configuration) 'chat/v1))
      (subscribe-room server (initial-room configuration)))
    (define (submit draft)
      (invoke server 'post-message draft))
    (define (received event)
      (dispatch-and-render event))))
```

`subscribe-room` obtains the `watch-room` stream and arranges delivery to
`received`; the browser host owns that subscription's scheduling and cleanup.
The server's stream result is relayed through its own connection, not returned
as a pointer to the store's stream object. Authentication is a server-library
operation using the connector's authenticated session context, not a trusted
author field supplied by the browser. The UI reducer itself remains pure.

The host invokes `started` or `mounted` as specified by each actor definition.
Neither actor contains its own event loop. A suspended append must not prevent
other connections from being serviced. Server-local connection globals are not
the durable chat database and are not shared across server instances.

**Checkpoint C03:** build a native server and browser WASM from explicit roots
in the same source. Two real tabs execute their own reducer and DOM work. Show
the browser artifact being loaded and a browser-local edit while disconnected;
a server-rendered page with JavaScript action URLs does not meet this checkpoint.

## 4. Separate discovery, connection, and ownership

The build exports an application description with named server/browser targets,
a `chat-store/v1` requirement, and a recipe for discovering it. Configuration
chooses a local test provider, a native persistent provider, or a remote service.
The compiler checks known interface compatibility and emits a dependency manifest;
the runtime resolves live addresses and authenticates connections.

```scheme
;; Proposed build.scm excerpt: ordinary library functions construct the recipe.
;; The build runtime invokes this exported handler once.
(define (build configuration)
  (application
    (list (actor-target 'server '(chat server) 'native)
          (actor-target 'browser '(chat browser) 'wasm32-browser))
    (list (service-requirement 'history 'chat-store/v1
                              (discovery-config configuration 'history)))))
```

These constructors produce descriptions. The build service resolves target
dependencies and publishes the completed native/WASM artifacts and manifest before
reporting success. The history requirement is runtime configuration, not a request
to connect to the production database during compilation.

| Build output | Runtime responsibility |
| --- | --- |
| Native server artifact and its exported contract | Spawn the root and provide its configured bindings. |
| Browser WASM, DOM adapter, initial HTML, and assets | Serve/load the browser actor, then establish its backend connection. |
| History service requirement and discovery recipe | Find an instance, validate its protocol, and obtain environment-owned credentials. |
| Schema/interface fingerprints | Reject or explicitly adapt incompatible peers. |

The server can supervise per-session or per-request actors, passing database and
reply destinations at spawn. A browser may also be a logical subordinate of a
web-session spawner, but closing its socket does not mean the server can kill the
user's browser process. The spawner states the lifetime it actually controls.
Connecting to an external store owns a client connection, not the database.

Export these recipes from `(chat application)`. A separate consumer vendors that
library, chooses configuration, and builds the deployment without rewriting its
source. Secrets and concrete live connections do not enter the artifacts.

**Checkpoint C04:** use the same package with a local and a remote store; change
the resolved service address without rebuilding the browser. Demonstrate a
version mismatch and a missing service as understandable connection failures.

## 5. Give the chat service concrete semantics

For this tutorial, the store assigns an increasing sequence within each room and
deduplicates append attempts by client operation ID. `watch` accepts the last seen
sequence and supplies replay followed by live events. Each browser subscription
receives every room event; this is pub/sub fan-out, not a worker group distributing
different posts to different users. A history-to-live handoff must not lose posts.

Choose a bounded subscriber queue. A slow client is disconnected with a resumable
cursor rather than making all other clients wait indefinitely. These are chat
protocol choices, not universal actor guarantees. An uncertain append outcome
is reported; an explicit retry with the same operation ID is safe because this
store's contract makes it so.

**Checkpoint C05:** race posts from two clients, disconnect during an append,
reconnect with a cursor, and slow one subscriber. Assert ordered, duplicate-free
display of the committed history and continued service to the other subscriber.

**Checkpoint C06:** restart a worker and reload server/browser artifacts. Retained
history survives in its native service. Connections release their own pending
calls and streams; compatibility, replay, and explicit browser state restoration
govern reconnection. A stream from one code version is never silently reinterpreted
using another version's schema.

## 6. Publish the application as an interactive document

This extension keeps the original Pollen/Scribble goal visible. Author a room
guide or moderation workbook as a syntactic tree, with Scheme literals and
functions composing the same elements as the chat view. Publish static HTML and
an interactive version with live room widgets from that source.

Start with Scheme authoring, then add a foreign markup reader behind an explicit
wrapper. Its syntax can draw on HTML/XML, ReST, and Pollen without introducing
`#lang` or a registry. Reuse located syntax and the existing parser libraries
where their contracts fit.

```scheme
;; guide.sld -- the planned generate-library form.
(generate-library (chat guide)
  (export make-guide)
  (import (scheme base) (chat markup-reader))
  (begin
    (read-guide-library "./guide.markup")))
```

Generator imports serve the reader. The reader's result declares the imports for
the generated code separately. Reading an embedded Scheme expression preserves
it as syntax; it does not run a database query or install a browser handler during
generation. Build evaluation can deliberately render a static page later.

**Extension C07:** make both editions from the same guide; verify phase separation,
hygiene, source locations, source-relative dependencies, and targeted rebuilds.
Document export and retained UI focus are observable behavior, not just matching
tree constructors. The markup grammar remains a separate design task.

## Proposed project contents

| File | Future responsibility |
| --- | --- |
| `application.sld` | Export the configurable application and service/build descriptions. |
| `chat.scm` | Clearly separated server/browser roots in one authoring source. |
| `types.sld` | The sole message/interface type definitions. |
| `view.sld` | Pure model, reducer, and functional tree composition. |
| `guide.sld`, `guide.markup` | Explicit reader wrapper and the literate document extension. |
| `fixtures/` | Posts, replay histories, codec/version cases, and local discovery configuration. |
| `tests/` | Chibi checkpoints, native service tests, and two-browser integration tests. |

Codecs, actor transports, DOM hosting, and production storage belong to reusable
libraries/providers. The tutorial's application code should remain small enough
to read separately from those libraries.
