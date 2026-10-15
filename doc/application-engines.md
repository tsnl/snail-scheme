# Channels, isolates, and explicit state services

**Historical design note.** The current model is
[Why Snail-Scheme?](why-snail-scheme.md), with
[tutorial requirements](tutorials/README.md) as its integration targets. This
earlier note's mandatory stateless invocation and fire-and-forget assumptions
are superseded by actor-owned state/resource lifetimes and connection-defined
calls. Its detailed memory and codec explorations remain background material;
they do not override the current design.

This is a planned execution model, not an implemented runtime API. The
[requirements and synthesis](application-model.md) collect the requested features.
The [candidate comparison](execution-primitives.md) supplies code examples and
derives three execution contracts: invoke isolated code, transfer encoded
messages, and own work across invocations. This note develops their execution,
memory, and resource rules. It replaces the earlier assumption that every actor
has a retained application model.

The [Chibi UI prototype](ui.md) demonstrates
model/update/view composition and an HTTP host. It does not implement the
isolation, mandatory message serialization, state services, or reload described
here. Procedure names are sketches. The filename preserves earlier design links.

## Actors are the application execution model

Use isolate for a heap/resource domain, invocation for one execution, and native
scope for ownership that may span invocations. Earlier microprocess terminology
describes a small disposable isolate; actor remains a description of a participant
with message behavior. Ordinary Scheme computation retains no
implicit application state across invocations. Its globals, stack, and working
heap belong to the current invocation. Long-lived data belongs to explicit state
or resource services, initially implemented in Rust or other native libraries.

Channels address work. A service channel can dispatch independent messages to
many fresh microprocesses; it need not identify one resident Scheme object. A
particular task or native service can also have its own endpoint. A browser or
server application exposes suitable channels while its runtime chooses how to
host the work. Logical model identity, endpoint identity, and worker identity
remain separate.

The runtime owns scheduling, loading, routing, and memory/resource enforcement.
Its control operations are also available as a native service protocol. A
supervisor requests work through that protocol; ordinary Scheme libraries expose
sending, spawning, cancellation, and state/resource requests as functions. The
runtime does not need a second application-visible engine/program distinction.
Its scheduling instructions themselves remain native implementation mechanisms.

| Term | Responsibility |
| --- | --- |
| Message | Typed value with a derived S-expression encoding. |
| Channel | Bound endpoint and protocol for admitting serialized messages. |
| Artifact | Passive code/data with a format, interface, and dependencies. |
| Isolate | Independent Scheme heap/resource domain with an explicit policy. |
| Invocation | Execution of an artifact entry with explicit input and channel bindings. |
| Scope | Native ownership of tasks and registrations across invocation lifetimes. |
| Topic | Native provider implementing publication, subscriptions, and their delivery policy. |
| Runtime | Implements execution and channels; exposes control operations through a native service. |
| Contract | Describes types, effects, ordering, failure, resource domains, and lifetime. |

The [build-target proposal](staged-programs.md#build-targets-artifacts-and-applications)
names artifact-producing recipes. A compiled handler artifact can instantiate
microprocesses. A texture, static document, or shader is consumed by a service;
not every artifact must implement actor message handlers. Applications compose
these recipes and their required channel bindings as ordinary library values.

## A precise actor boundary

For the default Scheme execution contract:

```text
Isolate = (owned-heap, temporary-execution-state, resource-policy)
invoke(artifact-entry, encoded-input, channel-bindings, budget, owning-scope)
    -> encoded outgoing messages and local execution outcome
```

The runtime decodes the input into the receiver's own heap and invokes an exported
function. The function computes results and effect requests. Outputs must be
encoded into independently owned buffers before the invocation's memory is
released. A native service also owns its decoded requests. No Scheme object or
pointer crosses the boundary, including local communication.

Within the invocation there is control state, local mutation, and possibly a
bounded sequence of messages. Statelessness means that these are not implicit
application storage for the next invocation. The preferred handler computes a
result and stops; a later completion carries explicit data into fresh work.
A task deliberately kept alive awaiting more messages consumes its reserved
resources until termination.

Messages to the same stateless service channel may execute concurrently. Ordering
is a channel/service contract, rather than a single-threaded application-object
rule. Each microprocess's own mutable Scheme heap is used by one execution at a
time. A native service can have its own internal synchronization and long-lived
resources without making every Scheme handler stateful.

An application can expose one channel that coordinates several internal services.
A browser process and a server process can each host many actors, and a frame
microprocess can exist without an OS process or thread of its own. A private task
endpoint may identify one live invocation; a stable service endpoint can outlive
many invocation and artifact versions. Reusing a runtime slot must not redirect
an old live-task reference to a new occupant.

## Contracts describe behavior and execution

Application behavior remains ordinary exported functions. The existing UI helpers
are useful without becoming methods of an automatically retained object:

| Procedure | Meaning |
| --- | --- |
| `initialize(options)` | Compute an initial model value for an explicit state owner. |
| `update(message, model)` | Compute a proposed next model from supplied values. |
| `view(model)` | Compute a presentation from a supplied model. |
| `migrate(old-version, model)` | Compute candidate data for an explicit storage migration. |

An event handler can call these helpers and return messages. The native host or a
model service owns any retained UI model. The current Chibi reducer returns only
a model; commands and the service protocol are future extensions. Restoring data
is an operation of that explicit state service, independent of a worker's identity.

A static renderer evaluates a view once. An interactive host supplies new snapshots
and evaluates it after updates. Start with HTML and the browser DOM. The generic
tree API remains applicable to other renderers. Resolve local component procedures
before crossing a channel: send a validated data tree or rendered HTML, not closures.

A contract declares input types and the meaning of outputs, required channel
bindings, resource domains, and failure/ordering rules. The initial implementation
can check dynamic values without whole-program type inference. Exported functions
and ordinary runtime APIs are sufficient before adding declaration macros.

A pure handler returns proposed commands; the runtime publishes them after
successful computation and encoding. This does not atomically commit a database
update or every external effect. A stateful service specifies conditional updates,
transactions, and any relationship between commit and publication. Direct IO
through an effectful runtime function must not be described as pure evaluation.
Returned messages are an optional adapter, not a requirement to accumulate all
output until termination. Explicit effectful handlers can publish incrementally;
later failure cannot retract already handed-off messages.

## Channel bindings and supervision

A binding specifies a provider/adapter, endpoint, protocol version, and required
resource namespace. Begin with explicit application-supplied bindings rather
than a universal naming or discovery system. A channel reference can be encoded
for another participant only when that participant can resolve its provider and
endpoint under the binding's rules. A local handle or heap address is not a wire ID.

The base operation sends an owned encoded frame without waiting for the receiver.
Handoff is to a local provider/adapter; it can reject malformed input or a full or
closed queue locally. It creates no implicit reply route, correlation ID, pending
request, or completion acknowledgement. Optional libraries can add tracking or
waiting using ordinary messages. Handoff transfers custody of bytes without
promising delivery, processing, durability, or completed effects. Concrete
providers specify capacity, ordering, retries, and failure/drop policy. Independent
invocations can finish out of order; a GPU stream can require ordered submission.

Runtime control accepts one-way start and cancel messages. A start names a
caller-chosen task reference, code, initial input, bindings, limits, and an owning
scope. Lifecycle notifications are optional subscriptions; starting does not
require a result channel or returned job identity. A local native setup function
may create and return a task reference directly. A supervisor's
registry and restart bookkeeping live in the native runtime or an explicit state
service; a Scheme policy handler can remain stateless. Subordinate jobs either
belong to the parent's cancellation scope or are explicitly detached. Define
resource release and late-result behavior in both cases.
The native job scope can outlive the parent handler's invocation and heap while
children run. Ending that scope, rather than merely returning from one Scheme
function, triggers its child cancellation policy.

Stopping one worker is not evidence that its child or an external operation never
ran. Retry pure computation against a known input; retry published effects only
under the destination's idempotency/transaction protocol. Native control services
and user programs share a message interface, while the scheduler still performs
the underlying work directly.

## Artifacts and messages at every stage

Building and deployed execution use the same invocation boundary. Artifacts are
passive inputs/outputs with explicit formats and interfaces. A Scheme source bundle
can run in an interpreter; a native or WASM handler module requires a compatible
loader; an ELF executable needs process launch; a graphics service consumes its
supported shader and resource formats. Loading is not inferred from a `#lang`
prefix or extension registry.

The baseline `build-interpreter` service dispatches a build request to an exported
`build` function. The notation `(build)` denotes a declared message, not arbitrary
Scheme evaluation of incoming data. The builder composes ordinary values and can
call compiler libraries within that same invocation. A compiler is placed behind
a channel when separate scheduling or isolation is useful, not because compilation
requires a new execution primitive.

A build-specific library can add compiler jobs and artifact-ready events over
fire-and-forget delivery. Keep orchestration data in explicit messages or a native
job/state service; do not implicitly retain
the builder's Scheme globals or continuation. Completion starts fresh computation
when necessary. Publish a manifest only after required artifacts are complete,
including their interface and dependency information.

The [staging design](staged-programs.md#build-evaluation-is-an-actor-invocation)
distinguishes expansion, ordinary evaluation, and later execution. The first build
service can use Chibi without compiler self-hosting. A generator returns located
syntax; a tracer produces typed IR; later evaluation consumes those artifacts.
Runtime and build invocations share memory and channel rules without merging their
language phases.

## Message values and delivery envelopes

The application payload is a value of a type accepted by the channel contract.
Use records for named commands and events; a union can group variants.
The workbook already defines:

```scheme
(define-record-type <adjust-count>
  (make-adjust-count delta)
  adjust-count?
  (delta adjust-count-delta))
```

A pure handler can return command data for delivery:

```scheme
;; Proposed command constructor, not an immediate IO operation.
(make-send counter-channel (make-adjust-count 1))
```

A possible envelope representation is:

```scheme
(<delivery>
  (to (<channel-ref> (provider "workbook") (endpoint "counter")))
  (payload (<adjust-count> (delta 1))))
```

The names are illustrative. The endpoint denotes a protocol accepting work; it
need not select one persistent counter worker. Envelope/reference schemas come
from runtime type metadata, while application schemas come from message types.
A higher-level request/response library can explicitly add reply routing and
correlation data. Neither is part of the base envelope or implied by sending.
A reply is another one-way message; correlation is not itself deduplication.

Every actor delivery encodes and decodes, including native service requests and
workers in one process. Once encoded, a sender's later mutation cannot change the
message. The runtime can move encoded buffers through a local queue, but cannot
bypass the codec by sharing Scheme records, closures, or heap pointers. Bound
encoded size, decoded allocation, and parsing depth; small text can still request
substantial work or allocation.

Large data crosses as a reference under an explicit resource protocol: database
IDs, agreed filesystem paths, artifact IDs, or device buffers. Participants may
share external resources and binary IO paths if their provider defines access,
mutation, and lifetime. They still exchange serialized control messages and never
lend one microprocess's Scheme heap to another. See the
[GPU example](application-model.md#serialization-is-unconditional-resources-are-explicit).

Queued is different from processed. Baseline delivery does not automatically retry
an uncertain remote request or failed handler. A connection that promises ordering,
retries, or persistence must implement and document that promise. A stopped task
cannot process further messages; a stable service channel can instead route new
work to another invocation. If a library adds tracked requests, that library must
specify their timeout/cancellation outcomes; ordinary sends create no pending call.

## Message types determine S-expression schemas

Messages use S-expression encoding. Their schemas are derived entirely from
their types: variants, record identities, fields, and any declared field types.
There is no separately maintained schema declaration or JSON representation.
An actor contract names the message type it accepts; the runtime derives the
encoder, decoder, and validation from that type's metadata.

The workbook already uses three distinct record types. A proposed union form
can group them without changing their constructors or wrapping their values:

```scheme
;; Proposed library syntax; not implemented in the workbook.
(define-union-type <message> message?
  <adjust-count>
  <toggle-notes>
  <reset-workbook>)
```

`<message>` would describe a closed set of record variants. `message?` accepts
instances of any member type. Each instance already carries its record identity;
the union adds metadata about the alternatives rather than another object around
each message. A type-aware case form could use this same metadata to check that
all variants are covered. Ordinary `cond` does not acquire exhaustiveness checks.

For this union, a possible data representation is:

```scheme
(<adjust-count> (delta 1))
(<toggle-notes>)
(<reset-workbook>)
```

The tags and field names come from the record types. Named fields let decoding
follow the receiving type's layout even if its field order changes. These are
data representations, not calls to constructors. Record-to-datum conversion
followed by `write` produces the text; `read` followed by validation and
reconstruction produces instances of the receiving environment's record types.
Received datums are never evaluated. An ordinary record's printed representation
is not itself a portable serialization.

The current record declarations provide field names but no field types. They
cannot establish that `delta` is an integer simply because the reducer adds it.
Unannotated fields use the codec's supported Scheme-datum type. Stronger field
constraints belong in the record type declaration and become part of the derived
schema. A record-valued field needs its record type represented in that metadata;
an ordinary list resembling an encoded record must remain ordinary list data.

Decoding is directed by the expected message type. The decoder accepts only its
known variants and fields, checks field values, and rejects missing, duplicate,
or unknown fields. It reconstructs a record only after those checks succeed.
The first codec should have acyclic value semantics: it reconstructs values
without promising object identity or shared mutable references. Its supported
datum grammar and input size/depth limits still need specification.

A type's external identity should derive from its defining library and declared
name. Import aliases, heap addresses, source locations, and variant positions
must not supply that identity. The short tags above assume an already selected,
unambiguous union. A Chibi prototype can reject ambiguous reflected record names;
Snail's type metadata should retain the defining library identity.

A structural fingerprint can be derived from the type declarations for reload
and deployment checks. It detects a schema change; it does not decide semantic
compatibility or replace a migration. Renaming a declared type or changing a
field's meaning still needs an explicit compatibility decision. Compatible data
is reconstructed with the new invocation's types rather than retaining old record
descriptors. A state service owns any retained values. Every delivery to a new
actor or invocation uses the same encoding/decoding contract, including local delivery.

This can begin as a Chibi library using record metadata, with a small union
descriptor and declaration macro. [SRFI 99](https://srfi.schemers.org/srfi-99/srfi-99.html)
provides record inspection and procedural construction under Chibi. Any future
field annotations and case syntax should feed that same metadata. This does not
require `generate-library`, generalized transformers, or whole-program type
inference before the first experiment. The current workbook still keeps its
records in the HTTP host and sends only action URLs to the browser.

## Ordinary globals belong to the invocation

Every Scheme invocation receives fresh mutable library state. Changing a global
or an object reachable from it does not retain application data for later work.
Pooling code and empty arenas must not expose mutations from a previous task.
This is an execution contract, not a change to ordinary Scheme expression semantics.
Module initialization runs under that contract; a global binding is not a
once-per-application startup hook or an implicit durable state declaration.

| State | Owner and lifetime |
| --- | --- |
| Scheme globals, stack, and temporary objects | Current microprocess; discarded after encoded output handoff. |
| Model snapshots in a message | Decoded into the receiving invocation; changes are proposals until a service accepts them. |
| Retained or durable application data | Explicit native state service; keyed independently of worker identity. |
| Files, connections, DOM nodes, GPU resources | Explicit native provider with access, lifetime, and cleanup rules. |

A local UI state service can be in-memory. A database service can promise durable
commit. Neither is automatically supplied just because a worker has an identity.

## Persistence uses runtime functions

Expose storage through ordinary runtime/library functions backed by a channel
protocol. Functions can emit commands and consume state-change events; any API that
performs IO directly must expose its asynchronous/effectful semantics. No special compiler
meaning attaches to `define`, and storage is not a method on every Scheme actor.

The application supplies a state-service binding and a namespace/key. An invocation
can reopen access to that service without owning or reinitializing its stored data.
The provider defines consistency, versions, supported values, durability, and
retention/deletion. A missing record differs from a failed load. Worker ID, machine,
and artifact version must not accidentally become the data's persistence identity.

For pure reducers, the host supplies a model snapshot and event. The worker computes
a proposed update. The service accepts it under a transaction, compare-and-swap, or
explicit per-key serialization rule. Independent workers may race; two reads followed
by blind writes do not constitute an atomic increment. Use request identities with
atomic deduplication if retries must not apply a committed operation twice.

Explicit state does not automatically make a computation pure, nor a send durable.
A service transaction/outbox can coordinate retained updates and pending effects;
recipients still need their own duplicate-handling rules. Durable schemas and reload
migrations refer to the stored data, not an old worker's object layout. Closures,
continuations, and arbitrary live host handles are not implicitly persistable.

## Microprocess heaps are temporary regions

A Scheme microprocess owns an isolated, bounded working heap. Most tasks handle
one message and finish; a deliberately longer task can handle several messages
within its declared lifetime. On completion, encode outgoing messages into owned
buffers and transfer explicit resource ownership before recycling temporary memory.
Retained application data remains with its state/resource service.

No longer-lived object may retain a raw pointer into a discarded heap. Every
incoming message is decoded into the receiving microprocess's heap. Native service
requests also cross through serialized values. The runtime may transfer an already
encoded buffer without copying it, but no local delivery shortcut shares a Scheme
object graph. Explicit external resource references remain valid only under their
provider's lifetime rules.

Keep retained data partitioned inside native providers or managed external storage.
There is no automatically promoted global Scheme heap. Code and empty regions may
be pooled; mutable Scheme objects and initialization belong to each fresh task.

| Policy | Allocation and collection |
| --- | --- |
| Bounded task | Allocate within a reserved budget, avoid collection during computation, and release memory after output handoff. |
| Collecting task | Permit a local collector under an explicit allocation limit and scheduling policy. |

An arena can discard cyclic temporary graphs together. Exhausting its budget follows
the explicit spawn policy below. Retrying a pure computation against the same input
is different from retrying work that already published an effect.

Local collection still consumes CPU and can block other work sharing a thread.
Schedule expensive work away from a frame thread or provide bounded preemption.
Bound queued encoded messages, decoded values, output buffers, and native resources
as well as the task heap. Mandatory serialization is measurable work and belongs
in the frame budget.

The current runtime allocates individual boxed objects and separate payloads;
dropping it still walks those objects. Cheap region reset needs appropriate
allocation and resource accounting. Resetting an arena does not close ports,
release GPU resources, or finish pending IO automatically. Bulk ownership and native
cleanup obligations must be known before teardown.

Pending IO belongs to native services, with explicit resource ownership and
optional notification destinations and serializable context. It must not retain a
callback into a discarded Scheme heap. A later event can start another microprocess;
a task deliberately waiting with its heap alive needs an explicit lifetime and budget.

## Collection policy is part of spawning

Spawning supplies a memory-policy value alongside the behavior artifact and input
message. Keep collection permission, region capacity, and the action on exhaustion
explicit. The policy is ordinary runtime data, and is fixed before a task starts.
For example, these are proposed constructors and operations:

```scheme
(define frame-memory
  (make-memory-policy
    (* 8 1024 1024) ; reserved region capacity, including charged overhead
    'no-gc         ; collection forbidden in every build profile
    'fail))        ; release action when the region is exhausted

(spawn frame-artifact frame-input frame-memory)

(define speculative-memory
  (make-memory-policy
    (* 8 1024 1024)
    'expect-no-gc   ; debug asserts that this task needs no collection
    'collect))     ; release may collect within the reserved capacity
```

The numbers are illustrative, not a measured frame budget. A policy constructor
should validate its combinations, for example rejecting `no-gc` with a collection
fallback. Use three distinct collection modes:

| Mode | Debug | Release |
| --- | --- | --- |
| `no-gc` | Trap on exhaustion or an explicit collection request. | Collection stays forbidden; exhaustion fails the task. |
| `expect-no-gc` | Trap on exhaustion or an explicit collection request before recovery. | Follow the selected action: fail, or collect and try to continue. |
| `allow-gc` | Allow normal collection within the capacity policy. | Allow normal collection within the capacity policy. |

A debug violation should stop immediately and make the debug runner crash, with
the actor/task identity, source location, requested bytes, and allocation totals.
Reserve reporting capacity so diagnosing a full region does not need another
allocation from it. Production recovery is an explicit policy choice; it does not
follow automatically from disabling assertions. An actual host allocator failure
is a different condition from reaching a checked region limit.

An ordinary collection heuristic is not proof that a region is exhausted. Under
`no-gc` or `expect-no-gc`, suppress threshold-triggered collection while admitted
allocations still fit. Gate every real collection entry, including explicit
`collect-garbage` and native requests, so helper code cannot bypass the policy.
Here `no-gc` permits allocation; a separate zero-allocation contract is stronger.

Check and charge allocation before changing the region, including object headers,
alignment, variable payload capacity, and growth. Define whether input decoding,
mutable library initialization, and output construction use this region; include
them in its accounting when they do. Runtime stacks, compiler/FFI scratch space,
collector scratch, and external buffers need separately stated limits or charges.
The existing object-count collection threshold is not a byte budget, and a limit
on the Scheme region alone is not a bound on all host memory.

Release collection recovery occurs only at a valid safepoint with live values
published. Allocation itself must remain unable to collect, including inside a
native call that holds temporary borrows. Preflight an atomic operation's needs,
or return a checked capacity condition to a boundary with a specified retry rule.
Do not continue arbitrary partially completed work after catching an allocation
failure or panic. A collector fallback also requires an allocator capable of
reusing reclaimed space; a bump-only arena cannot gain that ability from a flag.
If collection cannot make enough room, fail within the same capacity limit.

Growing instead of collecting can be a later fallback with a separately declared
larger hard limit. It preserves the absence of collection while relaxing the
original reservation, and must preserve existing pointer validity. Neither growth
nor collection fallback preserves the original frame-latency expectation. Record
fallback use and expose it in the task result or runtime diagnostics so release
builds can reveal violations missed in testing. Frame actors select strict `no-gc`.

The runtime functions and failure handling described here are planned. The
[interop allocation contract](rust-interop.md#allocation-ownership-and-failure)
already separates soft thresholds, future quotas, and host allocation failure.

## Proving a task fits its region

A checked budget and a static allocation proof complement each other. A checked
budget ensures that a task stays within its limit or takes the selected failure
path. A proof can establish that accepted inputs do not reach that path, assuming
the reserved storage is available and the implementation satisfies its cost model.
For a region with no reclamation before reset, bound total charged allocation
since reset, rather than only the maximum live object graph. A loop discarding
one fresh pair per iteration has a small live set but consumes region space on
every iteration.

A useful handler summary is an upper bound in terms of validated input sizes:

```text
allocation(frame, n) <= setup-bytes + n * bytes-per-entity
requires: 0 <= n <= maximum-entities
```

The coefficients must come from the selected lowering and allocation layout;
they are not source-level counts of `cons` calls. Include captured cells, closure
environments, numeric boxing, rest-argument lists, strings, vectors, and other
implicit allocations. Input preparation and result transfer need bounds for the
regions that own them. A claim about one handler's body should identify that scope.

Start with a conservative allocation-summary pass over known operations and
resolved calls. Sequences add their costs, branches include their test and the
maximum branch cost, and bounded iterations multiply the per-iteration bound.
Account for loop-control work and allocation in size-dependent primitives as well.
Known higher-order callees can contribute their own summaries. Unresolved calls,
unbounded growth, and unsupported recursion produce an unknown bound until further
analysis or checked input restrictions justify one. Annotation alone is not proof;
native summaries need an explicit trusted contract and validation strategy.

Build artifacts can carry the derived bound, its input preconditions, collection
effects, and the compiler/runtime layout it assumes. At spawn, validate the input
preconditions, evaluate the bound with checked arithmetic, and reserve enough
space for the full invocation before admitting it. A task requiring proof is
rejected if the bound is unknown; other tasks can use runtime checking. Changing
code, its callees, lowering, or object layout requires recomputing the bound.
Runtime charging remains useful in debug builds to detect implementation mistakes.

A finite allocation bound does not rule out an explicit `collect-garbage` call;
collection permission remains a separate effect/dispatch check. Nor does an
allocation bound prove termination, a deadline, or bounded external IO. Those
properties need their own contracts. The valuable first guarantee is that the
prepared task fits its reserved region and performs no collection.

[Resource Aware ML](https://www.raml.co/interface/howto/) is a precedent for
deriving resource bounds as functions of input size under an explicit cost model.
Snail can start with simple conservative summaries after the measured backend
baseline; adopting a general resource type system or proving arbitrary Scheme
programs is not required for the initial checked policy. No allocation-summary
pass or proof-enforced spawn operation is implemented yet.

## Thirty-two-bit heaps and external data

Keep the Scheme object ABI and ordinary local addressing 32-bit. Large datasets,
neural-network weights, and GPU buffers belong to external storage with explicit
64-bit positions. A 32-bit runtime can carry 64-bit scalar data in boxed values or
several words; this does not widen its heap pointers. The full unsigned 64-bit
range needs an explicit representation and checked arithmetic: the current exact
integer implementation uses signed `i64`, which cannot represent that whole range.
Do not silently route storage offsets through floating-point numbers.

An external reference identifies a storage owner, an object or region within that
owner, a version where needed, and a byte range. Its offset and length are `u64`.
The owner may be a file, buffer, or device service actor. A raw process address is
not a portable storage identity. A native adapter may resolve a reference to a
pointer internally, while Scheme sees explicit storage operations.

| Value | Meaning |
| --- | --- |
| Local Scheme pointer | A 32-bit address valid in the current allocation domain. |
| External region reference | An owner/object reference plus 64-bit offset and extent, with defined access and lifetime. |
| Local transfer buffer | A bounded bytevector or explicitly owned buffer that fits the local address space and task budget. |

Expose binary range reads, writes, and copies through runtime functions and
service messages. An operation can copy a bounded window into local memory, or
copy between external resources without sending all bytes through a Scheme heap.
Rust's [positional file API](https://doc.rust-lang.org/std/os/unix/fs/trait.FileExt.html#tymethod.read_at)
is a concrete precedent: it accepts a `u64` file offset and a local byte buffer,
and reports the actual transfer length. The public protocol must specify short
transfers, errors, overlap behavior, and when a destination becomes available.

The binary operation is memcpy-like for bytes already accessible to an adapter.
An ordinary [native memory copy](https://doc.rust-lang.org/std/ptr/fn.copy_nonoverlapping.html)
requires valid local pointers; casting a 64-bit storage offset into a 32-bit pointer
does not access external storage. Check ranges without overflowing offset/length
arithmetic and split large transfers into chunks that fit local buffers. Raw
binary copying applies to byte data, not Scheme object graphs containing local
pointers and record descriptors.

Asynchronous requests cannot borrow a task's temporary destination pointer after
it returns. The provider owns or explicitly pins a transfer buffer until completion,
then transfers ownership or supplies a reference usable by the next invocation.
Storage references in messages use type-derived S-expression codecs; the referenced
bytes remain binary. Keep weights immutable or versioned for readers, with explicit
single-writer ownership for updates. The resource owner defines release or lease
rules; collecting a local reference wrapper alone does not settle resource lifetime.

A 32-bit address space bounds each working set but does not by itself require
multiple actors: one actor can stream a much larger dataset. Spawn actors for
independent tasks, ownership, or parallelism, and choose coarse enough work to
amortize scheduling and copying. Many heaps in one native 32-bit process still
share that process's address space. Scaling resident data beyond it needs separate
processes or external backing; spawning logical actors alone does not expand it.
Use actor budgets substantially below the address-space ceiling for predictable
collection. A multi-gigabyte heap would still permit a long local mark or sweep.

## One microprocess per frame

A native frame/state service owns the current game-state version and frame
admission policy. A renderer owns the surface and GPU resources. For a first
design, admit one game-state transition at a time:

1. Supply a serialized input/snapshot reference to a fresh frame microprocess,
   with a bounded region and collection disabled.
2. Compute a proposed state delta and draw requests. Publish owned external
   buffer data through the explicit binary-resource API when required.
3. Encode the proposal and transfer its bytes to the frame/state service. That
   service accepts the next version under its commit rule.
4. After acceptance, the service submits serialized draw commands naming resident
   resources. The renderer retains
   buffers and textures until GPU completion, independently of the task heap.
5. Discard the frame microprocess's memory after handoff.

Do not deserialize the whole game world or textures into every frame heap. Use
bounded inputs and explicit external snapshot/resource references. References
alone do not populate changed transform buffers: account for their writes/uploads
or GPU computation. Native resource sharing is explicit and never exposes another
microprocess's Scheme pointers.

Warm code and arena reuse avoid requiring OS process creation for each frame.
Bound the number of in-flight frames and output queues. Define what happens on
budget exhaustion or deadline failure, such as retaining the last complete frame.
No-GC execution does not by itself bound scheduling, serialization, native IO,
rendering, or teardown latency; measure those costs independently.

## Reload code at invocation boundaries

A native development service watches the artifact dependency graph and builds
candidates while the current binding remains usable. One file may produce server,
browser, and shader artifacts. The validated artifact/contract is the replacement
unit; the source file is its authoring unit.

Route new work to the accepted version. Existing invocations keep their code and
resource versions until completion or explicit cancellation. A failed build leaves
the old binding in place. Stateless workers do not need a retained Scheme object
migrated from one code image to another.

Stored data and native resources have their own compatibility rules. Quiesce or
version service access as needed for a migration, transform a snapshot, and publish
only after the state service accepts it. New/old clients and pending replies may
still use earlier message schemas. A compatible structural fingerprint is not a
proof that field meanings or effects remain compatible.

For shaders, validate a new pipeline before swapping it into service. Retain old
resources while in-flight GPU work refers to them. Compatible interfaces can reuse
textures/buffers; changed layouts need packing, migration, or reconstruction.
The runtime/development service implements watching and replacement. Applications
supply data migrations and resource reconciliation where their protocols need them.

## Distribution and hosting

Stateless service channels can dispatch independent messages across threads or
machines without moving a persistent Scheme object. Runtime bindings select
routes and compatible code. Explicit resource requirements still constrain placement:
a path may require a shared filesystem; a GPU handle belongs to a provider/device.

Stateful services carry the necessary consistency and ownership mechanisms.
A replicated store or a native owner that can move between nodes needs the
corresponding replication, fencing, and recovery rules. Stateless compute does not
make reads and writes atomic or remove storage contention. A timed-out request may
have committed; retry and deduplication are protocol choices.

Bound queue capacity and specify failures at each transport boundary. Local and
remote channels use the same value codec while allowing different declared
latency, ordering, and persistence contracts. Location abstraction is valid only
where those contracts and resource bindings remain compatible.

Managed serverless and self-hosted deployments are hosting choices. A desktop or
browser can implement the same channel interfaces without distributed infrastructure.
A vendored library supplies targets and required service protocols; its consumer
supplies bindings, namespaces, mounts, and placement. Reusing compiled code does
not mean sharing application data. Sharing a store is an explicit binding.

## Relationship to reading and staging

[Generated libraries](generate-library.md) select readers through explicit paths.
Their outer imports serve generator code; generated runtime imports are separate.
Reading embedded Scheme emits syntax and does not run the document's behavior.

[Staged programs](staged-programs.md) can put server, browser, and typed shader
declarations in one source while emitting separate artifacts. The runtime loads
behavior artifacts and dispatches messages under their contracts. Shader type and
resource validation belong to that dialect. A shader declaration can produce
an artifact without being a callable Scheme procedure.

Actor contracts and runtime state functions can first be prototyped as ordinary
libraries. They do not need to wait for `generate-library` or generalized syntax
transformers. Those features improve authoring and compilation across targets;
they do not replace the host's execution and storage responsibilities.

## Current boundary and next experiments

The [Chibi workbook](ui.md)
uses one application shared by all tabs. Its HTTP host retains Scheme objects and
serializes reduction and HTML publication. It has no isolated invocation heaps,
message codec, native state service, browser Scheme, or actor reload protocol.

The current Snail backend links a whole-program entry point. The
[Rust embedding plan](rust-interop.md#reusable-embedding-and-targets) scopes repeated
invocation and rooted ownership. An embedding API alone does not supply isolated
heaps or satisfy mandatory channel serialization.

1. Derive the record codec and test actual encode/decode for local deliveries.
   Keep envelope and application types explicit; reject unsupported values.
2. Invoke a stateless handler with separate heaps and fresh globals. Run independent
   jobs concurrently and check encoded output ownership before teardown.
3. Introduce a native state-service binding. Test concurrent conditional updates,
   missing records, load failures, and durability only where promised.
4. Add runtime-control and supervision protocols with cancellation, completion,
   bounded queues, child ownership, and explicit retry behavior.
5. Replace a channel's artifact version while work is in flight. Reject a bad
   candidate and test storage migration and replies from the old schema.
6. Connect browser and renderer services. A real DOM event and rendered shader
   exercise the same channel boundary with different resource requirements.
7. Measure a bounded frame microprocess, including serialization and native resource
   transfer. Exercise no-GC policy failures and recovery only at valid safepoints.
8. Read/copy external binary ranges above 4 GiB with exact 64-bit encoding and
   checked lifetime/overflow, without a cross-heap pointer.
9. Derive allocation bounds for known primitives and bounded loops, including
   decode/output overhead, input preconditions, and runtime layout versions.

The [synthesis](application-model.md#boundaries-worth-testing-before-adding-more-language-forms)
orders the smallest useful experiments. Track implementation in the
[TODO issue](https://github.com/tsnl/snail-scheme/issues/11).

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
