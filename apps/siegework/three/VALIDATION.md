# 3D prototype validation

The initial integrated artifact is generation `0fc45bae47dae09add19f7f0`.
Its shared solo/cloud simulation is 425,178 bytes, SHA-256
`aa2b5a635f7bd25fe1e51e892bce3184fe1f30ccac914c30e49e59d064a9823f`.
The final build's recorded Scheme source hashes matched the checked sources.
The UI host uses the client-owned number-field restriction from the UI stack.

## Executed checks

- `scripts/test-draw3d` compiles and executes actual Wasm for affine transforms,
  inverse-transpose normals, both camera projections, zero-to-one clip depth,
  projection/ray agreement, ground/box intersections, immutable indexed
  geometry, shader checking and a copied colony frame (1,584 vertices,
  786 triangles).
- `tests/draw3d/colony.mjs` executes contextual building and upgrade orders,
  locked Tower/Artillery choices, roof selection, moving/cancelling a tower
  with the original ore ledger restored, narrow picking and compatible
  replacement through the real compiled application.
- `tests/draw3d/browser.mjs` reads actual WebGPU pixels, proves depth hides a
  later submitted triangle, rejects invalid shader preparation while retaining
  the working renderer, resizes during queued readback, and closes with both
  preparation and readback pending. Admission stops and owned buffers/targets
  are released.
- `tests/draw3d/colony-browser.mjs` passes against both hosts. It uses real
  pointer/key events for construction, roof upgrades and a locked tower site;
  observes moving loaded freight; checks Pause with native Enter/Space without
  a ground action; queues/cancels movement; injects controller Y; uses touch
  for choice/cancellation; reopens the durable match; checks portrait and short
  landscape containment; and verifies page exit releases GPU targets.
- A live publication from preliminary generation `c4eeeb380bdb5382b2d28b38`
  to the final generation retained exact match and client snapshots and the
  existing GPU renderer on both hosts, followed by a successful pixel readback.
  `tests/draw3d/reload-browser.mjs` reproduces this with two compatible builds.
- All 52 existing colony checks passed through the updated shared runtime
  using the unchanged schema-7 gameplay fixture. Existing browser-input checks,
  `make test`, `make check` and CI matrix tests passed.

The applications CI suite now invokes both `scripts/test-ui` and
`scripts/test-draw3d`. The headed browser checks remain explicit local checks;
CI does not claim GPU coverage from compiling a shader alone.

## Scope of evidence

Browser checks used headed Chromium, Xvfb and Vulkan SwiftShader with WebGPU
enabled. They demonstrate rendering and input behavior on a software GPU,
not performance on the user's hardware or Firefox stability. Controller
mapping was checked with an injected browser gamepad, not a physical device.
The mobile tests check emulated viewport/touch behavior, not a handset browser.

The focused simplify pass used a fresh source-free explanation and critical
debate, then removed nested scene-list assembly in favor of explicit semantic
groups. A separate newcomer read the public API and ownership documentation;
constructor arguments, light direction, box-picking limits and host close
responsibility were clarified. Matrix assembly, shader source, scene data and
the atomic GPU render pass remain cohesive longer operations.

This is an initial reusable scene library. It does not claim complete Three.js
compatibility, arbitrary mesh picking, shadows, textures, asset loading,
instancing, physically based materials or a path tracer. Existing colony rules
and 2D saves remain separate from the `siegework-3d` application identity.

## Screen-relative camera and bright palette follow-up

Generation `0d0f127f99d15fe87859b053` contains the follow-up (426,054-byte Wasm,
SHA-256 `eecac89c9369edcb4ad8daf30fa1cc3fdc02600a7e9cc1338bfd61d44f6d3abb`).
Its recorded Scheme hashes match the checked sources.

The follow-up maps screen-right/down movement through the actual fixed camera
basis onto the ground, compensating for both yaw and pitch. It shortens a pan
uniformly at the first world bound and rounds the final target to the existing
integer thousandths. No client schema or shared input semantics changed.
Independent held directions still compose separately, including their existing
boundary sliding; no hidden camera state or input aggregation was introduced.

The focused source-free simplify explanation verified this projection and
first-bound clipping. We retained existing fixed-point quantization instead of
adding unsaved fractional state: real held-input checks bound its visible error.
Sunny grass, blue sea backdrop, turquoise minerals, warm roofs, vivid machinery
and workers, plus cream/navy HUD styling change presentation and lighting only.

`tests/draw3d/pan-browser.mjs` samples projected hub displacement under actual
held Chromium W/S/A/D and open-space diagonals, then checks cardinal movement
at camera bounds. It also exercises injected analog axes/diagonals/bounds and
native text-input focus gating while proving the paused match is unchanged.
The test reproduced the old W defect with roughly 81px horizontal movement
alongside 86px vertical movement. The corrected sustained cardinal holds moved
268–275px along their intended axes with less than 0.4px perpendicular drift.
Both isolated browser hosts retained exact match/client snapshots and the same
GPU renderer through the old-to-new generation publication. All destructive setup belongs to isolated
4201/4202 test packages; publication to the live previews sends no gameplay
commands and preserves their current pause states. HUD CSS changes require a
page refresh; Scheme palette and camera changes hot reload in place.

Final live publication preserved the already-paused cloud match's exact
snapshot, including its pause state, and both live preview manifests accepted
the new generation. The existing solo IndexedDB and cloud SQLite were not
replaced. The bright combined scene passed the contextual desktop/portrait/
landscape browser checks and an independent UI visual review.

## Construction feedback and pending-order recovery

Final cloud and solo packages share generation `ada252d67a0c413a4eacacb0` and
the same 426,113-byte Wasm module (SHA-256
`2cfd7b5ae2e748ebd900e5a5c1ce6dad14dbf4942763fc47c644892d83b1f165`).
Both final packages passed the headed Chromium/SwiftShader persistence flow on
isolated ports 4205 and 4206. Cloud completed two towers and an extractor with
90 ore spent; solo completed a tower and extractor with 65 ore spent. Their
active-game reloads retained the structures and expenditure while the clock
continued normally. The browser traces contained no uncaught runtime exception.
`make check`, the queue boundary checks, and the actual linked-Wasm colony
checks passed. Replacing the previous bright-palette Wasm and restoring the
new module retained exact snapshots for both owners.

The ordinary fresh cloud and solo mouse flow both constructed a tower, delivered
its paid kit with a worker, completed it, and retained it across an active-game
reload. The reported failure was reproduced at a narrower cloud boundary: a
delayed command produced a local tower and spent ore, but the in-memory queue
disappeared on reload before the server had received it. The reopened server
snapshot therefore contained neither that tower nor its expenditure. This is a
demonstrated failure path, not evidence of the original player's network state.

`tests/draw3d/persistence-browser.mjs` uses disposable saves and actual Chromium
mouse input. The cloud checks block `/command` with DevTools, reload while the
order is unavailable, then unblock it; the retained order commits once. A second
case holds a response after the server commits, then reloads and verifies that
the server's next sequence consumes the stored prefix without another purchase.
Acknowledged commands remove their storage record. A stale-epoch rejection
retains the server save, clears unsaved orders visibly, and stays visible after
the event stream reconnects. The fresh session check also verifies that opening
a session before its first command returns the same live client identity.

The executable queue-boundary checks in
`tests/applications/cloud-outbox.mjs` cover protocol incompatibility, malformed
payloads, sequence gaps, epoch replacement, fresh-identity recovery, and failed
storage writes/acknowledgement cleanup. They run from `scripts/test-applications`.
The independent source-free simplify review confirmed the FIFO and exact-head
acknowledgement model; it identified the need to retain live session identities
while a first request can still be in flight. No generic migration or background
coordination layer was added.

World schema 7, client schema 1, application ID and durable save formats remain
compatible. Deployment needs a cloud server restart for the session rule and a
browser page reload for the host code. Pending queues survive same-tab reload;
closing the tab and duplicated tabs sharing one client UUID are outside this
slice. This validation did not modify the player's live previews or saves.

## First extractor guidance and defeated colonies

The isolated onboarding packages share generation `2062ee7c1eaf306590a6dd18`
and byte-identical 438,079-byte solo/cloud Wasm (SHA-256
`c9ca8e19afe27fc99593efd000475d5ebfb28ad66bcd8c515682012383161542`).
`make test`, `make check`, the cloud-outbox boundary checks, and both compiled
colony/onboarding fixtures passed. Replacement from the previous generation
`ada252d67a0c413a4eacacb0` retained the exact protocol contract and snapshots
for both owners. World schema 7, client schema 1, application identity and
durable save formats remain unchanged; there is no saved tutorial flag.

`tests/draw3d/onboarding.mjs` executes the shared compiled application. It
checks order dismissal, cancellation recovery, completed-extractor history
after actual enemy destruction, and an established save without guidance.
After two towers reveal a richer northern deposit, both the guidance and the
automatic planner choose that deposit. Unsafe deposit fallback, an actual hub
defeat, and the enabled restart action are also covered. It writes durable
established and defeated fixtures for browser checks.

The picking fixture reproduces the previous visible-tip failure: at a 960×640
viewport, the starter crystal tip at world `(11.8, 20, 0.63)` projects near
pixel `(573, 287)`. Ground-only picking selected cell `(11, 19)`; the corrected
nearest structure/crystal bounds select its owning deposit `(12, 20)`.
Structures retain precedence for exact distance ties.

Actual headed Chromium/SwiftShader checks passed against isolated cloud 4207
and solo 4208. Each fresh colony displayed the explicit start card and bright
ground marker, including a GPU readback with the cursor on the hub. Reloading
before an order retained guidance. H and injected controller Back selected and
revealed the deposit after panning. Actual crystal-tip clicks ordered an
extractor, removed the marker/card, and retained dismissal across reload and
completion. Cancellation restored guidance; an established colony stayed
dismissed. The 390×844, 390×600, 844×390 and 640×390 viewport checks verified
that the tip remained on the canvas rather than beneath a HUD control, both
on entry and after H. Screenshots of the short portrait and landscape layouts
were inspected for readable guidance and a clear target.

The actual defeated fixture displayed **COLONY LOST** and an enabled
**Start a new colony** action on both hosts, including a separately seeded
cloud package on 4209. Reload retained the defeat card; activating restart
returned to an active colony with first-extractor guidance. Both hosts also
passed the existing pointer, keyboard, injected controller, touch, movement,
pause, saved reopen and GPU-disposal browser regressions. Browser traces had
no uncaught runtime exception. The persistence browser regression also passed
on both hosts: cloud retained unavailable orders across reload, reconciled a
lost response without another purchase, and visibly rejected stale-colony
orders; completed structures and spending survived active reload on both.
These checks use emulated viewports and an
injected controller on a software GPU; they do not claim handset, physical
controller or hardware-GPU coverage.

The focused simplify review used a fresh source-free explanation and critical
debate. It kept guidance as a pure world predicate plus the planner's existing
selection, and kept picking as one stable nearest-hit fold. Camera framing is
derived from the viewport and current guidance using existing client fields.
All packages and saves used for this validation were disposable; live ports
4200/4191 and their packages were not modified or published.
