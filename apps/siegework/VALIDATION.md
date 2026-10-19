# Release validation — 2026-10-18

These checkpoints record the release revision before native-backend retirement.
Their native execution evidence is historical. Current serialization and
application runners execute Wasm; see [the test guide](../../tests/README.md).

## Crowd and visibility checkpoint

`build/siegework-crowd-final/solo` passes 137 actual-Wasm application checks.
Generation `5abe5ae9c1f5fda7b44a34fb` contains a 648,530-byte simulation with
SHA-256 `036bc7377807933793dff78161fd254ddcd42675d3d63517d2620da05bca39f7`.
Crowds use bounded parallel ground lanes: the overlap fixture measures 40px
for two enemies and 80px for sixteen, while both reach their target. Tests cover
fast-enemy detour commitment, saved/hot-replaced movement, water, walls, digging,
path limits and the 128-enemy cap. Five new visibility checks cover every build
kind, stale menus, observer destruction and fogged kit deliveries. These cases
do not reproduce the reported transition crash.

The serialization CI harness now traps both animation-history host imports.
All 15 serialization fixtures pass, including raw/optimized linked Wasm, native
execution, malformed-input probes and compile rejections. Local evidence is in
`/tmp/siegework-crowd-final-runtime.log` and
`/tmp/siegework-serialization-ci-repair-20261018.log`.
The newer 3×3 hub, separate upgrade trees and playtest UI revisions remain in
progress; this checkpoint does not claim them.

## Touch release

The consolidated PR #334 is based on main `9bdee767`, including rank-one
`All ... requires` and the compiler-performance changes from PR #331.
The canonical build is `apps/siegework/build.scm`; there is one static 3D game.

The verified release package is `build/siegework-touch-release/solo`:

- Generation: `bc7325e9da0aa05411935248`.
- Simulation: 645,395 bytes, SHA-256
  `b7b113c57b23cc2128a5d8f88262ca892bcb52629e78e1ee170d89c07090d78c`.
- Application ID: `siegework-colony-v10`; world schema 10, client schema 4.
- Host JavaScript, stylesheet and shader are packaged with that module. Host
  changes require a page refresh; compatible Scheme/shader replacement preserves
  both live owners. The saved world is independent of client-only controls.

## Executed checks

`make test`, `make check`, the CI partition tests and `mdbook build` pass.
`scripts/test-ui` passes typed control, hover, circular-readout, layout and
negative-owner checks. `scripts/test-draw3d` passes linked geometry, projections,
picking, retained dependency identity, motion, inset scope and reveal contracts.
The freshly rebuilt game passes all 123 application integration checks plus the
headless camera/selection and onboarding/outcome runners.

Those transitions exercise physical shared kits, refunds and losses, paid worker
assembly, three-level mines/towers, cart speed and weighted assignment, persistent
track geometry, worker sight, hidden construction, walls, excavation, rank
introduction and the first-order clock. A model-only stress artifact built from
the same World10 source passed 31,494 commands, 1,026 exact save round-trips and 156
injected close encounters over four 7,200-tick seeds. Its 26 explicit repairs keep
defeated fixtures running into later waves; this is adversarial testing, not four
unaided winning games.

The release hosting runner passes all 19 sections in Chromium 152.0.7977.82 using
private Xvfb and SwiftShader. It exercises real IndexedDB, one-tab ownership,
transaction abort and retry, hidden-page suspension, retained failure diagnostics,
browser restart, changed mount paths, compatible/rejected reloads, and the optional
checkpoint service including outage/conflicts. Both embedded product browser
runners pass. No gameplay-server requests are made by the local-only build.

Independent product browser checks pass mouse and touch select-then-action,
repeated hub hiring, explicit upgrading/cancellation, restart confirmation and
prior-pause restoration, screen-aligned pan, smooth Home/rotation, wheel/pinch
zoom, and portrait/landscape card bounds. The camera drag endpoint is checked
at all quarter turns, regular/orbital scales and portrait/landscape sizes; it
ignores drag requests during restart confirmation. Real mouse, pen and touch
input checks cover threshold crossing, subpixel/frame coalescing, final release,
cancellation, blur, settings replacement and pinch handoff. A real DPR3 touch
drag of 60×40 CSS pixels moves the map by 60×40 without selecting or changing
the world; pinch leaves its center intact. Header and action labels are checked
for clipping. Attack cards and live thumbnails fit portrait and landscape screens;
omitted thumbnails release their GPU resources, and selecting an attack pans
without changing the world. A defeated zero-worker colony retains its result
across reload and requires a confirmed restart. Native DPR is retained, including a 1170×2532 backing canvas at
3× scale. Screenshots were inspected for the selected deposit, build boundary,
artillery preview and hub-hire card.

The reusable GPU fixture also checks fragment-level feathering, main/inset reveal
clock sharing, native 2× DPR, resizing, camera/shader replacement, terminal-frame
sleep, pending-readback cleanup and a single adapter/device. Camera-only changes
retain geometry; clock-only reveal changes do not upload geometry. These are
correctness and avoided-work checks, not hardware frame-time measurements.

## Limits and reproduction

The user's earlier invalid-transition crash remains unreproduced in the old
World8 checkpoint and the new World10 stress runs. Rejected reducers now capture
one exact local reproduction separately from the committed save. The browser
fixture deliberately injects one invalid staged result and verifies unchanged
save/revision, a stopped clock and retained command/candidate/prior snapshots
across reload. Inspect with `await snailApp.session.store.failure()`.
No claim is made that the unknown original cause or Firefox's queue crash is fixed.

The live preview remains on port 4212. All destructive browser checks use private
hosts, profiles and saves. Logs for this pass include
`/tmp/siegework-touch-release-runtime.log`, `/tmp/siegework-touch-release-hosting.log`,
`/tmp/siegework-application-tutorials.log`, `/tmp/siegework-reveal-fixtures.log`
and `/tmp/siegework-reveal-gpu.log`. Temporary evidence is local; CI retains its
own artifacts. The CI applications job builds Siegework, the application tutorials,
UI and 3D fixtures. Full backend coverage remains partitioned across the existing
jobs rather than replaced by these focused checks.

# Earlier static-client checkpoint — 2026-10-18

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
