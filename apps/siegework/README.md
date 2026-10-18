# Siegework

Explore a seeded world, establish a supply network and destroy the nest before
its escalating waves overwhelm your colony. The game runs entirely in the
browser. Scheme defines its rules, 3D scene and touch-friendly HUD; reusable
application, UI, input and WebGPU libraries live under `src/`.

For smaller steps first, follow the [five application tutorials](../../doc/book/lofi/tutorials/index.md).
Each isolates a piece of this app and points back to its implementation here.

## Build and play

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
python3 -m http.server 4191 --directory build/siegework/solo
```

Open `http://127.0.0.1:4191` in Chromium with WebGPU and WasmGC support.
IndexedDB saves automatically. One tab owns each origin/application save.
The current application ID is `siegework-colony-v10`, with world schema 10 and
client schema 4. Earlier incompatible colonies retain their separate save identity.
Compatible code and shader replacement preserves the running colony and camera;
changes to host JavaScript require a page reload.

An optional `SAVE_SERVICE_URL` build also emits `synced/` with explicit online
checkpoint controls. Gameplay still runs locally. See the
[save service guide](../../doc/static-saves.md).

## One interface for mouse and touch

Hover shows a dotted build boundary and construction-tool symbol. It does not
open a dialog or spend resources. Click or tap a cell to select it; the pointing
card beside it offers explicit actions. Click away or press Escape to dismiss.

- Select a violet deposit, then choose **Extractor** (`1`). Even the first
  extractor requires this confirmation. The clock starts only after an accepted
  order, so you can inspect the map first.
- Select empty ground, then choose **Tower** (`1`), **Artillery** (`2`) or
  **Wall** (`3`). Hovering a choice previews that structure. A completed railway
  reserves its route: buildings cannot overlap the tracks.
- Select a building, then choose **Upgrade** (`U`) or **Cancel** (`C`) for a pending
  order. Dismissing its card does not cancel construction.
- Select the hub to order a paid **Worker** (`F`). Its card stays open for more
  orders. An existing worker must assemble each recruit.
- The header shows ore with a hub-health ring, active workers, and difficulty
  with a next-wave ring. Its Home (`H`) button smoothly returns to the hub.
  Pause (`P`) and Restart (`N`) sit beside it. Restart pauses the world and asks
  for confirmation; canceling restores the previous pause state.
- WASD pans in screen directions. Q/E smoothly rotates between quarter turns,
  always using an orthographic camera. Mouse wheel or two-finger pinch zooms;
  the Regular/Orbital button (`V`) changes scale without moving the view center.
  Arrow keys move the selected cell; Enter/Space selects it. Gamepad controls
  are intentionally absent from this game.

Cards use the same icons, controls and visible shortcut keys on every screen.
They never scroll or resize the full-screen world. WebGPU renders at native
pixel density, including HiDPI displays.

## Supply lines and threats

Workers choose reachable jobs using travel and completion costs. They can take
construction supplies from nearby extractor or tower stock, preempt suitable
jobs for construction, and flee threats. Carried gems, construction crates,
destination markers, sweat and carts make their activity visible.

A mine has one worker slot per level; upgrades increase slots and output together.
Its three levels provide an expensive fallback when further deposits are hard to
reach. Towers progress through three roles:

| Level | Role |
| --- | --- |
| 1 | Visibility, resource depot and automatic railway connection. |
| 2 | Artillery while retaining the depot. |
| 3 | Cart station replacing the gun as the frontier moves outward. |

Each tower level needs another delivered 25-ore kit. Direct artillery placement
needs two kits. Workers and their cargo travel five times faster on links whose
ends are both cart stations or the hub. Ordinary resource freight already uses
completed depot links. Laid tracks remain after a station is destroyed, but an
abandoned track alone cannot transport anything.

Workers reveal a small nearby radius. New work and supply pickup at an unseen
construction site stall until it is visible again; a yellow warning marks the
site and its card explains the delay. Existing carriers can finish their known
route, revealing their destination as they approach.

Walls are cheap translucent turquoise shields. Enemies can stop to attack them
rather than always finding a long detour. Water blocks movement. About one in ten
spawned enemies may begin excavating a mountain; others can join an existing
excavation. They stop and chip away before a permanent opening appears.

The 384×288 map places the hub near its center and the nest farther away. Enemy
approach directions help locate it. Waves introduce progressively stronger ranks
with distinct shapes, armor and colors, including elites and a much larger boss.
Artillery has limited range and deals more damage at close range. Defeated enemies
award no ore: extraction and defending your supply lines remain necessary.

Attacks produce smoke and red notifications with live views. Select a notification
to move to that attack. Newly surveyed ground unveils through a soft, expanding
fragment-level reveal. The simulation and durable saves run at 10Hz; moving units
and freight interpolate at display frame rate.

## Read and verify

Start with [TOUR.md](TOUR.md), then the [application chapter](../../doc/book/lofi/applications.md),
[UI contract](../../doc/ui.md) and [scene library](../../src/draw3d/README.md).
No colony rules are implemented in JavaScript. Geometry is retained between
changes; display animation does not rebuild the Scheme HUD each frame.

```sh
scripts/test-applications
scripts/test-ui
scripts/test-draw3d
node tests/draw3d/colony.mjs build/siegework/solo
node tests/draw3d/onboarding.mjs build/siegework/solo /tmp/siegework-fixtures
# These browser checks reset disposable saves: use an isolated test host/profile.
node tests/applications/hosting.mjs build/siegework
node tests/draw3d/colony-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9452
```

See [validation evidence](VALIDATION.md) for exact results and limitations, and
[TODO.md](../../TODO.md) for delivery status. This is an early scene library;
textures, arbitrary-mesh picking, shadows and full Three.js compatibility remain
future work. Multiplayer and automatic investment are outside this iteration.
