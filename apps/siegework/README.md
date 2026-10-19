# Siegework

Explore a seeded world, establish a supply network and destroy the nest before
its escalating waves overwhelm your colony. The game runs entirely in the
browser. Scheme defines its rules, 3D scene and touch-friendly HUD; reusable
application, UI, input and WebGPU libraries live under `src/`.

For smaller steps first, follow the [five application tutorials](../../doc/book/lofi/tutorials/index.md).
Each isolates a piece of this app and points back to its implementation here.

## Build and play

Run these commands from the repository root with Chibi, Binaryen, Node 24 and
Python 3 available. The [repository setup](../../README.md#getting-started)
provides the development environment; no native game server is required.

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
python3 -m http.server 4191 --directory build/siegework/solo
```

The recipe defaults to debug builds with basic Wasm optimization. Add `--release`
before the repository path for the existing O3 pipeline with inlining and
convergence. Both profiles compile and check the same game and shaders; build
time, artifact size and runtime performance can differ.

Open `http://127.0.0.1:4191` in Chromium with WebGPU and WasmGC support.
IndexedDB saves automatically. One tab owns each origin/application save.
The current application ID is `siegework-colony-v12`, with world schema 12 and
client schema 8. Hub capacity upgrades deliberately start a new colony: World12 stores a completed
capacity tier and removes constructible houses. Old browser records
remain under their previous identity; importing them into this version is rejected.
Compatible code and shader replacement preserves the running colony and camera;
changes to host JavaScript require a page reload.

An optional `SAVE_SERVICE_URL` build also emits `synced/` with explicit online
checkpoint controls. Gameplay still runs locally. See the
[save service guide](../../doc/static-saves.md).

## One interface for mouse and touch

The status dials and controls occupy one vertical edge strip. **Pause** opens a
centered menu with Resume, Restart and the control-side setting. The same icons
and touch-sized buttons appear on desktop and mobile.

Pause also exposes the in-memory game recorder, replay scrubber and dump
export/import controls. Recording starts at this page's checkpoint and is
bounded; export before reloading to keep its history. Replay preserves the saved
colony. See [recording and analysis](recording.md) for the event contract and
the Node analysis command.

- Tap a resource deposit to open its **Extractor** action (`1`). Extractors
  are not part of the ordinary construction choices. Persistent first-extractor
  guidance points toward the glowing deposit. The first accepted extractor order
  spends 40 ore and starts the clock. Every other purchase stays locked until
  then, preserving the initial 160 ore for this opening. Selection alone is free.
- Tap an empty tile to open its construction popup: **Tower** (`1`),
  or **Artillery** (`2`), with ore costs shown before ordering.
  The hologram uses this session’s last successfully ordered ordinary building, starting
  with a tower. Tap that same tile again, or double-click it, to order that type.
  Tapping a different tile only moves the selection; it does not spend ore.
- One order saves at a time. Accepted orders close the popup and update the next
  hologram; an extractor leaves the ordinary choice unchanged. A rejected or
  unsaved order keeps its selected site and attempted type available for retry.
  Selection alone never starts the colony clock. The popup keeps the actual
  rejection reason, including missing tower coverage, gaps in the surveyed
  walking route, inaccessible pickup supplies and failed saves.
- Select an existing building for **Upgrade** (`U`) or **Cancel** (`C`) on its
  pending order. Repeated tile taps only inspect an existing building; they do
  not upgrade or cancel it. Dismissing selection does not cancel construction.
  Completed towers and artillery always stand on the same stone plinth, with
  corner supports and open arches on all four faces. Workers and carts pass underneath.
  Their upper structures and the hub have lower profiles; the arches retain
  their clearance. Wider violet crystals and pulsing extractor halos identify
  resource sites using the existing fixed meshes and display clock.
  An animated indicator above a tower or artillery shows that it is waiting
  for upgrade materials; current services stay active.
  Buildings may occupy transport paths and intersections; their foundations
  leave clearance for the carts.
- Select the hub, then choose **New worker** (`F`)
  to order paid recruits. The actions remain open for repeated orders. An existing
  worker assembles each recruit. The hub occupies nine tiles. Worker capacity
  starts at 12. **Upgrade** (`U`) at the hub adds two places after one worker returns
  and assembles for three seconds. Six upgrades cost 100, 200, 400, 800, 1,600 and
  3,200 ore, reaching a maximum of 24 workers. Only one expansion can be pending.
  Its payment is reserved immediately and refunded if the worker dies before
  completion. Hiring remains separate: 25 ore and three seconds of assembly.
  Queued recruits count against completed capacity; unfinished upgrades grant no
  places. The popup shows the next price, capacity, pending work and maximum.
- **Repair** (`R`) quotes the hub's affordable target percentage and ore cost.
  It reserves only the needed or available ore, at two health per ore. A worker
  returns to the hub and works for three seconds; further damage can reduce
  the eventual percentage. Unused payment returns if that worker dies. There
  is no automatic repair.
- Ore, hub health, working workers and difficulty have separate readouts. The
  worker ring shows busy workers divided by all workers, excluding idle,
  fleeing and hiding jobs from the busy count. It is not a population-cap ring.
  The difficulty ring advances toward the next strength increase, not an unseen
  enemy spawn. Home (`H`) smoothly returns to the hub.
- **Pause** (`P`) stops the colony and opens the menu. **Resume**, Escape or a
  tap outside resumes play. **Restart** opens a confirmation; Cancel, Escape or
  a tap outside returns to the paused menu. A saved paused colony reopens with
  Resume available. Pausing preserves the unpaid selection.
  Pending Resume and Restart show progress and disable duplicate actions until
  saving finishes; a failed save leaves the action available to retry.
- WASD pans in screen directions. Q/E smoothly rotates between quarter turns,
  always using an orthographic camera at 30° elevation. Each resting quarter
  turn gives a 2:1 dimetric ground diamond; intermediate turns remain smooth.
  Lighting rotates with the camera. Mouse
  wheel or two-finger pinch zooms without moving the view center. Two on-screen
  arrow buttons provide quarter turns on touchscreens, without changing the
  world-drag gesture.
  Arrow keys move the cursor; Enter or Space selects a tile and a second press
  orders its previewed structure. Gamepad controls are absent.

Pill-shaped cards use equally sized circular action buttons, icons, costs and
visible shortcut keys on every screen. The pause menu uses labeled rows. Names
remain available to assistive tools and tooltips; construction choices use icons
rather than visible building names.
They never scroll or resize the full-screen world. HUD text and controls retain
native HiDPI resolution. The 3D world also renders at native device-pixel
resolution, without MSAA. Its 2:1 dimetric camera retains smooth orthographic
rotation and zoom. Pointer coordinates and callout anchors use the full logical
viewport.

Drag the world with one finger, a mouse or a pen to pan. A tap selects only when
released; moving more than eight CSS pixels turns the gesture into a drag and
cancels that selection. Two-finger pinch only zooms, so lifting one finger never
starts an accidental pan. The reusable `dragHandler` setting sends signed CSS
pixel deltas to the Scheme camera once per display frame, independent of DPR.

Attack notifications appear beside the edge strip as compact white-on-red
labels. Tap the notification to inspect its location, or its close
button to silence the area. The four most recently dismissed areas stay muted
for up to eight seconds of game time, including nearby worker damage. Other
locations still alert.

Canceling returns uncollected reserved materials to their source. A kit already
on a worker stays physical and returns to the hub before its refund; delivered
materials stay spent. Canceling a tower upgrade preserves its existing level
and services. Outside build mode, clicking another world cell dismisses the old
card and selects that cell without placing an order.

## Supply lines and threats

Workers choose reachable jobs using travel and completion costs. They can take
construction supplies from nearby extractor or tower stock, preempt suitable
jobs for construction, and flee threats. Carried gems, construction crates,
destination markers, sweat and carts make their activity visible.

A mine has one worker slot per level; upgrades increase slots and output together.
Its three levels provide an expensive fallback when further deposits are hard to
reach. Artillery and observation/logistics towers have separate upgrade trees:

| Level | Observation/logistics tower | Artillery |
| --- | --- | --- |
| 1 | Sight, depot and worker carts. | One gun assembly with six-cell range. |
| 2 | Greater sight and twice the cart speed. | Two stacked gun assemblies; 1.5× damage. |
| 3 | Twice the cart speed again; retains sight and depot. | Three stacked gun assemblies; 2× damage. |

Each upgrade needs another delivered 25-ore kit and keeps the current level
working until delivery completes. Artillery starts with two kits; a tower starts
with one. Existing tower-mounted guns remain functional when their towers are
upgraded. Every completed tower provides carts. Links run at the slower tower's
level; the hub supports level three. Workers travel 2, 4 or 8 cells per tick
(10×, 20× or 40× walking speed); freight moves 32, 64 or 128 world units per
tick and carries up to 32 ore. These are movement speeds, not extra deliveries
or production within one tick.

The transport network is a deterministic minimum spanning tree rebuilt from
scratch each simulation tick over the hub and completed towers. Its edge cost
is squared straight-line cell distance, restricted to links with a known,
passable route of at most 1024 steps. It does not minimize terrain travel
length. Extractors obstruct freight paths; tower and artillery
plinths permit crossings. Unreachable depots keep their stock.

Dotted lights pulse toward the hub at display rate. They show only the current
network, with cyan identifying available worker cart service. Terrain maps and
legal paths are cached by their inputs; tree selection itself runs afresh.
Unchanged routes retain shuttle progress and cargo. Rerouting returns a
shuttle's cargo once to its surviving source and resets that shuttle; destroying
the source loses its stock and undelivered freight. Obsolete track cells never
render, even while paused.

Workers reveal a small nearby radius. New work and supply pickup at an unseen
construction site stall until it is visible again; a yellow warning marks the
site and its card explains the delay. Existing carriers can finish their known
route, revealing their destination as they approach.

Water blocks movement. About one in ten
spawned enemies may begin excavating a mountain; others can join an existing
excavation. They stop and chip away before a permanent opening appears.

The 128×128 map places the hub within eight cells of its center and the nest
32–41 cells away, roughly five or six observation hops. The intended ordinary
expedition lasts about ten minutes. Enemy
approach directions help locate it. Waves introduce progressively stronger ranks
with distinct shapes, armor and colors, including elites and a much larger boss.
The opening lasts 45 seconds before the first spawn. Ordinary waves are thirty
seconds apart, strength steps are ninety seconds apart, and the first boss spawns
at nine minutes. Raids replace an ordinary wave every ninety seconds starting at
2:15. Wave sizes grow more slowly than strength. The nest remains the objective;
time never grants a victory, and unfinished runs continue beyond ten minutes.
Artillery has limited range and deals more damage at close range. The map outlines
the combined range of operational guns. Enemies wounded by a gun pursue that
attacker. Other buildings do not intercept that pursuit.
Crowds spread into nearby walking lanes.
Defeated enemies
award no ore: extraction and defending your supply lines remain necessary.

Attacks produce smoke and compact red notifications. Select a notification
to move to that attack. Newly surveyed ground unveils with a sharp, expanding
fragment-level contour rather than a tile-aligned edge. The simulation and durable saves run at 10Hz; moving units
and freight interpolate at display frame rate.

## Read and verify

Start with [TOUR.md](TOUR.md), then the [application chapter](../../doc/book/lofi/applications.md),
[UI contract](../../doc/ui.md) and [scene library](../../src/draw3d/README.md).
No colony rules are implemented in JavaScript. Tiles share fixed colored meshes;
buildings, workers, freight and enemies use fixed colored composite models.
Changed ticks transfer their occurrence transforms, while the GPU retains model
vertices and indices. Independently aimed guns remain separate instances.
Camera motion reuses these batches; display animation does not rebuild the
Scheme HUD each frame. Native HiDPI and single-sample rendering remain in use.
Thin tile borders come from a small inset of those shared terrain planes.

```sh
scripts/test-applications
scripts/test-ui
scripts/test-draw3d
node tests/draw3d/colony.mjs build/siegework/solo
scripts/max-dps-test
node tests/draw3d/onboarding.mjs build/siegework/solo /tmp/siegework-fixtures
# These browser checks reset disposable saves: use an isolated test host/profile.
node tests/applications/hosting.mjs build/siegework
node tests/draw3d/colony-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9452
```

See [validation evidence](VALIDATION.md) for exact results and limitations, and
[TODO.md](../../TODO.md) for delivery status. This is an early scene library;
textures, arbitrary-mesh picking, shadows and full Three.js compatibility remain
future work. Multiplayer and automatic investment are outside this iteration.

The [damage-budget guardrail](../../tests/applications/max-dps-test.md) obtains
costs, production, gun damage and wave health from the compiled game model. It
checks one optimistic investment policy; it does not establish real survival or
globally optimal play. Difficulty tuning still needs actual colonies and feedback.
