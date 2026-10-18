# Current static-client validation — 2026-10-18

The canonical `apps/siegework/build.scm` builds the 3D game and runs the entire
Scheme simulation in the browser. It emits static `solo/` files and, with
`SAVE_SERVICE_URL`, static `synced/` files with explicit checkpoint save/load.
Both contain identical 459,803-byte Wasm, SHA-256
`8a6ce4864d90a5846e927b26ed3cd72a81365ec000c890782f6b25c8f7a276eb`,
generation `045471be3397e7a6b7bb24c7`. Application ID `siegework-colony` starts
a fresh save identity; world schema is 7 and client schema is 1.

Passed `make test`, `make check`, `scripts/test-draw3d`, 77 linked-Wasm application
checks, three expected compile rejections, opaque HTTP/SQLite service tests,
compiled contextual controls and onboarding. Application tests compile the full
game once; adversarial runtime fixtures use small independent reducers.

The canonical private hosting runner passed in headed Chromium 152 with
SwiftShader: real IndexedDB legacy envelopes, transaction aborts, tab ownership,
slow/failed persistence, visibility, hot replacement, browser restart, moved
subpaths, optional online save/load, stale writes, canceled/invalid imports and
service outage. Local-only packages made no gameplay-server requests. Compatible
hot replacement installed a fresh Wasm instance and preserved both state owners;
an incompatible replacement retained the previous code.

Actual mouse/touch/injected-controller playtests built and completed a tower and
extractor, upgraded the extractor, moved freight, canceled moves and restored the
colony after reload. WebGPU readback produced 73 distinct channel values, with
2,564 vertices and 1,272 triangles. A visually inspected screenshot confirmed the
scene rendered. A camera-only pan preserved all batch identities and performed
**zero geometry uploads**. This demonstrates avoided work, not an end-to-end
frame-time speedup.

Focused simplification reviewed local publication, independent HTTP revisions,
load consent, shutdown and the bounded request parser. The runtime remains free
of UI callbacks; online requests never hold its message lane. The full 3D cold
build still takes minutes despite the landed overload optimization; compiler
latency remains separate work.

Headed evidence was recorded under `/tmp/snail-hosting-8ztcj8/`; screenshots use
a private Xvfb display and software GPU, not hardware performance measurements.
Earlier validation records are preserved under [`doc/history`](../../doc/history).
