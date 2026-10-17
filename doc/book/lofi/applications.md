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
(import
 (scheme base)
 (application reducer)
 (only (lofi core) I32))

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
(import
 (scheme immutable)) ; supplies immutable list construction
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
an isolated read-only scope over the encoded candidate. Independent
owners need no shared global message order.

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
compatible reload. Cold starts must retain matching package settings and saved
state; this local store does not persist a separate configuration policy. The
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
library. Build outputs must stay
outside source directories. The shader entry signals a diagnostic by returning a
negative length; the build refuses to publish it. Packaging also executes isolated
initial states and the pure view before publishing the manifest. Vector lengths
are not statically indexed types: a declared/encoded word-count mismatch is
caught by this executable startup check, while current-state validation still
runs at each live replacement boundary.

An app supplies `index.html` (a canvas and elements with `data-status` and
`data-connection`), `style.css`, and `settings.json`. The Scheme build recipe
selects the application source. Settings map its bindings to `match`/`client`; name the
clock/reset handlers; enumerate remotely permitted match handlers; and map input
to client handler bindings. These names resolve against the generated manifest
at the host boundary, not through runtime evaluation of arbitrary Scheme names.
Buttons can use `data-handler` and JSON `data-args`; keyboard/controller mappings
contain `[binding, ...payload]`. The shared browser adapter contains no game costs,
movement, collision or victory rules.

For example, a board with `world-app` and `local-app` could use these settings.
The owner mapping must match the argument order passed to `serialized-program` or `program`; the compiler
checks each application's handlers, while this host wiring is explicit build
configuration. Every named binding must exist in the generated manifest.

```json
{
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

A minimal page loads the packaged shared adapter:

```html
<canvas width="640" height="360" tabindex="0"></canvas>
<p data-status></p><p data-connection></p>
<button data-handler="confirm">Add</button>
<script type="module" src="/lib/browser/client.mjs"></script>
```

The shader compiler, pure application API and immutable record library are
independent of this two-owner host. Broader owner routing and richer wire codecs
can be added without making them game-specific.

## Three state lifetimes

| Owner | Survives compatible code reload | Survives process/tab restart |
| --- | --- | --- |
| Authoritative match in stable host | Yes | Through committed durable snapshot |
| Durable aggregate in SQLite adapter | Yes | Yes, acknowledged commits |
| Browser selection/cursor/pending requests | Yes | Not promised; a full page load creates a new local model |

The demo's SQLite backend has **one authority process**. Its revision compare
and swap rejects conflicting durable writes; it does not make multiple game
servers into a distributed authority. A shared backend must provide serializable
commit or a single fenced writer with explicit revision retry. Authority transfer,
replication and distributed effects are future work.

A replacement Wasm module has a fresh managed heap. No WasmGC object pointer is
transferred between instances. Derived deserialization copies the current bounded
snapshot into a fresh typed graph; one transition produces its replacement.
The private bridge stages words and effect descriptions. Validation reads the
proposed snapshot through a read-only view while committed stores remain untouched.
A successful durable commit publishes the replacement atomically. The host may
reuse a Wasm instance between calls; fresh decoding and the application discipline
protect snapshots without recreating a module per message.

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
is compatible; adding, removing or changing an endpoint requires a restart or a
future explicit protocol migration. Pending requests retain their original
encoded identities and payloads.

State schemas version meaning, not just byte length. A changed schema is rejected
until an explicit migration exists; automatic migrations are not implemented.
Candidate initialization cannot access the snapshot bridge outside a transaction.
Validation is read-only and exercises the pure view against initialized state.
Failure retains the old state and installed code. A
trapped transition cannot publish partial writes or effects; the runtime retains
one previous compatible module for recovery. Live GPU handles stay in the browser
host and are never serialized as portable state.

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
`(application serialization)` supplies derived state transport; `(application bridge)`
composes the typed applications, a pure quad view and status text into a scalar entry. The browser adapter forwards input, performs
network transport, copies quad data and calls WebGPU. Game rules live entirely in
Scheme. The same generated simulation runs on the authority and in the browser
for speculative command feedback; server validation determines accepted state.

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
