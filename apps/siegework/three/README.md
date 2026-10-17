# Siegework 3D prototype

The existing colony rules are presented as a lit, low-poly scene with a compact
Scheme-authored HUD. Terrain remains a flat grid: building height is visual,
with no new elevation, movement or combat rules. Workers and loaded rail
shuttles use their actual simulation positions.

Build from the repository root:

```sh
chibi-scheme -I bootstrap apps/siegework/three/build.scm "$PWD" "$PWD/build/siegework-3d"
python3 -m http.server 4191 --directory build/siegework-3d/solo
PORT=4200 node build/siegework-3d/cloud/lib/browser/server.mjs build/siegework-3d/cloud
```

Use a Chromium browser with WebGPU and WasmGC support. Solo runs from static
files with IndexedDB persistence; cloud uses the same compiled Scheme module
with a Node/SQLite authority. The application ID is `siegework-3d`, and the
cloud build has its own database. Existing 2D packages and saves are separate.
Compatible code and shader reloads retain the world, client selection and camera.

## Contextual controls

- Hover to see the prospective action, cost and any blocked reason.
- Click a mineral deposit to build an extractor. Click an existing extractor
  to upgrade it. Buildings are selected through bounds around their 3D forms,
  so clicking a roof selects the building rather than the ground behind it.
- Click empty ground to lock a site and choose Tower or Artillery. Press `1`
  or `2`, controller X or Y, or the corresponding touch control. Moving the
  pointer while choosing does not move the locked site. Escape/B cancels.
- WASD or the left stick pans in screen directions, with pitch compensation
  keeping vertical and horizontal travel consistent. Each pan stops at the
  first camera bound; independent held directions can still slide along it.
  Arrows or the d-pad moves the selected cell;
  Enter/Space/controller A activates it. H or controller Back returns home.
- P, controller Start, or the always-visible Pause control pauses/resumes.
  Context controls expose moving, arming, cancellation and worker fabrication.
- Manual, Explore and Defend select the existing colony automation policy.

The canvas fills the viewport. Projection and pointer rays use its current
logical dimensions, while the GPU target follows the physical pixel size.
HUD controls consume their own input and preserve native keyboard focus.

## Follow the implementation

[`(draw3d)`](../../../src/draw3d/README.md) owns reusable scene, transform,
camera, geometry, material and picking values. The game only composes those
values. [`three-game.sld`](../src/siegework/three-game.sld) resolves contextual
input into existing typed match requests; JavaScript contains no colony rules.
The [UI library](../../../doc/ui.md) allocates rectangles top-down in Scheme
and uses semantic DOM controls for focus, input and accessibility.

The renderer supports indexed opaque meshes, hierarchical affine transforms,
orthographic/perspective cameras, directional and ambient lighting, and depth.
Ground and box ray intersections support this prototype. This is an initial
Scheme scene library, not complete Three.js compatibility; textures, arbitrary
mesh raycasting, shadows, asset loading and instanced rendering are future work.

## Checks

```sh
scripts/test-draw3d
node tests/draw3d/colony.mjs build/siegework-3d/solo
# With a separately launched Chromium CDP browser:
node tests/draw3d/colony-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9452
node tests/draw3d/colony-browser.mjs http://127.0.0.1:4200 http://127.0.0.1:9452
# Movement checks pause a test match: use an isolated package/save.
node tests/draw3d/pan-browser.mjs http://127.0.0.1:4201 http://127.0.0.1:9452
```

The fixture executes the actual Scheme math, geometry, shader and scene bridge
in Wasm. Browser checks use pointer/key input, GPU readback, moving freight,
narrow viewports and saved-state reopen. The focused renderer fixture also
checks closing while readback is pending.

See [validation evidence](VALIDATION.md) for the integrated artifact, live
replacement checks, browser coverage and its practical limits. Browser checks
disable the HTTP cache so a preceding preview's host JavaScript cannot mask
the code being checked. Scheme/shader live reload deliberately retains the
running host; host JavaScript changes require a page reload.
