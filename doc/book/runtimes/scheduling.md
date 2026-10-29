# Driving the scheduler

The scheduler is written in Snail-Core ([task operations](tasks.md)); a
host only drives it and completes the operations its tasks wait on.
`host/browser/tasks.mjs` is the driver Node and the browser share, and
`drive` in `crates/snail/src/program.rs` is wasmtime's. Each runs on one
execution agent and creates no workers.

## Turns

`drive` calls `tasks:turn` with the host's clock and rests as the answer
says, until no task is live:

| Answer | The host rests |
| --- | --- |
| 0, a task is ready | until the next turn of the event loop, so the host's own events run between turns: `setImmediate` in Node, a message in a browser, whose zero timeouts are clamped |
| a positive number of milliseconds | until that deadline, or until a completion wakes a ticket |
| -2, every task waits on a ticket | until a completion wakes one; with no operation outstanding, nothing will, and the run fails |
| -1, no task is live | not at all: `drive` returns |

A trap unwinds out of `turn`. The scheduler took the trapped task off its
queue before running it, so the driver reports the trap with the id
`tasks:running` gives, and turns again. `drive` takes a `stopped` test,
asked after each turn: the application runtime stops at the loop's answer
and only then decides whether its children may go on. `interrupt` ends a
rest early, so that `stopped` is asked again. A CPU loop that does not
wait still monopolizes the execution agent; the scheduler does not
preempt it.

## Host operations

An operation that completes later is started through a synchronous import
with the ticket its task took, and finished through another
([waiting on the host](tasks.md#waiting-on-the-host)). The driver's
`start(ticket, operation, deliver, dispose)` runs the operation with the
run's `AbortSignal` and counts it outstanding until it settles. Settling
wakes the ticket and keeps the outcome under it until the task's finish
calls `finish(ticket)`, which runs `deliver` on a success, building the
managed result through the library's exposed helpers, or throws a failure
into the finish, where it traps the task. `coded` turns a native failure
with an error code, such as `ECONNRESET`, into the operation's `Err`
value, and leaves a cancellation or an uncoded failure a failure.

A success whose ticket wakes nothing, because its task trapped or its run
closed, is disposed of exactly once, through the operation's synchronous
`dispose`: an accepted connection is closed. Delivered results and
failures are not disposed of.

## Closing a run

`close` aborts the run's signal, drops every task through `tasks:close`,
and disposes of each outcome still held. An operation that cannot abort
may finish normally afterwards; its ticket then wakes nothing, and its
outcome is disposed of. Its external effects are not rolled back.

An adapter receives the `AbortSignal` and returns one Promise covering
both its operation and its owned cleanup. It must handle an already
aborted signal, remove listeners on normal completion, and settle only
after owned cleanup finishes. Timers and event waits can disarm promptly.
A disposer must not suspend or reenter Snail-Core; if it starts OS
resource closure, the native owner awaits that remaining cleanup during
shutdown. An adapter that never settles keeps its run from ending.

A task failure does not close its siblings' run. A Node host holds a
process-lifetime token until `drive` returns, since a task waiting on a
timer or a ticket is live work that no OS handle keeps Node alive for.
