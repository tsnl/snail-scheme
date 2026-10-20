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
The decoded-snapshot fixture checks exact identity reuse, newly encoded candidate
validation, failed saves, pending queries, per-instance rollback and bounded
cache eviction through actual managed Wasm execution.
`scripts/test-applications-async` rebuilds and runs those small host-boundary
fixtures without compiling the game.
The same runner executes [`max-dps-test`](max-dps-test.md), a small model-only
balance probe with three-minute deposit discovery and 0.5 artillery utilization.
Its optimistic capacity result is distinct from a real-map survival playtest.
The same compiled probe runs [`starter-economy-test`](starter-economy-test.md):
64 seeded price experiments compare visible-only paid scouting, a geometric
lower bound, explicit defense allowances and ideal depletion windows. Both
scout policies currently fail one sampled seed; CI checks the necessary geometric
budget floor and real-model accounting, not reliable exploration or survival.
An actual-tick seed-one sprint then replays one measured route through ordinary
paid game commands, requiring the second mine to operate before starter
exhaustion. It retains worker travel, construction and waves; its fixed route and
zero deliberation do not establish typical player timing.
The paid pacing fixture executes a seed-one expedition with north, southeast and
southwest search bearings through visible-site orders, extraction, hauling,
construction and combat. It requires genuine paid expansion beyond the finite
starter, then reports depletion, spending, losses and any front clears. It never
injects resources or removes enemies and does not require a win. The current
policy loses before discovering a nest; it is pressure evidence, not a victory
proof, normal-player duration or a general scouting strategy across seeds.

```sh
node tests/applications/async-runtime.mjs build/application-tests
node tests/applications/snapshot-cache.mjs build/application-tests
node tests/applications/headless.mjs build/application-tests/siegework/solo
node tests/applications/world-profile.mjs build/application-tests/siegework/solo
node tests/applications/runtime.mjs build/application-tests/siegework/solo build/application-tests build/application-tests/siegework
node tests/applications/colony-pacing.mjs build/application-tests/siegework/solo build/application-tests/pacing-probe.wasm build/application-tests/pacing-report.json
```

The headless runner executes the same compiled browser package through the
[local environment](../../apps/siegework/headless.md), checking deterministic
World parity, player visibility, action validation, episode limits, checkpoint
accounting and actual JSONL/MCP subprocesses. It runs in the applications CI
partition. Its local timing/size sample is diagnostic, not a clean benchmark.
`nest-rewards.mjs` executes bounded combat, construction and depletion encounters,
World12 rejection, threat-clock boundaries, and defeat map
inspection through the compiled game. These establish transition invariants,
not normal-player survival or completion times. `resource-geography.mjs` runs
32 deterministic seeds through a compiled map probe and the actual reducer. It
measures deposits per eligible ground cell in three distance bands, checks the
realized density gradient and verifies bounded unique reserves; candidate
acceptance percentages alone do not establish those results.
`colony-compact.mjs` checks free physical extractor construction, zero-cargo
ownership, cancellation and casualty accounting, paid-upgrade refunds and
resignation during a captured flight on the 64×64 World14 map.

There is no network game server, command outbox or snapshot-replication path.
The save service does not run game logic.

## Browser hosting and persistence

The hosting runner creates private static hosts, a checkpoint service, a Chromium
profile and disposable IndexedDB saves. It never targets a live game:

```sh
node tests/applications/hosting.mjs build/application-tests/siegework
```

It checks:

- Pure static packaging with no Node modules in the browser bundle.
- Real transaction abort after `put` succeeds; concurrent IndexedDB CAS writes;
  incompatible records retained; legacy browser records reopened without receipts.
- Web Lock ownership, browser restart, moved static subpaths and saved pause.
- Slow persistence without tick accumulation, abort/retry, hidden-page behavior,
  compatible hot replacement and cleanup when leaving during startup.

Default ports are static 4282 and DevTools 9346. Use `TEST_SOLO_PORT` and
`TEST_CDP_PORT` to override.
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
