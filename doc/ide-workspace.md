# An IDE with file and browser documents

> **Proposed.** This design consumes the [IDE backend contract](workspace.md).
> It changes no implementation yet. Today's static IDE has editor panes
> and a special preview dock; its worker already compiles unsaved edits.

One IDE instance manages one workspace folder. Its frontend edits files
and browses running applications; its backend owns the buffers,
watch/compile loop and application runs through the same API used by CLI
clients. There is no workspace-switching UI or multi-workspace manager.
A browser document is a peer of a file document in the same split layout.
The IDE backend launches a server, the server publishes an address, and
the user opens that address once or several times. The server answers the
clients' real page, asset and application requests.

## Two document kinds

| Document | Owns | Shares |
| --- | --- | --- |
| File | Editor selection, scroll and view state | The IDE backend's buffer and its revision |
| Browser | Address, iframe and one client session | The running server with other clients |

Keep the existing split tree, generalized to these two leaves. Browser
documents have an address bar for HTTP(S) or `this-browser://` addresses.
The command palette offers Launch server, Stop, Restart, Open address,
Open another client, Split and Pin. Launch reports a clickable address in
run status; it need not open a pane automatically. A pin prevents ordinary
file navigation from replacing that document; an explicit close still
closes it.

The backend recognizes a project by its root `project.sld`. Its `inputs`
export declares metadata read patterns; under the IDE-supplied filesystem
handler, `build` and `launch` return the build graph and launch menu as
data. The palette lists those server launches, not a separate client target
or `launch.datum`. Description functions do not build or start programs.

Two views of a file share a buffer. Two browser views of an address start
distinct clients of the same server. Splitting or moving an existing
browser document must preserve its client; creating another client is an
explicit action. Closing or navigating that document ends its old client,
not the server. Client identity must be per page/session; origin cookies
or local storage alone do not distinguish two views.

Preserve an iframe's DOM attachment across layout changes. Today's
`src/ide/panes.mjs` rebuilds the layout with `replaceChildren`, which is not
a safe way to preserve live frames. Use stable document hosts and update
their geometry when splitting, resizing, moving or pinning. Retain iframe
focus and normal input behavior. This needs a small layout change, not a
new rendering or browser framework.

Ordinary HTTP(S) applications use ordinary iframes. Respect their framing
policy and offer Open externally when embedding is unavailable; owned
applications can permit the IDE origin through their
[frame-ancestors policy](https://www.w3.org/TR/CSP3/#directive-frame-ancestors).
An external top-level tab is optional, not another pane implementation.
The file editor stays an editor, not a special URL in a universal web
application/plugin system.

## A browser-local server needs a real request path

The chosen first provider uses a Service Worker for request interception,
an owning IDE page for routing, and a dedicated worker for each server run.
The compiler runs in an internal worker. Service Worker eviction must not destroy
IDE buffers or live server state: its lifetime follows events, and
it may be terminated while idle. Its
[Client messaging and fetch response APIs](https://w3c.github.io/ServiceWorker/)
provide the bridge, not a permanently running server host.

```text
IDE address: this-browser://<ide>/<run>/
    |
iframe URL: <IDE HTTPS scope>/_lofi/<owner>/<run>/
    |
Service Worker fetch -> owning IDE page -> server run worker
    ^                                         |
    +--------- actual server response --------+
```

This is a proposed use of those APIs, with the following concrete route:

1. On startup, register the Service Worker under the IDE's own site path
   and wait for control before advertising browser-local launch. A
   handshake obtains the owning window's `Client.id`; the first provider
   uses it as the IDE-instance token. No workspace registry is needed.
2. Resolve the logical address into an HTTP(S) URL under that scope,
   including the owner and fresh run ID. Keep the logical address in the
   IDE's address bar. The fragment stays with the document; the path and
   query go to the server. This mapping belongs to the browser provider,
   not to the application or compiler.
3. For each mounted request, the Service Worker finds the owner through
   `clients.get(owner)`, transfers a reply port to it, and uses `respondWith`
   for the eventual response. The page routes the request to that run's
   worker. Neither hop compiles code nor looks up an application's assets.
4. The server handler receives the mount-relative method, path/query,
   headers and body. Its status, web-exposed response headers and body bytes
   return through the reply port. Root HTML, JavaScript modules, Wasm, CSS,
   images, API replies and server errors all take this path.
5. If the owner has disappeared, the run has stopped, or the reply times
   out, settle the request with an explicit transport failure. Do not
   manufacture a successful app page, retry a mutation or fall through to
   the static site's files. After Service Worker restart, the same URL
   locates the still-running owner and run again.

The same server implementation on Node receives the same request shape
from a real HTTP listener. Both providers mount each run beneath its fresh
run ID. A run's assets and requests cannot drift into a newer build. A
missing resource reaches the server and returns its actual response; it
does not cause the IDE to search compiler output for a substitute.

The first bridge handles finite requests and bodies. It does not emulate
WebSockets, streaming servers or cookies for separate virtual origins.
Application values cross workers through the backend proposal's derived
binary transport.

### URL and origin limits

Portable applications must work below a mount path. In the first proof,
the page uses relative asset references and the client resolves API URLs
relative to that mount, for example through its module URL. The provider
does not rewrite HTML, scripts, redirects or response bodies.

`fetch('/api')` addresses the origin root, not the mounted application.
Reject same-origin subresource/API requests from a mounted client when
they escape its mount with `UnsupportedMountPath`; identify that client
from the fetch event solely to reject the escape, not to redirect it into
a different route. Test root-relative script, image and API requests as
failures. The native listener also rejects paths outside its run mount,
so local development does not hide this mistake. A top-level navigation
outside the Service Worker scope follows normal browser navigation and is
outside this portable subset; arbitrary origin-root applications are not
supported.

The real iframe retains the bridge site's origin. A path is not a new
origin, so the first provider is for trusted programs from this workspace, not
isolation of untrusted applications from the IDE. Separate-origin hosting
would be additional design work. Browser-local addresses are ephemeral
within their owner, origin and browser partition, not network invitations.

Serve the static playground over HTTPS or a permitted loopback context,
with the Service Worker script and virtual paths under its scope; a bare
`file://` folder is insufficient. If the required browser APIs are
unavailable, report the limitation rather than selecting a network
transport. The logical scheme requires no protocol registration or PWA
installation. [Fetch's scheme handling](https://fetch.spec.whatwg.org/#scheme-fetch)
does not make `this-browser://` a native fetchable address.

## Editing and running remain separate

An edit updates the IDE backend's buffer and queues a build from the exact
accepted revision. Saving persists the buffer; it is not a prerequisite
for compilation. Show build failures and stale diagnostics against their
revisions while the last good server continues serving its pinned assets.

Reuse the parsed project plan across ordinary application edits. Only
metadata compiler inputs or changes matching its declared read patterns
require querying the description again; the same patterns authorize reads
and cover new or deleted matching files. If metadata fails, show that the
current launch menu is unavailable or stale. Existing runs and their Stop
controls remain available; an old plan cannot silently authorize a new run.

Manual restart is the default: a successful build makes Restart available.
A run can instead opt into restarting after a successful build, consuming
that build without compiling again. Both use cold replacement: close the
old run, start the new one and navigate its open IDE documents to the
corresponding new address. A failed build leaves the running server alone;
explicit Stop disables automatic replacement until another Launch, so a
pending build cannot bring it back.
No client state or server count is preserved by that operation. If startup
fails, show that failure; do not quietly connect those views to another run.
An external tab is not implicitly controlled by the IDE's restart action.

Today's `(lofi app)` page relinking remains implemented and useful. The
proposal neither removes it nor claims it already handles server/client
protocol changes. Reusing it through server-owned reload responses is later
work, after build coherence and protocol compatibility are explicit. Logs,
errors and run status come first; source debugging remains separate
compiler work.

## Placements and later extensions

In native development, an IDE server manages one folder, serves its
frontend as a regular web application, compiles edits and starts servers
under its lifetime. Closing a frontend tab leaves the IDE server and its
application servers alive. In the static playground, the owner page and
its internal workers provide that backend; closing the owner ends the IDE
instance and its application servers. Closing only a browser document
never does. The workspace's saved files remain available.

Shared hosting across tabs is later work. A SharedWorker could hold a
single IDE backend while same-origin clients reference it, subject to
browser storage partition and lifetime rules; it is not an always-running daemon.
Its [constructor is exposed to windows](https://html.spec.whatwg.org/multipage/workers.html#shared-workers-and-the-sharedworker-interface),
so a Service Worker cannot simply construct one to recover an application.
A multi-tab design must establish a real window/port connection and define
who keeps the IDE backend alive. The first version needs neither this
coordination nor a standalone client tab to prove two clients.

Siegework is currently one browser application with world and view/input
state together. Splitting it into a logical game server and UI clients is
separate game work. Eventually both could run in a browser for solo play,
or the same server logic could run on a backend for several browser clients.
The IDE proof uses a counter first; it makes no multiplayer or
automatic distributed-state claim.

An IDE server editing and starting another IDE instance is a later proof
of the application model. Keep a stable bootstrap outside the component
being edited, and keep buffers owned by the original IDE backend so a failed
self-build does not lose them. The IDE does not need to hot-reload itself
to deliver the first backend and browser documents.

## Acceptance gates

1. **Real project and server, both placements.** Query `project.sld`, compile
   its client target and bundle the result as the server's resources. That
   server serves its page, JS, Wasm and relative assets on Node and in the
   static playground. Open
   it twice: distinct client identities observe one server count. Requests
   and missing-resource responses are observable in the server handler.
2. **Bridge failures and lifetime.** Exercise root-relative escape,
   unknown/stopped run, a pending request during Stop, owner closure,
   Stop or a newer Restart overtaking a pending launch/replacement,
   Service Worker termination/restart, and an unsupported native
   `this-browser://` connection. No request hangs or reaches an unrelated
   static file or later run. No automatic retry duplicates an increment.
3. **Working text and metadata.** Prove unsaved client/server compilation,
   an edit during a build, correctly labelled diagnostics and failed target
   or metadata builds leaving the running revision usable. Count queries:
   an ordinary source edit reuses the plan and compiler sessions; metadata
   code or a matching input change requeries. Check pattern errors, denied
   reads/writes, initialization/`inputs` restrictions, future matching
   files and stale-plan completions.
4. **Documents.** Split code beside two browser documents; pin, resize and
   move them without a reload or new client identity. Closing one client
   leaves the other and the server alive. Restart visibly resets the run.
   Check the optional restart policy against both a failed build and Stop
   overtaking a pending successful build.
   Check persistence failures and embedding restrictions as user-visible
   failures, not successful launches.

These gates include the complete client-to-server-resource build graph.
A prebuilt client can prove the request bridge earlier, but cannot prove
live client-source editing or project-plan invalidation.

A disposable Chromium 152 probe verified the proposed page/Service Worker/
server-worker route for two iframes, relative JS/Wasm/image loads, a POST,
a server-produced 404 and rejection of a root-relative API fetch. Forcing
the Service Worker to stop preserved the server count on the next request.
This was a JavaScript browser-API experiment outside the repository, not a
Lofi IDE backend implementation or the acceptance suite above. The next
implementation must supply the actual typed server, binary bridge, worker
termination and build contracts before these proposals can be called done.
