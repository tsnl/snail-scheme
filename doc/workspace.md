# A workspace for editing, building and running servers

> **Proposed.** This document specifies a small workspace service. It does
> not describe an implemented API. The existing
> [toolchain](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md)
> and [actor host](https://github.com/tsnl/snail-scheme/blob/main/doc/actors.md)
> supply parts of it.

A workspace owns a folder's files, working buffers, compiler sessions,
diagnostics and running servers. It can live in a native development
service or a static browser playground. The IDE uses that service; an
application server serves its own clients.

This service subsumes the current watch/compile loop and the IDE backend.
CLI and IDE clients use the same workspace API: file watching and buffer
edits feed one revision/build path. The compiler and server runs remain
isolated from the service's control event loop.

Launching names **only a server program**. The server chooses the page,
client code and assets returned to requests. A successful launch reports
`Application running at <address>`. Opening that address is a separate
action and may create several clients of the same server.

## One root, ordinary source files

Start with a folder and the existing library search roots. There is no
workspace file. Launch accepts an explicitly chosen server source path;
the UI can remember the last choice. There is no target registry,
automatic application discovery or package hierarchy. Existing
`main.sld` conventions remain useful where the entry is a server; today's
`(lofi app)` entries do not become servers by renaming them.

The workspace API is a library boundary with these operations, whose
spellings and wire representation remain to be chosen:

| Operation | Result and owner |
| --- | --- |
| Open / observe a workspace | An initial snapshot of files, working buffers, builds and runs, followed by ordered changes and logs on one channel. |
| Edit a buffer | Accept its exact text and return the new source revision. |
| Save a buffer | Persist that revision; report a failure without discarding its text. |
| Build a server entry | Return diagnostics or an immutable artifact bundle, labelled with the input revision. |
| Launch an entry on an executor | Build the current revision, start that server and publish the address returned by its listener. |
| Restart a run | Obtain a successful build of the current revision, then replace the run with a fresh execution. |
| Stop a run | Close its listener, terminate its execution and settle pending requests. |

A compiler error makes Launch or Restart fail before changing a running
server. Running an older successful build is an explicit choice with its
revision shown. Manual restart is the default. A run may opt into restart
after a successful build, using that completed build and the same cold
replacement rules as manual Restart; it does not queue another build.
A failed build leaves the current run untouched.

The snapshot and following events have no gap. Notifications identify
their source revision, build entry or run as appropriate; reconnecting
starts with another snapshot rather than requiring an event history.

## A build sees one revision

The working files are the saved files with buffer text overlaid. Each
accepted edit creates a source revision. A build freezes those inputs,
including included resource bytes and library inputs, before compilation;
later edits cannot change them. A revision identifies inputs, not a cache
format or a demand for a new content-addressed storage system.

```text
Workspace = files + buffers + revision + sessions + runs
Session(entry) = compiler session + revision-labelled diagnostics + last good build
Build = entry + input revision + immutable server and resource artifacts
Run = fresh ID + chosen Build + execution handle + listening address
```

One session builds one entry at a time. Edits during a build queue the
latest revision, rather than parallel builds of the same session.
Diagnostics retain their revision, so an old error cannot become a squiggle
on unrelated new text. The UI distinguishes edited text, the last build and
the running build. A fresh run ID distinguishes executions of the same build.

Saved files and working buffers have different lifetimes. Persist working
text for recovery in browser storage, and mark disk Save successful only
after the write succeeds. Quota or permission failures stay visible. A disk
watch event can replace an unmodified buffer; if it conflicts with an edit,
retain the edit and report the conflict. This is single-writer editing in
the first version, not collaborative editing.

### The server owns its client resources

An artifact bundle contains the server and its resolved resources. The
server serves them through its normal request handler; neither the launch
request nor the IDE carries a separate client target. All resources used
by a run remain pinned to its build, including lazily requested assets.

For the first transport proof, include a prebuilt client bundle as ordinary
server resources. This proves that the server serves those exact bytes. It
does **not** prove that editing their upstream Lofi source rebuilds them.

Live client editing is the next build milestone. Use a server-owned
generated resource dependency to compile its client source against the
same frozen inputs, then make its output available to server compilation.
Any client compilation or resource generation failure fails the enclosing
build. Reuse the existing `generate-library` mechanism if its portable
operations suffice; do not introduce another dependency notation first.

This requires work: today's incremental loop cannot execute producers.
The proof must establish portable recipe execution in both hosts, a
separate compiler session for a requested client entry, dependency
invalidation when its inputs change, and outputs private to the candidate
build until it succeeds. Whether the existing recipe API can express this
cleanly is the principal open build question. Native shell commands are
not browser capabilities.

## Same decisions, different providers

Keep workspace decisions in Lofi and bind their I/O through platform
providers. Reuse the existing compiler sessions and development loop where
they fit; the workspace is not another compiler pass. Keep compilation
off the service's control event loop, so editing, Stop and application
requests remain responsive.

| Responsibility | Native workspace | Browser workspace |
| --- | --- | --- |
| Files and recovery | Folder, working overlay and file watching | Virtual files and persisted working buffers; granted folder access where available |
| Compiler | Isolated compiler execution | Compiler worker |
| Server run | Node child process hosting Wasm actors | Dedicated worker hosting Wasm actors |
| Listener | HTTP(S) provider backed by a real network listener | Browser-local request provider and HTTP(S) bridge |
| Workspace lifetime | Development service; it may serve the IDE frontend | Owning IDE tab; ending that tab ends its runs |

The browser's coordinator can run in the owner page; it needs no extra
worker just to forward commands. Application requests go to the run's
worker, never through compiler execution. Runtime actors remain ordinary
independent actors inside each run. The current host is cooperative on one
JavaScript execution agent, and does not yet supply cross-worker transport
or cancellation. Separate run workers/processes are the first version's
termination boundary, not an actor thread pool.

Workspace placement and application placement are separate choices. An
executor consumes a server build and supplies its required capabilities;
the default executor is local to the workspace. The first proof covers
native/native and browser/browser. Executing a native workspace's build in
an attached browser, or a browser build on a connected native executor,
requires explicit artifact transfer and executor connection later. Opening
an already-running HTTP(S) server needs neither remote launching nor a
deployment manager. “Native” here can mean Wasm on Node, not a new native
code backend.

## Listening and connecting

The proposed portable server boundary accepts finite requests containing
method, path/query, headers and body bytes, and returns status, headers and
body bytes. A server asks its provider to listen; readiness and the actual
address come from that provider. The first example uses request/response
HTTP for both assets and its typed application protocol. Streaming,
WebSocket emulation and arbitrary HTTP server compatibility are later
work, not assumptions of this API.

| Address | Meaning |
| --- | --- |
| `http://…` or `https://…` | A network endpoint, subject to ordinary browser policy. |
| `this-browser://<workspace>/<run>/…` | An endpoint in the current browser workspace context; its meaning does not travel to another machine or browser partition. |

Parse the address once into a network or browser-local endpoint and select
its provider explicitly. A host without browser-local transport returns
`UnsupportedTransport` for `this-browser://`; it never substitutes a
network address. Missing or closed local runs fail separately. Detect
missing imports or known capabilities at launch when possible, and still
check dynamically supplied addresses at connection time. No global
compiler target checker is required first.

`this-browser://` is a logical connection and IDE navigation address.
Ordinary `fetch`, links and iframe navigation do not implement it; the
browser provider must map it to a real request bridge. It does not require
OS protocol registration. An ordinary page cannot provide a raw TCP
listener; [Direct Sockets requires an isolated context](https://wicg.github.io/direct-sockets/).

Typed application messages use derived `Serialize`/`Deserialize` binary
codecs across workers or network boundaries, without handwritten field
mapping or JSON. The existing actor binary path demonstrates codecs within
one host, not this transport. Direct immutable WasmGC references are an
optimization only inside a compatible reference domain; they cannot be
assumed transferable between workers. Protocol mismatch is a connection
error, not a reason to cast an unverified payload.

## Stop, restart and failure

A run owns its listener and execution. A client document owns one client
session. Closing the last client leaves the server running; Stop belongs
to the workspace. Run-to-empty actor lifetime is not a stop primitive:
suspended actors and children may still be alive.

The first Stop closes admission, retires the run ID, terminates its worker
or process and fails pending bridge requests with `RunStopped`. It does
not promise application cleanup handlers or transactional rollback. A
request may have changed state before its reply was lost; do not retry a
mutation automatically. Keep requests bounded and report a stalled bridge
as an error rather than waiting forever.

Reserve a launch identity before asynchronous build/startup, so Stop can
also cancel a pending launch. Launch creates an independent run; Restart
replaces a specified run. Stop or a newer Restart supersedes a pending
replacement. Its late completion must close any acquired resources, not
start or publish a server afterward. Explicit Stop also disables automatic
replacement until another Launch; a pending or subsequent build cannot
bring the stopped server back.

Restart first obtains a successful build, or uses the build that triggered
the automatic policy. Then stop the old run and start a fresh one with a
fresh address. This permits downtime and resets server state.
A startup failure is distinct from a build failure; retain the last good
artifacts for another explicit launch. Old requests and old addresses never
silently reach the new run. Retain artifacts while a session's last good
build or a run references them. No pool of old live generations is required.

Existing browser application relinking still has its
[state handover contract](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md#4-hot-reload).
It does not establish server migration or compatibility of a new client
with an old server. Preserving server state would need quiescence, settling
or cancelling requests, a checkpoint, restore and rollback, and an explicit
client reconnect/protocol contract. That is a later milestone. Logs, errors
and run status are sufficient initially; source stepping requires separate
compiler source-location and debugger work.

## Proofs and deliberate cuts

First, build an unsaved server edit at a recorded revision and launch it on
each local executor. It serves a small counter client and resources. Two
clients share the server count but have distinct session identities. A
failed build leaves that run usable; closing a client leaves it alive;
Stop settles pending requests; Restart produces a new run and reset count.
With automatic restart enabled, a successful build replaces the run, a
failed build preserves it, and Stop prevents a pending build from reviving
it. A native connection to `this-browser://` fails explicitly.

Next, compile a changed client dependency into the same candidate build as
its server, in both placements. A failed client build must leave the old
server and all its assets intact. This is the gate for claiming live client
source editing through the workspace.

The design deliberately omits discovery/configuration machinery, a package
or deployment hierarchy, migration, and a general supervision framework.
Explicit entry paths, build revisions and
killable runs are enough to test the boundary. They cost convenience and
state continuity, which can be added only when an example requires them.
