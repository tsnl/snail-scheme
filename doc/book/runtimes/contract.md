# Tasks, values and runtimes

This is the language contract for tasks and effects. The [runtime overview](index.md)
distinguishes its implemented subset from future requirements. There is one shipping target: WebAssembly GC, on one
execution agent. A second backend is future research.

## Computations

A **task** is a single execution of a zero-argument closure. A **runtime**
holds tasks and the platform operations they await. Dispatch turns a
closure into a task; it does not create an actor instance, mailbox or
request/reply protocol. A task finishes by returning or failing. There is
no terminate effect and no supervisor hierarchy.

Tasks may overlap in lifetime. The language permits a runtime to execute
eligible tasks on different threads. The current implementation interleaves
them cooperatively: a task runs until it returns, fails, explicitly yields,
or awaits a runtime operation. A CPU loop that never yields monopolizes
the execution agent. Waiting is not CPU parallelism.

A runtime is exhausted only when all its tasks have settled. A waiting
task and an outstanding host operation remain live work. Nothing cancels a
task; tasks that should stop early arrange it between themselves. An empty ready queue is not exhaustion. Dispatch counts the new task
live before returning to the caller, so a parent can finish immediately
after dispatch without letting the runtime exit early.

## Values in tasks

Every value may be shared ([values](../snail-core/values.md)). Capturing a
value in a closure, or dispatching that closure as a task, keeps the value
reachable from there, and the engine's collector reclaims it once nothing
reaches it. A resource outside the managed heap has an explicit close
operation; nothing closes it when its last reference goes. A suspended
computation whose resumption is never called runs nothing more.

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

A deep handler runs its ordinary implementations again for each
operation, so each is an ordinary closure that may be called repeatedly.
A handler may capture mutable state, and its individual invocations may
allocate local mutable storage.

A handler implementation is distinct from an **installation** of that
handler. Installations and their outer bindings belong to a computation.
Suspending and resuming a computation preserves those bindings. Reusing
handler code does not duplicate a control delimiter or permit two resumes
of one continuation: a second resume panics. Newly dispatched tasks inherit
the current ordinary bindings. Each task has its own binding vector; the
reusable implementations may be shared. This preserves the dispatched closure's declared effects.
It does not establish rules for cloning future control delimiters.

Waits are control operations of `tasks`: the scheduler retains a one-shot
resumption and later makes it ready, when a timer passes or the host
wakes its ticket. Like every `ctl` operation they compile to evidence
passing, with a one-shot, first-class `resume` (see
[control handlers](../snail-core/effects.md#control-handlers)), and never
reach the host, which only drives the scheduler
([task operations](tasks.md)). Ordinary handlers remain tail-resumptive:
their result returns once to the operation caller.

## Events and application state

The runtime turns platform callbacks into completed waits. It may buffer
input while application code waits, and coalesce redundant motion,
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
