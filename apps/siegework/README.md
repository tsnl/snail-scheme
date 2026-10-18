# Siegework

The colony rules are presented as a lit, low-poly scene with a compact
Scheme-authored HUD. Terrain remains a flat grid: building height is visual,
with no new elevation, movement or combat rules. Workers and loaded rail
shuttles use their actual simulation positions.

Build from the repository root:

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
python3 -m http.server 4191 --directory build/siegework/solo
```

Use Chromium with WebGPU and WasmGC support. The entire simulation runs in the
browser and saves to IndexedDB. Its application ID is `siegework-colony`. Compatible
code and shader reloads preserve the world, selection and camera.

For optional explicit Save online / Load online controls, set
`SAVE_SERVICE_URL=http://127.0.0.1:4174/saves/` when building and serve the additional
`build/siegework/synced` static directory. The [save service guide](../../doc/static-saves.md)
explains setup. Gameplay and automatic local saves work while that service is down.

## Contextual controls

- A new colony shows **START: BUILD AN EXTRACTOR** and a bright ground marker
  around the planner's preferred visible, safely reachable turquoise deposit.
  H or controller Back selects and reveals that deposit; resizing also keeps
  it clear of the card while this first step is active. Ordering the first
  extractor dismisses the card; canceling an unfinished order restores it.
  Completed extractor survey history keeps it dismissed after reload or loss
  of the extractor. This uses the saved world without a tutorial flag.
- Hover to see the prospective action, cost and any blocked reason.
- Click a mineral deposit to build an extractor. Click an existing extractor
  to upgrade it. Buildings and crystals are selected through bounds around
  their 3D forms, so roofs and crystal tips select their owning cell.
- Click empty ground to lock a site and choose Tower or Artillery. Press `1`
  or `2`, controller X or Y, or the corresponding touch control. Moving the
  pointer while choosing does not move the locked site. The compact chooser
  opens beside that site's world cursor and does not preview a tower railway;
  rails appear only for committed, completed depots. Selecting a site alone
  creates no build order and spends no ore. Escape/B cancels.
- WASD or the left stick pans in screen directions, with pitch compensation
  keeping vertical and horizontal travel consistent. Each pan stops at the
  first camera bound; independent held directions can still slide along it.
  Arrows or the d-pad moves the selected cell;
  Enter/Space/controller A activates it. H or controller Back returns home
  after the first extractor order.
- P, controller Start, or the always-visible Pause control pauses/resumes.
  Context controls expose moving, arming, cancellation and worker fabrication.
- Manual, Explore and Defend select the existing colony automation policy.
- A defeated colony shows **COLONY LOST** and **Start a new colony**.

The canvas fills the viewport. Projection and pointer rays use its current
logical dimensions, while the GPU target follows the physical pixel size.
HUD controls consume their own input and preserve native keyboard focus.
Game commands publish after their local IndexedDB transaction completes. No game
commands or tick snapshots travel over the network.

## Follow the implementation

[`(draw3d)`](../../src/draw3d/README.md) owns reusable scene, transform,
camera, geometry, material and picking values. The game only composes those
values. [`game.sld`](src/siegework/game.sld) resolves contextual
input into existing typed match requests; JavaScript contains no colony rules.
The [UI library](../../doc/ui.md) allocates rectangles top-down in Scheme
and uses semantic DOM controls for focus, input and accessibility.

The renderer supports indexed opaque meshes, hierarchical affine transforms,
orthographic/perspective cameras, directional and ambient lighting, and depth.
Ground and box ray intersections support this prototype. This is an initial
Scheme scene library, not complete Three.js compatibility; textures, arbitrary
mesh raycasting, shadows, asset loading and instanced rendering are future work.

## Checks

```sh
scripts/test-draw3d
node tests/draw3d/colony.mjs build/siegework/solo
node tests/draw3d/onboarding.mjs build/siegework/solo /tmp/siegework-onboarding-fixtures
# With a separately launched Chromium CDP browser:
node tests/draw3d/colony-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9452
# Movement checks pause a test match: use an isolated package/save.
node tests/draw3d/pan-browser.mjs http://127.0.0.1:4201 http://127.0.0.1:9452
# These checks reset disposable test saves; never point them at a player's save.
node tests/applications/save-service.mjs
node tests/draw3d/persistence-browser.mjs http://127.0.0.1:4205 http://127.0.0.1:9452
node tests/draw3d/onboarding-browser.mjs http://127.0.0.1:4208 http://127.0.0.1:9452 /tmp/onboarding-solo
```

The onboarding fixture's optional fourth argument is a previous compatible
package for exact protocol and snapshot checks. For the defeated browser case,
pass the generated `defeated.json` as the browser runner's fourth argument:
the runner installs it in its disposable IndexedDB save.

The fixture executes the actual Scheme math, geometry, shader and scene bridge
in Wasm. Browser checks use pointer/key input, GPU readback, moving freight,
narrow viewports and saved-state reopen. The focused renderer fixture also
checks closing while readback is pending.

See [validation evidence](VALIDATION.md) for the integrated artifact, live
replacement checks, browser coverage and its practical limits. Browser checks
disable the HTTP cache so a preceding preview's host JavaScript cannot mask
the code being checked. Scheme/shader live reload deliberately retains the
running host; host JavaScript changes require a page reload.
