# Task operations

`(snail shell task)` defines the `tasks` effect and the scheduler that
handles it, both in Snail Scheme:

| Operation | Meaning |
| --- | --- |
| `(dispatch work)` | Run a thunk as an independent local task. |
| `(yield)` | Let every other ready task run first. |
| `(sleep milliseconds)` | Wait for an `I64` number of milliseconds. |
| `(ticket)` | A fresh `I64` ticket, naming one wait. |
| `(await ticket)` | Wait until the ticket is woken. |
| `(tasks-wake! scheduler ticket)` | Ready a task waiting on that ticket; a stale ticket does nothing. |
| `(tasks-close! scheduler)` | Forget every queued, sleeping and waiting task; none runs again. |
| `(through-host start finish)` | Wait on a host operation by ticket ([below](#waiting-on-the-host)). |
| `(make-mailbox)` | A new, empty `(Mailbox T)`: a queue of messages between tasks. |
| `(mailbox-post mailbox message)` | Add a message at the back. Posting never waits. |
| `(mailbox-receive mailbox)` | Take the message at the front, waiting until one is posted. |
| `(mailbox-try-receive mailbox)` | Take the message at the front, or answer `None` at once when there is none. |

```scheme
(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (snail shell task))

(define (main) (→ Unit) (! mut host tasks output-port)
  (dispatch
   (lambda ()
     (yield)
     (write-line "the child finishes after main returns"))))
```

The host creates one explicit `Scheduler` for a program and passes it to
`start-main`, turns, wakes and closure. The root `main` runs as its first
task and may yield, sleep or await like any other task. A child starts when
the parent yields or returns. Every task runs until it finishes: nothing
cancels one. Tasks that should stop early agree on it between themselves,
for example through a mailbox or a flag in a record they share. A trap
fails the run. The host reports it and closes the
scheduler, which forgets its queued work; Wasm traps do not unwind, so
nothing more runs in the trapping frame.
Whole-program and separately linked builds use this same explicit scheduler.
Libraries have no runtime initializers or implicit scheduler globals.

The operations are not actors: there are no request/reply protocols or
supervisors. A task's id names it to the host, which reports a trap under
it, and to an application, whose loop is a task ([applications](../snail-core/applications.md#task-lifetime)).

## How a task runs

A task is a function that runs one step of it, closed over the handlers in
scope where the task was dispatched. Its first step runs the work under
the task's own handler of `tasks`, whose control operations do not
resume: each answers a `Step` holding the rest of the task, closed over
the same handlers.

```scheme
(enum Step
  (Finished)
  (Yielded ((next (Fn → Step ! host))))
  (Sleeping ((delay I64) (next (Fn → Step ! host))))
  (Waiting ((ticket I64) (next (Fn → Step ! host)))))
```

The scheduler keeps every task that is not running in exactly one list:
the ready tasks, the timers, sorted by deadline, or the waiters, by
ticket. A turn takes the ready list whole and runs those tasks, so tasks
that yield to each other cannot keep the host from its events, files
each step where it says, then readies the sleepers whose deadline has
passed. `tests/programs/tasks.sld` shows the order: yields interleave,
sleepers with one deadline wake in the order they slept.

Because every task holds its handlers in its closures, a child keeps its
parent's handlers after the parent returns, and at every resumption:
there is no global handler state to save or restore. A waiting task
holds no stack either. Its handle returned when it waited, through each
frame of the work, which saved the rest of itself in the resumption
([control handlers](../snail-core/effects.md#control-handlers)).

## Scheduling

The policy is cooperative first-in, first-out, with no priorities:

- `dispatch` adds a new task to the ready list. A turn begins by
  taking the whole list, leaving an empty one, and runs what it took in
  the order it became ready; a task that yields joins the new list, so it
  runs again only in the next turn. Tasks that yield to each other
  therefore cannot keep the host from its events.
- `sleep` moves the task to the timers, kept sorted by deadline, a new
  timer after every timer due no later, so sleepers with one deadline wake
  in the order they slept. After the ready tasks have run, every timer
  whose deadline has passed joins the ready list, in deadline order.
- `await` parks the task on its ticket among the waiters. When the host
  operation settles, the host calls `wake` with the ticket, which moves
  that one waiter to the ready list. A ticket nothing waits on wakes
  nothing, as after a trap or a close.
- Between turns, `turn` answers what the host should do next
  ([driving the scheduler](scheduling.md#turns)): 0 when a task is ready,
  the milliseconds until the earliest deadline, -2 when every live task
  waits on a ticket, and -1 when no task is live.
- After a trap, `running` still names the trapped task for the host's
  report, and the host closes the scheduler instead of running more tasks.

`Scheduler` is an ordinary record whose fields hold its lists as
immutable values, and saved task handlers hold the scheduler itself; the
collector reclaims the cycle between them once nothing else reaches it.
Closing marks the scheduler closed and empties every list. A task that
stops after its scheduler has closed is forgotten, as is the rest of the
turn's tasks, and a late wake finds nothing. No language global holds the
scheduler.

## Effects and locality

The dispatcher must admit both `tasks` and the effects of the thunk, so
dispatching cannot hide an otherwise unhandled operation. The work may
yield only to `tasks`: its other handlers may have returned by the time
it runs, so preparation refuses work that may yield to any other
control effect where it is dispatched.

`tasks` is an ordinary effect. A program can handle it itself, for a
simulated clock in a test or a scheduler of its own;
`tests/programs/tasks-handler.sld` runs a countdown under a handler whose
`sleep` advances a logical clock, then under the real scheduler.

Local dispatch may capture shared mutable objects, because the work stays
in this single-threaded instance. Work for another instance travels
as bytes through a queue, never as a closure ([#553](https://github.com/tsnl/snail-scheme/issues/553), proposed).

Only `yield`, `sleep` and `await` let other tasks run. Console and
the core `fs` services remain synchronous; performing an arbitrary effect
does not by itself wait, and the scheduler does not preempt a CPU loop.
Dispatching a filesystem operation from `(snail core io)` defers it but
does not make the kernel operation asynchronous;
[the native capability below](#native-asynchronous-file-reads) supplies
asynchronous reads.

## Native asynchronous file reads

`(snail shell async-files)` exports the ordinary `files` effect. Its
`read-file : String I32 -> Result<Bytes, FileError> ! files tasks` reads
an entire file up to the supplied byte limit. It suspends the calling task
while other tasks run. A task that has other work meanwhile dispatches the
read and receives its result through a [mailbox](#mailboxes):

```scheme
(let ((results (make-mailbox)))
  (dispatch (lambda ()
              (mailbox-post results (file-read-file "notes.txt" 1048576))))
  ;; Other work can happen here; dispatch did not wait.
  (consume-result (mailbox-receive results)))
```

Here `file-read-file` is imported with a `file-` prefix, and the dispatched
task retains the explicit `files` capability (`tests/async-files/main.sld`).

Limits range from zero through 16 MiB. The host reads at most limit plus
one bytes, distinguishing an exact fit from `TooLarge`; metadata is not
proof that the subsequent read fits. Other error values are `Unavailable`,
`InvalidInput`, `NotFound`, `PermissionDenied`, and `Failed`. Reads of a
changing file are not snapshots. This first capability does not change
core filesystem operations or the IDE service's non-yielding save transaction.

On Linux, the Rust host submits open, read and close through `io_uring`,
with one outstanding kernel request per file operation and at most 64
active operations. When the scheduler has no runnable task, the host waits
for a completion or its earliest deadline using
[`submit_with_args`](https://docs.rs/io-uring/0.7.16/io_uring/struct.Submitter.html#method.submit_with_args).
There is no periodic polling or language worker pool. An unavailable ring,
including one denied by the host environment, returns `Unavailable`; other
native platforms currently return the same. Node provides matching reads
through its asynchronous filesystem API. There is no implicit browser backend.

A suspended read holds only its request's id. The host retains the
pathname, buffer and descriptor until the outstanding kernel request
completes, then closes the file before releasing the operation. A completed
result whose ticket wakes no task, because the task trapped or the run
closed, is discarded. Orderly host shutdown drains outstanding operations. If a fatal kernel-driver
error prevents that drain, kernel-visible allocations are retained until
process exit rather than freed while the kernel may access them.

Only scalar operation IDs, tickets, path characters and bytes cross the
host boundary. The runtime constructs managed `Bytes` on its owning thread,
after completion; no managed object is shared with the kernel.

## Mailboxes

A `Mailbox` is how tasks hand each other values. Messages are received in
the order they were posted. Its queue of messages and the wakers of the
tasks waiting for one are Snail Scheme data in its fields: tasks share a
mailbox, so its contents are the one piece of state this library cannot
thread through a single task. A post queues its message and wakes every
waiting task, and each takes a message for itself when it runs; one that
finds none waits again. Each message, such as a work item, goes to exactly
one receiver, and no message is handed to a task that may never run, as
one whose scheduler closed. The price is fairness: a task that asks while
a message waits takes it, even ahead of receivers woken for it that have
not run yet (`tests/programs/mailbox-order.sld`). The name is `mailbox-receive`,
not `receive`, because `(snail shell socket)` exports UDP's `receive`, and a
program importing both libraries would have conflicting imports.

```scheme
(let ((mailbox (make-mailbox)))
  (dispatch (lambda () (write-line (mailbox-receive mailbox))))
  (dispatch (lambda () (mailbox-post mailbox "hello"))))
```

A receiver that finds the queue empty takes a ticket, keeps in the
mailbox a waker, `(Fn → Unit ! mut)`, closed over its scheduler and that
ticket, and awaits the ticket. A waker only moves its task to the ready
list, so any code may call it: another task, or code between turns. A
call after the task was woken, or once its scheduler has closed, wakes
nothing. A waiting task does not run again until it is woken, so waiting
costs nothing while nothing is posted, where a loop of `yield`s would run
every turn. `tests/programs/mailbox.sld` has two tasks posting and one
receiving.

## Waiting on the host

A host operation that completes later, such as a socket read, waits the
same way. Its default takes a ticket, starts the operation on the host,
which reads its arguments and returns at once, awaits the ticket, and
finishes by taking the result the host built for it:

```scheme
(define through-host
  (lambda (start finish) (let ((id (ticket)))
    (start id)
    (await id)
    (finish id))))
```

`(snail shell socket)`, `(snail shell process)` and the application's
event and storage waits all wait through `through-host`, so each waiting
operation's latent row names `tasks`: a program that reads a socket can
see that it waits, and must do so from a task. Waiting needs no lock,
because a task runs until it waits: nothing else runs between taking a
ticket and awaiting it, so neither a post nor a host completion can come
first.

## The host boundary

The host sees the scheduler only through five exports of
`(snail shell task)`:

| Export | Meaning |
| --- | --- |
| `tasks:turn now` | Run a turn at the host's clock, in milliseconds. Answers 0 when a task is ready, -1 when none is live, -2 when every live task waits on a ticket, and otherwise the milliseconds until the next deadline. |
| `tasks:wake ticket` | Ready the task waiting on a ticket, answering whether one was. |
| `tasks:close` | Forget every task, as ending or relinking a program does. |
| `tasks:running` | The id of the running task; after a trap, the task that trapped. |
| `tasks:live` | How many tasks have not finished. |

A host's loop calls `turn`, rests until the answer says, or until a
completion wakes a ticket, and calls it again until no task is live
(`host/browser/tasks.mjs`'s `drive`, and `drive` in
`crates/snail/src/program.rs` for wasmtime). A trap unwinds out of `turn`.
The host reports the trap under `tasks:running`, closes the scheduler and
ends the run. An
answer of -2 while no host operation is outstanding is a deadlock: no
completion will wake a ticket, so the run fails. The wasmtime host
completes no host operations, so there -2 always fails; a program that
uses sockets or processes runs on Node.

A host operation's start and finish are synchronous imports.
`host/browser/tasks.mjs` keeps each outcome under its ticket until the
finish takes it. The finish answers with numbers, from which the library
builds its result in the waiting task's own call; a host never builds a
managed value ([the native boundary](networking.md#wasm-boundary)). An outcome
whose ticket wakes nothing, because its task trapped or its run closed, or
that is still held when the run closes, is disposed of instead: an
accepted connection is closed.

Tickets count from 1 in each scheduler. Every wake names its scheduler as
well as its ticket: a host's through the scheduler it created, and a
waker's through the scheduler it closes over. A relink starts a new
scheduler, so a waker that a `Mailbox` in the application's state kept
from the old one finds that scheduler closed and wakes nothing in the
new one.

A task runs on the host's ordinary Wasm stack, and keeps none while it
waits. Deep non-tail recursion can overflow it; use tail calls for loops
requiring constant stack space.
