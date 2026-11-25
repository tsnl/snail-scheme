# Tasks, values and runtimes

This is the language contract for tasks and capabilities. The [runtime overview](index.md)
distinguishes its implemented subset from future requirements. Programs run as
WebAssembly with linear memory on one execution agent.

## Computations

A **task** is a single execution of a zero-argument closure. A **runtime**
holds tasks and the platform operations they await. Dispatch turns a
closure into a task; it does not create an actor instance, mailbox or
request/reply protocol. A task finishes by returning or failing. There is
no terminate operation and no supervisor hierarchy.

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

Ordinary values may be shared ([values](../snail-scheme/values.md)). Capturing a
value in a closure, or dispatching that closure as a task, keeps the value
reachable from there, and the instance's collector reclaims it once nothing
reaches it. A resource outside the managed heap has an explicit close
operation; nothing closes it when its last reference goes. A suspended
computation whose resumption is never called runs nothing more.

Each instance of a program runs on one thread, and no value it holds is
reachable from another thread. So the language has no thread-safety
markers, and a capability or a task may capture mutable state. Instances
will talk to each other only through queues, which copy bytes, and through
shared memory holding plain data; that design is proposed in [#553](https://github.com/tsnl/snail-scheme/issues/553).
Foreign code and host capabilities are explicit trusted boundaries.

## Capabilities and suspension

What code may do to a platform is in the capabilities it holds: values the
runtime's target hands the program's `main`, which passes them on
([capabilities](../snail-scheme/capabilities.md#capabilities)). An application
makes its own for abstractions and tests. Holding no capability, code can
reach no platform resource.

A capability is an ordinary value, usually a record of closures, each of
which may be called repeatedly, may capture mutable state, and may allocate
local mutable storage. A task keeps the capabilities it closed over across
its waits, and a newly dispatched task has those its closure captured.

Waits are suspensions to the task library's prompt: the scheduler retains
a one-shot resumption and later makes it ready, when a timer passes or the
host wakes its ticket. Like every suspension they compile to ordinary calls
and saved frames, with a one-shot, first-class `resume` (see
[suspension](../snail-scheme/suspension.md)), and never reach the host,
which only drives the scheduler ([task operations](tasks.md)). A second
resume of one continuation panics.

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

A page's save keeps its state across a page reload. It is an application
protocol on top of tasks, not the definition of a task.

The [typed state proposal](../snail-scheme/state.md) would replace application saves
with durable records and disposable views; that API remains under review.
