# Application integration checks

Run `scripts/test-applications` from any directory. It builds the actual Siegework
artifacts into the disposable `build/application-tests/siegework` package, plus
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

For real browser checks, start the packaged server:

```sh
PORT=4176 node build/application-tests/siegework/lib/browser/server.mjs "$PWD/build/application-tests/siegework"
```

Start a separate Chromium with a local DevTools port, then run:

```sh
node tests/applications/browser.mjs "$PWD/build/application-tests/siegework" http://127.0.0.1:4176 http://127.0.0.1:9336
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
zero kill income, manual pause and all four camera margins. The browser runner
also verifies shared Pause/Resume, visibility changes without clearing pause,
retained paused/camera state across reload, and rejected margin placement.

The focused input checks use real keyboard/pointer/focus events and injected
Gamepad samples; they do not claim physical-controller coverage:

```sh
node tests/applications/browser-input.mjs http://127.0.0.1:9336
```

That runner serves its own ephemeral fixture and covers held-input repeat, native
controls, reconnect/reload latching, axes and responsive layout. It does not
change the game match.

The isolated Linux software-adapter invocation used during development was:

```sh
chromium --headless=new --no-sandbox --enable-unsafe-webgpu \
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
adversarial bridge fixtures. The portable game snapshot codec belongs to the app.
