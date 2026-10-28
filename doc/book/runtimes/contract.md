# Tasks, ownership and runtimes

This is the language contract for tasks and effects. The [runtime overview](index.md)
distinguishes its implemented subset from future requirements. There is one shipping target: WebAssembly GC with JSPI, on one
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

Grades belong to types. A **linear** value is used exactly once on every
path that returns; grade `omega` permits repeated use and discarding.
Moving a linear value transfers its ownership. The alternatives of a
branch must consume the same linear values, and two uses along one
execution path may not. Capturing it moves it into the closure, and
requires a one-shot closure. Records containing a linear field are linear.
This is an ownership check, not a borrow checker.

An owned value's lifetime ends where it is consumed: by a call, by an
explicit `drop`, or by a match that moves its fields out. Moving into a
task keeps it alive in that task. Deterministic
resource cleanup is separate from tracing the managed storage: abandoning a
pending one-shot continuation must disarm its operation and initiate cancellation,
not merely release the allocation holding its captures. Unrestricted
aliases cannot each independently destroy a shared resource at last use.
Dropping one reference to a future reusable continuation does not cancel
other retained invocations.

Each instance of a program runs on one thread, and no value it holds is
reachable from another thread. So the language has no thread-safety
markers, and a handler or a task may capture mutable state. Instances
will talk to each other only through queues, which copy bytes, and through
shared memory holding plain data; that design is proposed in [#553](https://github.com/tsnl/snail-scheme/issues/553).
Foreign code and host capabilities are explicit trusted boundaries.

## Effects and handlers

An effect row states which operations code can perform. The runtime binds
platform effects; applications may bind ordinary handlers for abstractions
and tests. Possessing an effect label alone does not confer authority to a
platform resource.

Every ordinary handler implementation must be grade `omega`, because a
deep handler runs it again for each operation. Ordinary closures always
are: they cannot capture a one-shot value. A handler may capture mutable
state. Its individual invocations may also own linear arguments and
allocate local mutable storage.

A handler implementation is distinct from an **installation** of that
handler. Installations and their outer bindings belong to a computation.
Suspending and resuming a computation preserves those bindings. Reusing
handler code does not duplicate a control delimiter or permit two resumes
of one linear continuation. Newly dispatched tasks inherit the current ordinary
bindings. Each task owns its binding vector; the reusable implementations
may be shared. This preserves the dispatched closure's declared effects.
It does not establish rules for cloning future control delimiters.

Runtime event waits are control operations: the runtime retains a one-shot
resumption and later makes it ready with a result or cancellation. JSPI
implements this restricted control boundary today. User-defined `ctl`
operations compile instead to evidence passing, with a one-shot,
first-class `resume` (see
[control handlers](../snail-core/effects.md#control-handlers)), and never
reach the host. Ordinary handlers remain tail-resumptive: their result
returns once to the operation caller.

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
useful during browser hot reload. They are an application protocol on top of tasks,
not the definition of a task. Reload waits for the old computation to
settle before relinking its modules.

The [typed state proposal](../snail-core/state.md) would replace application handover
with durable records and disposable views; that API remains under review.
