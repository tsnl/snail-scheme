# Siegework

Explore a seeded map, mine ore, and destroy three nests before their waves
destroy your hub. The whole game is Lofi; the browser only forwards input,
draws frames and stores the save.

```sh
make site
python3 -m http.server 4191 --directory build/siegework
```

Open `http://127.0.0.1:4191` in a browser with WebGPU.

## Playing

- Your hub starts with 60 ore and three workers. Place an **extractor** (25)
  on the gold deposit near the hub; workers fetch its kit from the hub, build
  it, then haul its ore home.
- **Towers** (25) reveal more of the map. **Guns** (50) shoot enemies and
  nests within six cells. Another **worker** costs 40.
- The first wave leaves the nests after a minute, and one comes every 30
  seconds after, each larger than the last. Enemies attack the nearest
  building. Destroy every nest to win; lose the hub and you lose.
- WASD or the arrow keys pan, the wheel zooms, 1–3 choose a building, Esc
  cancels and P pauses. The game saves itself in the browser.

## How it is built

| Module | Responsibility |
| --- | --- |
| [`grid.sld`](src/siegework/grid.sld) | Cells, distances and breadth-first paths. |
| [`world.sld`](src/siegework/world.sld) | All rules. `advance` is a pipeline of total tick functions: mine, workers, waves, enemies, guns, clean up, judge. |
| [`game.sld`](src/siegework/game.sld) | The camera, tools and pointer around the world; maps each `Input` to a new game. |
| [`view.sld`](src/siegework/view.sld) | Mesh instances and HUD panels for a frame. |
| [`main.sld`](main.sld) | `define-application` ties them together. |

Time is the world's tick: units step on multiples of their period, guns and
strikes fire on periodic ticks, and construction ends at a deadline, so no
unit keeps a countdown.

A worker's `Job` names the building it works toward. An idle worker
returns any ore it carries, otherwise fetches the kit for the oldest site no
other worker has claimed, otherwise collects from the fullest extractor
nobody else is collecting from. A site counts as claimed exactly when some
worker's job names it, every job ends in `Idle`, and a job whose building is
gone is abandoned.

`tests/economy.sld` plays a scripted colony and checks that ore is
conserved; `tests/siege.sld` runs the waves against a defended and an
undefended hub; `tests/headless.mjs` drives the compiled package without a
browser, including a save and restore.
