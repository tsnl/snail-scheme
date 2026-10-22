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

- **The land.** Each map's seed picks one of four biomes. Meadows have
  lakes and mountains; deserts have no water, only mesas and winding
  canyon walls; tundra has frozen lakes, mountains and scattered
  boulders; an archipelago is sea but for its islands. Open ground is
  walked and built on. Rock stops walkers, sight lines and wires until
  burrowers dig it out. Water stops only walkers, so wires reach islands
  enemies cannot. Ice is walked but not built on. Every nest has a way in
  to the hub, though it may wind through a pass or over a causeway.
- **Energy.** The colony runs on one store of energy, starting at 160.
  Extractors draw it from violet crystals until they run dry: the starter,
  four cells from the hub in a direction the seed picks, yields 2 a second, richer crystals more, and each
  extractor level multiplies its yield. A destroyed nest exposes a rich
  crystal of its own.
- **The network.** Every finished building is wired to every other within
  reach whose line to it crosses no rock (water is fine). The hub reaches
  9 cells, pylons 7, 10 and 12 by level, turrets 6 and extractors 4. A
  building the hub cannot reach through wires is unpowered and does
  nothing: no energy, no shots, no sight. Rebuild the link and it wakes up.
- **Building takes time.** A new building needs visible open ground and a
  powered building that can wire to it. Its cost is paid at once and it is
  built while it holds one of the hub's build slots: pylons take 2 s,
  extractors 3 s and turrets 4 s, and the colony's first extractor is
  ready at once. Nothing happens until it is ordered: the crystals in
  sight pulse white under a title banner that points to them and links to
  this guide; the camera opens on the starter crystal. Once a crystal is
  selected, the banner points to the build button, which pulses. The hub starts with one slot; upgrading it adds a second
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
  through rock. Turrets shoot the nearest enemy in sight and range, harder
  up close, and their guns stay where they last fired. A wounded enemy turns on the first turret that hit it and
  hunts that one until it falls, whatever else shoots it; a raider then
  goes back to its outpost.
- **Winning.** Destroy all three nests to win. Lose the hub and you lose.

## Controls

The same controls work with a mouse, a pen and fingers. Drag to pan, pinch
or use the wheel to zoom, and tap a cell to select it; the selection alone
never orders anything. The dock on the side of your hand shows hub health,
energy and the nests' strength with the time to the next attack, then the
build menu for the selected cell: a pylon, a turret, an extractor, an
upgrade, a rush and closing. A button that may work later, waiting on
energy, work, the network or the first extractor, turns flat blue with
faint lines; one that cannot apply to the selection fades. Rush
finishes the selected work, or else makes new buildings rushed. A selected
building or hub adds cancelling its work and scavenging it, or at the hub
repair. Beside it come the menu and turning buttons and the build queue,
with a ring while a work builds and ! while it is unpowered; tap one to go
to it. Under the nests in the opposite corner, a red alert throbs while the
colony is under attack and goes to the latest attack, and a notice says why
an order was refused.

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

Keys held with ⌘, Ctrl or Alt go to the browser, so its shortcuts, such as
reloading, keep working. With Shift, WASD and the arrows pan as they do
alone, and other keys do nothing.

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
| [`grid.sld`](src/siegework/grid.sld) | Cells, distances, the cells a straight line crosses, the fewest closed cells joining two places, and breadth-first distance fields. |
| [`terrain.sld`](src/siegework/terrain.sld) | The seeded land in stages: the biome, hub and nest fronts; noise fields shaped by the biome; clearings; passes so every nest can walk in; and crystal sites. |
| [`world.sld`](src/siegework/world.sld) | The state, and what derives from it: wires, power, sight and exploration. |
| [`colony.sld`](src/siegework/colony.sld) | Orders and their rejections, the work queue with slots and rushing, and production. |
| [`siege.sld`](src/siegework/siege.sld) | Attacks, enemies and their routes, digging, turrets, strikes and alerts, and the outcome. |
| [`simulation.sld`](src/siegework/simulation.sld) | `act` and `advance`, the only ways the world changes, and the journal that replays them. |
| [`game.sld`](src/siegework/game.sld) | The camera, selection, commands, keys, gestures, dialogs and saves. |
| [`view.sld`](src/siegework/view.sld) | The scene in the original's palette and models. |
| [`hud.sld`](src/siegework/hud.sld) | The dock, build menu, queue, opening banner, notices and dialogs. |
| [`public/app.css`](public/app.css) | The HUD's palette and symbols. |

Time is the world's tick: periodic rules fire on multiples of their period,
and only work in progress keeps a count.

The programs in [`tests/`](tests) check the land, that on 64 seeds every
nest can walk in and every crystal can be wired, the economy, the queue,
power, the siege, replay, and on eight seeds across the biomes that an
undefended hub falls soon after the first attack while a hub ringed with
turrets holds for five minutes; `headless.mjs` drives the compiled package through taps and the
HUD, then replays its save.
