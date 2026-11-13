# Task operations

`(snail shell task)` defines the `tasks` effect and the scheduler that
handles it, both in Snail Scheme:

| Operation | Meaning |
| --- | --- |
| `(dispatch-local work)` | Transfer a `FnOnce` thunk into an independent local task. |
| `(dispatch-task work)` | The same, answering the new task's `I64` id. |
| `(yield)` | Let every other ready task run first. |
| `(sleep milliseconds)` | Wait for an `I64` number of milliseconds. |
| `(ticket)` | A fresh `I64` ticket, naming one wait. |
| `(await ticket)` | Wait until the ticket is woken. |
| `(tasks-wake! scheduler ticket)` | Ready a task waiting on that ticket; a stale ticket does nothing. |
| `(tasks-close! scheduler)` | Detach and drop queued, sleeping and waiting tasks. Cleanup may notify futures. |
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
  (dispatch-local
   (once (lambda ()
           (yield)
           (write-line "the child finishes after main returns")))))
```

The host creates one explicit `Scheduler` owner for a program and passes it
to `start-main`, turns, wakes and closure. The root `main` runs as its first
task and may yield, sleep or await like any other task. A child starts when
the parent yields or returns. A trap fails the run. The host reports it and
closes the scheduler, disposing reachable queued work. Wasm traps do not
unwind language owners, so cleanup cannot recover owners held by the
trapping frame.
Whole-program and separately linked builds use this same explicit scheduler.
Libraries have no runtime initializers or implicit scheduler globals.

The operations are not actors: there are no request/reply protocols or
supervisors. A task's id names it to the host, which reports a trap under
it, and to an application, whose loop is a task ([applications](../snail-core/applications.md#task-lifetime)).

## How a task runs

A task is a `FnOnce` that runs one step of it, closed over the handlers in
scope where the task was dispatched. Its first step runs the work under
the task's own handler of `tasks`, whose control operations do not
resume: each answers a `Step` holding the rest of the task, closed over
the same handlers.

```scheme
(enum Step
  (Finished)
  (Yielded ((next (FnOnce → Step ! host))))
  (Sleeping ((delay I64) (next (FnOnce → Step ! host))))
  (Waiting ((ticket I64) (next (FnOnce → Step ! host)))))
```

The scheduler keeps every task that is not running in exactly one place:
the ready queue, the timers, sorted by deadline, or the waiters, by
ticket. A turn runs the tasks that were ready when it began, so tasks
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

- `dispatch-task` appends a new task at the back of the ready queue. A turn
  reads the ready count when it begins and runs that many tasks from the
  front, one at a time; a task that yields goes to the back, so it runs
  again only in the next turn. Tasks that yield to each other therefore
  cannot keep the host from its events.
- `sleep` moves the task to the timers, kept sorted by deadline, a new
  timer after every timer due no later, so sleepers with one deadline wake
  in the order they slept. After the ready tasks have run, every timer
  whose deadline has passed goes to the back of the ready queue.
- `await` parks the task on its ticket among the waiters. When the host
  operation settles, the host calls `wake` with the ticket, which moves
  that one waiter to the back of the ready queue. A ticket nothing waits
  on wakes nothing, as after a trap or a close.
- Between turns, `turn` answers what the host should do next
  ([driving the scheduler](scheduling.md#turns)): 0 when a task is ready,
  the milliseconds until the earliest deadline, -2 when every live task
  waits on a ticket, and -1 when no task is live.
- A task leaves the queue, and the rest of the queue is back in place,
  before it runs. After a trap, `running` still names it for the host's
  report, and the host closes the scheduler instead of running more tasks.

`Scheduler` is `Rc SchedulerState`. Its linear task queues are ordinary
mutable fields: replace a queue with an empty value, process the removed
owner, then put it back before invoking work. Saved task handlers capture a
`WeakRc` link to the scheduler, avoiding a scheduler–task ownership cycle.
Closing marks the scheduler closed and detaches every queue before dropping
work, so cleanup can reenter safely. The host releases its final scheduler
credit after closure; no language global owns it.

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

Local dispatch may capture shared mutable objects and `Rc` owners, because
the work stays in this single-threaded instance. Work for another instance travels
as bytes through a queue, never as a closure ([#553](https://github.com/tsnl/snail-scheme/issues/553), proposed).

Only `yield`, `sleep` and `await` let other tasks run. Console and
the core `fs` services remain synchronous; performing an arbitrary effect
does not by itself wait, and the scheduler does not preempt a CPU loop.

## One-shot results

`(snail shell future)` supplies a result channel independently of any task.
`make-promise` returns a `Pair` of a linear `Promise<T>` and a linear
`Future<T>`, even when `T` is Copy. Constructors are private. The producer
consumes its promise in `fulfill`; the receiver consumes its future in
`poll`, which answers one of:

```scheme
(enum (Poll T)
  (Pending ((future (Future T))))
  (Ready ((result (Completion T)))))

(enum (Completion T)
  (Completed ((value T)))
  (Abandoned))
```

Pending returns the future for the next poll. Ready transfers the result
exactly once. A result may itself be linear. Polling neither runs work nor
waits for work: it performs `mut`, but no control effect. A model can own
the future inside an `Rc` payload and keep its last display snapshot alongside
it. Views receive ordinary shared model references; polling transfers the
future out of its slot with `replace!` ([application models](../snail-core/applications.md#resource-owning-models-and-futures)).

`fulfill` answers `Ok Unit` after publication, or `Err T` if the receiver
was already dropped, returning the unsent value to its caller. Dropping a
promise publishes Abandoned. Dropping a future cancels reception and drops
any buffered result with its own Drop effects. These are deterministic
ownership operations; garbage collection is not responsible for cleanup.
Ordinary application failures belong in `T`, usually `Result<A, E>`.
Fatal traps retain the language's fatal contract and do not unwind owners.

Publication performs `mut` and the ordinary `completion` effect. Its
`completed` operation defaults to doing nothing; a reactor can handle it
to request another update without inventing a message for each result
type. Synchronization does not make publication pure: it changes what a
later poll of another endpoint observes.

`on-ready` consumes and returns a future with a replacement waker, an
ordinary `(Fn → Unit ! mut)` function. A pending future stores it; a ready
future invokes it immediately. Publication restores the shared slot before
calling the waker and then `completed`, so either may reenter without
observing a half-written slot. A scheduler must register its waker and
park without an intervening yield. The channel has no scheduler, timer,
polling loop, or task of its own.

## Dispatching and awaiting futures

`(snail shell async)` connects these two libraries:

| Operation | Result | Effects |
| --- | --- | --- |
| `(dispatch work)` | A `Future<T>` immediately; work starts on a later turn. | `mut`, `host`, `tasks`, `completion`, and work/result cleanup effects. |
| `(await-future future)` | `Completion<T>`, parking this task if necessary. | `tasks`, `mut`, and the result's cleanup effects. |
| `(after milliseconds)` | A `Future<Unit>` fulfilled after a scheduler deadline. | `mut`, `host`, `tasks`, `completion`. |

The `tasks` effect is the suspension surface; `async` is a library, not a
new compiler effect. Polling needs no `tasks` capability. An update that
polls returns without suspending; code calling `await-future` must admit
`tasks`. A task is schedulable work and a future is a result receiver:
neither must own the other. `dispatch` is the convenient composition.

```scheme
(let ((future (dispatch (once (lambda ()
                               (sleep 10)
                               (Ok "finished"))))))
  ;; Other work can happen here; dispatch did not wait.
  (match (await-future future)
    ((Completed result) (consume-result result))
    ((Abandoned) (producer-was-canceled))))
```

Await first polls. If pending, it takes a scheduler ticket, registers a
waker and parks without an intervening yield. The continuation owns the
future throughout the wait. Fulfillment moves the waiter to the ready
queue; another task never resumes inline inside `fulfill`. A timer or
socket operation uses the same task scheduler, so waiting does not busy
poll and requires no worker pool. For example, dispatching a thunk that
calls `(read connection 4096)` from `(snail shell socket)` returns a
`Future<Result<Option<Bytes>, SocketError>>`; its task waits on the host's
socket completion and then fulfills that future.

Filesystem operations in `(snail core io)` are still synchronous. Putting
one in `dispatch` defers it but does not make the kernel operation
asynchronous. The separate native capability below supplies asynchronous reads.

Dropping a future cancels reception, not external I/O or the producer
task. Scheduler shutdown does cancel tasks: it first detaches all queues,
then runs their cleanup under the handlers captured at dispatch. A dropped
producer abandons its promise, and a dropped waiter releases its future.
Late wakeups find no queued waiter. Work dispatched by cleanup is drained
before shutdown returns. Fatal traps are distinct from this orderly
cancellation and retain their fatal contract.

## Native asynchronous file reads

`(snail shell async-files)` exports the ordinary `files` effect. Its
`read-file : String I32 -> Result<Bytes, FileError> ! files mut tasks` reads
an entire file up to the supplied byte limit. It suspends the calling task;
use `(snail shell async)`'s `dispatch` to obtain a future immediately:

```scheme
(dispatch (once (lambda () (file-read-file "notes.txt" 1048576))))
```

Here `file-read-file` is imported with a `file-` prefix. The result is a
`Future<Result<Bytes, FileError>>`. An update can poll it with `mut` but
without `tasks`; the producer retains the explicit `files` capability.

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

The suspended frame owns a private linear request token. Dropping it
withdraws reception immediately. The host retains the pathname, buffer and
descriptor until the outstanding kernel request completes, then closes the
file before releasing the operation. Cancellation does not promise prompt
interruption of a blocked kernel request. An already completed, unread result
is discarded; a stale readiness event cannot resume a canceled task.
Orderly host shutdown drains abandoned operations. If a fatal kernel-driver
error prevents that drain, kernel-visible allocations are retained until
process exit rather than freed while the kernel may access them.

Only scalar operation IDs, tickets, path characters and bytes cross the
host boundary. The runtime constructs managed `Bytes` on its owning thread,
after completion; no managed object is shared with the kernel.

## Mailboxes

A `Mailbox` is how tasks hand each other values. Messages are received in
the order they were posted, and receivers are served in the order they
began to wait. Its queues are Snail Scheme data, each in an `UnsafeSlot` of
`(snail shell slot)` ([scheduling](#scheduling)), one of messages
posted while no task waited and one of waiting receivers: tasks share a
mailbox, so its contents are the one piece of state this library cannot
thread through a single task. A post hands its message straight
to the receiver that has waited longest, and wakes it, so a task that
asks before that receiver runs waits behind the others instead of taking
it. A message may be linear, such as a work item: it moves into the
mailbox and out to the one receiver that takes it. A message handed to a
receiver whose task never runs again, because its scheduler closed, goes
with that task. The name is `mailbox-receive`,
not `receive`, because `(snail shell socket)` exports UDP's `receive`, and a
program importing both libraries would have conflicting imports.

```scheme
(let ((mailbox (make-mailbox)))
  (dispatch-local (once (lambda () (write-line (mailbox-receive mailbox)))))
  (dispatch-local (once (lambda () (mailbox-post mailbox "hello")))))
```

A receiver that finds the queue empty takes a ticket, adds it to the
mailbox's receivers and awaits it; a post wakes the receiver that has
waited longest. A waiting task does not run again until it is woken, so
waiting costs nothing while nothing is posted, where a loop of `yield`s
would run every turn. A woken receiver looks again, since a receiver that
was already ready may have taken the message first. A receiver whose
ticket wakes nothing, because its task trapped or its scheduler closed
while it waited, is skipped. `tests/programs/mailbox.sld` has two tasks
posting and one receiving.

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
| `tasks:close` | Drop every task, as ending or relinking a program does. |
| `tasks:running` | The id of the running task; after a trap, the task that trapped. |
| `tasks:live` | How many tasks have not finished. |

A host's loop calls `turn`, rests until the answer says, or until a
completion wakes a ticket, and calls it again until no task is live
(`host/browser/tasks.mjs`'s `drive`, and `drive` in
`crates/snail/src/program.rs` for wasmtime). A trap unwinds out of `turn`;
the scheduler took the trapped task off its queue before running it. The
host reports the trap under `tasks:running`, closes the scheduler and ends
the run. An
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

Tickets are numbered from the clock of the scheduler's first turn,
times a thousand. A relink starts a new scheduler while a `Mailbox` in
the application's state keeps the tickets of receivers the old one
dropped, and those must not name the new one's waits.

A task runs on the host's ordinary Wasm stack, and keeps none while it
waits. Deep non-tail recursion can overflow it; use tail calls for loops
requiring constant stack space.
