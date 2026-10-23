# An IDE backend for one workspace

> **Proposed.** This document specifies the IDE backend. It does
> not describe an implemented API. The existing
> [toolchain](https://github.com/tsnl/snail-scheme/blob/main/doc/toolchain.md)
> and [actor host](https://github.com/tsnl/snail-scheme/blob/main/doc/actors.md)
> supply parts of it.

A **workspace** is the single folder being worked on, whether on disk or in
the browser's virtual files. One **IDE instance** manages exactly one workspace.
Its backend owns working buffers, file watching, compiler sessions,
diagnostics and application runs. Managing multiple workspaces or switching
an instance between folders is out of scope.

The IDE backend runs as a native IDE server or inside a static browser
playground. It subsumes the current watch/compile loop. The IDE frontend
and CLI clients use the same IDE API: file watching and buffer edits feed
one revision/build path. Compiler workers are internal, isolated from the
backend's control event loop. Public endpoints belong to the IDE or to
user applications; an application server serves its own clients.

Launching names **only a server program**. The server chooses the page,
client code and assets returned to requests. A successful launch reports
`Application running at <address>`. Opening that address is a separate
action and may create several clients of the same server.

## `project.sld` describes the project

A root `project.sld` marks a recognized project folder. It is an executable
Lofi metadata library with three exports (`inputs` is the proposed name
for the declaration):

| Export | Returns a datum describing | Does not do |
| --- | --- | --- |
| `inputs` | Expected read patterns for the metadata queries | Read the filesystem or grant ambient authority |
| `build` | Build recipes: file inputs, targets and dependencies between targets | Execute the build |
| `launch` | Named server launches: built target references, arguments and options | Start programs |

The IDE compiles and dynamically loads this library, obtains the input
declaration, queries the descriptions and owns actual building and
launching. Exact signatures, pattern grammar and returned recipe grammar
remain open; this document does not prescribe Scheme forms for them.
Plain folders may remain editable without the marker, but the IDE does
not invent a project graph or launch menu for them.

Both returned datums become one immutable **ProjectPlan**. At the metadata
execution boundary, parse finite data into target recipes, resolve IDs and
launch references, and establish a dependency order. Diagnose duplicate or
unknown IDs, invalid target references and cycles before installing the
plan. Reject procedure values in the returned data. Execution consumes
these structured records; it does not interpret datums again on each build.
Only the validated plan crosses a worker boundary, not arbitrary WasmGC
`Datum` values. Publish the graph and launch menu together, never one from
a new description and one from an old description.

The graph describes dependencies between target outputs. Each compilation
target keeps the compiler's existing library dependency tracking and
session cache; metadata does not duplicate that import graph. Launch
entries refer only to server artifacts. Compilation and loading still
check their actual entry points and platform requirements.

`project.sld` is the canonical source for both descriptions. A separate
`launch.datum` is unnecessary. `.datum` remains the extension for any plain,
non-executable S-expression data; the metadata functions return data, not
JSON. No package hierarchy or deployment language is introduced.

### Declared reads and a hermetic handler

The IDE's trusted compiler loads metadata sources/imports/resources within
fixed workspace and toolchain bounds. These bootstrap reads are separate
from query authority. Runtime module/import initialization and `inputs`
run with filesystem access unavailable: the declaration cannot depend on
reads made before its policy exists.

The IDE parses `inputs` into one read policy, then supplies the standard
filesystem handler over a frozen view, unsaved buffers included. Reads
outside the declared patterns and **all writes** from `build` or `launch`
fail through that handler. The project does not need to implement its own
handler. An optional reset/binder may narrow the IDE's authority, never
expand it. Ambient time, environment and network access are unavailable;
any later input capability must be explicit.

The proposed standard filesystem handler must enforce resolved paths
within the supplied snapshot, including `..` and symlink traversal. A
string-prefix filter is insufficient; [cap-std's rooted directory model](https://github.com/sunfishcode/cap-std/blob/main/README.md#capability-based-security)
illustrates this distinction, without prescribing a new dependency here.
Today's `fs` effect includes writes and does not itself prove read-only or
rooted access. This handler and pattern-based invalidation are new work, not
an existing type guarantee or a claim of isolation from arbitrary foreign
code.

Use one fresh instance and one snapshot to query `build` and `launch`.
Retain compiled-code caches; do not let old module globals become hidden
inputs. Cache the parsed plan with its metadata compiler dependencies and
declared read policy. These are distinct from the application's target
and library dependencies.

The **same parsed patterns** authorize reads and define the metadata watch
scope. Conservatively requery when a matching path changes, appears or
disappears, even if the queries did not read it. Watch for future matches,
not only files present today; creation of a missing matching path matters.
Metadata compiler inputs invalidate the description independently of this
scope. A data-only change can reuse compiled metadata. Ordinary application
edits reuse the plan unless they match the declared scope or metadata
compiler inputs. Broad patterns intentionally cause more reevaluation;
fine-grained observation tracing is an optional later optimization.

On a failed query or plan parse, retain its attempted policy for retry
when matching files change, without installing its candidate plan.
Compilation or `inputs` failures retry when bootstrap inputs change; missing
imports must not become permanently cached errors. A failed or stale
description leaves the running server intact but cannot authorize a new
launch or automatic restart as the current project plan.

## The IDE API

The IDE API is a library boundary with these operations, whose
spellings and wire representation remain to be chosen:

| Operation | Result and owner |
| --- | --- |
| Connect / observe the IDE | An initial snapshot of its workspace's files, working buffers, builds and runs, followed by ordered changes and logs on one channel. |
| Edit a buffer | Accept its exact text and return the new source revision. |
| Save a buffer | Persist that revision; report a failure without discarding its text. |
| Build a target | Execute its dependency closure from the current plan; return diagnostics or immutable artifacts with plan and source revision. |
| Launch a named server on an executor | Build its target closure, start the server and publish the address returned by its listener. |
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
Workspace = folder
IDE state = workspace + buffers + revision + plan cache + target sessions + runs
ProjectPlan = identity + linked target recipes + server launch entries
Plan cache = metadata compiler inputs + declared read policy + ProjectPlan
Session(entry) = compiler session + revision-labelled diagnostics + last good build
Build = plan identity + target + input revision + immutable artifacts
Run = fresh ID + chosen Build + execution handle + listening address
```

One session builds one entry at a time. Edits during a build queue the
latest revision, rather than parallel builds of the same session.
Ordinary application edits reuse the parsed project plan: visit affected
targets in dependency order and retain each compile target's session.
The compiler decides which imported libraries need recompilation. Exposing
its dependency observations to the IDE is new integration work; a second
library graph or a general scheduler framework is unnecessary. A small
target set can be walked directly before adding any persistent reverse
index. A new plan need not discard cached results for unchanged recipes
and inputs.

Diagnostics retain their revision, so an old error cannot become a squiggle
on unrelated new text. The UI distinguishes edited text, the last build and
the running build. A fresh run ID distinguishes executions of the same build.
Before launch or automatic replacement, require the current plan, selected
source revision and still-valid launch intent. Invalidate this eligibility
as soon as metadata becomes stale, not only when a new plan installs.
An older completion may remain useful in the cache or for an explicitly
chosen historical run; it cannot replace the server after a newer edit or
plan is known. Target IDs alone do not identify an artifact across plans.

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

A project graph can compile a client target and include its output in the
server's resource bundle. The launch menu still starts only the server.
All targets needed for that bundle use the same frozen inputs; failed
client compilation or bundling prevents publication of the candidate.
The server reads its pinned resources and answers the actual requests.

The first complete project proof must edit client source and rebuild the
affected client/resource/server target closure. Prebuilt client bytes can
test the request bridge earlier, but do not complete this build contract.
Compilation and resource bundling are enough for that example; the exact
recipe vocabulary remains open. Reuse compiler sessions and existing
resource mechanisms where they fit, without making arbitrary shell
execution a recipe primitive. Today's incremental loop cannot execute
`generate-library` producers, and browser project-description loading and
graph execution are also proposed work.

## Same decisions, different providers

Keep IDE backend decisions in Lofi and bind their I/O through platform
providers. Reuse the existing compiler sessions and development loop where
they fit; the IDE backend is not another compiler pass. Keep compilation
off its control event loop, so editing, Stop and application requests
remain responsive.

| Responsibility | Native IDE server | Browser-local IDE backend |
| --- | --- | --- |
| Files and recovery | Folder, working overlay and file watching | Virtual files and persisted working buffers; granted folder access where available |
| Compiler | Isolated compiler execution | Compiler worker |
| Server run | Node child process hosting Wasm actors | Dedicated worker hosting Wasm actors |
| Listener | HTTP(S) provider backed by a real network listener | Browser-local request provider and HTTP(S) bridge |
| IDE backend lifetime | IDE server; it also serves the frontend | Owning IDE tab; ending that tab ends its runs |

The browser's coordinator can run in the owner page; it needs no extra
worker just to forward commands. Application requests go to the run's
worker, never through compiler execution. Runtime actors remain ordinary
independent actors inside each run. The current host is cooperative on one
JavaScript execution agent, and does not yet supply cross-worker transport
or cancellation. Separate run workers/processes are the first version's
termination boundary, not an actor thread pool.

IDE backend placement and application placement are separate choices. An
executor consumes a server build and supplies its required capabilities;
the default executor is local to the IDE backend. The first proof covers
native/native and browser/browser. Executing a native IDE server's build in
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
| `this-browser://<ide>/<run>/…` | An endpoint in the current browser IDE instance; its meaning does not travel to another machine or browser partition. |

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
to the IDE backend. Run-to-empty actor lifetime is not a stop primitive:
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

Recognize a project by its root marker, query both exports and build a
counter's client and server resource bundle from its linked plan on each
local executor. An unsaved client or server edit reaches the served result
through only the affected targets. Two
clients share the server count but have distinct session identities. A
failed build leaves that run usable; closing a client leaves it alive;
Stop settles pending requests; Restart produces a new run and reset count.
With automatic restart enabled, a successful build replaces the run, a
failed build preserves it, and Stop prevents a pending build from reviving
it. A native connection to `this-browser://` fails explicitly.

Count metadata queries: an ordinary source edit reuses the plan, while a
changed metadata import or matching file causes reevaluation. Check missing
file creation/deletion, declaration and initialization restrictions, denied
reads/writes, an invalid graph, a failed metadata
query, a failed client build, and old-plan completions racing edits or Stop.
Each failure must preserve the running server and its assets without
presenting its old build as the current successful result.

The remaining design choices are exact export signatures, pattern and
recipe grammars, the initial recipe operations, and an optional reset/binder
hook. The fixed boundary is input declaration, bounded executable description,
parsed plan, then IDE-owned execution. Cut duplicate launch configuration,
unconditional per-edit metadata evaluation, mandatory read tracing, a
second compiler dependency graph, package
or deployment hierarchies, migration and general supervision. The plan
needs no more machinery to establish these contracts.
