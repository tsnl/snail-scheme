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

Ordinary handlers are reusable. Handlers are evidence: every function takes the list of handlers in scope as a
parameter, so a task's handlers live on its own Wasm stack. Dispatch
hands the host the evidence in scope at `dispatch-local` along with the
work, and the host passes it back when the work runs, so a child keeps
using its parent's handlers after the parent returns. Root entries start
with the empty list, where every operation reaches its runtime default.

Because nothing about handlers is global, a JSPI wait saves and restores
nothing: the runtime releases the permit, and a wake only makes a
resumption ready. The scheduler later resolves or rejects its wait
Promise. It keeps the permit until the resumed Wasm suspends again or
settles; resolving the Promise alone does not establish that Wasm has run
yet. Three imports suspend: `yield`, `sleep` and a ticket's `await`. A
host operation does not suspend at all; it starts, and its task awaits a
ticket that its completion wakes ([waiting on the host](tasks.md#waiting-on-the-host)).

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

A host operation's successful result is owned by the completion table
(`host/browser/completions.mjs`) until its task finishes the ticket. If the
ticket wakes nothing, because its task was cancelled or has gone, or the
task is cancelled between the wake and the finish, the table disposes of
the result exactly once, through the operation's synchronous native
disposer: an accepted connection is closed. It does not dispose delivered
results or operation failures.

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
