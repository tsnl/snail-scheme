# Applications, state, and hot reload

For a guided introduction, follow the [five small application tutorials](tutorials/index.md):
a counter, immutable inventory, local commands, a shared marker board, and saving
and reloading that board. This chapter is the reference for their contracts.

An application is a collection of typed handlers over one state type. A handler
receives a stable state value and its payload, then returns a replacement state
and effect descriptions. It does no asynchronous work. The runtime owns storage,
ordering and delivery. This is a library programming model, not a compiler proof
of purity: use immutable records and lists, and do not mutate values reachable
from an earlier state. Keep persistent application state in that explicit value;
handlers, codecs and views must not retain hidden mutable state between calls.

Start with the [documented Scheme subset](macros.md#initial-scheme-base), rather
than assuming Chibi's complete standard library is compiled into the application.
The product exports are listed in
[`(scheme base)`](https://github.com/tsnl/snail-scheme/blob/main/src/scheme/base.sld) and
[`(lofi base)`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/base.sld). The current arithmetic surface includes
`quotient` and `remainder`; `min`, `max` and `modulo` are not provided. Small
application helpers can use comparisons. `remainder` is useful for nonnegative
tick cycles, but is not a general replacement for Scheme's `modulo` on negative
inputs.

Arithmetic procedures currently take two operands: nest additions, and write
`(- 0 value)` for negation. Use `(empty-list)` for an empty list. Import
`string-append` from `(lofi base)` when assembling text; it is not yet re-exported
by `(scheme base)`.

```scheme
(import (scheme base) (application reducer) (only (lofi core) I32))

;; Inside a define-library's ordinary (begin ...):
(application counter (state I32 1) 0
  (add (state (amount I32)) (no-effects (+ state amount)))
  (reset (state) (no-effects 0)))

(transition-state (dispatch counter 40 (add 2))) ; 42
```

`add` is a lexical, typed command constructor. It describes an invocation; it
does not run the reducer or close over a live state. `dispatch` supplies the
state. The macro checks every handler against the same state/result type and
introduces a private nominal owner type, so commands from two applications that
both use `I32` state cannot be mixed. There is no manually maintained message
enum. Generated constructors occupy ordinary lexical names: a helper named
`add` in the same scope would collide with this handler, so give it a distinct
name. The complete executable example is
[`examples/applications/counter.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/counter.sld).
Build and execute it from the repository root:

```sh
mkdir -p build/examples
chibi-scheme -I bootstrap tests/applications/build.scm \
  "$PWD" "$PWD/examples/applications/counter.sld" "$PWD/build/examples/counter.wasm"
node examples/applications/run.mjs build/examples/counter.wasm
```

It prints `42`. The small build helper selects the exported `answer` procedure;
it uses the same explicit map compiler as an application's `build.scm`. Extra
arguments after the output path add application source roots; without them, the
only search root is the repository's shared `src/`.

The initial payload subset is zero, one or two `I32` arguments. This is a small
wire codec, not a claim that application data must be integers. State itself is a
typed Scheme value. `(Transition State)` contains that state and an immutable list
of effect values. `no-effects` means "no effects"; its argument may be a newly
computed state.

For cross-owner dispatch, attach an application to an explicit destination and
return a send description:

```scheme
(import (scheme immutable)) ; supplies immutable list construction
(define counter-target (destination match-owner counter))
;; From a handler returning its own next state:
(transition next-client (list (enqueue counter-target (add 2))))
```

`enqueue` checks the command's owner and state types against the destination.
The numeric attachment is runtime composition, not a state lookup/mutation API.
`match-owner` and `client-owner` are the two slots in the first browser adapter;
other transports can provide their own owner attachment layer. Effects run after
the replacement commits. Their results must enter as later messages. A handler
cannot await a network response while holding the state owner.

### Testing handlers without a host

Pure tests can call `dispatch` directly. The initial expression in `application`
is delayed: `application-initial` returns a zero-argument initializer, so
`((application-initial counter))` constructs its initial state. This does not
read or change a runtime owner's committed state.

```scheme
(define before ((application-initial counter)))
(define result (dispatch counter before (add 2)))
(transition-state result)   ; 2; before is still 0
(transition-effects result) ; an empty immutable list
```

For returned effects, use `effect-send?` or `effect-notice?` before inspecting
the corresponding variant. Send accessors are `effect-owner`, `effect-a` and
`effect-b` for the destination and up to two payload values; `effect-text` reads
a notice. Dispatch does not deliver the effect. The generated `effect-slot` and
numeric `effect-kind` serve the private scalar bridge; tests should not depend
on those wire details.

The complete [`testing.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/testing.sld) example
checks an immutable prior stock value, a replacement value, local state and a
typed send description. Compile and run it with the same commands as the counter,
substituting `testing.sld` and `testing.wasm`; it prints `42`. This exercises pure
handler behavior, not host ordering, durability or effect delivery.

## One owner, one ordered transition

Each owner commits one message at a time. The handler sees the previous committed
value; readers retain that value even after a replacement. A trap or failed
durable commit discards the candidate state and staged effects. Before commit,
the runtime checks the replacement schema and runs the application's decoder in
an isolated read-only scope over the encoded candidate.

The current `ReducerRuntime` uses one FIFO for its shared two-owner Wasm instance.
Both owners' commands, initialization, snapshot restoration, code installation
and closing share that order. A client command waits behind a pending match save;
separate runtime instances proceed independently. `dispatch`, `initialize`,
`restore`, `replace` and `close` return promises. Observe their completion and
errors with `await` or another promise consumer; commands can be admitted
concurrently and awaited together.
`prepare`, `snapshot` and `view` remain synchronous. During a save, queries see
the previous committed snapshots, and the scalar execution scope is inactive.
Queued commands and restored snapshots capture their inputs
when called, so later caller edits cannot change an admitted message.

Reduction, candidate validation, text conversion and effect routing finish
synchronously before persistence starts. The saver receives an immutable copy
of the candidate snapshot and materialized effects. Send effects carry stable
handler identities from their originating generation, so a later slot reorder
cannot reinterpret them. The runtime awaits the saver before publishing state;
the local save revision joins that publication in the same synchronous turn. A rejected save publishes nothing and does not roll back code. A failed
message rejects its own promise without poisoning the FIFO.

`LocalState.open(runtime, {saved, commit, publish})` restores the game's saved
`{revision, state}` checkpoint after initializing both runtime owners. `state` is
an array of signed 32-bit words. `commit(checkpoint, expectedRevision)` must
atomically compare the stored revision and write the replacement. It can return a
promise; the browser's IndexedDB adapter resolves only when its transaction
completes. `submit(command)` invokes the typed game handler through the same
runtime FIFO and advances the revision only after that write succeeds.

```javascript
import {ReducerRuntime} from './src/application/runtime.mjs';
import {LocalState} from './src/application/local.mjs';
import {acquireWriter, openStore} from './src/application/indexeddb.mjs';

// Browser code: initialize from this static package's bytes and manifest.
const runtime = new ReducerRuntime();
await runtime.replace(runtime.prepare(bytes, manifest));
await runtime.initialize(1); await runtime.initialize(2);
const release = await acquireWriter(manifest.settings.id);
const store = await openStore(manifest);
try {
  const local = await LocalState.open(runtime, {
    saved: await store.load(),
    commit: (checkpoint, expected) => store.commit(checkpoint, expected),
    publish: output => console.log(output.effects),
  });
  await local.submit(runtime.command('match', 'pause-colony', [1]));
  console.log(local.snapshot()); // {revision, state}
} finally {
  await runtime.close(); store.close(); await release();
}
```

The application manifest preserves state/schema identity, handler identity,
argument types and generated dispatch slots. Requests carry stable identities and
structured scalar payloads. They never carry a closure or a Wasm function pointer.
Reordering declarations changes private slots without changing public identities;
renaming a handler or changing its schema/payload changes its identity.

Both game and presentation execute in the browser. There is no replicated match,
network command queue, player session, presence tracking or server-owned clock.
`runtime.message(operation)` remains a low-level host facility for serialized
operations; use the supplied dispatcher once inside it and do not await another
queued mutation from that callback. Ordinary callers use `dispatch` or `LocalState`.

Optional online save/load transfers complete checkpoints outside the reducer lane.
A load validates and persists its replacement through `local.restore(state)`;
failed validation or storage leaves the previous game intact. Effects are emitted
after a committed transition. The runtime does not promise exactly-once external
effects; a future payment or other remote effect needs its own delivery contract.

The initial build inspects literal `application` declarations inside a library's
outer `begin`. `(application manifest bootstrap)` reads the exact parsed library
that the host compiler receives, so protocol metadata cannot come from a later
edit of the source file. This is Chibi build support; the public reducer API is
shared by product Scheme and Lofi. Arbitrary generated application declarations
are not currently inspected.
The `application` macro itself expands through `(lofi core)`'s `library-begin`
declaration splice; library-level `begin` also splices into the surrounding scope,
while expression `begin` creates a block. Export handlers that
another library must call, just as with other library bindings.

## Assembling a browser application

The initial host is a two-owner adapter: one game model and one presentation model, both in the browser. Declare both with `application`, derive `Serialize` and `Deserialize`
for their state records, then import `(application serialization)` and compose:

```scheme
(serialized-program world-app client-app validate-world validate-client view status)
```

| Argument | Contract |
| --- | --- |
| `world-app`, `client-app` | Different typed applications; their initial expressions create absent owners. |
| `validate-*` | `State -> State`; check application-specific invariants after typed deserialization and reject invalid values by trapping. |
| `view` | `(-> World Client (List Quad))`, a two-argument procedure with no mutation or effects. |
| `status` | Two arguments, `World` and `Client`, returning `String`. |

The browser host routes `enqueue` effects between these two owners. World sends
pass through durable storage; their reply effects enter the browser queue only
after commit. Client self-messages enter that same queue, so a UI can distinguish
an authoritative result from completion of an attempt. A failed save publishes
no World effects. Already admitted independent sends and completion messages
still drain, with errors reported afterwards. This permits partial success; it
does not turn a group of effects into one atomic transaction.

For example, Siegework pairs each planned placement with a Client completion
message. Acceptance removes its preview; completion releases its pending slot.
If saving fails, no acceptance is delivered and the preview remains retryable.
The UI keeps new submissions locked until the admitted batch has settled.

The adapter serializes through the shared S-expression representation and its
compact binary encoding. Its envelope carries schema version, byte length and
four bytes per `I32` word, with checked final zero padding. Snapshots may grow or
shrink within the host's 1,048,576-word bound. Schema zero marks an absent owner only
inside the host; restoring a committed snapshot requires its declared positive
schema. Neither derive implements migration between incompatible schemas.

On page refresh, adding game endpoints can reopen an existing save if the world
state/schema, effects, run marker, reset identity and every previous endpoint
contract remain identical. Removing or changing an old endpoint is rejected.
Live code replacement still requires the complete endpoint contract to match:
refresh when adding handlers or changing transient client schema. The browser
retains incompatible saved records rather than silently resetting them.

The browser host supplies scalar diagnostic services for malformed snapshots.
`Symbol` fields also need the interning services supplied by the linked Rust
runtime; adding those services to this browser host remains future work.

Construct quads with `(quad x y width height packed-rgb opacity)`, using `I32`
logical pixels and opacity 0–255. Export an entry annotated
`(-> I32 I32 I32 I32 I32)` that forwards its four arguments to
`(run-program program operation a b c)`. Applications do not call raw bridge
imports themselves.

### Immutable records and derived snapshots

`(scheme immutable)` provides `list`, `append`, `reverse` and
`define-immutable-record`, separately from `(scheme base)`. A record names its
constructor, accessors and pure replacements. Replacement names follow the
accessor with `-set`, without `!`; every replacement preserves the prior value.
Import `(lofi serialization)` to opt a record into independent capabilities:

```scheme
(define-immutable-record Stock stock
  (ore I32 stock-ore stock-ore-set)
  (deriving derive-serialize derive-deserialize))
(define before (stock 40))
(define after (stock-ore-set before 42)) ; before still contains 40
```

The macro forwards the complete generated `data` declaration to each derive.
Its ordinary checked instances transport the declaration's type, constructor
and fields without an application-specific field codec. See the
[serialization contract](types.md#data-graph-serialization) for supported
containers, graph identities and initialization evidence.

The lower-level `(application bridge)` still provides `program` for explicit
`State -> (Vector I32)` encoders and reverse decoders. Positive word counts
require exactly that fixed length; zero requests variable size. The runnable
[`examples/applications/state.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/state.sld)
retains a small explicit adapter example. Vector lengths and indices use `I64`.
Import `(browser application)` for `Quad`, `quad`, `text-scalar` and `integer-text`,
and `(application bridge)` for `run-program`.

### Previous snapshots for presentation

Keep three responsibilities separate. The game model owns rules and deadlines;
for example, it computes when difficulty increases. A pure presentation projection
turns that interval into a label and progress value. Display animation interpolates
positions or advances visual effects between committed snapshots. It must not
invent a second game timer or change the simulated outcome.

Siegework's [`presentation.sld`](../../../apps/siegework/src/siegework/presentation.sld)
contains that projection. Its HUD and accessible status consume the same result;
changing a difficulty interval does not require changing either renderer. Camera
and selection belong to client state, while transient GPU interpolation belongs
to the display clock. Only the game world is the durable colony.

`(application bridge)` exports `(read-snapshot owner)` and
`(read-previous-snapshot owner)`, where owner is `1` for the game model or `2` for
the presentation model. Each call copies an encoded snapshot into a Wasm-owned
`(Vector I32)`. Decode that vector with the application's snapshot codec before
reading typed fields. Previous and current snapshots can have different lengths.

The runtime retains one prior committed snapshot per owner. After a successful
state change, the current snapshot becomes the prior snapshot in the same
publication turn that installs its replacement, after validation and any durable
save. Pending saves, rejected saves and failed transitions advance neither
snapshot. A byte-identical transition preserves both identities and their history;
it still follows the existing persistence and effect-publication contract.

Initialization and explicit `restore` set previous and current to the same
snapshot, so presentation starts at the loaded state. If no prior snapshot exists,
the previous read uses the current snapshot. History is transient runtime data
and is not part of a saved checkpoint. Compatible code replacement preserves it.

A presentation query can decode the prior world once and match entities by ID
to supply `moving-group` transforms in a [`motion-batch`](../../../src/draw3d/README.md#motion-between-committed-states).
Use current transforms for newly created entities or discontinuities such as a
new run. The GPU advances the supplied transition on display frames; this does
not increase the reducer tick rate or rerun Scheme layout for entity motion.

### Packaging the compiled application

The app-local `build.scm` compiles that entry through `(lofi compiler bootstrap)`
and compiles a shader entry which returns WGSL Unicode scalars (negative index
queries length). It then calls `src/browser/build.mjs REPOSITORY APP OUTPUT` to
package already-built `simulation.wasm`, `shader.wasm`, and the
`application.syntax.json` emitted by that host helper from the selected parsed
library. The compiler writes these raw inputs once into `OUTPUT`; packaging
emits `OUTPUT/solo`, a static distribution with a browser-local simulation and
IndexedDB saves. With `SAVE_SERVICE_URL` set, it also emits `OUTPUT/synced`, a
static distribution with optional explicit online save/load. Both use identical
simulation bytes and `lib/browser/solo.mjs`. Disabled builds omit the online
save module entirely. Build outputs must stay
outside source directories. The shader entry signals a diagnostic by returning a
negative length; the build refuses to publish it. Packaging also executes isolated
initial states and the pure view before publishing the manifest. Vector lengths
are not statically indexed types: a declared/encoded word-count mismatch is
caught by this executable startup check, while current-state validation still
runs at each live replacement boundary.

An app supplies `index.html` (a canvas and elements with `data-status` and
`data-connection`), `style.css`, and `settings.json`. The Scheme build recipe
selects the application source. Use relative HTML asset URLs and one
`<script type="module" data-application-entry></script>` marker; the packager
replaces it with the selected relative entrypoint. Settings require a stable
lowercase `id` (letters, digits, dots and hyphens, starting with a letter), map
bindings to `match`/`client`; name the
clock/reset handlers; and map input
to client handler bindings. These names resolve against the generated manifest
at the host boundary, not through runtime evaluation of arbitrary Scheme names.
Buttons can use `data-handler` and JSON `data-args`; keyboard/controller mappings
contain `[binding, ...payload]`. The shared browser adapter contains no game costs,
movement, collision or victory rules.

For example, a board with `world-app` and `local-app` could use these settings.
The owner mapping must match the argument order passed to `program`; the compiler
checks each application's handlers, while this host wiring is explicit build
configuration. Every named binding must exist in the generated manifest.

```json
{
  "id": "counter-board",
  "title": "Counter board", "width": 640, "height": 360, "cellSize": 40,
  "tickMilliseconds": 100,
  "owners": {"world-app": "match", "local-app": "client"},
  "tick": "tick", "reset": "reset",
  "pointer": {"move": "move", "confirm": "confirm"},
  "keys": {"Enter": ["confirm"]}, "controller": {"0": ["confirm"]}
}
```

The clock and reset handlers take no payload. Pointer movement takes two `I32`
screen-cell coordinates; the client reducer owns camera offsets. Confirmation
takes none. Key names are `KeyboardEvent.key` values, and controller keys are
standard Gamepad button indices. Commands fire once per press unless their keys
or button indices appear in `repeatKeys` or `repeatButtons`. The optional positive
integer `inputRepeatMilliseconds` defaults to 160. A held input fires at most once
per interval; a stalled frame does not cause catch-up commands.

`continuousKeys` and `controllerAxes` entries with `continuous: true` scale their
two I32 payload coefficients by elapsed frame milliseconds; axes also use stick
magnitude outside the deadzone. Each frame contributes at most 50 ms. Focus,
visibility, device and settings changes discard held input; continuous keys send
no keydown command. A key cannot be both continuous and repeated.
`pointer.coordinates: "pixels"` sends logical-canvas integer pixels instead of
cells. Scheme owns speed, camera bounds, projection and gameplay.

Responsive canvases with a `viewportHandler` default to native device-pixel
resolution. Optional `renderScale` must be finite, greater than zero and at most
one. It scales each physical backing dimension after applying the device-pixel
ratio: `0.25` renders one sixteenth as many pixels, with pixelated canvas
filtering. CSS sizing, DOM text, logical viewport dimensions and pointer
coordinates stay unchanged. The policy follows accepted generations and rollback;
device-pixel-ratio changes resize the backing buffer even at an unchanged CSS size.

`zoomHandler` optionally names a client endpoint with one `I32` argument. Wheel
and two-finger pinch input over the canvas supply a signed logarithmic scale
delta in thousandths: positive zooms out, negative zooms in. A client can apply
`scale * exp(delta / 1000)`, or an approximation appropriate to its numeric
representation, then enforce its own scale bounds. The host never changes the
camera center or projection.

Wheel pixel deltas use CSS pixels directly; line deltas multiply by 16 and page
deltas by the canvas's CSS height. A 100-pixel wheel delta therefore sends 100.
Trackpad pinch events delivered as Ctrl+wheel follow the same rule. Two-touch
pinches use `1000 * log(previousDistance / currentDistance)`, so spreading fingers
to twice their prior distance contributes approximately -693. Pinch distances
use CSS coordinates independently of canvas resolution.

Input accumulates until the next available display frame, sends at most one zoom
command bounded to -1000 through 1000, and keeps fractional units. Excess whole
units are discarded; a delayed frame does not replay a backlog. Focus loss,
editing and settings changes discard queued zoom and active touch gestures.
Without `zoomHandler`, wheel input retains its browser behavior. With it, the
canvas owns wheel and pinch gestures and uses `touch-action: none`; surrounding
controls retain their native behavior.

By default mouse and pen confirmation occurs on press. A touch confirms only on
release of a single-finger tap, after sending its final pointer coordinates.
Moving more than eight CSS pixels or adding another finger permanently cancels
that gesture's confirmation, even if the finger later returns to its start.
Exactly two tracked touches can pinch. Additional fingers suspend zoom, and
returning to two starts a fresh distance baseline. Cancellation, lost pointer
capture or a reset cannot produce a confirmation.

An optional `dragHandler` names a client handler taking two `I32` values: signed
CSS-pixel displacement, positive right/down. It opts the canvas into dragging for
mouse, pen and touch, coalesced on the existing display frame. All three then
confirm only on release of a tap. Movement beyond eight CSS pixels begins a drag
and permanently cancels that tap; a second contact suppresses dragging until all
contacts release, so a pinch cannot end with a camera jump. The application owns
the displacement-to-camera conversion. Without this setting, dragging does not
implicitly pan the view.

`controllerAxes` optionally maps each axis to negative and positive commands:
`{"axis":0,"negative":["pan",-1,0],"positive":["pan",1,0],"deadzone":0.35}`.
Axis commands repeat; the deadzone defaults to 0.35. Settings parsing checks these
bindings and typed payloads both when packaging and in the browser. After focus,
device or generation changes, held controls must be released before activating
again. Native controls and editable elements retain their keyboard behavior.

Applications can use the [Scheme UI library](../../ui.md) to declare typed
controls and allocate their rectangles in one top-down pass. Its browser adapter
maintains semantic DOM controls; Siegework's HUD uses this path. A handwritten
HTML form can also bind one or two text fields to a typed client handler.
Put `data-handler` on the form, `data-i32` on each
input, and a `data-input-error` element in the form. Fields become I32 arguments
in document order. The submit button uses ordinary native form behavior:

```html
<form data-handler="restart-seed" novalidate>
  <label for="seed">Next run seed</label>
  <input id="seed" type="text" inputmode="numeric" data-i32
         aria-describedby="seed-error" placeholder="1–65535">
  <button type="submit">Start this seed</button>
  <p id="seed-error" data-input-error role="alert"></p>
</form>
```

This follows the existing public path: HTML form submission → generic browser
I32 parsing → typed Scheme client handler → authoritative Scheme transition.
The browser trims surrounding whitespace and accepts signed decimal integer
text. Blank, fractional, non-decimal, or out-of-I32 input produces an accessible
field error without dispatching. A successful submit dispatches once; merely
editing the text dispatches nothing. Gameplay keys and controller input pause
while focus is inside the form.

In Siegework, `restart-seed(seed)` forwards `new-run-seed(seed)` to the match
owner. Scheme accepts seeds 1 through 65535 and preserves the colony with a
notice for other I32 values. The input is a local draft for the next run; the
Scheme status displays the active seed. Ordinary New run still advances the
persisted seed. These seed rules belong to Scheme, not the generic form adapter.

A minimal source page lets the packager select its browser entrypoint:

```html
<canvas width="640" height="360" tabindex="0"></canvas>
<p data-status></p><p data-connection></p>
<button data-handler="confirm">Add</button>
<script type="module" data-application-entry></script>
```

The shader compiler, pure application API and immutable record library are
independent of this two-owner host. Broader owner routing and richer wire codecs
can be added without making them game-specific.

## Static hosting and optional online saves

Compile and serve `OUTPUT/solo` over HTTPS or localhost. It works under a subpath,
runs all game logic locally, and automatically saves to IndexedDB. For explicit
cross-device checkpoint transfer, build with `SAVE_SERVICE_URL`; the additional
`OUTPUT/synced` directory is also entirely static. A service outage does not stop
gameplay or local saving. See the [static save guide](../../static-saves.md) for
complete build, service and API examples.

`packageApplications(root, app, artifacts, {saveServiceURL})` packages already
compiled inputs once. Without the option it produces only `solo`; with the option
it also produces `synced`. `packageApplication(root, app, artifacts,
{output, saveServiceURL})` writes a single static bundle to an explicit directory.
Both manifests have target `solo`; the enabled build also declares `saveService`.
An existing cloud or unversioned output requires a fresh destination. Old output
directories and SQLite databases are retained and must not be published as static
files. Existing browser saves remain compatible.

An origin/application pair owns database `snail.application:<settings.id>` and
Web Lock `snail.application:<settings.id>:writer`. Build hash and mount path do
not name the save. Moving a package on the same origin retains its save. A second
tab explains which tab must be closed; no unsafe lock fallback is provided.
Clearing site data or browser eviction can remove a local save.

The IndexedDB database retains version 1, its `authority` object store and `match`
key so older browser saves reopen. Records remain
`{format: 1, application, contract, snapshot}`. A new snapshot contains only
`{revision, state}`; obsolete epoch/client receipt fields are ignored on read and
dropped by the next successful commit. The save compatibility contract retains
the match schema, handler identities, effect ABI, reset identity and run-marker
policy. Client-only controls do not invalidate the saved world. Live replacement
still checks both owners' contracts, and the Scheme decoder validates loaded
state. An incompatible save is preserved with an explanation rather than erased.

`store.commit(checkpoint, expectedRevision)` compares and writes in one read/write
transaction. Transaction `complete` is the success boundary; a successful `put`
followed by an abort still fails. Strict durability is a browser hint, not a
universal power-loss guarantee. `store.record(checkpoint)` supplies the versioned
envelope used by online transfers.

Rejected reducers never replace the committed save. The browser retains one
separate failure reproduction, readable with `store.failure()`: generation,
command, committed owner snapshots and any staged candidate. This local record
supports debugging without changing the match revision or uploading diagnostics.

The browser schedules a tick only after the preceding tick settles and the
interval elapses. Hidden pages skip ticks; reopening never catches up elapsed
wall time. Manual pause belongs to game state and survives restart. A failed
local commit stops the clock and explains how to retry; a successful manual
retry restarts it. Slow storage slows simulation without accumulating tick work.

The browser polls its static manifest once per second after the previous poll
settles. Compatible application and shader replacement preserves both models.
Full reload restores the saved game and pause; camera and selection start anew.
Changing the online-save build configuration requires a page reload.

Closing stops admission and timers, drains accepted transitions, closes GPU and
storage resources, then releases the writer lock. Leaving during startup performs
cleanup when the pending open settles. Abrupt termination recovers only completed
transactions. Startup alone does not fabricate a durable checkpoint.

A replacement Wasm module has its own heap. The shared scalar snapshot codec
reconstructs typed values, and application validation establishes semantic
invariants. No managed pointer crosses module instances or reaches the save
service. The optional service stores opaque envelopes using HTTP GET/PUT and
conditional ETags; it never runs game code.

## Reload boundary

A successful build writes content-addressed Wasm and WGSL, then publishes its
manifest atomically. The browser runtime validates a candidate at a message
boundary. The browser prepares a new GPU pipeline while the old one remains
active, then revalidates the candidate against the *current* state before swapping.
Initialization only runs for an absent state owner. Compatible reload consumes no
gameplay tick and preserves local selection and pending input.
Preparing a first candidate also leaves absent owners untouched. Temporary zero
buffers exist only during synchronous validation; a failed or discarded
candidate cannot reserve its proposed state shape. Installation checks current
snapshots again before publishing any new owner buffers with the code.

Live reload also requires the same endpoint contracts. Reordering declarations
is compatible. Adding, removing or changing a client endpoint requires a page
reload, which initializes presentation state but can reopen the same saved world.
Changing the match contract requires an explicit save migration or a separate
application identity. Restart alone cannot make an incompatible saved world
readable: reopen the previous compatible package, or use a distinct application
ID. Pending requests retain their original encoded identities and payloads.

State schemas version meaning, not just byte length. A changed schema is rejected
until an explicit migration exists; automatic migrations are not implemented.
Candidate initialization cannot access the snapshot bridge outside a transaction.
Validation is read-only and exercises the pure view against initialized state.
Failure retains the old state and installed code. A
trapped transition cannot publish partial writes or effects; the runtime retains
one previous compatible module for recovery. Live GPU handles stay in the browser
host and are never serialized as portable state.

Preparation may run while a save is pending, but installation waits in the FIFO
and revalidates the latest committed state. A query trap schedules recovery after
already admitted messages; the recovery is tagged with its code activation and
cannot roll back a later installation. The browser reconciles its GPU pipeline
and input settings after that deferred recovery. `close()` immediately rejects
new messages, `view` and `prepare`, drains accepted messages and saves, then
disposes code. `snapshot` remains readable. The browser closes IndexedDB after draining.

Each host schedules its next tick only after the previous tick settles and the
tick interval elapses. Slow persistence slows the simulation instead of creating
a backlog of catch-up ticks. Local effects, state imports and code replacement share the same ordered
message lane. Held movement pauses while earlier local work is pending and does not
repay elapsed time after it completes.

HTML, CSS and the JavaScript platform adapter are presently restarted with a
normal page load. The state-preserving path covers Scheme application modules and
shader pipelines; it does not claim to hot-patch arbitrary host JavaScript.

## Scheme shaders and browser support

`(webgpu shader)` provides a closed AST, checked stage/width rules, and a WGSL
compiler. Both Scheme and Lofi can import the same library:

```scheme
(compile-shader (gpu (vec4 position zero one))
                (gpu (* color one)))
```

`gpu` is a Scheme macro. Shader expressions can be composed through ordinary
Scheme functions and macros before validation. The initial vocabulary is
`zero`, `one`, `position`, `color`, `vec4`, and multiplication. The fixed vertex
layout carries a two-component position and four-component color. Fragment
expressions cannot read vertex-only position. Compilation returns either WGSL
or a diagnostic, and the WebGPU host checks the real pipeline before replacing it.

This is not a complete WGSL implementation or Scheme execution on the GPU.
Future expressiveness can come from reusable functions, hygienic macros, richer
typed ASTs, specialization and code generation; it does not change hardware
capabilities. The dialect's public name remains provisional.

`(browser application)` supplies immutable quad values and text conversion.
`(application serialization)` provides derived state transport; `(application bridge)`
composes typed applications, a pure quad view and
status text into a scalar entry. The browser adapter forwards input, performs
local durable submission, copies quad data and calls WebGPU. Game rules live
entirely in Scheme and execute in the browser.

See the [Siegework build instructions](https://github.com/tsnl/snail-scheme/blob/main/apps/siegework/README.md) and
[prototype contract](https://github.com/tsnl/snail-scheme/blob/main/apps/siegework/PROTOTYPE.md). The
[browser validation guide](https://github.com/tsnl/snail-scheme/blob/main/tests/applications/README.md) records the
tested Chromium/SwiftShader setup, GPU pixel readback and headless screenshot
limitations. Its flags are for an isolated software-GPU test process, not normal
hardware-WebGPU browser use. The host APIs used here
are the [WebGPU specification](https://www.w3.org/TR/webgpu/) and Node's
[`node:sqlite` API](https://nodejs.org/docs/latest-v24.x/api/sqlite.html).

## TODO: model checking and protocol analysis

The generated manifest is inspectable input for future analysis, not a current
model-checking guarantee. Handlers, schemas and effect destinations should remain
typed and identifiable as the API grows. Optional invariants and bounded trace
exploration could check, for example, that Siegework never has negative resources,
that a rejected checkpoint never replaces valid state, and that an invalid reload
never changes the accepted world.

Safety asks what must never happen; liveness asks what eventually happens.
"A queued repair is eventually considered" needs delivery, scheduling and crash
assumptions. "The match eventually ends" also needs a fair tick source and an
explicit time bound. A deliberate game-tick cycle differs from an unbounded chain
of same-request self-messages; future tools should expose causal chains, bounds
and effect budgets without forcing users to hand-write a protocol enum.

No current checker proves arbitrary Scheme termination, fairness, cross-node
ordering or crash recovery. Useful next work is a pure transition runner with
optional invariant hooks, bounded finite-state exploration and recorded traces,
followed by explicit models of network loss, retries, authority fencing and
effect completion. Full Scheme conformance, richer payload codecs and a broader
shader language are separate milestones.
