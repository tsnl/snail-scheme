# Tasks, ownership and runtimes

This is the language contract for the runtime rewrite. The book's
[runtime chapter](https://tsnl.github.io/snail-scheme/runtimes/index.html) distinguishes the implemented
subset from this contract. It supersedes the actor hierarchy proposed in
PR #412. There is one shipping target: WebAssembly GC with JSPI, on one
JavaScript execution agent. A second backend is future research.

## Computations

A **task** is a single execution of a zero-argument closure. A **runtime**
owns tasks and the platform operations they await. Dispatch transfers a
closure into a task; it does not create an actor instance, mailbox or
request/reply protocol. A task finishes by returning or failing. There is
no terminate effect and no supervisor hierarchy.

Tasks may overlap in lifetime. The language permits a runtime to execute
eligible tasks on different threads. The current implementation interleaves
them cooperatively: a task runs until it returns, fails, explicitly yields,
or awaits a runtime operation. A CPU loop that never yields monopolizes
the execution agent. Suspension is not CPU parallelism.

A runtime is exhausted only when all its tasks have settled. A suspended
task, an outstanding event registration and cancellation cleanup remain
live work. An empty ready queue is not exhaustion. Spawning reserves work
before returning to the caller, so a parent can finish immediately after
dispatch without letting the runtime exit early.

## Grades and transfer

Grades belong to types. Grade `1` means **at most once**, not exactly once;
grade `omega` permits repeated use. Moving an affine value transfers its
ownership. Alternatives in a branch may each consume it; two uses along
one execution path may not. Capturing it moves it into the closure, and
requires a one-shot closure. Records containing an affine field are affine.
This is an ownership check, not a borrow checker.

An owned value's lifetime ends at its last use, not the enclosing lexical
scope. Moving into a task keeps it alive in that task. Deterministic
resource cleanup is separate from tracing the managed storage: dropping a
continuation must disarm its pending operation and initiate cancellation,
not merely release the allocation holding its captures. Unrestricted
aliases cannot each independently destroy a shared resource at last use.

`Send` means ownership may cross a thread boundary. `Sync` means shared
access is safe across threads. Neither means serializable. The compiler
establishes these properties from representations and captures; users
cannot assert them with an empty marker instance. Mutable aliased `Ref`
and `Array`, opaque `Any`, and unclassified foreign references do not gain
these properties just because this implementation uses one thread.

Local dispatch may retain values that are not `Send`. A task eligible for
any worker must be `Send`. A reusable closure's signature alone does not
prove anything about its environment. Foreign code and host capabilities
are explicit trusted boundaries, with thread confinement recorded there.

## Effects and handlers

An effect row states which operations code can perform. The runtime binds
platform effects; applications may bind ordinary handlers for abstractions
and tests. Possessing an effect label alone does not confer authority to a
platform resource.

Every ordinary handler implementation, including its captured environment,
must be `Send + Sync` and grade `omega`. Its individual invocations may own
affine arguments and allocate local mutable storage. An operation that
needs a local resource takes that resource as an argument rather than
hiding it in a shared handler. Host implementations may use synchronized
capability proxies or execution-agent confinement.

A handler implementation is distinct from an **installation** of that
handler. Installations and their outer bindings belong to a computation.
Suspending and resuming a computation preserves those bindings. Reusing
handler code does not duplicate a control delimiter or permit two resumes
of one continuation. Newly dispatched tasks inherit the current ordinary
bindings. Each task owns its binding vector; the reusable implementations
may be shared. This preserves the dispatched closure's declared effects.
It does not establish rules for cloning future control delimiters.

Runtime event waits are control operations: the runtime retains a one-shot
resumption and later makes it ready with a result or cancellation. JSPI
implements this restricted control boundary today. User-defined `ctl`
handlers and first-class continuations are deferred. Ordinary handlers
remain tail-resumptive: their result returns once to the operation caller.

## Events and application state

The runtime turns platform callbacks into completed waits. It may buffer
input while application code is suspended, and coalesce redundant motion,
resize and frame notifications. A frame wait can return the input received
since the previous frame. Each input is consumed once by its owning loop.
The runtime does not infer a shared current application state.

An application owns its state as loop arguments. For example, in schematic
syntax:

```text
animate(window, world):
    frame = next_frame(window)
    next = update(world, frame.inputs, frame.dt)
    render(window, next)
    animate(window, next)
```

The existing application's checkpoint and save/restore handover remain
useful during live reload. They are an application protocol on top of tasks,
not the definition of a task. Reload waits for the old computation to
settle before relinking its modules.

## Implementation sequence

1. Delete the actor library, protocol checks, transports and actor-only
   sharing primitives, retaining the application's JSPI entry boundary.
2. Record this contract and the backend research without claiming it is
   all implemented.
3. Establish compiler-owned transfer proofs and reusable handler capture
   checks in the existing typed core.
4. Add affine one-shot thunks and check ownership before Wasm emission,
   including branches, captures and the boundaries that erase types.
5. Implement the JSPI task scheduler, preserving handler bindings at every
   suspension and resumption. Test cancellation and exhaustion independently.
6. Expose task operations to Lofi and exercise linked and whole-program
   Wasm, then use the same machinery for application lifecycles. Update the
   book and validate reload in a browser.

Each step must work on its own. Backpressure, network protocols, region
allocation, borrowed captures and user-defined control handlers are not
part of this series.
