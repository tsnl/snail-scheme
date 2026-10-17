# Siegework

Siegework is a cooperative colony defense game built around short, fresh runs.
Place infrastructure, let autonomous workers supply it, and protect the economy
that pays for your defenses. The current experiment is an **eight-minute run on a seeded
48×36 map** in top-down 2D. Three workers share mining, construction, hauling and repairs;
observation towers reveal opportunities for expansion. There is no player avatar
or individual worker control.

Game rules, client reducers and presentation are Scheme libraries. Real WebGPU
renders the world; a local Node authority runs the same generated Wasm, commits
to SQLite and serves cooperating browser clients. The
[prototype contract](PROTOTYPE.md) separates this experiment from future ideas.

The [code tour](TOUR.md) follows a purchase through client input, immutable game
state, durable authority, snapshots and WebGPU rendering, then explains the build
and reload paths.

## Build and play

From the repository root, with Chibi, Binaryen and Node 24 available:

```sh
chibi-scheme -I bootstrap -I wasm-native/scheme apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
node build/siegework/lib/browser/server.mjs "$PWD/build/siegework"
```

Open `http://127.0.0.1:4173` in a browser with WebGPU and WasmGC. A second tab joins
the same colony. The server binds localhost; internet hosting, authentication and
matchmaking are outside this experiment. Prefix the server command with
`PORT=4175` to use another port. The clock advances only while at least one
connected event-stream client reports its page visible. Hiding one tab does not
pause a colony another player is viewing; input focus is not required. The shared
**Pause colony / Resume** buttons explicitly stop and restart simulation for all
players. Manual pause survives visibility changes, compatible code reload and
authority restart. Camera movement and orders remain available; paid construction
and worker assembly wait until Resume; upgrades take effect immediately.

This version uses **world and client schema 6**. Older prototype and colony
matches cannot be loaded or hot-reloaded into it implicitly. Use a new output directory for a
fresh colony, retaining the old package and `match.sqlite` together. For example,
build to `"$PWD/build/siegework-colony"` and serve that directory on another port.
Do not delete or replace a database while its authority is running. There is no
automatic schema migration. Records derive serialization through the shared
S-expression text/binary format; the [code tour](TOUR.md) follows the complete path.

## Your first colony

The pale cross is your hub. The turquoise diamonds are deposits; outlined
buildings are paid construction kits waiting for a worker. Small moving dots
are workers, with turquoise cargo when hauling ore.

1. Place an **extractor** on the visible turquoise deposit northeast of the hub
   (the starting cursor is already there). A worker carries its kit from the hub.
   Once built, one worker occupies its mining slot and produces ore into a local
   buffer. Other workers haul it; only deliveries increase the ore you can spend.
2. Place **artillery** along the eastern approach. It automatically aims at visible
   enemies within eight cells. A brief muzzle flash, traveling shot and impact mark
   show each actual firing event; damage is immediate, not a ballistics model.
   Towers can reveal threats beyond a gun's own sight.
3. Extend **observation towers** north or east. Their sight starts when workers
   finish construction. Blueprints require currently visible ground and a walking
   route through surveyed terrain. Remembered, shaded terrain stays on the map
   after a tower falls, but it does not show current enemies or permit new orders.
4. Choose what the next delivery buys: another worker, a richer distant mine,
   an extra mining slot, wider observation, or another gun. More extraction can
   pile up at a mine when the same workers are busy building or travel is long.

Northern ore is modest and relatively close; the richer eastern deposit needs a
longer supply line through the ridge crossing. Revealing a deposit is only the
first step: the workers still need a known route to build and service it.

| Order | Cost and effect |
| --- | --- |
| Extractor | 40 ore; one worker slot, producing 2, 3 or 6 ore/sec when occupied; 120-ore buffer. |
| Artillery | 50 ore; automatic visible-target fire within eight cells. |
| Observation tower | 25 ore; seven-cell sight radius when completed. |
| Assemble worker | 25 ore; ready at the hub after three seconds, up to 12 workers. |
| Upgrade extractor | 40 ore; adds a second worker slot, once. Empty slots produce nothing. |
| Upgrade tower | 35 ore; increases its sight radius from seven to ten cells, once. |
| Automatic repair | 4 ore per 25 health; keeps 40 ore in reserve, one kit at a time. |

Three workers and 160 ore start each run. A worker parked in a mine produces its
deposit's rate; a worker walking to an empty slot does not. Upgrading adds capacity,
so two occupied slots produce twice as much. Each hauler carries up to **16 ore**.
Growing mine stock means delivery is the bottleneck; empty slots need workers,
and low stock at fully occupied mines calls for more extraction. A lone surviving
worker alternates mining and hauling so recovery can continue.

Workers take nearby reachable work from their actual position. Prioritizing a
site favors its construction, staffing and collection. Kits still require a hub
pickup and ore must reach the hub before spending. Construction and repairs keep
hauling capacity when possible. Repairs cover the hub and structures with one
paid kit at a time and a 40-ore reserve.

Workers flee nearby attackers and wait when no safe route exists. Defend supply
lines with artillery to make them usable again. Workers and completed buildings
can be destroyed; lost ore or kits are not refunded. A living hub assembles one
free emergency replacement in six seconds if every worker is lost. Arrival at a
living hub shelters and heals workers; it does not replace lost mines
or grant ore. **Defeating enemies gives no ore.** Combat protects production and
routes. The field status separates mining, hauling, kit work, retreat, danger
waits, idle workers and assembly. Workers physically at the hub are spread out
visually and counted; they are not all labelled as hiding.

## Choosing a map

Each **New run · next seed** advances the saved map seed, wrapping after 65535.
The starter deposit stays reachable while northern/eastern deposits, obstacles
and crossings vary. The active seed appears in field status. To reproduce a map,
enter a number from **1–65535** into **Next run seed** and press **Start this seed**.
Editing does not affect the current game; submitting starts a fresh shared colony
for everyone. The ordinary New run button ignores the draft and uses the next
seed. Invalid input keeps the current colony. Seed 1 is the original layout.

## Controls and threats

| Action | Keyboard / pointer | Standard gamepad |
| --- | --- | --- |
| Pan camera | WASD or view buttons | Left stick |
| Move cursor | Hover the field or arrow keys | D-pad |
| Choose extractor / artillery / tower | 1 / 2 / 3 or buttons | X / Y / B |
| Place at cursor | Click, Enter or Space | A |
| Assemble worker | F | Left trigger |
| Prioritize site under cursor | P | Right trigger |
| Upgrade site under cursor | U | Left bumper |
| Toggle automatic repairs | R | Right bumper |
| Return camera and cursor home | H | View |
| Pause / resume for everyone | Pause colony / Resume buttons | Use the on-screen buttons |
| New run for everyone | N | Start |

Held WASD and the left stick move the camera continuously; view buttons move it
one cell at a time. The camera can pan three cells beyond each map edge. The plain margin and map
perimeter show where the playable field ends; the minimap separates that boundary
from the visible camera area. Hovering the margin is allowed, but placing there
is rejected without moving the order onto a neighboring cell.

To upgrade or prioritize, **hover or move the cursor onto an existing site, then
use U/P or its button**. Clicking is a placement command, not a selection mode.
Field status names the site, its buffer, workers collecting from it and any
remaining upgrade. It also explains placement failures and labels the last order
separately from the current placement preview.

Eastern waves arrive each minute. An announced raid at 3:30 targets an outer
operation when one exists; otherwise it attacks the hub. The siege beast arrives
at 7:00. Broad warnings are global even when enemies are outside active sight. Actual
hits create named damage alerts and pulsing minimap markers, including at your
own out-of-view assets. Nearby hits coalesce; markers retain the hit location
when a worker or structure dies.
Lose if the hub falls, repel the siege by surviving to 8:00, or exterminate it by
destroying every remaining attacker after the beast arrives. The attack schedule is fixed for this experiment; the map seed varies the routes
and expansion decisions.

## Reload and implementation

Rebuild while playing to replace compatible Scheme code and shader pipelines.
The colony, local camera/cursor/tool and pending requests stay in the stable host.
Invalid builds do not publish a manifest; failed candidates or pipelines keep the
previous generation running. HTML/CSS/host JavaScript changes require a page or
server restart. A page restart creates a fresh local UI model; the authoritative
match is restored from the package's `match.sqlite`.

The [application chapter](../../doc/book/lofi/applications.md) explains typed
handlers, state lifetimes, reload and the shader dialect. Shared code stays under
`src/application/`, `src/browser/`, `src/webgpu/` and `src/scheme/immutable.sld`.
This app owns `terrain.sld` (map and routes), `model.sld` (colony transitions),
`state.sld` (gameplay validation and derived snapshot envelope), `view.sld` (quads/status), `game.sld` (typed commands
and camera), shaders, settings and its [build recipe](build.scm). App HTML/CSS
declare controls and layout; generic `src/browser/input.mjs` maps physical input
and typed integer forms to Scheme handlers. Seed range and restart rules stay in
Scheme.
The [validation record](VALIDATION.md) distinguishes executed checks from limits.

The broader aim remains a low-input cooperative game, with fresh runs under an
hour and varied, fairly warned finales. Walls, a large tech tree, 3D/elevation,
unbounded terrain generation, additional resources and manual artillery aiming are deferred.
This experiment asks whether extending observation, paying for physical logistics
and protecting a distant operation produce useful choices before adding systems.
