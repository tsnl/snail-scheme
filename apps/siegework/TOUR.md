# Siegework code tour

Siegework is a small application built from Scheme libraries: an immutable
simulation, a separate client model, portable snapshots and pure presentation.
The same compiled Wasm runs in the browser and in a local Node authority. Shared
host libraries connect it to input, SQLite, the network and WebGPU.

This tour follows the implemented two-minute, fixed-map prototype. Start with
the [build and play instructions](README.md#build-and-play) to run it. The
[prototype contract](PROTOTYPE.md) distinguishes this slice from the broader
game vision; the [compiler tour](../../TOUR.md) follows Scheme into Wasm.

## Read the app in this order

| File | What to follow |
| --- | --- |
| [`game.sld`](src/siegework/game.sld) | `match-app` and `client-app` declare commands; `game` joins their codecs and presentation; `application-entry` exposes the scalar entry point. |
| [`model.sld`](src/siegework/model.sld) | `World` and its component records explain the state; command functions and `advance-world` explain every simulation change. |
| [`codec.sld`](src/siegework/codec.sld) | `encode-world` and `decode-world` translate between records and the fixed snapshot layout. |
| [`shaders.sld`](src/siegework/shaders.sld) | Scheme macros compose shader expressions, and `shader-entry` exposes the generated text. |
| [`settings.json`](settings.json) | Handler names connect to keyboard, pointer, controller and authority clock inputs. |
| [`build.scm`](build.scm) | Chibi compiles the two exported entry points and invokes the shared packager. |
| [`index.html`](index.html), [`style.css`](style.css) | The page owns the canvas, controls and surrounding interface. |

The four app libraries import reusable code from the repository's `src/`.
Those shared libraries know about applications, snapshots and quads; Siegework
supplies the mines, hauler, enemies and rules.

## Follow an extractor purchase

The initial world has 110 ore. The initial client selects the extractor tool and
cell `(8, 3)`, one of the two deposits. Pressing Enter follows this path:

1. [`client.mjs`](../../src/browser/client.mjs) looks up Enter in the settings
   and calls `local('confirm')`. The local runtime dispatches to `client-app`.
2. The `confirm` handler in `game.sld` reads the selected tool and cell. It
   returns the same `Client` plus a `send` effect describing
   `(extract 8 3)`, addressed to `match-target`. The shared
   [`application` macro](../../src/application/reducer.sld) provides these typed
   command constructors and reducers.
3. The browser converts the effect into a request with an endpoint identity,
   payload, player identity, sequence and match epoch. It queues that request
   and runs the same match reducer locally for speculative feedback.
4. [`server.mjs`](../../src/browser/server.mjs) accepts `/command` requests for
   the configured remote handlers. Its [`Authority`](../../src/application/authority.mjs)
   checks the epoch and retry sequence, then dispatches against the latest
   authoritative snapshot.
5. The match handler calls `extract-world`. The model checks that the run is
   active, no extractor exists, the cell is a deposit and 30 ore is available.
   It returns a replacement world containing the mine and 80 ore. A rejected
   placement returns the prior world.
6. The runtime validates the encoded replacement. The authority commits its
   snapshot, revision, epoch and consumed retry metadata through the
   [SQLite adapter](../../src/application/sqlite.mjs), then publishes the
   accepted snapshot. A failed durable commit publishes no replacement.
7. Browsers receive snapshots through the event stream or command reply. Each
   restores its world snapshot, retaining its own client model, and marks the
   view for redraw. An older revision cannot overwrite a newer accepted one.

The browser's speculative world is temporary. Accepted authority snapshots
replace it. The authority also remembers the latest consumed request per player:
a matching retry returns its receipt without making another purchase.

## State is explicit at each boundary

`model.sld` defines `Mine`, `Bot`, `Turret`, `Enemy` and `World` with
[`define-immutable-record`](../../src/scheme/immutable.sld). Accessors read fields;
functions such as `world-credits-set` construct replacements while preserving
the other fields. Retaining an earlier record preserves its earlier values.

`game.sld` gives the two applications separate state types and owners:

| State | Contents | Lifetime |
| --- | --- | --- |
| `World`, match owner | Clock, resources, hub health, mine, bot and combatants. | The authority owns accepted revisions; SQLite preserves them across server restarts. |
| `Client`, client owner | Selected tool and cursor cell. | Each browser owns its local model; it survives compatible code replacement. A full page reload initializes it again. |

The stable [`ReducerRuntime`](../../src/application/runtime.mjs) holds integer
snapshots outside the replaceable Wasm instance. The
[`scalar bridge`](../../src/application/bridge.sld) decodes a snapshot for a
handler and encodes its replacement. Reads see the prior snapshot while writes
and effects are staged. This makes rollback and code replacement independent
of the old Wasm heap. Immutable application code remains a programming contract;
the current compiler does not prove whole-program purity.

The app owns the meaning of those integers. `codec.sld` declares a 192-word
`I32` world snapshot:

| Word indices | Meaning |
| --- | --- |
| `0` | Schema version, currently `1`. |
| `1`–`6` | Tick, outcome, credits, hull, kills and next enemy ID. |
| `7`–`10` | Mine position, level and stock. |
| `11`–`14` | Bot position, cargo and direction flag. |
| `15`–`16` | Turret and enemy counts. |
| `24`–`47` | Up to eight turrets, three words each. |
| `48`–`127` | Up to sixteen enemies, five words each. |
| Remaining words | Reserved; the encoder initializes them to zero. |

The client codec lives beside `Client` in `game.sld`: four words hold schema,
tool, x and y. Vector indices use `I64`, so the codecs explicitly widen their
`I32` indices. `decode-world` currently checks schema, list counts, tick range
and nonnegative credits; `decode-client` checks schema, tool and cell bounds.
Snapshot words contain values, with no Wasm references or GPU handles.

## Follow one simulation tick

`settings.json` selects `advance` as the clock handler and a 100 ms interval.
The server submits clock commands while at least one connected event stream
reports a visible client. Browser animation frames draw the current state;
they do not advance the simulation clock.

Read `advance-world` from its innermost call outward:

1. Increment the tick of an active run.
2. `haul` produces ore when due and moves the bot toward the mine or hub.
   Cargo becomes spendable credits when the bot reaches home.
3. `spawn-due` adds timed attackers, including the siege beast at tick 850.
4. `fight` moves enemies, fires ready turrets at eligible targets, removes dead
   enemies, rewards kills, advances cooldowns and applies hub damage when due.
5. `finish` chooses the outcome: hub lost, final threats exterminated, siege
   repelled at tick 1200, or still active.

The composition exposes the ordering: a newly spawned enemy participates in
that tick's combat, and the outcome observes the resulting hull and enemies.
Once the outcome is terminal, `advance-world` returns the world unchanged.
`new-run` explicitly constructs a fresh world; the authority changes the match
epoch so requests from the prior run cannot affect it.

## Follow the view onto the GPU

The `view` function in `game.sld` consumes a `World` and `Client` and produces a
list of [`Quad`](../../src/browser/application.sld) values. The `status`
function produces the accompanying text. Scene layout, colors, health bars
and the selection marker all come from these Scheme functions.

The browser asks `runtime.view()` for that presentation when state changes.
[`quads.mjs`](../../src/webgpu/quads.mjs) converts each rectangle into two
triangles, converts logical pixels to clip coordinates, uploads vertices and
submits a real WebGPU render pass. Status text goes into the DOM.

`shaders.sld` supplies the vertex and fragment expressions for this fixed vertex
layout. Its `clip-position` macro expands to a shader expression; the shared
[`shader library`](../../src/webgpu/shader.sld) checks stage and width rules
before emitting WGSL. At build time, the packager runs `shader-entry` from
`shader.wasm` to retrieve that text. Inspect the generated `.wgsl` file in the
build directory to see what WebGPU compiles.

## Follow a build and a compatible reload

`build.scm` supplies the app's source root alongside the shared `src/`, then
compiles `shader-entry` and `application-entry` into `shader.wasm` and
`simulation.wasm`. The compiler also supplies retained application declarations
as `application.syntax.json`.

The shared [`build.mjs`](../../src/browser/build.mjs) joins those declarations
with settings to derive versioned endpoint identities and check input mappings.
It runs a startup check that initializes both owners and queries presentation,
writes generation-specific Wasm and WGSL, and copies the host libraries and page
assets. It publishes `manifest.json` last through a rename, making the completed
generation discoverable.

While the game runs, the authority polls that manifest. The browser receives a
reload notification and loads the referenced artifacts. Each runtime prepares
and validates candidate code against its snapshots before installation; the
browser also waits for shader and pipeline validation. Compatible replacement
keeps world state, local selection and pending requests, without consuming a
tick or rerunning an existing owner's initializer.

Schema or endpoint incompatibility rejects the candidate. There is no automatic
migration. HTML, CSS and host JavaScript changes require a page or server restart;
the replacement path covers compiled Scheme modules and shader pipelines.

## Where to make a change

- Change costs, movement, damage or wave timing in `model.sld`.
- Add a command in `game.sld`, then connect its input and remote exposure in
  `settings.json`; add a page button in `index.html` when appropriate.
- Change stored fields in the record and its codec together. Field meaning is
  part of the schema, even if the word count stays the same.
- Change scene composition in `view` and `status`, or GPU expressions in
  `shaders.sld`.

Run `scripts/test-applications` from the repository root for compiled Wasm checks,
including immutable state, purchases, hauling, combat, reload and durable retry.
The [test guide](../../tests/applications/README.md) also describes the two-browser
WebGPU checks. The [validation record](VALIDATION.md) states what was executed
and the remaining limits.
