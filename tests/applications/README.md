# Application integration checks

Run `scripts/test-applications` from any directory. It builds the actual Siegework
artifacts plus small public-API fixtures, checks compile-negative state/payload/
owner errors, then executes the Wasm in Node. It exercises immutable records and
retained snapshots, automatic hauling, a losing and winning run, pure view,
effect staging, compatible reload, hostile candidates, trap rollback, serial
submissions, durability failure and restart with an unacknowledged request.
This is correctness testing, not a performance comparison.

For real browser checks, start the packaged server:

```sh
node build/siegework/lib/browser/server.mjs "$PWD/build/siegework"
```

Start a separate Chromium with a local DevTools port, then run:

```sh
node tests/applications/browser.mjs "$PWD/build/siegework" http://127.0.0.1:4173 http://127.0.0.1:9336
```

The browser test opens two clients, makes shared purchases, checks real WebGPU
pixel readback, holds a request across a compatible reload, injects invalid WGSL
and an incompatible schema, then restores the original manifest in `finally`.
It writes `browser-check.png` in the selected build directory. Use a disposable
build/match when running it: it starts a new run and changes that test match.

The isolated Linux software-adapter invocation used during development was:

```sh
chromium --headless=new --no-sandbox --enable-unsafe-webgpu \
  --enable-features=Vulkan --use-angle=vulkan --use-vulkan=swiftshader \
  --use-webgpu-adapter=swiftshader --disable-vulkan-surface \
  --remote-debugging-port=9336 --user-data-dir=/tmp/siegework-browser-test about:blank
```

These are local test-process flags, not application dependencies. Hardware
WebGPU browsers need no special application flags. Some headless Chromium
compositors leave WebGPU canvases blank in screenshots even when rendering
succeeds; the pixel-readback assertion verifies the actual render target. A
Chromium window on an isolated Xvfb display was also used for visual inspection.

The test fixtures intentionally use private scalar imports only to attack the
transaction boundary. Application code should use immutable values and the
public `(application reducer)` API. `build.scm` here is a tiny explicit-map compiler
runner selecting an exported `answer`; it is also used by the standalone counter
example in the book. The portable game snapshot codec belongs to the app.
