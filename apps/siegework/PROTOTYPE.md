# Minimal WebGPU prototype

This is an implementation plan, not a description of a running game. Its purpose
is to expose the hardest composition failures with the smallest playable loop.
Implement each gate and record its evidence before expanding the content.

## The smallest run

Use a fixed small grid viewed from above, one resource, and colored quads. Start
at a fixed hub with enough material to establish extraction. Choose an extractor
site and a defense site; a single bot repeatedly hauls from the extractor to the
hub. A fixed approach route brings one siege threat after a visible countdown.
The defense fires automatically. Hold the hub until the threat withdraws, destroy
the threat first, or lose the hub. A whole attempt takes about three minutes and
can restart immediately.

Provide two candidate extraction sites with different travel times or exposure,
and a small choice of defense positions. A single purchase or upgrade should
trade faster deliveries against defensive strength. Use fixed waypoints for the
hauler and threat; a pathfinder is unnecessary for this question. Display stock,
hauler cargo, time to attack and hub/threat health. No drop animation, 3D meshes,
procedural map or swarm is needed to test the loop.

The controller can choose a building in a small radial menu, move a snapped
preview, confirm and cancel. A keyboard equivalent helps testing. These produce
the same commands; neither input path applies costs or changes world state itself.

## Boundaries to establish first

| Piece | Owner | Initial responsibility |
| --- | --- | --- |
| Rules and state | `apps/siegework/src/siegework/` (planned) | Resource accounting, placement, hauling, damage, timers and outcomes; no DOM, GPU objects or sockets. |
| Presentation and settings | Siegework (planned) | Camera, colors, quad instances, menus, map and tuning; specific shader programs and message schema. |
| Shader language and compiler | Top-level `src/` (planned) | Construct a small GPU AST and compile it to WGSL with explicit types, stage inputs/outputs and binding layout. |
| Browser and WebGPU host | Top-level `src/` (planned) | Input events, scheduling, Wasm calls, GPU resources and uploads; explicit ownership and diagnostics. |
| Transport and serialization | Top-level `src/` (planned) | Bounded messages, connection lifecycle and server/browser transport; no game-specific rules. |
| App build and launch | `apps/siegework/` (planned) | Select libraries, compile artifacts, supply settings, package the page and start the app's server composition. |

Use ordinary library imports for composition. The game may use Lofi bindings and
the supported Scheme forms where useful. The shader library can start as
constructors for validated GPU syntax plus a compiler; a richer surface language
or macros can follow an actual readability need. Its first subset needs only the
vertex and fragment operations used to draw colored quads. Reject unsupported
operations and mismatched interfaces, retain source locations, and make generated
WGSL inspectable. Do not promise full WGSL coverage.

CPU simulation and GPU programs have separate compilation paths:

```text
game libraries → Snail compiler → simulation.wasm → browser/server simulation
shader values  → shader compiler → shader.wgsl    → browser WebGPU pipeline
                                               ↑
                         explicit draw data and buffer layout
```

The shader target is [WGSL](https://www.w3.org/TR/WGSL/). GPU code need not pass
through WasmGC; it has different types, execution and memory rules. The browser
host owns GPU objects and asynchronous work, and copies explicit render data out
of the simulation. A managed Wasm reference is not a GPU-buffer address. Agree on
field types, offsets and alignment once at the upload boundary. Use the
[WebGPU lifecycle and diagnostics](https://gpuweb.github.io/gpuweb/explainer/)
to report shader/pipeline failures and device loss. Clear cleanup and a visible
restart error are enough initially; seamless device recovery can wait.

## Command and state contract

Begin with a fixed-step authoritative simulation and identified players, even
when the authority lives in the same browser as the first player. The following
are proposed data requirements, not callable APIs:

- A command names a session, player, client sequence and action such as placing
  the extractor or buying a defense upgrade. The host associates a connection
  with its player; a packet cannot assign itself another player's authority.
- The authority orders commands at a simulation tick and decides affordability,
  permitted placements, occupancy and purchases. Reject invalid or repeated
  commands without charging twice; report a reason and the acknowledged sequence.
- A snapshot carries the session/build protocol, authoritative tick, resources,
  stable entity IDs and state needed to resume the next tick, plus command
  acknowledgments. Send plain values, never Wasm heap references or GPU handles.
- Local play crosses this same logical boundary in memory. The first server
  transport can use ordered messages and full snapshots; prediction, deltas and
  rollback are unnecessary for these low-frequency decisions.

At the two-client gate, a small server hosts the same compiled simulation rules
and owns the clock and resource ledger. Both browsers still load Snail-generated
Wasm: each can import a snapshot and apply the authority's ordered tick/command
stream to maintain its local simulation. The server settles all outcomes and
resynchronizes clients from snapshots. A client must not advance authoritative
time based on its render rate. Integer grid coordinates and tick counters keep
this first replay experiment small; test equivalence rather than assuming it.

Generic encoding and transport belong in shared libraries; Siegework owns what
its commands and snapshots mean. Parse incoming messages into structured values
before applying rules. Bounds, version mismatches, duplicate commands and stale
sessions must have explicit behavior. Matching clients can reconnect from a full
snapshot. If replay proves too fragile, repair that boundary while the map is tiny.

## Dependencies and current limits

The [host compiler](../../src/lofi/compiler/bootstrap.sld) already accepts an
explicit parsed library map and public entry and returns optimized Wasm. The
[source driver](../../src/lofi/source-driver.sld) supplies file-based collection.
The [existing build recipe](../../build.scm) demonstrates Chibi/native
composition. These are usable starting points, not an implemented browser build.

The [Wasm execution adapter](../../src/lofi/execute.mjs) has a scalar entry ABI
and explicitly supplied Wasm providers. A browser simulation's persistent state,
command/snapshot transfer, imports and repeated calls must be demonstrated with
that boundary. A small scalar dispatcher and explicit data-transfer adapter may
be enough; do not assume multiple managed exports or unrestricted JavaScript
imports are already supported. Keep any new general ABI support in `src/`.

Browser host packaging, required runtime providers, the shader AST/compiler,
WebGPU bindings and multiplayer transport are still missing. Check the exact
imports of the smallest simulation and supply only what it needs. Do not make
the game depend on a Node compiler service inside the browser. Build ahead of
time with Chibi and Binaryen, then load the generated artifacts.

The first execution record must name the browser/version, OS/GPU, required Wasm
features, served origin, build revision and actual providers. Verify WebGPU and
Wasm support on that target; absent capabilities are visible startup failures.
There is no Canvas2D fallback. A DOM status panel is fine, but the world is drawn
with WebGPU from day one.

## The app build recipe

Add a real `apps/siegework/build.scm` when gate 1 can build its declared inputs.
Keep it here even though it imports shared compiler and host libraries. The
following is its intended contract; there is no runnable command yet:

1. Accept explicit repository/app roots and an output directory. Discover app
   libraries under `apps/siegework/src/` and shared libraries under top-level
   `src/`, using the bootstrap host search path appropriate to the current build.
2. Compile the selected simulation entry and its dependencies to optimized Wasm;
   record the scalar ABI and required providers. Compile the app's shader values
   with the shared shader compiler into WGSL and matching buffer/binding metadata.
3. Package the actual Wasm/providers, shader files, reusable browser host, minimal
   page and app settings into the selected directory. Produce a manifest that
   identifies matching protocol/build versions. Fail on an absent input.
4. Once gate 3 exists, package the server entry using the same simulation artifact
   and schema. Keep serving and launch choices explicit in app orchestration.

At first, one game library, one presentation/shader library, a small page and its
launch composition should be enough app code. Add separate modules when their
subject merits it. Reusable browser, shader and server machinery remains visible
under top-level `src/`; a short build script does not mean that work is free.

## Gates and evidence

### 1. A real browser frame and simulation call

Build the smallest simulation that retains a counter or position across calls.
Load its generated Wasm in a browser, drive it through one command and successive
ticks, and draw its result as a moving colored quad through a real WebGPU render
pipeline. Compile its vertex/fragment shaders from the shared GPU AST library.
Use a valid host/upload layout and make a controller action change the Wasm state.

**Pass:** the app's build recipe reproduces those artifacts; a browser run proves
Wasm state changes and GPU drawing. A deliberately invalid shader/interface
reports a useful error. Reload and cleanup do not retain stale GPU resources or
simulation instances. Record the concrete imports and remaining ABI friction.

**Fail:** a screenshot without simulation execution, handwritten JavaScript game
rules, opaque shader strings bypassing the compiler, or a Canvas2D substitute.
If state transfer or providers block the frame, fix the shared boundary before
adding any game content.

### 2. One complete local run

Implement only the fixed map and three-minute loop above. Drive the authority at
a fixed tick rate, independent of drawing. Use the same typed commands that will
cross the network. Add an immediate reset and a deterministic scripted run.

**Pass:** a controller can place, cancel and restart; the bot repeatedly delivers
without orders; a longer haul changes delivery timing; spending on economy changes
what defense is affordable. At least one planned layout survives and one loses.
The hub, stock and outcome match when the same command sequence is replayed at
different render rates. Costs and timers come from the Wasm simulation.

**Fail:** holding buttons to collect resources or repeating worker orders is
required, route distance is cosmetic, or winning is mainly reflex input. Change
the tiny loop before adding more buildings.

### 3. Two browser clients and one authority

Move the local authority behind the small server without rewriting the rules.
Connect two browser clients with distinct player IDs. Use the same map, commands,
simulation artifact and snapshots. Add this before procedural content or art.

**Pass:** both players build in one world; conflicting purchases cannot spend
the same stock twice; duplicate or invalid commands are rejected consistently.
Both clients reach the same authoritative snapshot and outcome. Disconnect and
rejoin one client, and exercise delayed messages and a stale session; recover
from a current snapshot without resetting the shared run. Confirm each browser
executes the simulation Wasm, rather than just displaying server JSON.

**Fail:** two clients merely render independent local worlds, a browser owns the
shared resource ledger, or networking requires a second implementation of rules.
Repair the command/state boundary while the test remains small.

### 4. Decide what is worth expanding

Play the short loop together and record whether placement and spending create
understandable choices with few inputs. Keep a brief account of what each gate
cost in compiler work, shared libraries and app code, with the failed experiments
and diagnostics that guided the fixes. A reproducible build, local and two-client
run records, and a few meaningful command/replay regressions are the evidence.
Compilation alone does not establish any runtime gate.

Only then choose the next game question: more route choices, fair warnings about
a varying finale, or a simple 3D presentation. Full procedural worlds, a large
technology tree, matchmaking, persistence, advanced prediction, a general engine,
whole-WGSL support and GPU tensor/PyTorch integration remain deferred. The last
may motivate future reusable GPU libraries; it is not a dependency of this game.
