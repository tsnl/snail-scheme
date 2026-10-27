# Scheduling and suspension

`host/browser/tasks.mjs` implements the scheduler shared by runtime adapters.
The [Snail-Core task API](tasks.md) and application event and storage waits use
it in the CLI and browser. It uses one JavaScript execution agent and shipping
JSPI; it does not create workers.

A live task is either queued, executing or suspended. The runtime keeps a
set of these tasks. Dispatch inserts a child before returning to its
parent. Returning or trapping removes only the completed task; independently
dispatched work remains live. `drain()` resolves when the set is empty.
Work dispatched after exhaustion begins another interval of activity.

The ready queue contains starts and resumptions. An execution permit
allows only one of them to run at a time.
Short tasks normally advance through microtasks; a bounded number of
steps yields an event-loop turn so input is not starved. A CPU loop that
does not suspend still monopolizes this execution agent.

## Handler bindings

Ordinary handlers are reusable and satisfy `Send + Sync`. Handlers are
evidence: every function takes the list of handlers in scope as a
parameter, so a task's handlers live on its own Wasm stack. Dispatch
hands the host the evidence in scope at `dispatch-local` along with the
work, and the host passes it back when the work runs, so a child keeps
using its parent's handlers after the parent returns. Root entries start
with the empty list, where every operation reaches its runtime default.

Because nothing about handlers is global, a JSPI wait saves and restores
nothing: the runtime releases the permit, and I/O completion only makes a
resumption ready. The scheduler later resolves or rejects its wait
Promise. It keeps the permit until the resumed Wasm suspends again or
settles; resolving the Promise alone does not establish that Wasm has run
yet. One scheduler owns each program; runtime authors must route
suspending imports through its suspension bridge.

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

`suspend(operation, discard)` can take a synchronous native disposer for a
successful result. The suspension owns that result until the scheduler accepts
delivery. If cancellation wins while the result is queued, or a non-abortable
operation succeeds after cancellation, the runtime disposes the result exactly
once and rejects the parked invocation. It does not dispose delivered results or
operation failures. A disposer failure also rejects the parked invocation, so
Wasm still unwinds before task completion.

The disposer must not suspend or reenter Snail-Core. If it starts OS resource closure,
the native owner awaits that remaining cleanup during shutdown.
Work must return its complete invocation Promise, and
suspending imports must return or await their gate; abandoning either loses the
relationship between task completion and its parked stack.

This makes cleanup part of the suspended task's lifetime, without a
second cleanup counter. A host adapter that never settles can prevent
exhaustion. Runtime authors must uphold this boundary; a pending Promise
is not cancellation machinery by itself.

Closing a runtime rejects new work, cancels its live tasks and waits for
them to settle. A task failure does not cancel siblings. A Node host must
also hold a process-lifetime token until drain: unresolved Promises alone
do not keep Node alive.
