# Siegework

Siegework is a cooperative colony defense game built around short, fresh runs.
Place infrastructure, let autonomous workers supply it, and protect the economy
that pays for your defenses. The current experiment is an **eight-minute, fixed
48×36 map** in top-down 2D. Three workers share construction, hauling and repairs;
observation towers reveal opportunities for expansion. There is no player avatar
or individual worker control.

Game rules, client reducers and presentation are Scheme libraries. Real WebGPU
renders the world; a local Node authority runs the same generated Wasm, commits
to SQLite and serves cooperating browser clients. The
[prototype contract](PROTOTYPE.md) separates this experiment from future ideas.

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
and worker assembly wait until Resume, and upgrades can be planned immediately.

This version uses **world schema 3 and client schema 4**. Older schema-1 prototype and schema-2 colony
matches cannot be loaded or hot-reloaded into it implicitly. Use a new output directory for a
fresh colony, retaining the old package and `match.sqlite` together. For example,
build to `"$PWD/build/siegework-colony"` and serve that directory on another port.
Do not delete or replace a database while its authority is running. There is no
automatic schema migration.

## Your first colony

The pale cross is your hub. The turquoise diamonds are deposits; outlined
buildings are paid construction kits waiting for a worker. Small moving dots
are workers, with turquoise cargo when hauling ore.

1. Place an **extractor** on the visible turquoise deposit northeast of the hub
   (the starting cursor is already there). A worker carries its kit from the hub.
   Once built, it produces ore into a local buffer; only deliveries increase the
   ore you can spend.
2. Place **artillery** along the eastern approach. It automatically aims at visible
   enemies within eight cells. A brief muzzle flash, traveling shot and impact mark
   show each actual firing event; damage is immediate, not a ballistics model.
   Towers can reveal threats beyond a gun's own sight.
3. Extend **observation towers** north or east. Their sight starts when workers
   finish construction. Blueprints require currently visible ground and a walking
   route through surveyed terrain. Remembered, shaded terrain stays on the map
   after a tower falls, but it does not show current enemies or permit new orders.
4. Choose what the next delivery buys: another worker, a richer distant mine,
   increased production, wider observation, or another gun. More extraction can
   pile up at a mine when the same workers are busy building or travel is long.

Northern ore is modest and relatively close; the richer eastern deposit needs a
longer supply line through the ridge crossing. Revealing a deposit is only the
first step: the workers still need a known route to build and service it.

| Order | Cost and effect |
| --- | --- |
| Extractor | 40 ore; produces into a 120-ore buffer at its deposit's rate. |
| Artillery | 50 ore; automatic visible-target fire within eight cells. |
| Observation tower | 25 ore; seven-cell sight radius when completed. |
| Assemble worker | 25 ore; ready at the hub after three seconds, up to 12 workers. |
| Upgrade extractor | 40 ore; doubles that mine's production, once. |
| Upgrade tower | 35 ore; increases its sight radius from seven to ten cells, once. |
| Automatic repair | 4 ore per 25 health; keeps 40 ore in reserve, one kit at a time. |

Three workers and 160 ore start each run. Workers share jobs automatically;
construction and repairs leave hauling capacity when an operational mine exists.
Prioritizing a site favors its construction or mine collection. Workers avoid
observed danger on outward trips and return to the hub with their cargo or kit;
interrupted work becomes available again without another construction charge.
Workers themselves are not destructible in this experiment. Completed structures
can be destroyed. Repairs cover the hub and structures and use spare labor.
**Defeating enemies gives no ore.** Combat protects your production and routes.

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
at 7:00. Broad warnings are global even when enemies are outside active sight.
Lose if the hub falls, repel the siege by surviving to 8:00, or exterminate it by
destroying every remaining attacker after the beast arrives. The map and schedule
are fixed so this experiment can test expansion decisions before adding randomness.

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
`codec.sld` (portable schema), `view.sld` (quads/status), `game.sld` (typed commands
and camera), shaders, settings and its [build recipe](build.scm).
The [validation record](VALIDATION.md) distinguishes executed checks from limits.

The broader aim remains a low-input cooperative game, with fresh runs under an
hour and varied, fairly warned finales. Walls, a large tech tree, 3D/elevation,
procedural maps, additional resources and manual artillery aiming are deferred.
This experiment asks whether extending observation, paying for physical logistics
and protecting a distant operation produce useful choices before adding systems.
