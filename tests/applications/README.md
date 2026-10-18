# Application checks

Run `scripts/test-application-tutorials` for the smaller tutorial checkpoints.
It compiles the counter, inventory and local-controls examples and the marker
board, then executes input boundaries, explicit effect delivery, quad output,
compatible replacement, schema rejection and `LocalState` checkpoint restoration.
A temporary file-backed adapter checks failed-write rollback, explicit retry and
revision conflicts without touching an existing tutorial save. The
[tutorials](../../doc/book/lofi/tutorials/index.md) include browser writer-lock,
IndexedDB and live-rebuild exercises; Node checks do not establish GPU rendering
or browser storage behavior.

Run `scripts/test-applications` with Chibi, Binaryen and Node 24. It compiles
Siegework into a static `build/application-tests/siegework/solo` package and builds
adversarial reducer fixtures. It executes real Wasm for typed handler ownership,
immutable state, terrain, colony logistics, effect materialization, async local
commit/rollback, imported checkpoint validation and hot replacement. Separate
checks exercise the optional opaque HTTP/SQLite checkpoint service.
The same runner executes [`max-dps-test`](max-dps-test.md), a small model-only
balance probe with three-minute deposit discovery and 0.5 artillery utilization.
Its optimistic capacity result is distinct from a real-map survival playtest.

```sh
node tests/applications/save-service.mjs
node tests/applications/async-runtime.mjs build/application-tests
node tests/applications/runtime.mjs build/application-tests/siegework/solo build/application-tests build/application-tests/siegework
```

There is no game server, command outbox or snapshot-replication test path.
All game logic runs in the browser. The save service does not run game logic.

## Browser hosting and persistence

The hosting runner creates private static hosts, a checkpoint service, a Chromium
profile and disposable IndexedDB saves. It never targets a live game:

```sh
node tests/applications/hosting.mjs build/application-tests/siegework
```

It checks:

- Pure static packaging and identical local/online simulation bytes; online-save
  code is absent from the disabled build and Node code is absent from both.
- Real transaction abort after `put` succeeds; concurrent IndexedDB CAS writes;
  incompatible records retained; legacy browser records reopened without receipts.
- Web Lock ownership, browser restart, moved static subpaths and saved pause.
- Slow persistence without tick accumulation, abort/retry, hidden-page behavior,
  compatible hot replacement and cleanup when leaving during startup.
- Explicit online save/load, conditional-write conflicts, service outage and
  local reopen after an unavailable online save.

Default ports are static 4282/4283, saves 4294 and DevTools 9346. Use
`TEST_SOLO_PORT`, `TEST_SYNCED_PORT`, `TEST_SAVE_PORT` and `TEST_CDP_PORT` to override.
The runner prints its disposable artifact directory. With `DISPLAY` set it uses
headed Chromium; otherwise it uses headless Chromium with SwiftShader.

The focused 3D prototype runners require an already served **disposable** static
package and an isolated Chromium DevTools instance:

```sh
node tests/draw3d/colony-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9336
node tests/draw3d/persistence-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9336
node tests/draw3d/onboarding-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9336
```

The persistence and onboarding checks reset their test colony. Never point them
at a player's save. See the [static save guide](../../doc/static-saves.md).

## Input and rendering

```sh
node tests/applications/browser-input.mjs http://127.0.0.1:9336
```

This serves its own ephemeral input fixture and exercises actual keyboard,
pointer, focus and native forms plus injected Gamepad samples. It tests held
repeat, smooth axes, native-control latching and integer submission without
claiming physical-controller coverage.

For an isolated software GPU browser on Linux:

```sh
chromium --no-sandbox --enable-unsafe-webgpu --headless=new \
  --enable-features=Vulkan --use-angle=vulkan --use-vulkan=swiftshader \
  --use-webgpu-adapter=swiftshader --disable-vulkan-surface \
  --remote-debugging-port=9336 --user-data-dir=/tmp/siegework-browser-test about:blank
```

These are test-process flags. Ordinary hardware-WebGPU browsers need no special
application flags. Some headless compositors leave WebGPU screenshots blank;
GPU pixel readback checks the actual render target. Use headed Chromium under a
private Xvfb display when needed for visual inspection.

Fixture helpers only establish boundary scenarios; they contain no alternative
game simulation. Application tests use public typed handlers; private scalar
imports are reserved for attacking the transaction boundary. Snapshot assertions
use the shared wire decoder and application validators, not duplicated offsets.
