# Siegework as a local environment

The browser, Node experiments, and MCP tools execute the same compiled
`simulation.*.wasm` and its Scheme game rules. Node uses
[`ReducerRuntime`](../../src/application/runtime.mjs) without calling the view,
starting a wall clock, loading WebGPU, or opening a network listener. The existing
HTTP service remains an optional opaque save service; it does not simulate games.

Build one package for either host, using Node 24, Chibi and Binaryen:

```sh
chibi-scheme -I bootstrap apps/siegework/build.scm "$PWD" /tmp/siegework-environment
node tests/applications/headless.mjs /tmp/siegework-environment/solo
node apps/siegework/environment-cli.mjs /tmp/siegework-environment/solo
```

The package must provide player observation ABI version 1; older gameplay builds
deliberately fail the environment's version check. Rebuild from source to obtain
the extension, which changes neither World14 nor gameplay. Tested package
identities and temporary artifact paths are recorded in [VALIDATION.md](VALIDATION.md).

## Node API and episode semantics

Run this from the repository root with `node --input-type=module`:

```js
import {openEnvironment} from './apps/siegework/headless.mjs';

const env = await openEnvironment('/tmp/siegework-environment/solo', {
  horizonTicks: 12000, maxTicksPerStep: 600,
});
try {
  const {observation} = await env.reset(1);
  const candidate = observation.buildCandidates.find(site => site.kind === 1);
  const result = await env.step({type: 'build', ...candidate}, 100);
  console.log(result.reward, result.terminated, result.truncated, result.info);
  const {checkpoint} = await env.checkpoint();
  await env.step({type: 'wait'}, 100);
  await env.restore(checkpoint);
} finally { await env.close(); }
```

`openEnvironment` loads the package and initializes seed 1. `reset(seed)` starts
a reproducible fresh instance with a seed in 1..65535. `reset`, `observe`, and
`restore` return `{observation, info}`; `step` additionally returns
`{reward, terminated, truncated}`. These conventions are
[Gymnasium-inspired](https://gymnasium.farama.org/api/env/); this is a Node API,
not an implemented Python Gymnasium environment or fixed tensor/action space.

Every operation joins one FIFO. Input objects are captured before waiting.
An entire action and its tick count must parse before any game transition runs.
Malformed requests leave the game unchanged. A valid but game-rejected purchase
can update its ordinary notice; **the requested wait still runs afterward**.
`info.buildReason` preserves a construction command's exact decision, including
zero for acceptance, even when later ticks replace the current notice.

`step(action, ticks)` submits one action and up to `ticks` simulation ticks,
stopping at game termination or the episode horizon. Zero ticks submits only
the action. There are ten simulation ticks per game second. Paused and unstarted
worlds do not advance; only the first accepted free extractor starts the clock.
`info.ticksAdvanced` and `episodeTicks` count actual advancement, not attempted
ticks or elapsed host time. Ordinary actions do not advance time themselves.

The default request limit is 600 ticks, configurable in 1..6000. The default
external horizon is 12000 actual ticks (20 simulation minutes), configurable in
1..10000000. Victory or loss sets `terminated`; reaching only the host horizon
sets `truncated`. If both occur on the same tick, game termination takes
precedence. A finished episode rejects further steps until reset or restore.
Observation remains available.

Checkpoints return only an opaque token. At most 16 are retained per environment;
reset clears them and close releases them. Tokens cannot cross environments or
processes. Restore prepares a fresh instance, validates the saved World, and
restores its episode ticks and cumulative reward together. No full snapshot is
returned to a policy. Persistence/export of these tokens is not implemented.

An unexpected simulation or read-only observation fault in the current episode
requires recovery.
Simulation faults may occur after earlier ticks have committed.
The error's `info` reports `confirmedTicksAdvanced`, `episodeTicks`, and
`recoveryRequired`. It does not claim to roll back the batch or expose a Wasm
dump. Observe, step and checkpoint then require reset or restore first.
Standalone observation faults report zero requested/confirmed ticks. The sanitized
error retains its original `cause` for trusted Node debugging; JSONL and MCP
serialize only the safe message and progress info. Malformed requests and ordinary
game rejections do not fault the environment.
Failure while preparing a reset/restore candidate also returns a safe error, but
preserves the current episode, checkpoints, accounting, and existing fault status.
A healthy episode remains usable after failed preparation.

The default reward is +1 for victory, -1 for defeat, and zero otherwise, including
horizon truncation. Node callers may pass `reward: {victory, defeat, delivered,
hull, casualties, tick}` to override weights; omitted entries retain their
defaults. Each nonterminal field weights its public after-minus-before delta.
For example, `{delivered: 0.01, casualties: -1}` is an explicit research heuristic,
not a game rule or validated measure of strategy quality. The environment never
rewards hidden nest damage or hidden discoveries. Heuristic weights are fixed
for the environment's lifetime.

## Actions and player observations

| Action | Fields | Effect |
| --- | --- | --- |
| `wait` | none | Only the requested ticks. |
| `build` | `kind`, `cell` | Worker construction: **1 extractor (free), 2 artillery (50 ore), 3 observation tower (25)**. |
| `upgrade` | `cell` | Upgrade that building, or hub capacity when selecting a hub cell. |
| `cancel` | `cell` | Cancel an unfinished building, upgrade, pending move, or Scavenge job. |
| `scavenge` | `cell` | Assign a worker to demolish a completed non-hub building; pay its quoted 20% investment refund only on completion. |
| `relocate` | `from`, `to` | Ordinary paid move of a completed tower/artillery. |
| `fabricate` | none | Order a worker (25 ore), subject to the game's capacity and available workers. |
| `repair` | none | Order the game's paid hub repair. |
| `pause` | Boolean `paused` | Explicitly pause/resume. |
| `resign` | none | End the run intact, freeze simulation, and reveal the map. |

Actions are objects such as `{"type":"build","kind":1,"cell":2017}`.
Use a returned candidate's cell; do not assume an example cell is suitable for
another seed. Unknown types and extra fields are rejected. Restart belongs to
`reset`, not the action vocabulary. Legacy inert commands and presentation/camera
commands are not exposed.

Coordinates are explicit: `cell = x + y * width`, where width/height are 64.
Hub `x/y` and building `moveX/moveY` use grid cells; `-1` means no pending move.
Workers and enemies use integer world-space `x/y`, with `cellSize = 40` units
per grid cell. A cell center is `(x * 40 + 20, y * 40 + 20)`; divide an entity's
position by 40 and floor to obtain its grid coordinates.

[`observation.sld`](src/siegework/observation.sld) reads the validated World once
and writes bounded scalar rows. The Node decoder names these fields; it does not
deserialize World or reconstruct visibility/game rules. Version 1 contains:

- Public clock, outcome, pause/start flags, ore, hull, economy totals, kills and
  casualties, plus hub capacity and its current notice.
- `tiles`: only known terrain, with `visible`, `terrain` (0 rock, 1 ground,
  2 water), `depositRate`, `oreRemaining`, and `rockRemaining`. Outside current
  sight only original seeded geography is returned; dynamic reserves/damage
  are `-1` (unknown). This is not a remembered-state map of past breaches.
- `buildings`: player structures, excluding currently hidden unfinished
  construction as in the presentation rule. It includes identity, kind, cell,
  level, health, stage, stock, legacy armed flag, cooldown, and pending move.
- `workers`: owned identity, world position, health, job, and carried ore/kit.
- `enemies`: only currently visible identity, world position, health, kind and
  rank. `nests` contains only known sites; health is `-1` outside current sight.
- `buildCandidates`: currently visible cells/kinds passing the real cheap
  placement preview. These are **not an exhaustive legal-action mask or a
  guarantee of acceptance**: the command also proves route and kit ownership.
  `purchaseReasons` supplies the actual fabrication/repair/hub-upgrade checks.

The seed is public and deterministic. This is a policy-observation contract,
not adversarial secrecy against a program reconstructing seeded geography.
Full snapshots and the recording projection include hidden information. They
are available only to Node callers opening with `{diagnostics: true}` through
`env.diagnostics()`, or JSONL explicitly started with `--diagnostics`. MCP never
lists a diagnostic tool. Ordinary observations remain filtered in diagnostic mode.

The numeric vocabulary comes from the model and
[`reason-text`](src/siegework/status.sld), rather than a second host rules engine:

| Codes | Meaning |
| --- | --- |
| Outcome 0 / 1 / 3 | Ongoing / hub destroyed / all three nests destroyed. |
| Building stage 0 / 1 / 2 / 3 | Paid kit awaiting a worker / kit being carried / operational / kit reserved for a worker. |
| Building stage 4 / 5 / 7 | Operational structure awaiting upgrade: mirrors 0 / 1 / 3. |
| Worker job 0..3 | Available, collect, deliver ore, deliver building kit. |
| Worker job 4..7 | Return to assemble worker, return kit, hub assembly, blocked return (also accepts old retreat saves). |
| Worker job 8..11 | Mining, travel to mining slot, legacy blocked work (retried), collect reserved kit. |
| Worker job 12..15 | Return for repair, repair, return for hub expansion, assemble expansion. |
| Enemy kind 0 / 1 / 2 | Siege minion / outpost raider / final beast. Rank is its independent strength tier. |
| Reason 0 / 1 / 2 / 3 | Accepted or available / outside sight / rock or water / occupied. |
| Reason 4 / 5 / 6 / 7 / 8 / 9 | Needs deposit / reserve deposit for extractor / no surveyed route / insufficient ore / capacity limit / game finished. |
| Reason 10 / 11 / 12 / 13 | Construction ordered / unavailable upgrade / upgraded / worker ordered. |
| Reason 15 / 16 / 17 / 18 / 19 | Outside map / invalid seed / cancellation refunded / materials returning / no unfinished order. |
| Reason 20..26 | Upgrade queued, move queued, move complete, move cancelled, unavailable move, move too far, route changed. |
| Reason 27 / 28 / 29 / 30 / 31 | No safe available worker / reserved rail route / full hull / repair pending / repair ordered. |
| Build reason 32 / 33 | No walking route / no kit source. These retain World notice 6 for presentation. |
| Reason 35 / 36 / 37 / 38 / 39 | Hub upgrade pending / maximum capacity / hub upgrade ordered / buy first extractor / deposit depleted. |

## JSONL for local RL processes

Send one UTF-8 JSON object per line to the CLI's stdin. Stdout contains only
responses; startup errors go to stderr. The process serves requests sequentially
and exits on EOF or successful `close`. Lines are bounded to 65536 bytes, and
output honors pipe backpressure. No authentication or network setup is involved.

```json
{"id":1,"method":"reset","params":{"seed":1}}
{"id":2,"method":"observe"}
{"id":3,"method":"step","params":{"action":{"type":"wait"},"ticks":100}}
{"id":4,"method":"checkpoint"}
{"id":5,"method":"close"}
```

Responses are `{id, result}` or `{id, error: {message, info?}}`. Restore takes
`{"checkpoint":"the returned token"}`. JSONL returns full player observations;
it has no tensor conversion or Python package dependency. Horizon and batch
limits can be set with `--horizon=12000 --max-ticks=600`.

## MCP stdio

Configure a local MCP client to launch:

```json
{
  "command": "node",
  "args": [
    "/absolute/repository/apps/siegework/environment-cli.mjs",
    "--mcp",
    "/tmp/siegework-environment/solo"
  ]
}
```

The server implements the
[2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports),
`ping`, `tools/list`, and `tools/call`. Initialize and send
`notifications/initialized` before using tools. It exposes `siegework_reset`,
`siegework_observe`, `siegework_step`, `siegework_checkpoint`, and
`siegework_restore`, with the same semantics as Node/JSONL. Tool schemas describe
the actions, units, and configured tick limit. Protocol failures use JSON-RPC
errors; executed tool input/business failures use the
[tool error result](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
with `isError: true`. Full player results appear as both text and structuredContent.

MCP responses default to the first 32 elements of each observation array.
`siegework_observe({offset, limit})` pages each collection independently, with
limit 1..256 and explicit returned/total/omitted counts. Scalar colony facts
are never paged. Use the counts to distinguish an empty collection from an
omitted page. This bounds individual tool responses as explored territory grows.

## Duration and measurement

Games are not guaranteed to last 10–20 minutes. A loss may happen earlier,
victory requires all three nests, and the game has no 20-minute win/lose timer.
The existing paid seed-one expedition loses at **7:34**; it does not establish
typical human or policy duration. An environment horizon is an external research
limit and must be reported as truncation, never relabeled as a game loss.

For experiments, record package generation, seed, complete action/tick sequence,
horizon, reward weights, outcome, `simulationTick`, `elapsedSeconds`, and
`episodeTicks`. Repeat across seeds and policies; report victories, defeats and
truncations separately. Save opaque checkpoints only for within-process branching.
Use explicit privileged diagnostics for offline debugging, and keep them out of
policy inputs and reward calculations.

The focused runner checks actual Wasm snapshot parity, visibility, first purchase,
request validation, queue order, terminal/horizon precedence, checkpoint/reward
restoration, fault recovery, and both real subprocess protocols. One development
sample ran 600 ticks in 156 ms, with initial and tick-600 observations of 23171
and 34441 JSON bytes. These are instrumented local diagnostics, not a clean
benchmark or a throughput guarantee. Rendering, browser persistence and learning
quality are covered by separate work.

Building observations include `scavengeRefund` (completed construction and upgrade
investment divided by five, rounded down) and `scavenging` (a worker currently
claims demolition). Stored ore recovery is separate from this structural quote.

World14 uses `siegework-colony-v14` for sparser resource placement on the 64×64 map. Earlier saves and
checkpoints are rejected rather than reinterpreting their deposit identities. Extractor
construction costs zero ore but still requires a worker to reach the site; its
40/160-ore upgrades remain paid. Outcome 4 means resigned: the intact world is
frozen and fully revealed, and a new run starts through the normal reset intent.
