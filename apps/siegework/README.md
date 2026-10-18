# Siegework

For the current **3D prototype**, use the [3D build and play instructions](three/README.md).
The build recipe on this page is the retained 2D version.

Siegework is a colony defense game built around short, fresh runs, with automatic browser-local
saves and optional explicit online checkpoint save/load.
Place infrastructure, let autonomous workers supply it, and protect the economy
that pays for your defenses. The current experiment is an **eight-minute run on a seeded
48×36 map** in top-down 2D. Three workers share mining, construction and hauling;
observation towers reveal opportunities for expansion. There is no player avatar
or individual worker control.

Game rules, client reducers and presentation are Scheme libraries. WebGPU renders the game, and the browser runs the entire simulation and commits
to IndexedDB. An optional service stores opaque saves without running the game. The
[prototype contract](PROTOTYPE.md) separates this experiment from future ideas.

## Build and play

From the repository root, with Chibi, Binaryen and Node 24 available:

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
```

Compilation produces a static `solo` package. It saves on this browser; serve `build/siegework/solo` as static
files over HTTPS or localhost, including under a subpath. Open the hosted URL
with WebGPU, WasmGC, IndexedDB and Web Locks.
One tab owns the solo save; another tab explains how
to release it. Reopening restores the colony and manual pause. Camera, tool,
cursor and pending input restart with the page. Saves belong to this origin and
the stable `siegework` application ID, and can be lost if browser data is cleared
or evicted. Solo has no server or cross-device synchronization.

Online save/load is an optional build capability; it does not change gameplay or
local saves. Set `SAVE_SERVICE_URL=http://127.0.0.1:4174/saves/` when building to
also produce `build/siegework/synced`. That directory is static too. See the
[static save guide](../../doc/static-saves.md) for running the small save service,
conditional-write behavior and cross-device transfers. Multiplayer and server
simulation have been removed. Existing cloud databases and build directories are
left intact; use a fresh output directory and publish only the static bundle.

## Your first colony

The pale cross is your hub. The turquoise diamonds are deposits; outlined
buildings are paid construction kits waiting for a worker. Small moving dots
are workers, with turquoise cargo when hauling ore.

1. Place an **extractor** on the visible turquoise deposit northeast of the hub
   (the starting cursor is already there). A worker carries its kit from the hub.
   Once built, one worker occupies its mining slot and produces ore into a local
   buffer. Other workers haul it; deliveries increase your hub budget, while
   complete construction kits can also use local stock directly.
2. Place **artillery** along the eastern approach. It automatically aims at visible
   enemies within eight cells with a clear line past rocks. A brief muzzle flash, traveling shot and impact mark
   show each actual firing event; damage is immediate, not a ballistics model.
   Towers can reveal threats beyond a gun's own sight.
3. Extend **observation towers** north or east. Their sight starts when workers
   finish construction. Blueprints require currently visible ground and a walking
   route through surveyed terrain. Remembered, shaded terrain stays on the map
   after a tower falls, but it does not show current enemies or permit new orders.
   Completed towers also accept ore. Placement chooses an automatic railway to
   a nearby connected tower or the hub; its preview shows the proposed route.
   Ore becomes spendable only when freight reaches the hub.
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
| Observation tower | 25 ore; seven-cell sight, ore depot and automatic upstream railway when completed. |
| Assemble worker | 25 ore; ready at the hub after three seconds, up to 12 workers. |
| Upgrade extractor | 40 ore; adds a second worker slot, once. Empty slots produce nothing. |
| Upgrade tower | 35 ore; increases its sight radius from seven to ten cells, once. |
| Arm tower | 50 ore; adds artillery while retaining its sight, depot and railway. |
| Move completed tower / artillery | 5 hub ore; up to two cardinal cells; waits for supplies to drain and preserves damage/upgrades. |

Three workers and 160 ore start each run. A worker parked in a mine produces its
deposit's rate; a worker walking to an empty slot does not. Upgrading adds capacity,
so two occupied slots produce twice as much. Each hauler carries up to **16 ore**.
Growing mine stock means delivery is the bottleneck; empty slots need workers,
and low stock at fully occupied mines calls for more extraction. A lone surviving
worker alternates mining and hauling so recovery can continue.

Workers compare complete construction trips: finish carried ore delivery, pick up
materials, then reach the site. They jointly choose a worker and a source: the
hub, an extractor buffer, or a connected tower stockpile. One source must contain
the whole 25/40/50-ore kit; split-source pickups are not implemented. The reserved
kit stays at its source until collected, and cannot also go to haulers or trains.
Local materials pay the construction cost directly without also charging the hub.
After the first 16 ore arrives, one highest-rate extractor keeps up to 50 loose
ore for nearby construction. Haulers collect the excess. This cache needs at least
three workers and 40 hub ore; falling below either releases it for ordinary hauling.
It delays some hub income in exchange for local pickup opportunities. The hub may
still provide the fastest complete trip. Existing builders keep their
commitments. Waiting orders are reconsidered each tick; with enough workers,
two remain available for mining and hauling.

**Cancel build** returns an uncollected kit to its source. Carried kits return
physically to the hub before a refund. A locally funded returned kit becomes
newly delivered hub ore; a hub-funded kit reverses its original charge. Losing a
source loses its uncollected reserved kits; carried kits survive source loss.
Cancelling a build switches to Manual so automation does not recreate it.
There is no automatic repair: damage persists, and destroyed structures can be rebuilt.

**Move** is a small correction for completed towers and guns. Hover the source,
press M, then click a visible destination at most two cardinal cells away.
The 5-ore fee reserves the move. The old structure keeps operating while existing
stock, kit pickups and loaded incident rails drain. New deliveries reroute; child
shuttles wait before loading another trip. The move then preserves identity,
health and upgrades and recomputes the affected empty links. You need not wait and
click again. C cancels a queued move and refunds its fee exactly once. If an
affected route becomes invalid, the move cancels and refunds automatically;
destruction consumes the fee. Extractors remain on their deposits. Pause,
save/reopen and compatible reload preserve the queue.

## Try optional automation

New runs start in **Manual**. **Auto · Explore** and **Auto · Defend** are a gameplay
experiment: do you enjoy choosing expansion sites, or choosing a colony direction?
Opening **Manual mode** exposes placement, staffing and upgrade controls and stops
future automatic purchases. Existing commitments continue in either mode.

Auto develops visible, safely reachable deposits first, assembling workers when
needed. It opens one construction project at a time and keeps 40 hub ore in reserve.
Both focuses maintain a growing defense floor as the siege advances. Explore greedily chooses tower sites
that reveal the most new area and serve already observed deposits. Defend chooses
clear firing coverage over known approaches to the hub and existing operations,
expanding sight when no useful firing site is known.
It uses the same prices, observations, routes and worker rules as Manual. The
status gives one current action or reason for waiting. Manual moves remain available.

This is a deterministic greedy policy, not globally optimal play under fog and
changing combat. To compare, start the same seed in Manual, play a run, then start
that seed again and select an Auto focus. Compare the decisions you enjoyed,
extraction and delivery delays, exposure and survival—not just build count. Auto
may make a poor strategic choice; Manual is an equally supported way to play.

Haulers choose the nearest reachable connected depot or hub. Each automatic rail
has one shuttle carrying up to **32 ore**, with a visible empty return journey.
Freight may pass through several towers; depot stock can supply whole construction
kits, while rail cargo stays committed until arrival. A route remains fixed while its endpoints survive. When a tower falls,
freight on its broken links is lost and surviving depots seek a new upstream
connection. The rails themselves do not block walking or take damage. Arming a
tower keeps all its logistics roles and uses the same eight-cell fire range as
standalone artillery.

Workers flee nearby attackers and wait when no safe route exists. Defend supply
lines with artillery to make them usable again. Workers and completed buildings
can be destroyed; lost ore or kits are not refunded. A living hub assembles one
free emergency replacement in six seconds if every worker is lost. Arrival at a
living hub shelters and heals workers; it does not replace lost mines
or grant ore. **Defeating enemies gives no ore.** Combat protects production and
routes. The compact field status gives the colony mode, current plan and economy;
hover a structure for its supplies, staffing or freight. Workers physically at
the hub are spread out visually.

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
| Switch to Manual | Open Manual mode | Right trigger |
| Upgrade site under cursor | U | Left bumper |
| Cancel unfinished site under cursor | C | Left stick click |
| Arm tower under cursor | T | Right stick click |
| Move completed tower / gun | M, then destination click | Right bumper, then A |
| Return camera and cursor home | H | View |
| Pause / resume for everyone | Pause colony / Resume buttons | Use the on-screen buttons |
| New run for everyone | N | Start |

Held WASD and the left stick move the camera continuously; view buttons move it
one cell at a time. The camera can pan three cells beyond each map edge. The plain margin and map
perimeter show where the playable field ends; the minimap separates that boundary
from the visible camera area. Hovering the margin is allowed, but placing there
is rejected without moving the order onto a neighboring cell.

To upgrade, move, cancel or arm, **hover or move the cursor onto an existing
site, then use U/M/C/T or its button**. Clicking is a placement command, not a selection mode.
Field status names the site, its buffer, workers collecting from it and any
remaining upgrade. Reserved workers retain their current job marker, with a gold
construction commitment mark. The status separates mine stock, depot stock,
freight and refunds still returning to the hub. It also explains placement failures and labels the last order
separately from the current placement preview.

The first eastern group spawns at 1:00, then ordinary follow-ups use 45-second
spacing with groups growing from four to seven. Outpost raids at 3:30 and 5:30
target an outer operation when one exists; otherwise they attack the hub. The
first raid replaces the nearby 3:15 wave, and the second replaces its ordinary
wave. At 7:00 the unchanged siege beast spawns with six ordinary escorts. The
forecast shows the next spawn's time, kind and size; arrival depends on walking
distance and encounters. These warnings are global even outside active sight. Actual
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
previous generation running. HTML/CSS/host JavaScript changes require a page reload. A page restart creates a fresh local UI model; the authoritative
match is restored from IndexedDB.
Solo polls its static manifest for compatible updates; it needs no application server. A failed local save stops the clock with retry/reload guidance. A successful
retry resumes it. A forced tab/browser termination recovers completed commits;
it cannot guarantee that an unfinished command was saved.

The [application chapter](../../doc/book/lofi/applications.md) explains typed
handlers, state lifetimes, reload and the shader dialect. Shared code stays under
`src/application/`, `src/browser/`, `src/webgpu/` and `src/scheme/immutable.sld`.
This app owns `terrain.sld` (map and routes), `model.sld` (colony transitions and physical kit ownership),
`planning.sld` (optional colony investment policy),
`state.sld` (derived transport and colony invariants), `view.sld` (quads/status), `game.sld` (typed commands
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
