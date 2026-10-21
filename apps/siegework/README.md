# Siegework

Explore a seeded map, wire an energy network across it, and destroy three
nests before their attacks destroy your hub. The whole game is Lofi; the
browser only forwards input, draws frames and the HUD, and stores the save.

**[Play online](https://tsnl.github.io/snail-scheme/play/siegework/)** ·
[Player guide](https://tsnl.github.io/snail-scheme/games/siegework.html)

```sh
make site
python3 -m http.server 4191 --directory build/siegework
```

Open `http://127.0.0.1:4191` in a browser with WebGPU.

<!-- ANCHOR: guide -->
## Playing

- **Energy.** The colony runs on one store of energy, starting at 160.
  Extractors draw it from violet crystals until they run dry: the starter
  beside the hub yields 2 a second, richer crystals more, and each
  extractor level multiplies its yield. A destroyed nest exposes a rich
  crystal of its own.
- **The network.** Every finished building is wired to every other within
  reach whose line to it crosses no rock (water is fine). The hub reaches
  9 cells, pylons 7, 10 and 12 by level, turrets 6 and extractors 4. A
  building the hub cannot reach through wires is unpowered and does
  nothing: no energy, no shots, no sight. Rebuild the link and it wakes up.
- **Building takes time.** A new building needs visible grass and a
  powered building that can wire to it. Its cost is paid at once and it is
  built while it holds one of the hub's build slots: pylons take 2 s,
  extractors 3 s and turrets 4 s, and the colony's first extractor is
  ready at once. The hub starts with one slot; upgrading it adds a second
  and a third. Further orders wait in the queue, and an unpowered site
  waits without blocking the others.
- **Rush.** Rushing finishes work at once for four times the share of its
  cost that remains: five times the price when rushed as it is ordered,
  less later. Cancelling refunds the cost.
- **Upgrades, repair and scavenging.** Each building has three levels.
  Upgrades raise pylon reach, extractor yield, and turret damage (one and a
  half, then two times, with a gun more each level), and restore full
  health. Repair restores the hub to full health at one energy for each two
  health it lacks. Scavenging returns a fifth of what a building cost.
- **The siege.** The first attack leaves the nests at 0:45, then one every
  30 seconds; raids aimed at exposed outposts replace every other attack
  from 1:45, and a boss leads an attack every nine minutes. Enemies grow
  stronger every 90 seconds, less for each nest destroyed, and some burrow
  through rock. Turrets shoot the strongest enemy in sight and range, harder
  up close; a wounded enemy turns on the turret that hit it.
- **Winning.** Destroy all three nests to win. Lose the hub and you lose.

## Controls

The same controls work with a mouse, a pen and fingers. Drag to pan, pinch
or use the wheel to zoom, and tap a cell to select it; the selection alone
never orders anything. The dock on the side of your hand shows hub health,
energy and the nests' strength with the time to the next attack, then the
turning buttons, then five construction buttons for the selected cell,
greyed out where they do not apply: on open ground a pylon, a turret, an
extractor, the rush toggle and closing; on a building its upgrade, rushing
and cancelling its work, scavenging and closing, with repair in place of
scavenging at the hub. Beside it come the menu button, up to
two attack alerts, which go to the attack or silence it for eight seconds,
and the build queue, with a ring while a work builds and ! while it is
unpowered; tap one to go to it.

| Key | Action |
| --- | --- |
| 1, 2, 3 | Build a pylon, a turret or an extractor on the selected cell |
| 4 | Rush the selected work, or make new buildings rushed |
| 5 | Close the selection |
| U | Upgrade the selected building, or add a build slot at the hub |
| R | Rush, as 4 does |
| C, X | Cancel the selected work, scavenge the selected building |
| F | Repair the hub to full health |
| WASD, arrows | Pan |
| Q, E | Turn a quarter |
| H | Return to the hub |
| P | Open or close the menu |
| Escape | Back out of a dialog, then clear the selection |

The menu also restarts on a new map, resigns, and moves the dock to the
left or right edge.

## Saves

The colony depends only on its seed and the orders given at each tick, so
the save is a journal: the seed, the tick reached and each accepted order
with its tick, plus whether the game was paused and for which hand. Loading
replays the journal. Under rules that have changed since it was written,
an order that is now rejected is dropped and the colony grows differently;
there are no save versions.
<!-- ANCHOR_END: guide -->

## How it is built

| Module | Responsibility |
| --- | --- |
| [`grid.sld`](src/siegework/grid.sld) | Cells, distances, the cells a straight line crosses, and breadth-first distance fields. |
| [`terrain.sld`](src/siegework/terrain.sld) | The original game's seeded land: home neighborhood, regional lakes and mountains, nest fronts and crystal sites. |
| [`world.sld`](src/siegework/world.sld) | The state, and what derives from it: wires, power, sight and exploration. |
| [`colony.sld`](src/siegework/colony.sld) | Orders and their rejections, the work queue with slots and rushing, and production. |
| [`siege.sld`](src/siegework/siege.sld) | Attacks, enemies and their routes, digging, turrets, strikes and alerts, and the outcome. |
| [`simulation.sld`](src/siegework/simulation.sld) | `act` and `advance`, the only ways the world changes, and the journal that replays them. |
| [`game.sld`](src/siegework/game.sld) | The camera, selection, commands, keys, gestures, dialogs and saves. |
| [`view.sld`](src/siegework/view.sld) | The scene in the original's palette and models. |
| [`hud.sld`](src/siegework/hud.sld) | The dock, card, queue, alerts and dialogs. |
| [`public/app.css`](public/app.css) | The HUD's palette and symbols. |

Time is the world's tick: periodic rules fire on multiples of their period,
and only work in progress keeps a count.

The programs in [`tests/`](tests) check the land, the economy, the queue,
power, the siege, replay, and on eight seeds that an undefended hub falls
soon after the first attack while a hub ringed with turrets holds for five
minutes; `headless.mjs` drives the compiled package through taps and the
HUD, then replays its save.
