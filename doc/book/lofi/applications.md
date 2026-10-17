# Applications, state, and hot reload

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
[`(scheme base)`](../../../src/scheme/base.sld) and
[`(lofi base)`](../../../src/lofi/base.sld). The current arithmetic surface includes
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
[`examples/applications/counter.sld`](../../../examples/applications/counter.sld).
Build and execute it from the repository root:

```sh
mkdir -p build/examples
chibi-scheme -I bootstrap -I wasm-native/scheme tests/applications/build.scm \
  "$PWD" "$PWD/examples/applications/counter.sld" "$PWD/build/examples/counter.wasm"
node --input-type=module -e 'import {readFileSync} from "node:fs"; import {loadWasm, instantiate, invokeEntry} from "./src/lofi/execute.mjs"; console.log(invokeEntry(instantiate(loadWasm(readFileSync("build/examples/counter.wasm"))), []));'
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

The complete [`testing.sld`](../../../examples/applications/testing.sld) example
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
Queued commands, authority envelopes and restored snapshots capture their inputs
when called, so later caller edits cannot change an admitted message.

Reduction, candidate validation, text conversion and effect routing finish
synchronously before persistence starts. The saver receives an immutable copy
of the candidate snapshot and materialized effects. Send effects carry stable
handler identities from their originating generation, so a later slot reorder
cannot reinterpret them. The runtime awaits the saver before publishing state;
authority metadata and receipts join that publication in the same synchronous
turn. A rejected save publishes nothing and does not roll back code. A failed
message rejects its own promise without poisoning the FIFO.

`Authority.open(runtime, {saved, commit, publish, ...options})` asynchronously
restores a saved authority after runtime initialization. Use `new Authority`
only for an already initialized fresh owner; passing saved data to that
constructor is rejected. `commit(snapshot, expectedRevision)` may return a
promise or complete synchronously, and must atomically save state, revision,
epoch and client receipts. Its rejection must mean that the candidate was not
durably accepted; ambiguous outcomes require adapter-specific reconciliation.
The SQLite adapter still performs blocking synchronous I/O. The browser
IndexedDB adapter awaits transaction completion. Both use the same authority
and Web Crypto receipt implementation.

The host-only `runtime.message(operation)` boundary lets authority receipt checks
and reduction occupy the same FIFO entry. Its supplied dispatcher permits one
transition and expires when the callback finishes; the runtime drains that
transition even if its promise is not returned. Return or await that dispatcher,
never another queued runtime mutation from inside the message or persistence
callback: waiting for work behind the current message would deadlock.
The runtime's synchronous publication hook installs prepared authority metadata,
then calls the authority's `publish` observer. Asynchronous external effect
delivery needs its own adapter.

Here is a minimal Node host, run from the repository root with an already built
package at `build/siegework/cloud`. The same runtime and authority imports work in the
browser; file loading and the storage adapter belong to the host.

```js
import {readFile} from 'node:fs/promises';
import {ReducerRuntime} from './src/application/runtime.mjs';
import {Authority} from './src/application/authority.mjs';
import {openStore} from './src/application/sqlite.mjs';

const directory = 'build/siegework/cloud';
const manifest = JSON.parse(await readFile(`${directory}/manifest.json`, 'utf8'));
const bytes = await readFile(`${directory}/${manifest.module}`);
const runtime = new ReducerRuntime(), store = openStore(`${directory}/match.sqlite`);
try {
  await runtime.replace(runtime.prepare(bytes, manifest));
  await runtime.initialize(1); // Match owner; only initializes absent state.
  await runtime.initialize(2); // Local client owner.
  const authority = await Authority.open(runtime, {
    saved: await store.load(), runMarker: manifest.settings.runMarker,
    resetHandler: runtime.command('match', manifest.settings.reset).handler,
    commit: (snapshot, expectedRevision) => store.commit(snapshot, expectedRevision),
    publish: notification => console.log(notification),
  });
  const client = crypto.randomUUID(), epoch = authority.epoch;
  const command = runtime.command('match', manifest.settings.tick);
  const first = authority.submit({client, sequence: 1, epoch, command});
  const second = authority.submit({client, sequence: 2, epoch, command});
  await Promise.all([first, second]); // Admission order is retained.
  console.log(authority.snapshot()); // {revision, epoch, state}
  console.log(runtime.view()); // {result, effects, quads, label}

  // For reload, pass newly loaded compatible bytes and manifest here.
  const candidate = runtime.prepare(bytes, manifest);
  try { await runtime.replace(candidate); }
  catch (error) { runtime.discard(candidate); throw error; }
} finally {
  await runtime.close(); // Finish admitted saves before closing their store.
  store.close();
}
```

The saved record is `{state, revision, epoch, clients}`. `state` is an ordinary
array of signed 32-bit words, not an `Int32Array` or an opaque state object.
Each `clients[client]`
contains `{sequence, fingerprint, receipt: {revision, epoch}}`; persist and
restore this record together. Fresh initialization and `Authority.open` do not
save an initial snapshot: durability begins with the first accepted command.
Before that commit, restart creates a fresh initialized owner and epoch.
`submit` resolves to `{revision, epoch, state}`; a consumed retry also includes
`duplicate: true` and its original `receipt`. The observer receives
`{type: 'snapshot', revision, epoch, state}` followed by ordered
`{type: 'effect', revision, effect}` notifications. Materialized notices contain
`{kind: 'notice', text}`; sends contain
`{kind: 'send', owner, command: {handler, args}}`, where owner is 1 or 2.

Siegework's local server assigns a revision to each accepted command, including
commands that make no gameplay change. It commits the state, revision, match
epoch, and each client's consumed sequence together. A retry of the latest sequence must match its original request fingerprint and
does not spend resources twice. Older consumed sequences are rejected; this small
adapter retains the latest receipt per client. Commands from an earlier run are rejected. The browser
only accepts snapshots whose revisions are at least its latest accepted revision.
Effects become observable after this commit. This does **not** promise universal
exactly-once external effects: a future payment, email or remote service needs an
idempotency key or a transactional outbox appropriate to that service. This first
adapter has no durable effect outbox; Siegework authoritative handlers produce
state only. Its client send effects use the explicit in-memory retry queue.
If an observer throws after commit, state and the receipt remain committed even
though the caller receives an error. An immediate identical retry returns that
receipt without rerunning the handler or redelivering its effects. This can lose
an external notification; it does not undo a successful transition.

The public protocol preserves application/schema identity, handler identity,
argument types and generated dispatch slots. Network requests carry the stable
identity and structured scalar payload; they never carry a Scheme closure or a
Wasm function pointer. Slots are private to a compiled generation. Reordering
handlers changes slots but does not change stable identities. Renaming a handler
or changing its schema/payload changes its identity.

The local authority also accepts an optional `runMarker` setting: a positive
word offset within the encoded match snapshot. Scheme changes that scalar only
when it accepts a new run, including replaying the same map seed. During the
same durable commit, a changed marker rotates the network epoch and records the
request receipt. Rejected seed input leaves the marker and epoch unchanged;
retrying an accepted restart returns its receipt. Apps without this setting keep
the named `reset` handler behavior. The marker offset cannot change during a
compatible reload. SQLite cold starts must retain matching package settings and
saved state. The browser store additionally records the save compatibility
contract and refuses incompatible deployments without changing the record. The
marker describes a lifecycle boundary, not game rules in JavaScript.

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

The initial host is a two-owner adapter: one authoritative match and one local
client. Declare both with `application`, derive `Serialize` and `Deserialize`
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

The adapter serializes through the shared S-expression representation and its
compact binary encoding. Its envelope carries schema version, byte length and
four bytes per `I32` word, with checked final zero padding. Snapshots may grow or
shrink within the host's 65,536-word bound. Schema zero marks an absent owner only
inside the host; restoring a committed snapshot requires its declared positive
schema. Neither derive implements migration between incompatible schemas.

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
[`examples/applications/state.sld`](../../../examples/applications/state.sld)
retains a small explicit adapter example. Vector lengths and indices use `I64`.
Import `(browser application)` for `Quad`, `quad`, `text-scalar` and `integer-text`,
and `(application bridge)` for `run-program`.

### Packaging the compiled application

The app-local `build.scm` compiles that entry through `(lofi compiler bootstrap)`
and compiles a shader entry which returns WGSL Unicode scalars (negative index
queries length). It then calls `src/browser/build.mjs REPOSITORY APP OUTPUT` to
package already-built `simulation.wasm`, `shader.wasm`, and the
`application.syntax.json` emitted by that host helper from the selected parsed
library. The compiler writes these raw inputs once into `OUTPUT`; packaging
emits two independent distributions, `OUTPUT/solo` and `OUTPUT/cloud`, with
identical simulation bytes. `solo` contains the browser authority and IndexedDB
adapter; `cloud` contains the HTTP/SSE server and SQLite adapter. Their entrypoints
are `lib/browser/solo.mjs` and `lib/browser/cloud.mjs`. Build outputs must stay
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
clock/reset handlers; enumerate remotely permitted match handlers; and map input
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
  "tick": "tick", "reset": "reset", "remoteHandlers": ["add", "reset"],
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

`controllerAxes` optionally maps each axis to negative and positive commands:
`{"axis":0,"negative":["pan",-1,0],"positive":["pan",1,0],"deadzone":0.35}`.
Axis commands repeat; the deadzone defaults to 0.35. Settings parsing checks these
bindings and typed payloads both when packaging and in the browser. After focus,
device or generation changes, held controls must be released before activating
again. Native controls and editable elements retain their keyboard behavior.

The current UI shell is ordinary HTML/CSS, with application state and behavior
in Scheme; there is no Scheme widget DSL. A form can bind one or two text fields
to a typed client handler. Put `data-handler` on the form, `data-i32` on each
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

## Solo and cloud saves

Free solo runs the shared authority in the browser and saves to IndexedDB.
Serve only `OUTPUT/solo` using an ordinary static server over HTTPS or localhost;
it works under a subpath such as `/games/siegework/` and makes no application
server requests. WebGPU, WasmGC, IndexedDB, Web Crypto and Web Locks are required.
The cloud package runs the authority on Node and stores `match.sqlite` beside its
manifest. It supports a single player resuming on another browser as well as
multiple players sharing the match. This is the server-save foundation for the
premium product; accounts, billing, authentication and per-user save routing
are not implemented. The supplied server binds localhost and hosts one save.
Internet deployment needs separate routing and access control.

```sh
# Compile once; both directories are produced.
chibi-scheme -I bootstrap -I wasm-native/scheme apps/siegework/build.scm "$PWD" "$PWD/build/siegework"
# Free solo: upload build/siegework/solo to a static host, or preview locally.
python3 -m http.server 4174 --directory build/siegework/solo
# Cloud: one persistent hosted match, usable by one or multiple clients.
node build/siegework/cloud/lib/browser/server.mjs "$PWD/build/siegework/cloud"
```

For already compiled inputs, `node src/browser/build.mjs REPOSITORY APP OUTPUT`
repackages both targets without compiling Scheme. The JavaScript API is
`await packageApplications(root, app, artifacts)`; for one explicit destination,
`await packageApplication(root, app, artifacts, {output, target: 'solo'})`.
An existing manifest must declare the same target. Changing target, or reusing a
legacy package without a target, requires a new output directory. Packaging does
not delete old saves to make a directory publishable as static files.

Solo uses database `snail.application:<settings.id>` and an exclusive Web Lock
`snail.application:<settings.id>:writer`. Origin and application ID define the
save; build hash and mount path do not. Moving the package on the same origin
retains the save. Different origins have separate saves. A second tab shows an
ownership error; close the first tab and reload to acquire the save. There is no
unsafe fallback when Web Locks are unavailable. Browser site-data removal or
storage eviction can remove local saves; solo does not provide cross-device sync.

`src/application/indexeddb.mjs` exports `acquireWriter(applicationId)`,
`openStore(manifest)`, `saveName(applicationId)` and `saveContract(manifest)`.
Acquire the writer before opening/restoring the authority. `await store.load()`
returns the ordinary authority snapshot object described above or `undefined`.
`await store.commit(snapshot, expectedRevision)` compares the stored revision
and writes state, epoch, revision and receipts in one read/write transaction.
It resolves on transaction `complete`, not on `put` success; `abort` rejects.
Strict durability is requested as a browser hint, not a universal power-loss
guarantee. See [IndexedDB transactions](https://www.w3.org/TR/IndexedDB/) and
[Web Lock lifetimes](https://www.w3.org/TR/web-locks/).

The database has version 1 and an `authority` store with key `match`. Its record
is `{format: 1, application, contract, snapshot}`. The contract conservatively
includes both owners' state schemas and typed endpoint contracts, effect ABI,
reset identity and run-marker policy. Handler slot order and content generation
are excluded. Restore also runs the current Scheme decoder against the snapshot.
Incompatible database versions, record formats, policies or snapshots fail
visibly and preserve the existing data. Reopen the previous compatible package;
there is no automatic migration or erase-on-error recovery. Authors must change
the schema when changing the meaning of encoded words; unchanged declarations
cannot prove semantic compatibility.

Both hosts schedule the next tick after the preceding tick completes and the
interval elapses. Solo skips ticks while its page is hidden; cloud skips them
when no connected client reports visibility. Reopening never replays elapsed
wall time. Manual pause is Scheme match state and survives restart. The generic
clock still submits ticks while manually paused; Scheme may produce an unchanged
snapshot, which still receives a committed revision. A solo command failure
stops its clock and reports retry/reload guidance. A successful manual retry
resumes the clock; a durable revision conflict needs reopening the authoritative
save rather than silently overwriting it.

Solo polls its static manifest once per second after the previous poll settles.
Compatible Wasm/shader updates preserve both owners in place. Save compatibility
is checked before activation; a rejected update keeps the prior code and save.
A full page/browser restart restores the committed match, pause, epoch and
receipts. Cursor, camera, tool selection, pending requests and notices have page
lifetime. Fixed solo and clock client identities continue their saved receipt
sequences on reopen. There is no durable command or effect outbox.

Normal solo close stops admission and timers, drains accepted transitions, closes
the renderer and database, then releases the Web Lock. Leaving during startup
cleans up after the in-flight open finishes. A document restored from the browser
back/forward cache reloads to acquire fresh resources. Abrupt termination need
not finish asynchronous cleanup: only completed transactions are recoverable.
Fresh startup alone has no durable record until the first accepted command/tick.

## Three state lifetimes

| Owner | Survives compatible code reload | Survives process/tab restart |
| --- | --- | --- |
| Authoritative match in stable host | Yes | Through committed durable snapshot |
| Durable aggregate in IndexedDB or SQLite | Yes | Yes, completed commits |
| Browser selection/cursor/pending requests | Yes | Not promised; a full page load creates a new local model |

The demo's SQLite backend has **one authority process**. Its revision compare
and swap rejects conflicting durable writes; it does not make multiple game
servers into a distributed authority. A shared backend must provide serializable
commit or a single fenced writer with explicit revision retry. Authority transfer,
replication and distributed effects are future work.

A replacement Wasm module has a fresh managed heap. No WasmGC object pointer is
transferred between instances. Derived deserialization constructs a fresh typed
graph, then the application establishes its semantic invariants. One transition
produces a candidate snapshot and materialized effect descriptions. Validation
reads that candidate through its own read-only map while queries retain the
committed snapshots. A successful durable save publishes the replacement.
The host may reuse a Wasm instance between calls; fresh decoding and application
discipline protect snapshots without recreating a module per message.

## Reload boundary

A successful build writes content-addressed Wasm and WGSL, then publishes its
manifest atomically. The running authority validates a candidate at a message
boundary. The browser prepares a new GPU pipeline while the old one remains
active, then revalidates the candidate against the *current* state before swapping.
Initialization only runs for an absent state owner. Compatible reload consumes no
gameplay tick and preserves local selection and pending input.
Preparing a first candidate also leaves absent owners untouched. Temporary zero
buffers exist only during synchronous validation; a failed or discarded
candidate cannot reserve its proposed state shape. Installation checks current
snapshots again before publishing any new owner buffers with the code.

Live reload also requires the same endpoint contracts. Reordering declarations
is compatible; adding, removing or changing an endpoint requires an explicit
protocol migration or a separate fresh save. Restart alone cannot make an
incompatible solo record readable: reopen the previous compatible package, or
use a deliberately distinct application ID for a separate application. Pending requests retain their original
encoded identities and payloads.

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
disposes code. `snapshot` remains readable. The server closes SQLite after draining.

Each host schedules its next tick only after the previous tick settles and the
tick interval elapses. Slow persistence slows the simulation instead of creating
a backlog of catch-up ticks. Browser snapshot application, local effects and
session renewal are ordered; new envelopes wait for renewed sequence/epoch
metadata. Held movement pauses while earlier local work is pending and does not
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
local or network submission, copies quad data and calls WebGPU. Game rules live
entirely in Scheme. Solo commits through the browser authority. Cloud runs the
same generated simulation for speculative feedback in the browser; server
validation determines accepted state.

See the [Siegework build instructions](../../../apps/siegework/README.md) and
[prototype contract](../../../apps/siegework/PROTOTYPE.md). The
[browser validation guide](../../../tests/applications/README.md) records the
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
that a duplicate command never purchases two turrets, and that an invalid reload
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
