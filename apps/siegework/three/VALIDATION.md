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
