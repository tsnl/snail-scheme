# Static applications and local saves

Every application bundle runs entirely in the browser. Scheme owns game rules,
presentation and typed commands. The browser owns the clock, WebGPU resources,
hot replacement and automatic IndexedDB saves. Hidden pages skip ticks. No
server, replication stream or multiplayer session is required.

## Build and serve

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework-static"
python3 -m http.server 4191 --directory build/siegework-static/solo
```

Open `http://127.0.0.1:4191` in Chromium. Any ordinary HTTPS static host works,
including hosting under a subpath. The game requires WasmGC, WebGPU, IndexedDB
and Web Locks. One tab owns the save for this origin and application ID.

The current application ID is `siegework-colony-v13`. A compatible module replacement
retains the current colony, camera and selection. Schema-incompatible saves are
rejected visibly; this build starts a fresh save identity.

## Verification

```sh
node tests/applications/hosting.mjs build/siegework-static
```

The runner owns a disposable static host, a Chromium profile and browser saves.
It checks transaction aborts, tab ownership, legacy records, hot reload and
browser reopen.

A failed reducer retains the last committed colony. The static host also stores
one exact failure reproduction separately in IndexedDB, available as
`await snailApp.session.store.failure()` in developer tools. It contains the
command, generation, both committed snapshots and any staged candidate. It is a
local debugging record, not an automatic upload or a replacement save.
