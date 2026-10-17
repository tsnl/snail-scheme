# Applications, state, and hot reload

An application is a collection of typed handlers over one state type. A handler
receives a stable state value and its payload, then returns a replacement state
and effect descriptions. It does no asynchronous work. The runtime owns storage,
ordering and delivery. This is a library programming model, not a compiler proof
of purity: use immutable records and lists, and do not mutate values reachable
from an earlier state.

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
enum. The complete executable example is
[`examples/applications/counter.sld`](../../../examples/applications/counter.sld).
Build and execute it from the repository root:

```sh
mkdir -p build/examples
chibi-scheme -I bootstrap -I wasm-native/scheme tests/applications/build.scm \
  "$PWD" "$PWD/examples/applications/counter.sld" "$PWD/build/examples/counter.wasm"
node --input-type=module -e 'import {readFileSync} from "node:fs"; import {loadWasm, instantiate, invokeEntry} from "./src/lofi/execute.mjs"; console.log(invokeEntry(instantiate(loadWasm(readFileSync("build/examples/counter.wasm"))), []));'
```

It prints `42`. The small build helper selects the exported `answer` procedure;
it uses the same explicit map compiler as an application's `build.scm`.

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

## One owner, one ordered transition

Each owner commits one message at a time. The handler sees the previous committed
value; readers retain that value even after a replacement. A trap or failed
durable commit discards the candidate state and staged effects. Independent
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

The public protocol preserves application/schema identity, handler identity,
argument types and generated dispatch slots. Network requests carry the stable
identity and structured scalar payload; they never carry a Scheme closure or a
Wasm function pointer. Slots are private to a compiled generation. Reordering
handlers changes slots but does not change stable identities. Renaming a handler
or changing its schema/payload changes its identity.

The initial build inspects literal `application` declarations inside a library's
outer `begin`. `(application manifest bootstrap)` reads the exact parsed library
that the host compiler receives, so protocol metadata cannot come from a later
edit of the source file. This is Chibi build support; the public reducer API is
shared by product Scheme and Lofi. Arbitrary generated application declarations
are not currently inspected.
The `application` macro itself expands through `(lofi core)`'s `library-begin`
declaration splice; ordinary `begin` retains lexical scope. Export handlers that
another library must call, just as with other library bindings.

## Assembling a browser application

The initial host is intentionally a two-owner adapter: one authoritative match
and one local client. Declare both with `application`, then compose a program:

```scheme
(program world-app client-app world-word-count client-word-count
         decode-world encode-world decode-client encode-client
         view status)
```

| Argument | Contract |
| --- | --- |
| `world-app`, `client-app` | Different typed applications; their initial expressions create absent owners. |
| Word counts | Positive `I32` lengths of the portable snapshots. |
| `decode-*` | `(Vector I32) -> State`; reject invalid schema/values by trapping. |
| `encode-*` | `State -> (Vector I32)`; allocate an owned vector of exactly the declared length. |
| `view` | `(-> World Client (List Quad))`, a two-argument procedure with no mutation or effects. |
| `status` | Two arguments, `World` and `Client`, returning `String`. |

Word zero is the positive schema version; an all-zero host buffer means absent
state. Other fields belong to the application's codec. Construct quads with
`(quad x y width height packed-rgb opacity)`, using `I32` logical pixels and opacity
0–255. Export an entry annotated `(-> I32 I32 I32 I32 I32)` that forwards its four
arguments to `(run-program program operation a b c)`. Applications do not call the
raw bridge imports themselves.

### Immutable records and snapshot codecs

`(scheme immutable)` provides `list`, `append`, `reverse` and
`define-immutable-record`. These are separate imports from the initial
`(scheme base)` subset. A record declaration names its constructor, accessors and
pure replacements:

```scheme
(define-immutable-record Stock stock
  (ore I32 stock-ore with-stock-ore))
(define before (stock 40))
(define after (with-stock-ore before 42)) ; before still contains 40
```

Application word counts and snapshot contents are `I32`. The current Scheme
vector API takes **`I64` lengths and indices**, so use an explicit annotation for
a literal or `i32->i64` for a computed index. An encoder may mutate a newly
allocated, owned vector; it must not mutate an earlier application state or
snapshot. For example:

```scheme
(define (encode-stock value)
  (let ((words (ann (make-vector (ann 2 I64) 0) (Vector I32))))
    (vector-set! words (ann 0 I64) 1) ; schema
    (vector-set! words (ann 1 I64) (stock-ore value))
    words))
```

The complete runnable
[`examples/applications/state.sld`](../../../examples/applications/state.sld)
includes imports, schema checking and a retained prior record. Compile it with
the same `tests/applications/build.scm` command used for the counter, substituting
`state.sld` and `state.wasm`; invoking its `answer` prints `42`. Import
`(browser application)` for `Quad`, `quad`, `text-scalar` and `integer-text`, and
`(application bridge)` for `program` and `run-program`.

### Packaging the compiled application

The app-local `build.scm` compiles that entry through `(lofi compiler bootstrap)`
and compiles a shader entry which returns WGSL Unicode scalars (negative index
queries length). It then calls `src/browser/build.mjs REPOSITORY APP OUTPUT` to
package already-built `simulation.wasm`, `shader.wasm`, and the
`application.syntax.json` emitted by that host helper from the selected parsed
library. Build outputs must stay
outside source directories. The shader entry signals a diagnostic by returning a
negative length; the build refuses to publish it.

An app supplies `index.html` (a canvas and elements with `data-status` and
`data-connection`), `style.css`, and `settings.json`. Settings select the literal
application source; map its application bindings to `match`/`client`; name the
clock/reset handlers; enumerate remotely permitted match handlers; and map input
to client handler bindings. These names resolve against the generated manifest
at the host boundary, not through runtime evaluation of arbitrary Scheme names.
Buttons can use `data-handler` and JSON `data-args`; keyboard/controller mappings
contain `[binding, ...payload]`. The shared browser adapter contains no game costs,
movement, collision or victory rules.

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
transferred between instances. App codecs copy the current bounded snapshot into
fresh immutable values, execute one transition, and encode a candidate snapshot.
The host's private bridge stages words and effect descriptions in a transaction.
It never exposes a mutable global map as the application interface. The initial
192-word world codec favors an inspectable boundary over zero-copy performance.
Persistent trees, owned buffers and richer serialization may improve copying
later without changing the handler contract.

## Reload boundary

A successful build writes content-addressed Wasm and WGSL, then publishes its
manifest atomically. The running authority validates a candidate at a message
boundary. The browser prepares a new GPU pipeline while the old one remains
active, then revalidates the candidate against the *current* state before swapping.
Initialization only runs for an absent state owner. Compatible reload consumes no
gameplay tick and preserves local selection and pending input.

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
`(application bridge)` composes typed applications, codecs, a pure quad view and
status text into a scalar entry. The browser adapter forwards input, performs
network transport, copies quad data and calls WebGPU. Game rules live entirely in
Scheme. The same generated simulation runs on the authority and in the browser
for speculative command feedback; server validation determines accepted state.

See the [Siegework build instructions](../../../apps/siegework/README.md) and
[prototype contract](../../../apps/siegework/PROTOTYPE.md). The host APIs used here
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
