# Siegework

Siegework is a cooperative logistics and defense game built around short,
self-contained runs. Drop into a hostile place, establish an automated economy,
and turn the material it delivers into fortifications that can withstand a siege.
Each run starts fresh and ends within an hour.

The implementation is a deliberately small, two-minute fixed-map demo. Game
rules, client reducers and shader expressions are Scheme libraries. The world is
rendered with real WebGPU; a local Node authority runs the same generated Wasm,
commits to SQLite and serves cooperating browser clients. The
[prototype contract](PROTOTYPE.md) keeps the acceptance criteria and deferred work
separate from the broader vision below.

## Build and play

From the repository root, with Chibi, Binaryen and Node 24 available:

```sh
chibi-scheme -I bootstrap -I wasm-native/scheme apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
node build/siegework/lib/browser/server.mjs "$PWD/build/siegework"
```

Open `http://127.0.0.1:4173` in a browser with WebGPU and WasmGC. A second browser
tab joins the same match. The server binds localhost; internet hosting,
authentication and matchmaking are outside this prototype. Use `PORT=4175` before
the server command to choose a different local port.

Place an extractor on a turquoise deposit, then place artillery along the eastern
approach. The bot carries ore home automatically. `1`/`2` select extractor or
artillery; arrows move the snapped cursor; Enter/Space places it. `U` upgrades the
mine, `R` repairs the hub, and `N` starts a new run. Pointer controls and gamepad
D-pad/A/X/Y/LB/RB/Start are mapped in [settings.json](settings.json). The siege beast
arrives at 85 seconds. Survive to 120 seconds or destroy all final threats.

Run the build command again while playing to replace compatible Scheme code and
shader pipelines. The match, client selection and pending requests stay in the
stable host. Invalid builds do not publish a new manifest; failed candidates or
pipelines keep the previous generation running. A schema change is rejected;
automatic migrations are not implemented. Changes to HTML/CSS/host JavaScript
currently require a page/server restart. A page restart creates a new local UI
model, while the authoritative match is restored from `build/siegework/match.sqlite`.
Stop the server before removing that file if you want to discard its saved match.

The [application chapter](../../doc/book/lofi/applications.md) explains the typed
handler API, state lifetimes, reload contract and small shader dialect. Shared
code remains under top-level `src/application/`, `src/browser/`, `src/webgpu/`
and `src/scheme/immutable.sld`; this directory owns game rules, codecs, view,
shader composition, settings and its real [build recipe](build.scm).

## The run

1. **Drop in.** Parachute in with a small supply of material and choose a hub
   location. The opening is quick: the interesting decision is where to establish
   the operation, not how long to gather the first handful of resources.
2. **Build an economy.** Place mining or extraction camps near deposits. Bots
   automatically haul to hubs. Distance, route safety and placement determine
   what actually arrives; a rich but exposed deposit may be a poor investment.
3. **Prepare under pressure.** Spend scarce deliveries on more production or on
   defenses. Timed, escalating minion and monster attacks expose weak routes and
   force choices about what is worth protecting.
4. **Survive the finale.** A giant siege beast, a massed swarm, or later a
   combination tests the position. Fortifications and artillery do the fighting.
   The players' leverage comes from preparation, placement and coordinated
   priorities, with time to make a few meaningful adjustments during the attack.

Repelling an assault and exterminating its attackers are distinct outcomes. A
damaged settlement that holds until a beast withdraws can finish a successful
run; destroying the beast outright is a stronger result. Losing the hub ends the
run. Exact scoring and the risk/reward of pursuing extermination remain open.

## Decisions, not busywork

The game is controller-first and asks for few actions per minute. A radial build
menu, placement preview and snapping make construction deliberate. Workers keep
extracting and hauling without repeated orders. Defense operates automatically
within player-chosen priorities. Avoid unit selection chores, manual collection,
routine repair clicking and reflex melee as the core of survival.

The intended view is overhead or slightly isometric, with a simple 3D aesthetic
and clear silhouettes. Resource flow, route length, firing coverage and incoming
threats must be legible before decoration. Colored 2D quads are sufficient for the
prototype; its renderer still uses real WebGPU and shaders from the first frame.

Cooperation should reward dividing attention: one player extends extraction
while another prepares a defensive position, and both can understand the same
shared economy. Player identities and one authoritative simulation belong in the
initial command/state design. Singleplayer can run first, but two browser clients
must work before procedural maps or substantial art.

## Uncertainty with a fair response

The final event varies between runs so a single optimized build is not always
enough. Reward resilient layouts, reserves and the ability to redirect effort.
Warnings and scouting should reveal useful information early enough to change
plans; uncertainty must not make an otherwise sensible run unwinnable through an
unannounced hard counter. The first prototype has a fixed threat and timing so
its economy and defensive decisions can be understood before adding randomness.

## What this app should teach us

Siegework is a small application of Snail's libraries: game simulation compiled
to Wasm, an independently compiled shader program, browser input and GPU bindings,
and a shared command/state boundary that can move from local to server authority.
The browser must execute actual Snail-generated simulation Wasm. JavaScript
adapters may connect browser APIs and move data, but game rules have one source.

The goal is to reveal language, compiler and library friction early. A working
game loop should answer whether a small app can assemble those pieces clearly,
whether diagnostics identify the relevant source, and whether the boundaries
remain usable when a second player joins. The
[application layout](../README.md) keeps reusable machinery in top-level `src/`
and game-specific composition here.

The initial scope is one fixed map, one hub, one extractor, one automated hauler,
one defense and one threat in a short run. Procedural generation, many resources
or buildings, sophisticated art and a general game engine all wait for evidence
from that loop.
