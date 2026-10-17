# Siegework code tour

Siegework is a seeded colony simulation built from Scheme libraries. An immutable
world, a separate client model, portable snapshots and pure presentation run in
the browser and in a local Node authority. Shared host libraries connect them to
input, SQLite, the network and WebGPU. See the [play instructions](README.md) and
[compiler tour](../../TOUR.md) for the surrounding build and language.

## Read the app in this order

| File | Responsibility |
| --- | --- |
| [game.sld](src/siegework/game.sld) | Typed match and client commands, camera/cursor movement, snapshot adapters and the scalar entry point. |
| [model.sld](src/siegework/model.sld) | Immutable colony records, purchases, physical worker jobs, economy, combat and simulation ticks. |
| [terrain.sld](src/siegework/terrain.sld) | Seeded geography, deposits, remembered surveys and routing. |
| [state.sld](src/siegework/state.sld) | Gameplay validation and the restart marker around a derived world snapshot. |
| [view.sld](src/siegework/view.sld) | Pure world/client presentation, scene quads and status text. |
| [shaders.sld](src/siegework/shaders.sld) | Scheme-authored GPU expressions and the shader text entry point. |
| [settings.json](settings.json) | Input mappings, remote handlers, restart marker offset and authority clock settings. |
| [build.scm](build.scm) | Chibi compilation of simulation and shader entry points, followed by packaging. |

## Follow an extractor purchase

The initial colony has 160 ore. With the extractor selected, confirming the
starting deposit at `(12, 20)` follows this path:

1. The browser dispatches `confirm` to the local client application. Camera and
   pointer coordinates determine the selected world cell.
2. The client returns its unchanged local state plus a typed `extract` effect
   addressed to the match owner. The browser queues the command with player,
   sequence and epoch metadata, and speculatively applies it for feedback.
3. The authority checks endpoint identity, typed arguments and retry metadata.
   `extract-world` checks the placement and available resources, reserves 40 ore
   and creates a paid construction project. Workers must physically deliver its
   kit before it becomes a working extractor.
4. The runtime stages the replacement and decodes it to establish its validity.
   SQLite commits state, revision, epoch and consumed retry metadata before the
   authority publishes a snapshot. A failed commit publishes no replacement.
5. Browsers restore the accepted world while retaining their own client state.
   Older revisions cannot overwrite newer accepted snapshots. Repeating the
   same consumed request returns its receipt without buying another project.

## State and serialization

`define-immutable-record` declares `Building`, `Bot`, `Enemy`, `Alert`, `World`,
`Survey` and `Client`. Accessors read fields; pure replacements such as
`world-credits-set` preserve every other field and leave prior records intact.
Each transported record opts into
`(deriving derive-serialize derive-deserialize)`.

The shared [(lofi serialization)](../../src/lofi/serialization.sld) instances
construct an S-expression containing nominal type names, constructors, fields
and typed values. [Readable text and compact binary](../../src/lofi/sexp.sld)
represent the same data. Procedures and live resource handles have no supplied
instances. The [application adapter](../../src/application/serialization.sld)
packs the binary into four bytes per `I32` word with checked length and padding.
The snapshot grows with its data rather than reserving fixed record slots.

The client uses this generic snapshot directly. The world inserts its restart
counter at word 1, ahead of the generic byte length and payload. The host reads
that configured offset without interpreting colony records. Encoding derives
this counter from `World`; decoding requires equality with the decoded field.
Schema 6 rejects the former fixed-layout snapshots; existing saves need an
explicit migration or a new run.

Typed decoding establishes record shape and field types. `state.sld` then
checks bounded values, counts, identities, terrain, path continuity, worker
ownership and ore conservation. `game.sld` validates client tool, pointer and
camera bounds. The runtime validates staged output before persistence, so a
malformed candidate cannot replace committed state. These semantic checks are
application rules rather than a second serialization implementation.

## Follow the clock and the view

`settings.json` selects `advance` at 100 ms intervals. The authority submits
clock commands while a connected client is visible. Read `advance-world` and its
named operations in `model.sld` to follow physical work, construction, production,
hauling, attackers, damage and outcomes. Ore becomes spendable on delivery;
kills do not create income. Shared pause freezes the simulation while allowing
inspection and paid planning. Accepted restarts increment the world counter,
rotating the epoch so old commands cannot affect a new run.

Browser animation frames draw state rather than advancing the clock. The client
owns its tool, pointer and camera, including milli-pixel camera coordinates used
by smooth panning. `game.sld` passes those coordinates into `colony-view` and
`colony-status` in `view.sld`. Presentation produces immutable quads and text.
The [WebGPU adapter](../../src/webgpu/quads.mjs) uploads rectangle vertices and
uses the compiled Scheme-authored shaders for a real GPU render pass.

## Build and reload

`build.scm` compiles `shader-entry` and `application-entry` through the Chibi-hosted
compiler, retaining application declarations for the packager. The shared
[build module](../../src/browser/build.mjs) derives endpoint identities, checks
input settings, runs startup validation, writes generation-specific artifacts
and publishes `manifest.json` last.

Live runtimes prepare new code against their current snapshots before installing
it. The browser also validates the shader pipeline. Compatible replacement
preserves the colony, local camera/selection and pending requests without
consuming a tick. Schema, endpoint or restart-marker incompatibility rejects the
candidate. HTML, CSS and host JavaScript changes require a restart.

Run `scripts/test-applications` for actual compiled Wasm transitions, snapshots,
reload and durable retries. The [test guide](../../tests/applications/README.md)
adds two-browser WebGPU checks. The [validation record](VALIDATION.md) describes
executed checks and their limits.
