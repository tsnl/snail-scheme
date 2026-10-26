# Draft mixed memory and continuations

**Status: proposed.** Lofi will keep one backend that emits WebAssembly
directly. Types will select GC references or owned linear-memory storage;
the compiler will lower control effects into explicit continuations. This
allows Scheme graphs to retain automatic cycle collection while eligible
Lofi tasks execute across workers using shared linear memory.

The implemented baseline is [affine one-shot work](ownership.md),
compiler-owned structural `Send` and `Sync` checks, and [local tasks](tasks.md)
scheduled through JSPI. The pointer types, ownership libraries, explicit
continuations and worker pool below are new work. Their names describe the
proposed contracts; their surface syntax is not settled.

## Scope

Ownership, continuation management and scheduling move into Lofi libraries;
Rust and JavaScript supply allocation, foreign services, startup and callbacks.
The existing frontend, Chibi bootstrap and separate compilation remain the
foundation. This uses one Wasm emitter, without Emscripten. The earlier
[backend research](future.md) retains the LLVM and C alternatives.

## Reference types and storage

`Gc<T>` and `Ptr<T>` are the two primitive reference representations.
`Gc<T>` lowers to an opaque WasmGC reference; `Ptr<T>` lowers to an address
in linear memory. They require different allocation and access
instructions. An allocator cannot interchange them behind a common raw
pointer interface, and a cast cannot turn one into the other.

Ownership libraries build safe owners over `Ptr<T>`:

| Type | Ownership and reclamation | Worker capability |
| --- | --- | --- |
| `Gc<T>` | Reusable traced reference; the engine reclaims unreachable graphs. | Neither `Send` nor `Sync`, even when `T` is immutable. |
| `Ptr<T>` | Raw address; copying it transfers no ownership. Access and deallocation require an unsafe contract. | Neither marker is derived automatically. |
| `Box<T>` | Affine owner; destruction drops the payload and frees its allocation. | `Send` when `T: Send` and the allocation supports transfer. |
| `Arc<T>` | Reusable shared owner; the last strong release destroys the payload. | `Send + Sync` when `T: Send + Sync`. |
| `Weak<T>` | Reusable weak reference; upgrade may fail after payload destruction. | `Send + Sync` under the same payload bounds as `Arc<T>`. |

These rules assume the linear allocation lives in the workers' shared
memory and its allocator permits allocation and deallocation on different
workers. Arc counters protect ownership, while payload access needs its
own synchronization. Weak references keep the control allocation alive
without keeping its payload alive, following the familiar
[Arc and Weak contract](https://doc.rust-lang.org/std/sync/struct.Arc.html).

Storage, grade and transferability are independent properties. An affine
continuation may retain local GC values. A reusable owner may use linear
memory. A raw pointer's numeric representation proves neither a valid
lifetime nor safe access from another worker. The compiler carries each
property separately through specialization and lowering.

The compiler must also establish whether a payload is representable in
the chosen storage. `T: Send` alone is not a layout proof. In particular,
an ordinary GC reference cannot occupy bytes in a linear record. The first
implementation preserves existing data layouts unless an explicit owner
or reference type selects a new representation. Existing implicit GC
strings, vectors and closures must not retain transfer evidence merely
because their contents are immutable.
Today's checks inspect types and captures; they do not prove that the emitted
WasmGC representation can cross workers. The proposed checks must establish
that additional representation evidence.

### Ownership and destruction

Extend the existing affine ownership pass. A move transfers an owner; a
last-use drop destroys it. For shared owners, repeated use may
require retaining a reference, while a final use may move it. Neither
operation is an untracked byte copy. Grade-polymorphic containers are
needed so queues and aggregates can own affine values.

The compiler generates destruction of fields and deallocation of their
owners. A proposed `Drop` typeclass supplies custom resource cleanup; its
interaction with generated field destruction and moves must be specified
before implementation. Initial custom destructors complete without
suspending or throwing. `Drop` does not imply duplicability.

Affine resource cleanup also applies when the wrapper itself is GC
allocated: the compiler performs the resource action at the ownership
boundary and the engine later reclaims the wrapper. A reusable GC alias
cannot independently perform that same destruction.

### Crossing between heaps

WasmGC and shared linear memory coexist, but they do not form one traced
ownership graph. The [GC representation](https://github.com/WebAssembly/gc/blob/main/proposals/gc/MVP.md)
keeps references separate from numeric addresses. Apply these initial
boundary rules:

- Linear records cannot directly store GC references. A local rooted
  handle table may provide an explicit bridge, with a defined owner and
  release operation. A handle stays local to its worker; copying its
  integer ID elsewhere does not transfer its referent.
- Safe reusable GC payloads cannot silently own a `Box`, Arc count or
  other resource requiring deterministic release. Collecting a numeric
  pointer field does not invoke `Drop`. Such ownership needs an explicit
  lifetime protocol before it is admitted.
- Arbitrary Scheme cycles stay entirely in GC storage. Strong Arc cycles
  still require weak edges. Cycles involving both rooted GC handles and
  linear owners are outside the initial safe ownership model.

Copying or converting a graph across representations is an explicit
operation with specified identity, sharing and resource behavior. There
is no implicit copy at a `Send` boundary. Unsafe foreign code remains
responsible for keeping borrowed addresses valid.

## Workers and transferable tasks

Each worker instantiates compatible code against the shared linear memory
and retains its own ordinary GC references, globals and local resources.
A task can allocate and use GC values after starting on a worker. It stays
on that worker whenever a live continuation contains non-transferable
state. A later suspension may become transferable if its complete captured
state permits it.

`Send` checks include closure captures, continuation frames, handler
installations, dynamic bindings, wind callbacks and foreign registrations.
The compiled code must also have no hidden access to an unshared global
that assumes another worker's identity. A procedure's argument and result
types alone do not establish this property.

A transferable closure uses a stable code identifier and an environment
in shared linear memory. Each worker resolves the identifier through its
own compatible code table. Wasm function references and instance-local
table entries are not shared by putting their numeric indices in a queue.
Module initialization establishes the mapping, separate worker stacks and
thread-local state before the worker accepts tasks. Reload drains all old
tasks before replacing a code generation; a queued identifier cannot be
interpreted using a different generation's code. Draining tasks alone does
not account for saved reusable continuations. Initially reject them in a
reload handover; supporting that handover later requires retaining or
explicitly migrating their code and captured state.

The Lofi scheduler owns queues of affine thunks. A task start and a bound
continuation invocation use the same work representation. Invoking a
reusable continuation creates one affine work item while retaining the
continuation for another invocation. Suspended work is owned by its
pending operation and is absent from ready queues. Local queues retain
pinned work; the shared queues accept only transferable work.

Start with synchronized queues and explicit ownership. Browser execution runs
bounded batches and returns to the event loop; the main thread does not wait for a
worker or an I/O completion.

The pool uses shared linear memory; sharing GC references through
[Shared-Everything Threads](https://github.com/WebAssembly/shared-everything-threads/blob/main/proposals/shared-everything-threads/Overview.md)
is not a prerequisite.

## Explicit continuations

Use selective control lowering inspired by Koka's
[generalized evidence passing and yield bubbling](https://www.microsoft.com/en-us/research/wp-content/uploads/2021/08/genev-icfp21.pdf).
Code proven not to capture control uses ordinary calls. On a yielding
path, relevant callers package their remaining computation and live values
until the matching handler receives an explicit continuation. Resumption
executes those frames with the correct dynamic context. The transformation
targets the existing Wasm emitter and retains proper tail calls.

Both continuation grades belong in the first control representation:

- An affine continuation owns its captures. Resumption consumes it;
  abandonment releases owned resources. Resumed code may suspend again,
  producing a new continuation.
- A reusable continuation preserves captured control state across
  invocations. Immutable frames can be shared; each invocation gets any
  mutable activation bookkeeping it needs. Ordinary captured mutable
  locations remain shared, rather than being restored from a snapshot.

Multi-shot control cannot silently duplicate a live affine resource.
Checking must cover caller frames across potentially capturing calls,
including calls through effect-polymorphic functions. Require reusable
captures for such control, or an explicit resource protocol that makes
the required sharing valid. GC allocation does not waive this ownership
rule.

The frame representation follows its captures. GC-backed continuations
serve unrestricted local Scheme control. Transferable continuations use
linear frames and compatible code identifiers. Affine local frames may
use GC storage while still having explicit resource cleanup. Multiplicity
does not select the heap by itself.

### Scheme control and dynamic wind

The Scheme layer needs abortive `call/cc` with reusable continuations of
unlimited extent, multiple values, dynamic parameters and exception
handlers. Invoking an escape continuation replaces the current
continuation. A root delimiter must model the Scheme execution context;
delimiting every ordinary function or temporary browser callback would
truncate it. Other Scheme conformance work remains in the
[language issue](https://github.com/tsnl/snail-scheme/issues/456). See [R7RS sections 6.10 and 6.11](https://standards.scheme.org/official/r7rs.pdf).

Represent `dynamic-wind` scopes as persistent nodes with identity, parent,
entry and exit thunks, and their surrounding dynamic context. A
continuation retains the applicable chain. For a control transfer, find
the common ancestor, exit current scopes from inside outward, then enter
destination scopes from outside inward:

```text
Current: root -> A -> B -> C
Target:  root -> A -> D
Actions: C.after -> B.after -> D.before -> resume target
```

Remove a scope before calling its exit thunk; install it after its entry
thunk returns. Preserve the body's returned values across normal exit.
The transition machinery must participate in control lowering when a
hook performs an effect. The standard library implementation in
[The Scheme Programming Language](https://www.scheme.com/tspl4/control.html#./control:h6)
illustrates the chain and ordering.

Compiler-generated returns used to package a suspension do not themselves
leave a language scope. Ordinary I/O waiting preserves the task's dynamic
context. Actual continuation transfers run the corresponding wind
transitions. Capturing a continuation and collecting an already inactive
continuation do not independently trigger wind hooks. Final resource
destruction and dynamic scope exit remain separate operations.

### Cancellation and foreign callbacks

A pending operation owns its one-shot continuation. Completion and
cancellation race to settle that operation once; only the winner may
enqueue its work or initiate cancellation cleanup. Abandoning a task
disarms its registration or retains the registration's storage until late
callbacks can no longer access it. An empty ready queue is not runtime
exhaustion while waits or cleanup remain live.

Cancellation follows an explicit task cleanup path. It does not rely on
GC reachability or a native Rust/JavaScript exception to walk language
frames. Reusable Scheme continuations require a distinct lifetime policy:
discarding one reference does not cancel every retained invocation or
destroy resources still reachable through another reference.

Foreign callbacks return normally. They copy transient inputs or transfer
an explicitly owned buffer, settle a registration and enqueue Lofi work.
They do not capture a foreign stack as part of a continuation. Browser
operations that need an immediate response, such as event suppression,
keep that decision in the synchronous adapter.

## Compiler and runtime responsibilities

Preserve representation, grade, capture multiplicity, effects and
capability evidence until the passes that consume them have completed.
`mono.sld` currently erases effect rows; continuation lowering requires
retaining the relevant evidence through specialization. Generic functions
must specialize or adapt consistently to the control ABI they receive.

Check source ownership and effect restrictions first, lower continuations,
then establish ownership and insert retain/drop operations for generated
frames as well as source values. Persist ABI-relevant evidence in library
interfaces and cache keys so separately compiled callers agree about
representations and suspension behavior. Chibi must continue to run the
same compiler sources, with compiler-used primitives supplied by its host.

| Component | Proposed responsibility |
| --- | --- |
| Lofi compiler | Reference representations, layouts, unsafe memory and atomic primitives, control lowering, ownership glue and foreign ABI checks. |
| Lofi libraries | Box/Arc/Weak, collections, continuations, handler contexts, dynamic wind, queues, synchronization and task lifecycle policy. |
| Rust services | Allocation and operations obtained from foreign libraries or the host; preserve existing behavior while portable algorithms migrate to Lofi. |
| JavaScript host | Module and worker startup, browser/Node API calls, DOM and WebGPU integration, and completion delivery. |

Use an explicit foreign mechanism, including `extern "C"` for Rust and
other Wasm libraries with a compatible ABI. Declare pointer width,
alignment, ownership and callback lifetime at the boundary. Rust's private
`Vec` and Arc layouts are not the Lofi ABI. Atomics can lower directly to
Wasm instructions.

Move portable policy into Lofi incrementally, preserving bootstrap-visible
behavior. The new representation need not wait for every scalar service to move.

## Validation boundary

[The implementation issue](https://github.com/tsnl/snail-scheme/issues/460) tracks
representation, ownership, control lowering, scheduler and worker proofs. Each
backend step must execute emitted Wasm on both linked and whole-program paths;
keep Chibi/bootstrap behavior and real browser reload tests. The existing JSPI
implementation remains until its replacement demonstrates those contracts.

A local feasibility probe on 2026-10-24 combined ordinary GC structs with
shared memory64 in the same module. Four workers each performed 100,000
atomic increments while maintaining local GC state; Node 24.19 and
Chromium 152 both produced 400,000 without experimental Wasm flags. This
establishes coexistence on those engines, not the allocator, continuation
or scheduler invariants above. Convert that probe into a reproducible
backend fixture when shared execution is implemented.

## Decisions to specify before implementation

- Surface syntax for reference allocation, unsafe operations and borrowed
  access; whether existing container names gain explicit storage variants.
- The `Drop` contract, field destruction order and the initial safe set of
  GC payloads and lifetime bridges.
- How control multiplicity appears in effect signatures and how Scheme
  callbacks cross typed code that has live affine owners.
- The representation of task-local dynamic contexts and which local
  handler forms the Scheme layer needs alongside existing transferable
  ordinary Lofi handlers. Representation-aware checks will reject some GC
  captures accepted today; specify how those handler environments migrate.
- Address width and the foreign ABI for the first delivery. Mixed heaps
  do not require memory64. The current Rust runtime targets
  `wasm32-wasip1`; moving it to Rust's Tier 3
  [`wasm64-unknown-unknown`](https://doc.rust-lang.org/rustc/platform-support/wasm64-unknown-unknown.html)
  also requires building the standard library and adapting platform I/O.
