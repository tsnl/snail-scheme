# Scheduling and suspension

`src/app/tasks.mjs` implements the scheduler shared by runtime adapters.
The Lofi task API and application integration are the next layers of the
rewrite. This scheduler uses one JavaScript execution agent and shipping
JSPI; it does not create workers.

A live task is either queued, executing or suspended. The runtime keeps a
set of these tasks. Dispatch inserts a child before returning to its
parent. Returning or trapping removes only the completed task; independently
dispatched work remains live. `drain()` resolves when the set is empty.
Work dispatched after exhaustion begins another interval of activity.

The ready queue contains starts and resumptions. An execution permit
allows only one of them to use a program's dynamic handler globals.
Short tasks normally advance through microtasks; a bounded number of
steps yields an event-loop turn so input is not starved. A CPU loop that
does not suspend still monopolizes this execution agent.

## Handler bindings

Ordinary handlers are reusable and satisfy `Send + Sync`. Dispatch copies
the current binding vector and gives it to the child. The implementations
may be shared, but the vector belongs to that task. This is why a child
can keep using a handler after its parent returns. Root entries start
with runtime defaults.

Wasm handler globals act as the executing task's registers. At a JSPI
wait, the runtime saves them, restores the defaults and releases the
permit. I/O completion only makes a resumption ready. The scheduler later
installs that task's bindings and resolves or rejects its wait Promise.
It keeps the permit until the resumed Wasm suspends again or settles;
resolving the Promise alone does not establish that Wasm has run yet.

One scheduler owns each program and all its handler globals. Runtime
authors must route suspending imports through its suspension bridge.
Dynamically loaded modules must appear in the handler-global enumeration
too. Their compiler-generated handler globals initially contain null.

## Cancellation and adapters

`cancel()` requests cancellation; `done` marks completion. Queued work
that has never entered Wasm can be discarded immediately. A suspended
invocation must resume with rejection and unwind before it leaves the
live set. Cancellation is sticky, including when a successful I/O result
has already queued a resumption.

An adapter receives an `AbortSignal` and returns one Promise covering both
its operation and cleanup. It must handle an already aborted signal,
remove listeners on normal completion, and settle only after owned
cleanup finishes. Timers and event waits can disarm promptly. An operation
that cannot abort may finish normally; the runtime then rejects its
resumption because cancellation was requested. Its external effects are
not rolled back.

This makes cleanup part of the suspended task's lifetime, without a
second cleanup counter. A host adapter that never settles can prevent
exhaustion. Runtime authors must uphold this boundary; a pending Promise
is not cancellation machinery by itself.

Closing a runtime rejects new work, cancels its live tasks and waits for
them to settle. A task failure does not cancel siblings. A Node host must
also hold a process-lifetime token until drain: unresolved Promises alone
do not keep Node alive.
