# Application engines, actors, and explicit state

This is a planned execution model, not an implemented runtime API. It records
the direction for bundled application engines and engines written by users in
Rust. The procedure names below are sketches. The
[Chibi UI prototype](https://github.com/tsnl/snail-scheme/pull/10) demonstrates
model/update/view composition and an HTTP host; it does not implement the worker,
persistence, or reload semantics described here.

## The engine owns control flow

An application engine receives platform events, manages resources, and invokes
Scheme behavior through an explicit contract. A few bundled engines should make
common applications easy to start. Users should be able to write other engines
as ordinary Rust applications using the same embedding and runtime interfaces.

An engine's contract identifies the procedures it can invoke on an actor, the
arguments and results of those procedures, and the rules for invoking them.
Scheme can implement these methods as ordinary library exports. An object system,
new reader syntax, and a special language entry-point declaration are unnecessary.
The native host owns its entry point and event loop. A browser host has to adapt
to the browser's event loop and capabilities.

| Term | Responsibility |
| --- | --- |
| Engine | Receives events, schedules invocations, owns platform resources, and applies the contract. |
| Contract | Defines exported methods, host capabilities, data formats, ordering, failure, and lifetime rules. |
| Actor | A logical instance of behavior with an identity and explicitly retained state. |
| Worker | One invocation with temporary Scheme memory; returns results and then ends. |

An actor need not be a resident Scheme process. The engine can keep its identity
and state while creating a worker for each message. A worker is an execution
boundary, not a requirement to create an OS process or thread. The runtime may
reuse execution machinery only while preserving the promised isolation.

Use an application identity such as a document, room, or session where useful.
A browser process or server process is a host that may contain many actors. An
actor's identity should not encode which machine currently runs its behavior.
Creating a child actor can be an explicit engine operation using a behavior
reference and initial data. Parenthood alone does not specify supervision,
cancellation, or deletion of the child's stored data; those need contract rules.

## Contracts describe behavior and execution

One proposed document/UI contract is:

| Procedure | Invocation | Result |
| --- | --- | --- |
| `initialize(options)` | Create a new actor | Model and initial commands |
| `update(message, model)` | Deliver an event | Next model and commands |
| `view(model)` | Produce a presentation | Composed tree |
| `migrate(old-version, model)` | Change an incompatible stored model | Model in the new format |

The message-first reducer order follows the Chibi prototype. Its current reducer
returns only a model; commands and migration are future extensions. Restoring an
existing actor loads its retained model rather than initializing a new one.

A static renderer can evaluate the view once. An interactive host reevaluates it
after model transitions. Start with HTML and the browser DOM as the presentation
backend; a custom graphics renderer can implement another presentation contract.
This permits ordinary Scheme composition to serve documentation, workbooks, and
applications without requiring a markup reader first.

An HTTP engine can define request methods, and a graphics engine can define
simulation and frame methods. Contracts should be explicit interfaces distinct
from engine implementations. A test host can implement the same interface using
synthetic events and recorded commands. Shared method names alone do not imply
compatible durability, resource, or concurrency guarantees.

There are two directions across the interface: Scheme exports methods that the
engine invokes, and the runtime exposes functions for capabilities supplied by
the engine. Validate exports, arity, and boundary values. The initial contract
can use checked dynamic values without requiring whole-program type inference.
Keep names and representations concrete before adding declaration macros.

For a first reducer contract, process one transition at a time for each actor,
allow different actors to run independently, and prohibit synchronous reentry
into an actor already processing a message. A handler computes proposed state
and commands. The host accepts that transition only after its required work
succeeds. Effects finish by delivering later messages. Waiting for network IO
does not require preserving the original worker's Scheme stack.

Other contracts may choose different semantics, but must specify ordering,
reentrancy, cancellation, failure handling, execution budgets, and what accepting
a result promises. In particular, completing computation, retaining state,
durably committing state, and completing external effects are different events.

## Ordinary globals belong to the invocation

In this engine model, changes to ordinary Scheme globals do not survive from
one invocation to the next. Workers receive freshly initialized mutable library
state. Mutating a global with `set!`, or mutating an object reachable from it,
does not request retention. Reusing an execution environment must not expose
mutations from a previous invocation. This is an engine execution contract,
not a change to ordinary Scheme program semantics.

Compiled code and proven immutable data can potentially be shared. Mutable
globals, captured mutable cells, and initialization effects need invocation
semantics even when the runtime pools resources. Module initializers should not
serve as a once-per-application startup hook; the engine's initialization method
provides that lifecycle event.

| State | Owner and lifetime |
| --- | --- |
| Ordinary globals and temporary objects | Worker; discarded after the invocation |
| Retained actor model | Engine; survives calls under the selected contract |
| Durable application records | Runtime storage service; survives the explicitly promised restart or deployment boundaries |
| Files, connections, DOM nodes, GPU resources | Host; represented by handles with defined validity and cleanup |

Retained state is not necessarily durable storage. A local UI can keep its model
in memory. A server engine can require a durable commit before acknowledging an
event. Both policies must be visible to the application.

## Persistence uses runtime functions

The persistence mechanism is an ordinary runtime API implemented through the
Rust interop boundary. The engine configures storage scopes and providers;
Scheme uses exported functions to access them. `define` has no special storage
meaning, and the compiler does not need to recognize individual state services.

```scheme
;; Illustrative runtime functions; not available today.
(define progress (open-state-map "progress"))

(define (save-progress! player-id value)
  (state-set! progress player-id value))

(define (load-progress player-id)
  (state-ref progress player-id #f))
```

The `progress` binding and its handle are recreated for each worker. Opening the
map resolves a stable store identity in the engine's application namespace. The
stored values outlive that binding according to the store's declared policy.
The name alone does not silently select durability: the engine must provide a
declared binding or an explicit scope/policy argument. The spelling and choice
between those API shapes remain open.

Specify actor/session/application scope, supported keys and values, atomic
operations, visibility, failure, schema versioning, and deletion. Reopening a
store must not overwrite existing records with initialization defaults. A load
failure must remain distinguishable from a missing record. Persistent identity
must not depend on a memory address or a source position that changes on edit.

For pure reducers, an adapter uses runtime functions to load and commit models.
If a contract permits direct state writes inside a handler, its transaction API
must define whether writes are staged until successful completion and what
happens when that handler fails. A read followed by a write is not automatically
atomic across actors. Explicit persistence does not itself establish purity.

Durable stores accept supported data with an encoding and schema. Closures,
continuations, ports, and live host handles are not implicitly serializable.
They can be represented by stable logical references only where the contract
defines how to resolve them. Saving data does not retain an old code image.

## Worker heaps and effects

A worker can release its temporary heap after the engine has taken ownership of
all escaping results. Copy, encode, or deliberately promote those results into
storage that outlives the worker; a raw pointer or tagged value into its heap is
not a transfer of ownership. Inputs need equally explicit ownership rules, so
mutating a worker's model cannot corrupt an already published snapshot.

Short worker lifetimes can reduce tracing of temporary allocations. This is a
design opportunity to measure, not a performance result. Today's Rust heap owns
individual boxed allocations; introducing invocation lifetimes does not by
itself provide constant-time arena teardown or safe cross-VM value transfer.

The engine owns pending timers, network requests, and other operations that
outlive a worker. Completion routes a data message to the actor's identity.
An initial command representation should use operation names and data rather
than retain arbitrary worker closures. Child creation follows the same rule:
use a behavior reference and explicit input data rather than a captured parent
heap. Define what happens to pending work when its actor is stopped or replaced.

## Reload code at invocation boundaries

The development engine should watch the build's declared artifact graph. An edit
to a file can change a server module, browser artifact, shader, or several of
them. The source file is an authoring unit; the generated artifact and contract
are the units that the engine validates and replaces.

Build and validate a candidate while the current version remains usable. Pin the
code and resources needed by each running invocation until it finishes. Admit
new invocations to the new version only at a compatible boundary. If retained
state needs migration, quiesce that actor, transform a snapshot, and publish the
new state and behavior together after success. A failed build or migration keeps
the old version available. Crash recovery still requires committed storage;
keeping an old in-memory version is not a recovery protocol.

Ordinary globals restart with the worker; explicit stores reconnect by stable
identity. Version pending commands and completion messages, and decide whether
to finish, adapt, or cancel old work. Separate server and browser deployments can
overlap, so their message schemas need compatibility rules beyond a local reload.

The engine supplies reload behavior. Application code supplies data migrations
and any resource-specific reconciliation required by its contract. A script
does not need to implement its own file watcher or module loader.

For shaders, compile and validate the candidate pipeline before swapping it in.
Keep the last usable pipeline on failure and retain resources referenced by
in-flight GPU work. A compatible shader interface can preserve existing buffers
and bindings; an interface change requires rebuilding or migrating those resources.
The [staging design](staged-programs.md) separates the shader dialect from dynamic
Scheme and describes generated resource layouts and source mappings.

## Distribution and hosting

The same separation of identity, state, and execution can support local and
distributed hosts. A distributed engine additionally needs routing to the current
owner, exclusive ownership and fencing, storage recovery, bounded queues, and
explicit network failures. Location-independent references make distribution
expressible; they do not supply these mechanisms automatically.

Scale by distributing different actor identities. A single busy actor can be a
bottleneck, and a transaction inside one actor's store does not become a
transaction across several actors. A timeout after a commit leaves the caller
uncertain whether the operation happened. Use request identities and atomic
deduplication where retries must not apply a transition twice.

A durable command protocol can commit state and pending commands together,
then deliver commands with retries. External recipients still need idempotency
or another explicit duplicate-handling protocol. Durable state does not imply
exactly-once external effects.

Serverless is one hosting option. A managed provider can operate the machines;
a self-hosted Rust engine can provide the same application contract while its
operator manages capacity. A desktop or browser engine can use it without any
distributed infrastructure.

## Relationship to reading and staging

[Generated libraries](generate-library.md) select readers through explicit paths.
Their outer imports serve generator code; generated runtime imports are separate.
Reading embedded Scheme emits syntax and does not run the document's behavior.

[Staged programs](staged-programs.md) can put server, browser, and typed shader
declarations in one source while emitting separate artifacts. Each engine loads
the artifact for its target and invokes the declared contract. Shader type and
resource validation belong to that dialect. A shader declaration can produce
an artifact without being a callable Scheme procedure.

Engine contracts and runtime state functions can first be prototyped as ordinary
libraries. They do not need to wait for `generate-library` or generalized syntax
transformers. Those features improve authoring and compilation across targets;
they do not replace the host's execution and storage responsibilities.

## Current boundary and next experiments

The Chibi workbook in [draft #10](https://github.com/tsnl/snail-scheme/pull/10)
uses one application shared by all tabs. Native forms send messages to a Scheme
HTTP host, which serializes reduction and HTML publication. It retains ordinary
Chibi objects in memory and loses its model when the server stops. It has no
per-message heap, Rust application engine, persistent map, hot reload, browser
Scheme execution, or asynchronous command protocol.

The current Snail backend links a whole-program entry point. The
[Rust embedding plan](rust-interop.md#reusable-embedding-and-targets) describes
the missing repeated-call interface and rooted result ownership. Establish that
boundary before adding a framework of engines.

1. Specify one reducer contract and implement a small Rust host that calls it
   repeatedly. Verify initialization, messages, views, and failure behavior.
2. Establish invocation isolation. Verify that ordinary global mutations do not
   survive, that explicit model state does, and that no escaping output refers
   into a released worker heap. Measure temporary allocation and teardown costs.
3. Expose a state provider through ordinary runtime functions. Test reopening,
   missing records versus failed loads, commit failure, and restart recovery
   only for providers that promise durability.
4. Add commands and child creation with data messages, completion routing,
   cancellation, and explicit queue limits. Test duplicate delivery and failure.
5. Reload a counter without losing its retained model, reject a bad candidate,
   and test a state migration and a completion from the previous code version.
6. Connect browser and shader artifacts to the same engine lifecycle. A small
   rendered shader and a working DOM event are the observable milestones.

Track implementation work in the [TODO issue](https://github.com/tsnl/snail-scheme/issues/11).

## Precedents

- [Cloudflare Workers](https://developers.cloudflare.com/workers/reference/how-workers-works/)
  dispatches handlers in reusable isolates. Its invocation lifetime does not
  promise a fresh heap for each request.
- [Durable Objects](https://developers.cloudflare.com/durable-objects/concepts/what-are-durable-objects/)
  combine named behavior and private storage. Their
  [activation lifecycle](https://developers.cloudflare.com/durable-objects/concepts/durable-object-lifecycle/)
  distinguishes discarded memory from explicitly saved data.
- [celld](https://celld.dev/docs/) provides a related model on machines operated
  by the application owner. Its [ownership protocol](https://celld.dev/docs/guarantees/)
  makes the conditional storage writes and fencing behind failover explicit.
- [Verse persistence](https://dev.epicgames.com/documentation/en-us/fortnite/using-persistable-data-in-verse)
  distinguishes session-scoped maps from player maps whose persistable values
  survive sessions. Snail should expose its own lifetime policies through runtime
  functions; a weak reference alone is not a durability policy.
