# Actor model: typed interfaces and a shared runtime

**Review draft — proposed, not implemented.** This is a focused overhaul
of the public programming model, actor lifetime and GUI integration. It
reuses the shared JSPI host landed in
[#407](https://github.com/tsnl/snail-scheme/pull/407). This PR contains only
the design; implementation PRs wait for sign-off.

The desktop IDE and project engine are separate downstream work. Their
approved requirements remain parked in the
[previous consolidated design](https://github.com/tsnl/snail-scheme/blob/be6c41ef76d79d186fc2f405e1c44d28450318bc/doc/proposals/desktop-ide.md).
None is a prerequisite here: existing compile, build and `lofi serve`
tools suffice for the actor and GUI proofs.

## 1. Reuse the runtime; clarify its objects

The [host](../../src/app/actors.mjs), [(lofi actor)](../../lib/lofi/actor.sld)
and [actor tests](../../tests/actors/check.mjs) already establish:

- Independent Wasm instances, typed request/reply mailboxes and dynamic
  spawn. Startup is reserved before asynchronous loading; waiting actors
  remain alive; children can outlive parents; drain waits for every actor.
- Direct, deeply immutable local messages. Tests compare the actual GC
  objects on both sides. This path uses no socket, pipe or serialization.
  The compiler rejects nested mutable values, functions and `Any`.
- Protocol witnesses and engine representation checks at the typed
  boundary. The automatic derived binary path is also tested, currently
  within one host; it is not proof of network transport.
- One JSPI invocation owning its dynamic handler globals through
  suspension, with restoration after settlement. Imports enqueue work
  rather than synchronously reentering Wasm.

Today the host takes a `programs` name-to-loader map and `run(initial)`
accepts a list. User code can use `define-actor`, `Actor<Q,R>` and explicit
receive/reply. Explicit Stop, context-specific bootstrap adapters and the
GUI integration below are not implemented. Existing GUI applications use
[`define-application`](../../lib/lofi/app.sld) and a separate `app_main`
loop in [the application runtime](../../src/app/runtime.mjs).

| Object | Owns or represents |
| --- | --- |
| Actor | One execution context, private state, mailbox and lifetime. |
| Handler state | A concrete struct owned by an actor; it may contain private mutable cells/resources. |
| Channel/proxy | A caller-owned endpoint value, not the remote actor or its state. |
| Host | Actor instantiation, admission, waits, mailboxes and platform-resource ownership. |
| Isolate | An engine heap/reference domain. This backend runs a host's actors on one shared execution agent. |
| Process | The OS container, not the unit of actor creation. |

The current Node/V8 and browser backends permit concurrent waits, not
parallel Wasm execution within one isolate. Keep the existing promise
scheduling; do not add a second runnable queue or a process per actor.
A future multi-isolate pool would need transport across reference domains;
it cannot assume the local GC-identity guarantee. Pools and preemption are
outside this overhaul.

## 2. Structs implement meaningful interfaces

Winit provides the useful distinction:
[`ApplicationHandler`](https://docs.rs/winit/0.30.13/winit/application/trait.ApplicationHandler.html)
defines callbacks on application-owned state, and its
[example](https://raw.githubusercontent.com/rust-windowing/winit/v0.30.13/examples/window.rs)
passes that state to `run_app`.
[`EventLoopProxy`](https://docs.rs/winit/0.30.13/winit/event_loop/struct.EventLoopProxy.html)
is a separate event endpoint that can report closure; it does not implement
`ApplicationHandler`. Borrow this ownership pattern, not every Winit
platform lifecycle callback.

Use ordinary libraries, concrete structs and Lofi's existing
[type classes and instances](../language.md#typeclasses). A CLI contract
describes command execution; a GUI contract describes model/event behavior;
an application protocol describes its actual operations. Root, GUI and
service are roles of actors, not a runtime category hierarchy.

Methods have fixed arity and explicit effects. Instance selection is
static, followed by monomorphization. No variadic or higher-kinded type
parameters, superclasses, associated types or runtime trait dictionaries
are required. Class evidence selects code; it does not grant authority,
create an actor or turn a call into communication.

For example, the actor's handler and the caller's channel have different
responsibilities. This is a **proposed library API sketch in existing Lofi
syntax**, not a claim that the new adapter exists:

```scheme
(struct CounterState
  ((count I64)))

(typeclass (CounterHandler S)
  (: add-state (-> S I64 (Pair S I64))))

(instance (CounterHandler CounterState)
  (define (add-state state amount)
    (let ((next (+ (CounterState-count state) amount)))
      (Pair (CounterState next) next))))

(enum CounterFailure
  (Unavailable)
  (BadResponse))

(typeclass (CounterClient P)
  (: add-count (-> P I64 (Result I64 CounterFailure) ! actors)))

(struct LocalCounterChannel
  ((endpoint (Actor I64 I64))))

(instance (CounterClient LocalCounterChannel)
  (define (add-count channel amount)
    (counter-request (LocalCounterChannel-endpoint channel) amount)))
```

The ordinary counter runner owns the state, receives an immutable amount,
applies `add-state`, commits the returned state and replies. The caller's
channel wraps the existing typed endpoint; its constructor stays private
behind the authority-granting creation function. `counter-request` is a
proposed fixed-signature adapter that must convert supported transport
failures into the declared result. Today's `request` instead rejects its
JSPI wait on host failure. Typed failure conversion is real new work, not
something a class declaration supplies. Unexpected program traps remain
actor failures; they must not be disguised as successful calls.

A local object and a proxy may implement the same class when their full
contracts match. Keep handler and endpoint contracts separate when their
ownership, signatures or effects differ. A future transport with a
different effect row cannot silently implement the `actors`-only method
above. Settling a common endpoint effect/failure contract is an explicit
choice, not a reason to add new type-system machinery now.

Only immutable protocol data crosses actors. A channel does not expose the
target's `Ref`s, resource handles or closures. Closing it does not stop the
target or confer management rights; local channels need no generic close
or revocation framework in this overhaul. A failed call may follow an
operation that already happened, so failure does not justify an automatic
retry of non-idempotent work.

There is no universal `Actor` marker, exported-method RPC, special `send`
syntax, or universal public spawn/connect framework. The existing typed
request transport remains useful underneath concrete interface instances.
Small ordinary runners/adapters can use the landed actor entry machinery
internally without making a dedicated actor/application definition form
the public programming model.

## 3. Construction and bootstrap are contextual

Parent/platform libraries expose ordinary functions with concrete types:
for example, a native counter constructor or browser GUI attachment
function. Each states its input data, providers, returned channel/control
handles and lifetime ownership. Construct private state inside the new
actor; do not move a parent's captured closure or mutable cell into it.
No class instance alone authorizes construction or loading.

Start each host through **one bootstrap actor**. Ship context-specific
defaults: a native bootstrap interprets CLI/startup selection; a browser
GUI bootstrap attaches a client in the page's host. Users can replace
these actors. A browser-development bootstrap is a future possibility,
not a browser-local IDE dependency.

Selection belongs to the bootstrap. It may use a catalogue, but the core
Host does not require a global registry or a separately exposed list of
initial actors. Later construction uses the appropriate parent/platform
function directly; it need not RPC through a permanent root. Replacing
the root grants neither scheduler privilege nor arbitrary path/URL loading
authority.

The loading boundary remains concrete. Compile a small typed startup
adapter while the constructor's structs and class instances are known.
Its artifact binds that adapter to frozen standalone code or a linked
library bundle. The loader verifies its entry/version/protocol contract
and actual required imports before starting it with granted providers.
Runtime selection of a class name cannot manufacture static evidence.
An opaque handle table or module cache is allowed as an implementation
detail; it is not a required program-name service.

Use ordinary compiled adapters for the first examples. Do not add code
generation or a new compiler feature merely to avoid a small explicit
wrapper. The exact startup ABI is still to be chosen. Existing build tools
can produce these artifacts without project metadata or artifact macros.

## 4. Own execution, failure and resources

One actor handles one message at a time, including while suspended in
JSPI. A runner may dispatch several messages within one entry; it cannot
start overlapping entries on that actor's handler globals. Other actors
can progress, and platform callbacks enqueue work. At outer entry
settlement, existing `runEntry` restores globals before publishing actor
completion or reusing the entry. Reuse these mailbox/ownership invariants.

A returned callback does not end a passive service. Its runner's completion,
failure or explicit retirement does. A finite bootstrap runner may finish
while its children remain alive. Drain counts those children and idle
mailboxes; it must not mistake a returned method for actor termination.
Calls to failed/stopped actors settle as failures, and unrelated actors
continue. Cyclic synchronous requests may deadlock; no detector is implied.

Add per-actor Stop and resource ownership before promising normal GUI
closure. The current name-only import factory needs an actual actor owner
for subscriptions, pending I/O and other platform resources:

1. Close admission before awaiting anything. Reserved/loading actors and
   newly acquired resources already have an owner.
2. Reject queued/current requests and cancel supported host waits; each
   operation settles once. Late startup/I/O completions cannot reenter or
   resurrect the actor and must release any resources they acquired.
3. Wait for entries and uncancelled owned work to settle, restore handlers,
   then release records/resources. Stop cannot claim completion merely
   because the actor disappeared from a lookup table.

Actor retirement closes that actor's resources, not other actors merely
because it spawned them. GUI subscriptions and storage operations belong
to the GUI actor and close with it. If a concrete constructor creates owned
helper actors, its ordinary cleanup must stop them explicitly. Parent
completion alone still leaves them alive. No landed GUI needs such actor
helpers yet, so this overhaul adds no synthetic helper, inherited scope
tags or general owner-scope API. Real composition can justify that later.
There is no IDE `Run`, build revision, launch manager or supervision tree.

Stop is cooperative and only as strong as the supplied effect providers.
A non-yielding Wasm computation blocks the shared event loop. Killing its
isolate affects other actors and is not per-actor Stop. An uninterruptible
host operation may require waiting for settlement. Stop does not roll back
I/O already performed. CPU budgets, preemption, automatic restarts and
general supervision are deferred.

## 5. GUI migration is part of the overhaul

GUI integration tests whether the public model works for real applications;
it is independent of editor/IDE work. The final runtime must not leave
`app_main` applications on a separate execution path beside actors.

Keep pure initialization, update, view, HUD, save and restore as library
helpers. Concrete GUI state structs implement the required contracts; a
platform adapter owns the actor, subscriptions and effect providers. For
example, a compact proposed model contract is:

```scheme
(typeclass (GuiModel S)
  (: update-gui (-> S Input S))
  (: view-gui (-> S Frame)))
```

Resize/input/time arrive as inputs; presentation effects belong to the
adapter. HUD and save/restore retain fixed-signature contracts. Drivers
list their required classes explicitly, without superclasses. Mutable
cells and reset-provided handler context remain private to the GUI actor,
including across suspension; the Rust analogy does not require shared
mutable Lofi state.

DOM events, frame ticks and storage work obey the actor's entry boundary.
Prefer bounded callbacks rather than one permanent startup call that blocks
every later message. An event commits its immutable checkpoint only after
update/presentation succeeds. Keep the last completed checkpoint and unread
input for recovery; a partially rendered candidate cannot replace it.

Reload closes old admission, settles active work and checkpoints before
new code enters. Transfer input ownership only after successful initial
presentation. Preserve same-type direct handover, Save-based migration
when types change, and rollback when adoption fails. The existing opaque
handover remains a private checked reload boundary, not permission to send
`Any` or mutable values as normal messages. Frame coalescing, delayed
storage/startup and handler cleanup remain part of the contract.

Migrate the counter first, then Siegework, Hearsay and application fixtures
to ordinary libraries with structs/instances and concrete constructors.
Retire their dedicated `define-application`/independent `app_main` runner.
Internal compatibility adapters can bridge the migration, but cannot be
the final second execution model. Preserve the games' behavior; no
multiplayer or authoritative-server redesign belongs here.

Use the existing [browser reload test](../../tests/browser/reload.mjs) and
runtime tests. A body edit must preserve state; changed state uses Save;
incompatible Save or a failed first view keeps the working version; a
consumed failing event is not replayed; unread input survives; suspended
startup/storage cannot overlap replacement. Serve these proofs with
`lofi serve` and existing build commands. No new HTTP application host or
IDE frontend is needed.

## 6. Five implementation increments

These are proposed review-sized PRs, not created implementation PRs.
Keep them linear; each proves an actor invariant used by the next.

1. **Typed local handler and channel.** Add the small counter interface,
   state instance, local channel and runner using `(lofi actor)` and the
   existing examples/tests. Define supported failure-result conversion.
   Execute real Wasm: independent state, typed protocol mismatch, failure
   after target exit, immutable transfer and actual GC identity.
   Assert no codec or socket is used locally. **Base:** #407.
   **Cut:** network transport, universal dispatch and new type features.

2. **Bootstrap and verified construction.** Adapt `src/app/actors.mjs`,
   the existing loader/native host and small compiled startup adapters.
   Prove default and custom roots; reject incompatible entry/protocol or
   unsupported imports; preserve both linked and standalone loading.
   After bootstrap completion, children must be able to construct further
   actors without consulting it.
   **Depends:** 1. **Cut:** global catalogues, arbitrary loading authority,
   project descriptions and runtime trait objects.

3. **Actor/resource lifetime and cooperative Stop.** Give native/browser
   providers actor ownership; add admission closure, settlement and cleanup.
   Test mailbox wait, delayed startup and pending I/O; the other actor must
   still answer. Parent retirement must leave a child alive; stopped-target
   calls must report failure. A passive actor stays alive between callbacks.
   **Depends:** 2. **Cut:** inherited owner scopes, generic channel-close
   management, IDE Run records, preemption, pools and supervision trees.

4. **GUI counter and state-preserving reload.** Adapt `(lofi app)`,
   `src/app/runtime.mjs` and browser loading/bootstrap to shared actor
   execution. Keep the pure helpers and migrate the counter fixture.
   Run actual linked Wasm and Chromium tests for input ordering, rendering,
   storage suspension, checkpoints, traps, rollback and replacement.
   Confirm no overlapping handler ownership. **Depends:** 3.
   **Cut:** editor panes, project/build infrastructure and server migration.

5. **Real GUI applications and transition cleanup.** Move Siegework,
   Hearsay and remaining application fixtures onto that path. See both
   applications running and an edit/reload preserving state; retain the
   existing runtime/browser regressions. Remove the independent application
   runner and temporary duplicate lifecycle paths, while keeping useful
   library helpers and the underlying typed actor transport.
   **Depends:** 4. **Cut:** game redesign, network actor systems and IDE work.

## 7. Decisions still to make

- **Interface and failure contracts:** exact CLI/GUI methods, endpoint
  effects and normal failure result types. Recommendation: fixed-signature
  library methods; explicit results for supported communication failures;
  unexpected traps remain actor failures. Share endpoint classes only when
  their full effects and failure semantics match.
- **Startup ABI:** the smallest verified adapter contract connecting a
  concrete constructor, startup data and statically selected instances.
  Prefer ordinary compiled wrappers and existing import/protocol checks;
  do not infer a new language feature or runtime class lookup.

## Parked downstream work

The prior design remains available at its
[stable revision](https://github.com/tsnl/snail-scheme/blob/be6c41ef76d79d186fc2f405e1c44d28450318bc/doc/proposals/desktop-ide.md).
Its `project.sld` inputs/build/launch interface, hermetic metadata queries,
shared CLI/IDE project engine, intra-project artifact macros, server-only
HTTP launch, IDE files/buffers/compiler worker, Browser documents and
deployment discussion are parked requirements, not cancelled requirements.
They should consume this actor model later rather than drive its core API.

General HTTP hosting, remote channels and client-session handshakes are not
needed for the initial local actor/GUI proofs. Browser-local IDE/backend
hosting, custom schemes, multi-isolate pools and advanced debugging remain
separate work. This overhaul has no dependency on the control-handler
prototype or state-preserving backend-server migration.
