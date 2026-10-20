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
  nests within five cells. Another **worker** costs 40.
- The first wave leaves the nests at 45 seconds, and one comes every 30
  seconds after, each larger than the last. Enemies attack the nearest
  building. Destroy every nest to win; lose the hub and you lose.
- WASD or the arrow keys pan, the wheel zooms, 1–3 choose a building, Esc
  cancels and P pauses. The game saves itself in the browser.

## How it is built

| Module | Responsibility |
| --- | --- |
| [`grid.sld`](src/siegework/grid.sld) | Cells, distances and breadth-first paths. |
| [`world.sld`](src/siegework/world.sld) | All rules. `advance` is a pipeline of total tick functions: mine, workers, waves, enemies, guns, settle. |
| [`game.sld`](src/siegework/game.sld) | The camera, tools and pointer around the world; maps each `Input` to a new game. |
| [`view.sld`](src/siegework/view.sld) | Mesh instances and HUD panels for a frame. |
| [`main.sld`](main.sld) | `define-application` ties them together. |

An idle worker follows one rule: return any ore it carries, otherwise fetch
the kit for the oldest waiting construction site, otherwise collect from the
fullest extractor nobody else is collecting from. Its `Task` enum says which
of these it is doing and toward which building.

`tests/economy.sld` plays a scripted colony; `tests/headless.mjs` drives the
compiled package without a browser, including a save and restore.
