# Why Snail-Scheme?

**Actors are Snail-Scheme's key programming feature.** An actor owns its memory
and resources, exposes ordinary functions, and communicates through connections.
The same model describes a game, a browser, a database client, a compiler, or a
small computation that lives for one frame.

This is the platform we intend to build. The actor runtime and the tutorial APIs
below are **planned**, not implemented. Today's compiler remains hosted by Chibi;
the [Chibi UI experiment](ui.md) already demonstrates functional tree composition
and reducers. Native and WASI compilation are useful foundations, but WASI alone
does not provide browser hosting or an actor system.

Snail-Scheme aims to be a platform for distributed, heterogeneous computation.
Like .NET in ambition, it should make a collection of runtimes, libraries, tools,
and deployment targets feel like one coherent programming environment. Scheme
provides the language for composition: functions build documents, applications,
programs, and even programs that generate other programs.

## The model

There are three things to keep in mind:

| Concept | Responsibility |
| --- | --- |
| **Actor** | A running instance with its own heap, globals, resources, and lifetime. Its exposed top-level functions handle messages. |
| **Connection** | Access to another actor through a particular protocol. It owns the pending calls, streams, and transport state at its end. |
| **Artifact** | Code or data with a format, interface, and dependencies. An actor artifact can be instantiated; other artifacts include HTML, tensor graphs, and GPU programs. |

An **isolate** names the actor's memory boundary. A **microprocess** is an
informal name for a small, often temporary actor. Neither requires a separate OS
process. A native database or GPU service is also an actor when it exposes a
connection; it need not contain a Scheme heap.

An actor definition selects a Scheme library and the contract of its exposed
procedures. Its compiled artifact tells a compatible runtime what to instantiate.
The runtime spawns the root actor and dispatches messages to its handlers. Scheme
does not need to own `main`, a window event loop, or a network polling loop. A new
`define-actor` form is not a prerequisite: ordinary library exports and build
descriptions can express this definition. Exact declaration syntax remains open.

### Functions handle messages

A handler is a top-level function. Its arguments and results define the call's
data; its library's globals are state local to that actor instance. Two instances
of the same library have separate globals. State survives calls within one actor,
but does not automatically survive actor destruction, replacement, or a crash.

Prefer a functional core: values in, values out, explicit effects at the edges.
Use runtime/library functions to access retained state and IO. Native actors in
Rust are the intended home for production databases, object stores, and device
ownership. Scheme can still implement stateful actors, including mocks and small
controllers. Statelessness is a useful design choice, not special semantics for
`define` or a ban on Scheme state.

### Spawn and connect do different jobs

**Spawn** creates an actor and establishes supervision: who owns its lifetime,
observes failure, and chooses cleanup or restart. The spawner supplies its artifact,
resource policy, and initial dependencies. An actor can therefore receive its
recipients when it is spawned, without a fixed application-wide wiring graph.

**Connect** opens access to an existing actor or service. The connector determines
how to resolve the destination, establish a compatible protocol, and transport
messages. Connecting to a database does not make its server a subordinate. A
browser can be provisioned with a WASM artifact before it connects to a backend.

```scheme
;; Proposed vocabulary, not an implemented API.
(define database (connect database-address 'chat-store/v1))
(define worker
  (spawn chat-worker-artifact
         (list (cons 'database database-address))
         worker-policy))
(define chat (connect worker 'chat/v1))
(invoke chat 'post-message draft)
```

Here `database-address` is a serializable service reference; `database` and `chat`
are connections owned by this actor. Spawning can transfer connection descriptions
for the child to open, never a pointer to the parent's connection object. A
spawner may establish those connections as part of loading the child's bindings.

There is no upward-only rule. Actors communicate with whoever their connections
allow. Supervision and communication form different graphs.

### A connection makes the recipient concrete

Invoke a named handler through a connection. Depending on its contract and
connector, an invocation can produce a value, a future, or a stream. Pub/sub is a
service protocol: subscribing can return a stream, and publication can have its
own acknowledgment policy. A Kafka-like topic is one possible recipient, not the
definition of every connection.

Ordering, delivery, cancellation, and retry rules belong to the connection and
service contract. Failures are reported through exceptions or stream termination
as appropriate. A disconnected call can have an uncertain outcome; the service
decides how that is represented and whether retry is meaningful. The platform
does not silently supply universal exactly-once delivery or automatic retries.

Each connection endpoint owns cleanup of its pending exchanges. An actor's death
closes its local resources; a remote endpoint detects failure under its transport's
rules. Closing a connection need not kill the recipient. A supervisor can handle
a subordinate's failure without losing its other children.

### Messages cross heaps; pointers do not

Every actor boundary encodes and decodes **S-expressions**, including local
delivery. Exposed methods have argument, result, and stream-item types. Record
and variant definitions supply the schema from which codecs and interface
metadata are derived; there is no separately maintained JSON or wire schema.
R7RS records alone do not supply field types or unions, so this metadata is
additional planned library/compiler support.

Decoding constructs values and validates the declared types. It never evaluates
received Scheme. Mutable object identity, closures, and continuations do not
cross the boundary. Resource references do: database IDs, file paths, artifact
IDs, and GPU buffer references are useful message values when both ends agree
on their namespace, access, version, and lifetime.

This keeps large binary resources out of message payloads. A GPU actor can retain
a texture and receive a small command referring to it. A remote connector must
explicitly transfer or remap a resource when that reference has no local meaning.
Location independence does not imply that every machine shares a filesystem or
device.

## Resource lifetimes are a programming tool

A frame actor receives a snapshot, computes a frame result, hands off owned output,
and dies. Its entire heap can be discarded. The renderer and world store outlive
it. The same pattern works for a web request, a build, or a tensor-training step.

The platform keeps a **32-bit Scheme heap/object ABI**. Large datasets, weights,
and buffers live in explicit external storage with full-width 64-bit offsets and
lengths and binary IO/copy operations. These are checked storage ranges, not
disguised Scheme pointers. The current runtime's 32-bit values are a foundation;
the actor isolation and external-storage contracts described here remain planned.

Spawning selects a heap budget and a collection policy:

| Policy | Debug | Release |
| --- | --- | --- |
| `no-gc` | Trap if the reserved allocation budget is exhausted. | Fail the actor; never collect. |
| `expect-no-gc` | Trap on budget exhaustion. | Explicitly choose failure or recovery with collection at a safepoint. |
| `allow-gc` | Collect at permitted safepoints within the resource policy. | Same permission, with configured resource limits. |

Allocation alone never triggers collection. Recovery must first publish live
roots; suspended continuations remain roots in their actor. Encoded outputs and
transferred external resources must have independent owners before a heap is
released. Native/device work may still be in flight after Scheme returns.

Small heaps bound individual collection domains. They do not prove a frame-time
bound: scheduling, IO, native resources, and queued work also need budgets. Later,
allocation analysis should prove that selected bounded computations fit their
regions. The [game project](tutorials/01-game/requirements.md) gives that research
a concrete workload and accounts for implicit allocation as well as user data.

## Control flow and code can change without changing the model

Independent actors can execute concurrently on different threads or machines.
An outstanding call must not lock the whole actor. Suspension releases execution
to the scheduler so other calls can make progress. CPS is a natural implementation
direction: suspended control flow is explicit state local to the actor. Interleaving
means handlers must not assume that actor globals stay unchanged while they wait.
Whether multiple threads may mutate one heap simultaneously remains an implementation
decision; concurrency does not require that choice.

A future `task-run` can schedule a closure within its actor. `call/cc` can help
construct control-flow abstractions, but `(call/cc task-run)` alone does not specify
a yield: capturing/enqueuing a continuation does not stop the original path. A
scheduler handoff must define suspension, resumption, cancellation, and how many
times a continuation can run. Copy-on-write snapshots and thread/fiber migration
are promising later work, subject to native resource affinity. No global thread
pool, async annotation system, or continuation representation is selected here.

Hot reload follows ownership. Build and validate a candidate artifact, then use
it for newly spawned work. In-flight work pins its old code and resources until
completion. A game can replace frame logic without replacing the window or GPU.
Replacing a retained actor requires an explicit reset or state migration; globals
are not a persistence mechanism. The same dependency graph rebuilds an embedded
shader or browser target when its enclosing source changes.

## Building is another use of the platform

A build runtime loads a Scheme source artifact, spawns a build actor, and invokes
its exported `build` procedure. It produces an application description and completed
artifacts, then retires. Runtime control is itself exposed through actor
connections; there is no separate application-visible engine/program hierarchy.
Some native code necessarily starts and schedules the first actor.

Application descriptions are ordinary values exported by libraries. They compose
named artifact recipes, actor definitions, service requirements, and deployment
configuration. A consumer can vendor a chat application, select a database
provider, and build both browser WASM and native server code. A target names a
recipe; it need not become another runtime abstraction.

Compilers and readers are libraries too. Calling a compiler locally does not
require spawning it. Ordinary Scheme can construct a typed tensor graph, transform
it with autodiff, and compile it into a GPU artifact. A GPU program can be typed
without imposing static types on all the Scheme that builds it.

Three activities must remain distinguishable: expand syntax; evaluate builders;
execute their shipped outputs. They can recur at later stages. Reading embedded
code does not run it. Capturing a training graph does not train a model. Build
closures stay local; only explicit syntax, IR, constants, and artifacts cross
stages. See the supporting [staging proposal](staged-programs.md).

Builds can validate service contracts and emit dependency and discovery recipes.
Actual instances, credentials, and placement are resolved in the deployment/runtime
environment. A compiled requirement for `chat-store/v1` is not a permanently baked-in
database connection. Local, self-hosted, and serverless adapters can satisfy the
same requirement where their service guarantees match.

The [generated-library proposal](generate-library.md) supplies explicit wrappers
for foreign sources: no `#lang`, reader registry, or file-extension lookup.
Generator imports belong to generator execution; generated imports belong to
the output library. One `begin` computes that library's implementation. A document
reader should emit calls to ordinary composition functions, preserving syntax
origins, hygiene, and dependencies.

## Three programs that should justify the platform

These are future integration tests as well as tutorials. Each project has a
reading sequence, proposed source responsibilities, and observable acceptance
criteria. None is claimed to run today.

| Project | What you build | What it must demonstrate |
| --- | --- | --- |
| [A game that reloads while you play](tutorials/01-game/README.md) | A small interactive game with runtime-dispatched handlers and disposable frame actors. | Native IO, supervision, heap budgets, resource ownership, and hot reload. |
| [A chat application in two places](tutorials/02-chat/README.md) | A native server, database service, and multiple WASM browser clients. | Derived S-expression protocols, streams, functional DOM composition, staged builds, discovery, and vendoring. |
| [A graph that learns handwritten digits](tutorials/03-tensors/README.md) | A Scheme-built tensor graph, autodiff, GPU training, and an interactive MNIST workbook. | Compilers as libraries, typed target IR, external data, numerical correctness, and heterogeneous execution. |

The three central demos alone would leave gaps. The chat project's document
extension exercises markup and `generate-library`; the game has an allocation
analysis extension; tensor training includes a typed-kernel extension. The
[coverage map](tutorials/README.md#requirements-coverage) assigns every earlier
requirement and the later refinements to explicit checkpoints. Allocation proofs,
generalized transformers, and continuation machinery remain language/runtime work
with these projects as clients, rather than features somehow supplied by actors.

This document is the current design. The earlier
[requirements synthesis](application-model.md),
[execution candidates](execution-primitives.md), and
[execution notes](application-engines.md) preserve the discussion history. Their
mandatory fresh heap per invocation and fire-and-forget-only assumptions are
superseded by actor lifetimes and connection-defined calls here. Work tracking
remains in the [TODO issue](https://github.com/tsnl/snail-scheme/issues/11).
