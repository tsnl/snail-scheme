# Application integration checks

Run `scripts/test-application-tutorials` for the smaller tutorial checkpoints.
It compiles the counter, inventory and local-controls examples and the marker
board, then executes input boundaries, explicit effect delivery, quad output,
compatible replacement, schema rejection and SQLite close/reopen restoration.
It uses a temporary database and leaves an existing tutorial match untouched.
The [tutorials](../../doc/book/lofi/tutorials/index.md) include the two-tab browser
and live-rebuild exercises; Node checks do not establish GPU rendering.

Run `scripts/test-applications` from any directory. It builds the actual Siegework
artifacts into `build/application-tests/siegework` with `solo` and `cloud` packages, plus
small public-API fixtures, checks compile-negative state/payload/
owner errors, then executes the Wasm in Node. It exercises immutable records and
retained snapshots, automatic hauling, a losing and winning run, pure view,
effect staging, compatible reload, hostile candidates, trap rollback, serial
submissions, invalid encoded replacements, packaging startup checks, durability
failure and restart with an unacknowledged request. Candidate checks include
abandoned initial state shapes and state advancing before installation; an
observer failure after commit retains its retry receipt. The runnable pure
handler example checks initial values and named effect variants without a host.
This is correctness testing, not a performance comparison.

`scripts/test-applications-async` builds only two tiny Wasm fixtures and runs the
focused async boundary checks. The full application runner includes these checks
too. Deferred persistence covers committed query visibility, both owners' FIFO
ordering, independent runtimes, captured inputs, concurrent reset retries,
rejected saves and retry recovery, immutable restored receipts, materialized
effects, reordered slots, installation against current state, deferred query
recovery, and draining close. These execute real compiled Scheme reducers; the
test controls only when the storage promise settles.

The 2026-10-17 async migration passed the focused script (10 checks), the combined
Node runner (52 checks), and the real two-client browser runner on private port
4182 with Chromium 152 / SwiftShader. The tiny async fixtures were freshly
compiled. Unchanged game and adversarial artifacts were reused from the
`siegework-playable-20261017` checkpoint at commit `b91d6e9d`, generation
`e11ebb903197e057398944d0` (schema 4, 6144 match words). The simulation SHA-256 was
`8d18de158326b9d855300320b9a7257aec05551f2df56350fe7829c27bb53133`.
The run used copied packages and a separate database; the full compiler fixture
build and compile-negative checks were not repeated for this JavaScript change.

For real browser checks, start the packaged server:

```sh
PORT=4176 node build/application-tests/siegework/cloud/lib/browser/server.mjs "$PWD/build/application-tests/siegework/cloud"
```

Start a separate Chromium with a local DevTools port, then run:

```sh
node tests/applications/browser.mjs "$PWD/build/application-tests/siegework/cloud" http://127.0.0.1:4176 http://127.0.0.1:9336
```

The browser test opens two clients, makes shared purchases, checks real WebGPU
pixel readback, reaches active combat with cargo in transit, holds a request
across a compatible reload with observably changed
reducer behavior, injects invalid WGSL
and an incompatible schema, then restores the original manifest in `finally`.
Set `SCREENSHOT=1` to also write `browser-check.png` in the selected build directory.
Use a disposable
build/match when running it: it starts a new run and changes that test match.
The combat checkpoint uses about 80 seconds of the actual authority clock.
Colony checks cover multiple deposits, physical kit ownership and danger recovery,
observation versus reachability, the actual outpost raid, an undefended finale,
zero kill income, occupied mining slots, sole-worker recovery, cargo/kit deaths,
seed replay, manual pause and all four camera margins. The marker/epoch checks
cover accepted and rejected seed restarts, duplicate retries, stale-run requests,
wraparound and failed durable commits. The browser runner
also verifies shared Pause/Resume, visibility changes without clearing pause,
retained paused/camera state across reload, rejected marker-offset changes,
native seed-form submission through the compiled Scheme reducer, and rejected
margin placement. It imports and executes the shared Web Crypto authority in an
actual browser with a deferred save, and holds session renewal while new input
arrives to check the next envelope's sequence and epoch.

The solo/cloud hosting runner owns disposable copies, servers, Chromium profile
and databases. Give it the raw build directory containing both packages:

```sh
node tests/applications/hosting.mjs "$PWD/build/application-tests/siegework"
```

It defaults to private ports 4182/4183 and DevTools 9346; override
`TEST_SOLO_PORT`, `TEST_CLOUD_PORT`, `TEST_CDP_PORT` or `CHROMIUM` as needed. Its
real-browser checks cover IndexedDB close/reopen, receipts/reset epochs, abort
after successful `put`, concurrent CAS, unsupported versions and incompatible
save contracts; tab ownership, retry after failure, static hot reload, actual
browser restart, moved subpaths and absence of application-server requests;
and a paused cloud save resumed by independent clients after server restart.
It compares package Wasm bytes and rejects changing a cloud output to solo
without touching a sentinel database. GPU setup uses the software-adapter flags
below. With `DISPLAY` set it uses a headed browser; otherwise it tries headless
Chromium. The tested Chromium 152 installation required a headed browser under
Xvfb for WebGPU. Start a private Xvfb display and pass its `DISPLAY` when needed.
The runner refuses occupied ports. Test artifacts and process logs stay in the
printed temporary directory.

The focused input checks use real keyboard/pointer/focus events and injected
Gamepad samples; they do not claim physical-controller coverage:

```sh
node tests/applications/browser-input.mjs http://127.0.0.1:9336
```

That runner serves its own ephemeral fixture and covers held-input repeat, native
controls, reconnect/reload latching, smooth axes, and responsive layout. Integer
form checks exercise native submission, I32 parsing, accessible errors, and
gameplay cancellation even when focus enters and leaves between frames. It does
not change the game match.

The isolated Linux software-adapter invocation used during development, with an
owned Xvfb display on `:99`, was:

```sh
DISPLAY=:99 chromium --no-sandbox --enable-unsafe-webgpu \
  --enable-features=Vulkan --use-angle=vulkan --use-vulkan=swiftshader \
  --use-webgpu-adapter=swiftshader --disable-vulkan-surface \
  --remote-debugging-port=9336 --user-data-dir=/tmp/siegework-browser-test about:blank
```

These are local test-process flags, not application dependencies. Hardware
WebGPU browsers need no special application flags. Concurrent test runs need
different DevTools ports and user-data directories; pass the chosen port to the
runner. Restart the owned browser process when changing its GPU flags.
Some headless Chromium
compositors leave WebGPU canvases blank in screenshots even when rendering
succeeds; the pixel-readback assertion verifies the actual render target. A
Chromium window on an isolated Xvfb display was also used for visual inspection.

The test fixtures intentionally use private scalar imports only to attack the
transaction boundary. Application code should use immutable values and the
public `(application reducer)` API. `build.scm` here is a tiny explicit-map compiler
runner selecting an exported `answer`; it is also used by the standalone counter
and state examples in the book. It accepts optional application source roots
after the output argument; the suite supplies Siegework's root explicitly for its
adversarial bridge fixtures. Snapshots use derived serialization; `snapshots.mjs`
reads the generic wire record format for assertions without knowing field offsets.
App-specific invariant checks remain beside the world and client models.
