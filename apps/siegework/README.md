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
  enemies dig it out. Water stops only walkers, so wires reach islands
  enemies cannot. Ice is walked but not built on. Every nest has a way in
  to the hub, though it may wind through a pass or over a causeway.
- **Energy.** The colony runs on one store of energy, starting at 160.
  Extractors draw it from violet crystals until they run dry: the starter,
  four cells from the hub in a direction the seed picks, yields 2 a second, richer crystals more, and each
  extractor level multiplies its yield. A destroyed nest exposes a rich
  crystal of its own.
- **The network.** Every finished building is wired to every other within
  reach whose line to it crosses no rock (water is fine). The hub reaches
  9 cells, pylons 7, 10 and 12 by level, and extractors 4. Turrets draw
  power only from a pylon within the pylon's reach. A building the hub
  cannot reach through wires is unpowered and does nothing: no energy, no
  shots, no sight. Rebuild the link and it wakes up.
- **Workers.** Building, upgrading and repairing need a worker at the
  site. The colony starts with three; the hub's "Build worker" button
  trains another for 20 energy in 3 s, up to twenty. Workers take the
  oldest work first, each going to the nearest free worker, and walk
  there; they cannot dig. A worker with an enemy beside it stops to fight
  for 6 damage a second, and one that falls leaves its work's progress
  for the next. Idle workers return to the hub.
- **Building takes time.** A new building needs visible open ground and a
  powered building that can wire to it. Its cost is paid at once and it is
  built once a worker has labored there: pylons take 2 s, extractors 3 s,
  turrets 4 s and walls 2 s, and the colony's first extractor is ready at
  once. Nothing happens until it is ordered: the crystals in sight pulse
  white under a title banner that points to them and links to this guide;
  the camera opens on the starter crystal. Once a crystal is selected, the
  banner points to the build button, which pulses. Orders wait in the
  queue for workers, and an unpowered site waits without blocking the
  others.
- **Portals.** Any built pylon can become a portal for 60 energy in 4 s,
  keeping its reach and wires. Workers jump at once between the hub and
  powered portals, then walk from whichever is nearest their work.
- **Walls.** Walls go on open ground for 10 energy, and upgrade for 10 and
  15 more, to 200, 250 and 300 health. Enemies and workers cannot walk
  through them and turrets cannot shoot past them, but enemies see past
  them and may dig through. Touching walls pass power along to any pylon
  or the hub that can see one. Removing a wall returns half its cost.
- **Rush.** Rushing finishes work at once for four times the share of its
  cost that remains: five times the price when rushed as it is ordered,
  less later. Cancelling refunds the cost.
- **Upgrades, repair and scavenging.** Each building has three levels.
  Upgrades raise pylon reach, extractor yield, and turret damage (one and a
  half, then two times, with a gun more each level), and restore full
  health. Repair restores the hub to full health at one energy for each two
  health it lacks, once a worker has labored there for 2 s. Scavenging
  returns a fifth of what a building cost.
- **The siege.** The first attack leaves the nests at 0:45, then one every
  60 seconds; raids of fast, light raiders replace every other attack
  from 1:45, and a boss leads an attack every nine minutes. Enemies grow
  stronger every 90 seconds, less for each nest destroyed. They know the
  land and where the hub is and make for it, but see buildings and
  workers only within four cells. Each thing that comes into sight may
  provoke an enemy, raiders most often; a provoked enemy attacks the
  nearest building or worker in sight until none is left, then heads on.
  Enemies may dig through rock and walls, likelier the more time it
  saves, and always when there is no other way; one in twenty is a
  burrower that digs three times as fast. Turrets shoot the nearest enemy
  in sight and range, harder up close, and their guns stay where they
  last fired. Shooting an enemy does not draw it to the turret.
- **Winning.** Destroy all three nests to win. Lose the hub and you lose.

## Controls

The same controls work with a mouse, a pen and fingers. Drag to pan, pinch
or use the wheel to zoom, and tap a cell to select it; the selection alone
never orders anything. The dock on the side of your hand shows hub health,
energy, the workers and the nests' strength with the time to the next
attack, then the build menu for the selected cell: a pylon, a turret, an
extractor, a wall, a portal, an upgrade, a rush and closing. A button that
may work later, waiting on energy, work, the network or the first
extractor, turns flat blue with faint lines; one that cannot apply to the
selection fades. Rush finishes the selected work, or else makes new
buildings rushed. A selected building or hub adds cancelling its work and
scavenging it, or at the hub repair and building a worker. Beside it come the menu and turning buttons and the build queue,
with a ring while a work builds and ! while it is unpowered; tap one to go
to it. Under the nests in the opposite corner, a red alert throbs while the
colony is under attack and goes to the latest attack, and a notice says why
an order was refused.

| Key | Action |
| --- | --- |
| 1, 2, 3, 4 | Build a pylon, a turret, an extractor or a wall on the selected cell |
| 5 | Make the selected pylon a portal |
| U | Upgrade the selected building |
| R | Rush the selected work, or make new buildings rushed |
| C, X | Cancel the selected work, scavenge the selected building |
| B | Build a worker at the hub |
| F | Repair the hub to full health |
| WASD, arrows | Pan |
| Q, E | Turn a quarter |
| H | Return to the hub |
| P | Open or close the menu |
| Escape | Back out of a dialog, then close the selection |

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
| [`world.sld`](src/siegework/world.sld) | The state, and what derives from it: wires, power (walls included), sight, exploration and the walls standing as terrain. |
| [`routes.sld`](src/siegework/routes.sld) | What enemies and workers can cross and what each cell costs them, digging included, and the cost fields kept until the terrain changes. |
| [`colony.sld`](src/siegework/colony.sld) | Orders and their rejections, the work queue with rushing, workers taking jobs and walking through portals, and production. |
| [`siege.sld`](src/siegework/siege.sld) | Attacks, enemies' sight, aggression, route plans and digging, turrets, strikes on both sides and alerts, and the outcome. |
| [`simulation.sld`](src/siegework/simulation.sld) | `act` and `advance`, the only ways the world changes, and the journal that replays them. |
| [`game.sld`](src/siegework/game.sld) | The camera, selection, commands, keys, gestures, dialogs and saves. |
| [`view.sld`](src/siegework/view.sld) | The scene in the original's palette and models. |
| [`hud.sld`](src/siegework/hud.sld) | The dock, build menu, queue, opening banner, notices and dialogs. |
| [`public/app.css`](public/app.css) | The HUD's palette and symbols. |

Time is the world's tick: periodic rules fire on multiples of their period,
and only work in progress keeps a count.

The programs in [`tests/`](tests) check the land, that on 64 seeds every
nest can walk in and every crystal can be wired, the economy, the queue,
power, the siege, workers, portals and walls, replay, and on eight seeds
across the biomes that an undefended hub falls soon after the first attack
while a hub ringed with turrets holds for five minutes; `headless.mjs` drives the compiled package through taps and the
HUD, then replays its save.
