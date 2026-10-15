# Execution candidates, examples, and requirement coverage

**Historical candidate comparison.** The chosen model is now documented in
[Why Snail-Scheme?](why-snail-scheme.md). Actors own their heaps and globals;
spawning and connecting are distinct; connected calls can return values, futures,
or streams. The one-way/fresh-invocation assumptions below belong to this earlier
debate. Use the [tutorial coverage map](tutorials/README.md#requirements-coverage)
for current requirements and examples.

This is a proposed design, not an implemented API. It develops the operational
primitives missing from the earlier [requirements synthesis](application-model.md).
Three independently developed candidates were compared and challenged against
web requests, GUI updates, supervised builds, GPU frames, and reload. Their
examples below use the same small computation so differences in topology and
effects remain visible.

The recommendation is to combine three execution contracts: **invoke isolated
code, transfer encoded messages, and own work across invocations**. Direct
endpoints, topics, and pure handlers returning outgoing messages are useful
compositions of those contracts. Language staging and compiler correctness have
their own obligations; messaging does not implement them.

## Shared example and notation

A count-change event supplies a model value. An ordinary function produces a
presentation, which is emitted to a destination supplied by the composition.
The count is not retained worker state. Rendering once supplies a static document;
rendering later snapshots supports an interactive application.

Messages are **fire-and-forget**. Sending does not create a pending request, reply
route, correlation ID, or wait. The outgoing presentation is another event; its
producer does not await the consumers. Request/response and completion tracking
can be higher-level libraries when an application chooses them.

For compactness, these sketches assume a proposed record-declaration convenience
macro. It defines the record, constructor, accessors, and field metadata together;
there is no second message schema. The declaration syntax is provisional, and
does not add a new execution primitive:

```scheme
(define-message-type <count-changed>
  (count <integer>))

(define-message-type <view-ready>
  (tree <presentation-forest>))

(define (render-view event)
  (make-view-ready
   (resolve
    (element 'output '()
             (number->string (count-changed-count event))))))
```

`<presentation-forest>` permits only declared element records and supported data
leaves. The existing `resolve` function permits opaque leaves, so resolving a
general tree is not sufficient to establish serializability. This particular tree
contains no procedures.

The `element` and `resolve` functions exist in the Chibi prototype. Record codec
generation, the annotated declaration above, and all runtime functions below are
proposals. Their implementations must use the [record-derived S-expression
contract](application-engines.md#message-types-determine-s-expression-schemas).
Artifact entries are data naming a version and exported procedure, not live Scheme
closures. Handlers consistently receive `(event bindings)`; each invocation gets
its explicitly supplied binding values in its own environment.

Each example assumes artifact values and a parent scope supplied by the host.
They share an ownership scope and an invocation policy:

```scheme
(define scope (open-scope! runtime parent-scope))
(define policy (isolate-policy 4 (* 2 1024 1024) 'no-gc))
;; At most four concurrent invocations, each in a fresh 2 MiB heap.
```

The policy is an illustrative budget, not a measured claim that this program fits.
Native queue, subscription, and resource budgets are separate. Setup functions
such as `open-scope!`, `serve!`, and `open-topic!` register resources with the local
host and return references; they are not synchronous calls to a remote actor.
A remote control protocol can use caller-chosen references in ordinary creation
messages, with explicit dependencies if later operations require creation first.

`send!` and `publish!` encode and hand off data to a local provider/adapter. Local
encoding or full-queue errors can be signaled immediately. A successful local
handoff is not a delivery receipt, remote acknowledgement, or completion promise.
Later delivery/drop/retry behavior belongs to the selected provider. These examples
assume successful local handoff, without installing per-message tracking.

## Candidate A: direct endpoints

The composition binds an exported procedure to an endpoint. Each delivered event
can start an independent invocation. The handler sends its output to a configured
destination:

```scheme
;; Exported by workbook-artifact.
(define (render-direct event bindings)
  (send! (binding-ref bindings 'views)
         (render-view event)))

;; Local host composition.
(define renderer
  (serve! runtime scope <count-changed>
          (artifact-entry workbook-artifact 'render-direct)
          (bindings 'views browser-display-endpoint)
          policy))

(send! renderer (make-count-changed 3))
```

The view can be handed off before `render-direct` returns. A later failure cannot
retract it. One endpoint represents one accountable logical service, which may
have many competing workers. Delivery guarantees still come from its provider:
neither retries nor exactly-once processing follow from the word endpoint.

For multiple observers, choose a topic service explicitly. Its publication
endpoint accepts the event, and its subscription protocol owns fanout:

```scheme
(define views (open-topic! topics scope <view-ready> 'ephemeral))
(subscribe-endpoint! topics scope views 'display browser-display-endpoint)
(subscribe-endpoint! topics scope views 'audit audit-endpoint)

(define observed-renderer
  (serve! runtime scope <count-changed>
          (artifact-entry workbook-artifact 'render-direct)
          (bindings 'views (topic-publish-endpoint views))
          policy))

(send! observed-renderer (make-count-changed 4))
```

Adding a view subscriber does not add another render invocation. The same handler
can send through a publication endpoint because that endpoint accepts `<view-ready>`
under its topic provider's contract. This candidate gives a small transport
interface, but `send!` alone says nothing about who creates heaps, keeps bindings
alive, or releases resources.

## Candidate B: topics and subscriptions

The composition describes a publication graph. A subscription is a logical
recipient; workers serving the same subscription divide its work. Both input and
output paths are topics:

```scheme
;; Exported by workbook-artifact.
(define (render-topic event bindings)
  (publish! (binding-ref bindings 'views)
            (render-view event)))

(define counts (open-topic! topics scope <count-changed> 'ephemeral))
(define views (open-topic! topics scope <view-ready> 'ephemeral))

(subscribe-handler! topics scope counts 'renderers
                    (artifact-entry workbook-artifact 'render-topic)
                    (bindings 'views (topic-reference views))
                    policy)
(subscribe-endpoint! topics scope views 'display browser-display-endpoint)

(publish! counts (make-count-changed 3))
```

The `'renderers` subscription can run up to four fresh isolates concurrently.
There is one logical recipient under its delivery policy, not four recipients.
Registering a second subscription adds a second logical recipient:

```scheme
(subscribe-handler! topics scope counts 'preview-renderers
                    (artifact-entry preview-artifact 'render-topic)
                    (bindings 'views (topic-reference views))
                    policy)
```

Now future count changes are routed independently to both subscriptions under
their delivery policy. If both handle an event, they publish to the same view
topic and its consumers can see both presentations. That is useful for
deliberately independent consumers, and wrong if the intent was merely to scale
one renderer. A topic can forbid extra subscriptions, but that adds an exclusivity
rule. Opening a topic here creates a scoped reference without a public name;
`'ephemeral` selects retention policy, not access control.

The graph is pleasant for events such as committed document changes. For a single
logical recipient, it adds membership and subscription lifetime rules without
needing fanout. A private topic with one subscription can implement an endpoint;
it does not eliminate that endpoint's routing or lifetime obligations.

## Candidate C: pure invocations returning outgoing messages

The handler is a pure function returning ordinary emission records. An adapter
sends them after successful computation and encoding:

```scheme
;; Exported by workbook-artifact. Performs no delivery itself.
(define (plan-render event bindings)
  (list
   (make-send (binding-ref bindings 'views)
              (render-view event))))

(define renderer
  (serve-effects! runtime scope <count-changed>
                  (artifact-entry workbook-artifact 'plan-render)
                  (bindings 'views browser-display-endpoint)
                  policy))

(send! renderer (make-count-changed 3))
```

`make-send` creates data. `send!` performs local handoff. The function's returned
list goes to its invocation adapter, not back to whoever sent the input event.
No sender is waiting for a result. The pure function can also be tested or called
locally without performing its proposed effects.

The adapter must encode the output envelopes and payloads into independently
owned storage before discarding the heap. Publication can fail or succeed for
individual destinations; successful return does not provide an atomic transaction
across them. Failure before the function returns publishes none of its planned
messages. Once publication begins, already handed-off events are not retracted.

This is a useful Elm-like authoring discipline over candidate A's execution and
delivery contracts. It is not a different irreducible runtime. Requiring every
handler to accumulate all output until final return would make streaming and
large builds awkward. Pure reducers should be convenient; explicit effectful
wrappers should also be able to send bounded chunks during execution.

## What the debate changes

| Candidate | Useful commitment | Obligation it cannot hide |
| --- | --- | --- |
| Direct endpoints | One provider takes custody of an accepted frame for a declared protocol. | Invocation creation, retained resource ownership, and provider-specific delivery rules. |
| Topics | Independent subscriptions fan out; workers within a subscription compete. | Membership, fanout admission, queue bounds, unsubscribe, and optional replay. |
| Returned outgoing messages | Ordinary pure functions describe results and effects as values. | An adapter still owns publication, partial failure, streaming, and lifetime. |

These choices occupy different axes. Endpoint versus topic chooses routing and
multiplicity. Direct effects versus returned emissions chooses an authoring and
publication discipline. Either can use fresh isolates and native scopes. We can
support all three examples without three execution models.

The topic candidate's strongest objection is that service routing already needs
a binding table. That is true. Pub/sub adds a separate obligation, however:
independent subscriptions each acquire delivery responsibility. Adding workers
within one binding must not multiply application side effects. The endpoint
candidate's weakest version was just `send`; it omitted execution and lifetime.
The pure-effects candidate's weakest version hid those responsibilities inside an
unspecified effect interpreter. The operational contracts below make them explicit.

## Three execution contracts

These are mechanism families, not a claim that the entire runtime has three
system calls. Runtime-control operations may themselves be exposed as ordinary
messages to a native provider.

| Contract | Operation and law |
| --- | --- |
| **Invoke** | Select an artifact entry/version, encoded input, bindings, policy, and owning scope. Decode into a fresh isolate, initialize fresh mutable globals, and execute. The scheduler observes termination locally; reporting it as a message is optional. Only owned outputs survive heap teardown. |
| **Transfer** | Hand an owned encoded S-expression frame to a bound local adapter. Local rejection leaves ownership with the sender; handoff transfers custody. Every receiving isolate decodes into its own heap. There is no built-in response or completion protocol. |
| **Own work** | Create ownership scopes, attach tasks/registrations/resources, and cancel or release them under explicit policy. Scope lifetime need not equal a Scheme heap lifetime. Transfer/detachment names a new owner; waiting for completion is an optional service. |

Remove invocation isolation and there is no bounded temporary heap or stateless
reset rule. Remove encoded transfer and neither heap separation nor remote delivery
has a common contract. Remove independent ownership and a returned function must
either retain its heap indefinitely or abandon its children, subscriptions, and
resource obligations. Those are the concrete reasons for these three contracts.

The important laws are:

1. **Sending creates no wait.** Local queue custody, finished computation,
   committed state, and completed GPU work are different events. The base send
   operation promises no response from a recipient and keeps no pending-call table.
2. **A scope is ownership, not a future.** Invocation return releases its heap after
   handoff. Native scopes keep subscriptions, child tasks, and resource obligations
   alive independently. Cancelling/releasing a scope follows its cleanup policy;
   it cannot undo effects already performed. Observing or joining that cleanup can
   be provided by a separate protocol.
3. **Versions are selected explicitly.** An invocation pins code and bindings for
   its attempt. Queueing a message does not necessarily select code. An application
   needing one version across later events carries explicit artifact references or
   chooses a provider that retains that binding generation.
4. **Serialized references do not own resources automatically.** A UUID or path
   has only its provider's lifetime guarantees. Resource transfer or lease
   acquisition needs that provider's protocol, not generic byte handoff.
5. **All retained work has an owner and a bound.** Fresh heaps do not bound native
   queues, subscribers, optional tracking tables, or GPU resources. Account for
   these separately and define full/slow-consumer behavior.

The examples leave `scope` alive to own their registrations. No particular input
message must be answered to keep or release it. When the host stops that component,
its configured cancellation/cleanup policy releases the owned work. Already
handed-off messages and externally performed effects are not rolled back.

### Optional completion tracking

A build library can explicitly publish artifact-ready events; another handler can
consume them. A join/workflow service may retain dependency IDs, collected results,
and completion conditions when someone wants to wait for several artifacts. It
must register and own that tracking state before forwarding work whose outcome it
tracks. None of this metadata is required on ordinary messages.

Likewise, a request/response convenience library could add reply routing,
correlation, deadlines, and an exported continuation entry with serializable
context. That is an application-selected protocol. It does not change fire-and-forget
transfer underneath it. Keeping an ordinary Scheme continuation suspended retains
its isolate and budget. Discarding that heap requires explicit continuation data
or a future compiler transformation, not hidden closure retention by `send!`.

## Topics, Kafka, and the word isolate

Pub/sub should be a first-class standard service. A generic endpoint is a route
into a protocol; a topic is a provider with publication and subscription semantics.
Kafka topics additionally hold partitioned, retained event logs. Consumers within
one consumer group divide partition work, while different groups subscribe
independently. Those are useful precedents without requiring a Kafka broker or
durable replay for every Snail message. See the [Kafka introduction](https://kafka.apache.org/intro/)
and [consumer design](https://kafka.apache.org/41/design/design/#the-consumer).

A concrete topic provider must specify its membership cut, handoff and overflow rules
when a subscriber is full, and what unsubscribe does to already accepted work.
It must distinguish an offline subscription from an absent subscription. Retention
and replay are explicit features. The sketches choose ephemeral topics, but do
not settle whether their initial provider rejects a full fanout atomically or
defines per-subscriber drop/failure behavior. Either is possible; ambiguous partial
success is not an adequate contract. A provider may expose diagnostics as events,
without requiring a receipt for every publication. Remote delivery still has
later failures.

One immutable encoded frame can be retained by native transport for fanout, with
each receiving isolate decoding separately. That shares bytes, not a Scheme
graph. Replaying a serialized GPU handle does not recreate or retain its buffer;
replay needs an available version, an explicit lease/snapshot, or a stated failure.

**Isolate** is the better term for the heap/resource boundary. V8 uses it for a
VM instance with its own heap; [its embedding guide](https://v8.dev/docs/embed)
distinguishes isolates from contexts. Snail's proposal adds mandatory serialized
crossings and a default fresh invocation policy. The word alone does not imply
short lifetime, purity, a separate OS process/thread, or a security sandbox.

Use **invocation** for one execution and **scope** for native ownership that may
span executions. A higher-level **job** can add a completion condition when useful;
it need not be part of every message delivery. **Actor** remains useful behavioral vocabulary for
a participant exposing a message protocol. **Microprocess** can be an informal
description of a small disposable isolate, without introducing another runtime
type. Stateful native providers are deliberate protocol implementations, not
implicit Scheme application objects.

## Every requirement mapped to its mechanism

The [inventory](application-model.md#requirements-inventory) supplies stable IDs.
This table separates ordinary language/library/compiler work from the three
execution contracts and native provider protocols. The construction layer uses
ordinary values, functions, and libraries plus explicit syntax/stage/type rules;
it is not derived from message passing.

| ID | Requirement | Mechanism and remaining obligation |
| --- | --- | --- |
| R01 | Documents | Pure tree libraries compute a presentation. Invoke once for a build or repeatedly for supplied models; a presentation provider consumes the result. |
| R02 | Markup | Parser and located-syntax libraries construct valid trees. Messaging does not define the reader grammar. |
| R03 | Reader selection | Explicit wrapper imports and source-path resolution; no dispatch registry or `#lang`. |
| R04 | Generated libraries | Staged library elaboration with generator imports separate from generated imports and the generated library's exports. |
| R05 | Reader staging | Expansion preserves hygiene, locations, phases, and dependencies. Reading does not evaluate embedded runtime code. |
| R06 | Ordinary Scheme API | Functions and values supply authoring APIs before any custom reader. |
| R07 | Tree composition | Ordinary elements, fragments, and functions compose locally; resolve and validate before transfer. |
| R08 | UI updates | Pure reducer receives event/model values. Transfer connects events and proposals; an explicit state provider owns committed models. |
| R09 | Chibi prototype | Existing composition libraries run now. Fresh Chibi subprocesses could demonstrate isolate separation; current UI callbacks do not. |
| R10 | HTML/DOM first | Renderer libraries produce presentation data; a browser/native adapter owns DOM effects. |
| R11 | Browser computation | WASM compilation and embedding implement invocation; the browser bridge implements encoded transfer. |
| R12 | One source, multiple destinations | Staging and dependency extraction produce separate artifacts; transferred messages define runtime crossings. |
| R13 | Typed shaders | Annotated declarations, typed IR validation, and shader backends. A shader artifact can be consumed without being a callable Scheme procedure or an actor. |
| R14 | Resin | Layout/packing libraries and shader compilers share type descriptions; a GPU provider owns device resources and completion. |
| R15 | Named targets | Ordinary named build recipes and configuration produce formatted artifacts. A target is not another execution primitive. |
| R16 | Vendored applications | Library-exported recipes compose dependencies and retain source origins. The consumer supplies compatible providers/bindings. |
| R17 | Compilers as libraries | Ordinary direct calls; isolated invocation is optional when separate scheduling or memory ownership helps. |
| R18 | Relative staging | Explicit syntax expansion and evaluation boundaries; one evaluation's artifact/typed graph becomes a later compiler or invocation's input. |
| R19 | Build execution | Invoke an exported builder on a Scheme artifact. A build-specific workflow can retain dependencies and joins over artifact-ready events. |
| R20 | Native control | Native scheduling invokes global exported handlers and transfers events. No Scheme-owned entry loop or retained object is required. |
| R21 | Extensible hosting | Native adapters implement declared protocols, invocation ABI, and resource rules. Deployment may be local, distributed, or serverless. |
| R22 | Runtime and program | The runtime exposes control protocols over transfer; native code still implements invoke and scope ownership. |
| R23 | Stateless compute | Invoke initializes fresh mutable state; later work receives explicit inputs rather than previous globals. |
| R24 | Explicit state services | Native providers retain data and specify transactions, CAS, or sequencing. Ordinary runtime functions expose their protocols. |
| R25 | Concurrency | Independent invocations schedule on threads/machines; adapters transfer frames without a shared Scheme heap. |
| R26 | Supervision | Native scopes own children, bounds, and cancellation. Optional lifecycle events invoke stateless restart policy; waiting is separate. |
| R27 | Communication | Fire-and-forget transfer uses typed bindings naming provider, route, protocol, and resource assumptions independently of worker placement. No implicit response/wait. |
| R28 | Message types | Record/type metadata generates codecs and validation. Optional unions describe variants without a duplicate schema. |
| R29 | Serialization | Transfer always performs actual S-expression encode/decode, including local delivery; no Scheme pointers or closures cross. |
| R30 | Shared resources | Resource providers define namespaces, access, versioning, leases, and ownership of referenced external data. |
| R31 | GPU efficiency | Small commands transfer references; the GPU provider owns buffers/textures/fences independently of the frame isolate's scope. Binary data uses explicit uploads/IO. |
| R32 | 32-bit local addressing | Compiler/runtime ABI bounds local heaps. External storage providers and full-width unsigned 64-bit offset values address bulky data; messaging alone does not supply that scalar type. |
| R33 | Temporary memory | Invoke owns a bounded region and tears it down after output handoff; scopes retain only explicitly owned outstanding work/resources. |
| R34 | GC policy | Invocation budget and safepoint policy enforce no-GC, expect-no-GC, or allow-GC behavior. Native retained resources need separate limits. |
| R35 | Allocation proofs | Compiler cost analysis proves supported allocation bounds under input/callee assumptions; invocation guards check those assumptions. This is separate analysis work. |
| R36 | Hot reload | Rebuild and validate artifacts, pin each attempt's version, rebind new work, drain old scopes/protocols, and explicitly migrate provider-owned data when necessary. |
| R37 | Pub/sub | A native topic protocol supplies independent subscriptions, competing workers, bounded fire-and-forget fanout, and optional replay over encoded transfer. |

## Stress tests and the next prototype

Four cases expose the promises an implementation must actually establish:

1. **Counter and two browser tabs.** Workers compute proposals from snapshots; a
   state provider supplies CAS/transactions. Only committed changes are events.
   Two tabs use two subscriptions; two server workers share one logical command
   recipient. Atomic commit plus publication needs an outbox/transactional
   protocol, or an explicit best-effort gap.
2. **GPU frame.** The renderer already owns buffers and textures; a no-GC isolate
   computes small commands referring to them. The renderer retains device work
   through its fence after the Scheme heap is gone. Uploads and serialization
   remain real costs; obsolete frame policy is explicit.
3. **Parallel build.** Compiler libraries run locally or as child jobs. A builder
   can return while a native workflow owns pending jobs and their join. Completion
   starts a fresh handler for the next dependency stage; no hidden Scheme closure
   keeps the old heap alive.
4. **Reload during work.** Replace a validated binding for new attempts while
   started attempts retain old code. Retain compatible decoders for already queued
   events. Queueing an event and selecting the code for it are distinct operations
   unless its provider explicitly pins the version at handoff.

Start by implementing derived record codecs and one direct endpoint with bounded,
fresh Chibi subprocess invocations. Add a native scope that survives invocation
return, then a returned-emission adapter and a bounded ephemeral topic provider.
Keep the existing library/app examples separately readable in the same worktree.
This sequence exercises the common contracts before adding syntax sugar or
requiring distributed infrastructure. It is a proposed implementation sequence;
none of these sketches makes the current Chibi UI an isolate runtime.
