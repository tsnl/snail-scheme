# Static applications and online checkpoints

Every application bundle runs entirely in the browser. Scheme owns game rules,
presentation and typed commands. The browser owns the clock, WebGPU resources,
hot replacement and automatic IndexedDB saves. Hidden pages skip ticks. No
replication stream, gameplay server or multiplayer session is required.

## Build and serve

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework-static"
python3 -m http.server 4191 --directory build/siegework-static/solo
```

Open `http://127.0.0.1:4191` in Chromium. Any ordinary HTTPS static host works,
including hosting under a subpath. The game requires WasmGC, WebGPU, IndexedDB
and Web Locks. One tab owns the save for this origin and application ID.

The current application ID is `siegework-colony-v10`. A compatible module replacement
retains the current colony, camera and selection. Schema-incompatible saves are
rejected visibly; this build starts a fresh save identity.

## Enable online save/load at build time

```sh
SAVE_SERVICE_URL=http://127.0.0.1:4174/saves/ \
  chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework-static"
python3 -m http.server 4192 --directory build/siegework-static/synced
SAVE_ORIGIN=http://127.0.0.1:4192 PORT=4174 \
  node src/save/server.mjs /tmp/siegework-checkpoints.sqlite
```

The build still produces `solo/`, and additionally produces `synced/` with the
same simulation bytes and two controls: **Save online** and **Load online**.
Disabled bundles omit the online-save module. The service URL must be an HTTP(S)
base ending in `/`; `/saves/` works behind a same-origin reverse proxy.

Local saves remain automatic. Online transfers are explicit: Save uploads the
current committed checkpoint; Load asks before replacing this browser's colony.
Network requests run outside the reducer lane. An unavailable service leaves
gameplay and local saves usable. Loading runs the current Scheme decoder and
commits to IndexedDB before publishing replacement state. Invalid or incompatible
checkpoints preserve the current game.

The first save creates an online slot. Subsequent saves replace the last online
revision loaded or saved by this page. A newer online revision causes a visible
conflict and remains intact. Load it before saving again. On a new device, choose
Load online to resume. This first interface deliberately has no automatic merge,
background synchronization, named save slots or overwrite-on-conflict action.

The example service binds loopback and stores one checkpoint per application ID.
`SAVE_ORIGIN` permits the static bundle's exact origin, including its port. It has
no accounts or authentication. A personal deployment can place it behind an
authenticated HTTPS reverse proxy; multi-user account routing is future work.

## HTTP contract

`src/save/service.mjs` exports `saveService(store, {origin})`, which returns
`respondHttp(request) -> Promise<Response>`. The Node entrypoint adapts incoming
HTTP requests to this function. Routing and checkpoint policy live in the library.
The service never imports a game manifest, runs Wasm or interprets game state.

| Request | Result |
| --- | --- |
| `GET /saves/<application-id>` | Versioned checkpoint and strong `ETag`, or 404. |
| `PUT` with `If-None-Match: *` | Create only; 204 plus new `ETag`, or 412 if occupied. |
| `PUT` with `If-Match: <etag>` | Replace exactly that revision; 204/new tag, or 412. |
| `PUT` without a precondition | 428; existing record retained. |
| `OPTIONS` from configured origin | CORS methods and conditional headers. |

The opaque JSON envelope is `{format: 1, application, contract, snapshot}`. The
snapshot currently contains `{revision, state}`; its revision belongs to the
local game's durable history. Service ETags version online replacements
independently, so loading an earlier game checkpoint cannot bypass write conflicts.
Checkpoint bodies are bounded to 1 MiB; very large local colonies may exceed this optional service limit. SQLite performs the conditional update in
one statement, preserving the previous save after malformed or conflicting writes.

## Verification

```sh
node tests/applications/save-service.mjs
node tests/applications/hosting.mjs build/siegework-static
```

The first runner exercises the actual SQLite store through HTTP Request/Response
objects. The second owns disposable static hosts, a save service, a Chromium
profile and browser saves. It checks transaction aborts, tab ownership, legacy
records, hot reload, save/load conflicts, service outage and browser reopen.

A failed reducer retains the last committed colony. The static host also stores
one exact failure reproduction separately in IndexedDB, available as
`await snailApp.session.store.failure()` in developer tools. It contains the
command, generation, both committed snapshots and any staged candidate. It is a
local debugging record, not an automatic upload or a replacement save.
