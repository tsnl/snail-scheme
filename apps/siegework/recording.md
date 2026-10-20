# Recording and inspecting games

Recording and replay are **deferred** while Siegework stabilizes. Its package
sets `recording.enabled` to `false`: the browser neither loads the recording UI
nor captures transition history. Ordinary IndexedDB saves, reload and restart
continue normally. Headless inspection reads the current World on demand.

The reusable recording libraries and manual developer tests remain available.
The rest of this document describes that retained developer format, not a
currently available player feature. Inspection metadata stays in the manifest
for headless diagnostics and existing analysis tools. The compact-map revision
uses `siegework-colony-v15`, World15/Client8 and inspection projection 3.
World12 recordings belong to earlier packages and cannot be loaded into the
smaller map. Historical measurements below retain their original version labels.

## What a dump means

Each entry identifies the handled World command, emitted effects, committed
revision, code generation, run marker and resulting exact encoded World. A
`persisted` flag says whether the transaction awaited its persistence callback.
The solo browser records after the IndexedDB transaction and normal state,
revision and effect publication. Rejected reductions and failed saves produce no
commit entry. Client camera and display-animation messages are excluded.

An unchanged, effect-free call to the manifest's clock endpoint is also omitted.
These idle polls still persist and advance the live revision, so retained
revisions and elapsed times can have gaps. Active ticks, emitted effects and
all other World commands remain recorded, including unchanged user commands.
Idle time before play, while paused or after a game finishes cannot evict play.

Commands/effects are the recorded event stream. Most game handlers emit no
domain events: a dump does **not** claim to contain every individual hit, job
decision or economic transfer. Those details can be observed or inferred from
successive Worlds, with that distinction preserved in analysis.

Checkpoint, explicit restore, run-marker change and generation change start
independent keyframes. Recording off/on creates a new checkpoint after the gap.
Capture failures stop recording and keep its valid prefix. The pause panel shows
the failure. Reducer traps retain the runtime's existing separate
`snailApp.runtime.lastFailure` reproduction diagnostic.

The default packed-history limit is 64 MiB and 12,000 entries. Chunks start with
a full I32 keyframe and contain at most 128 entries. Later entries use the
smaller of a prefix/suffix splice or sparse index/value replacements. A chunk
also closes before exceeding the byte budget. Eviction removes whole chunks;
the panel and dump explicitly report the removed entries. Ten minutes is a
retention target, not a promise for every possible World.

`stats()` reports actual packed word bytes, UTF-8 metadata bytes, framing bytes,
chunk/entry counts, and the retained reference to the latest runtime bank.
JavaScript objects, the manifest, Wasm heaps, reconstruction workspace and export
buffers are additional bounded memory; the byte limit is not a total-tab heap
limit. Binary `.snailrun` export avoids a large decimal JSON word array. Import
rejects files over 72 MiB before reading them, checks framing/counts/word bounds,
ordered sparse indices, schemas and boundary keyframes, and reconstructs the
chain. The real Scheme decoder validates a selected World before playback or
analysis uses it. A malformed selected World cannot overwrite the colony.

Playback instantiates a separate Wasm runtime and Client. It restores snapshots,
discards effects, permits only camera commands, and has no save callback. The
live host clock stops for playback and the saved colony remains unchanged.
Rendering uses the currently installed compatible code; recorded and renderer
generations appear together. Historical commands are never executed again, and
the dump does not archive old Wasm, shaders, camera motion or historical pixels.

## Browser diagnostics

```js
const history = snailApp.recording.recording;
history.stats();
history.entry(history.last);       // Command/effects and commit metadata.
history.snapshot(history.last);    // An independent exact Int32Array.
snailApp.recording.export();       // Download the live history or open replay.
await snailApp.recording.replay();
await snailApp.recording.seek(history.first);
snailApp.recording.playback.inspect(); // Pure Scheme-derived observations.
await snailApp.recording.exit();
```

`Open dump` validates a file and opens it in the same isolated player. It never
imports a checkpoint into the saved colony. To retain a dump programmatically,
use `history.exportBlob()`. The immutable Blob captures a stable export without
exposing the retained word buffers. `RunRecording.import(arrayBuffer)` in
`src/application/recording.mjs` reconstructs the same bounded recording in Node
or the browser. Imported recordings start with capture disabled.

## Analyze an exported game with Node

Use a compatible built Siegework package with Node 24/WasmGC:

```sh
node apps/siegework/analyze-recording.mjs game.snailrun build/siegework/solo > analysis.json
```

The command validates each retained World through the actual compiled Scheme
decoder. The app-owned `(siegework recording)` projection supplies tick, seed,
outcome, ore production/delivery/commitment/loss counters, hull/nest health,
kills/casualties, buildings, workers, enemies, permanent surveys and frontier
distance. It also reports known versus currently visible nest state. JavaScript
collects those values into segments, command lists and ten-second observations.
The `siegework-observations-v2` output also records observed per-front clears and
exhaustion-count increases between adjacent retained states. These are observations,
not separately emitted domain events; checkpoint gaps do not invent clear dates.

`firstObservedNestKnown` and `firstObservedNestDamage` are observations within
the retained segment, not recovered dates before its first checkpoint. `spent`
is the model's net commitment counter and can decrease after refunds; changes
in hull health do not separately measure damage and repair. Restores and run
changes start new analysis segments so their jumps are not counted as ordinary
play. The complete encoded World remains in the dump for deeper inspection of
individual structures, paths, cargo and enemy targets.

## Reproduce the checks

```sh
node tests/applications/recording.mjs build/siegework/solo
node tests/applications/recording-profile.mjs build/siegework/solo 6000 /tmp/dense.snailrun
node tests/draw3d/recording-browser.mjs http://127.0.0.1:4191 http://127.0.0.1:9336
```

The profiler executes real ticks between explicit dense-fixture restores. Its
capture timings measure instrumented CPU overhead, not frame rate or natural
player behavior. The browser check applies only to a developer package with
`recording.enabled` set to `true`; it is skipped by Siegework hosting checks
while the feature is deferred. It requires a disposable origin/profile and
exercises a real IndexedDB abort, dump import, camera/gameplay input isolation
and saved-checkpoint reload. Never run that fixture against a player's save.

The current World12 dense diagnostic uses 64 depots, 24 workers, a fully paid
level-six hub and 128 enemies. All fixture funds are withdrawn from finite
reserves. Across 6,000 actual advances its maximum World is 88,180 bytes; the
64 MiB recorder retains ticks 1,380–6,000 (7 minutes 42 seconds), evicting 1,403
entries. Capture costs about 0.038 ms median and 0.050 ms at the 95th percentile.
The matching pre-deposit hub checkpoint with the same legal population retains
the same interval, at 86,252 maximum World bytes. These are instrumented CPU and
retention observations, not frame rates or natural games.

Historical World11 used a 64-worker fixture: 95,312 bytes per World and ticks
1,920–6,000 retained. That population is no longer legal in World12. The separate
100 KB synthetic fixture changing 249 words per tick retains all 6,000 ticks in
about 16.8 MiB. Serialization shifts and crowd movement affect packed cost, so
retention is reported rather than promised.
