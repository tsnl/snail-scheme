# Task operations

`(snail shell task)` defines the `tasks` effect and the scheduler that
handles it, both in Snail-Core:

| Operation | Meaning |
| --- | --- |
| `(dispatch-local work)` | Transfer a `FnOnce` thunk into an independent local task. |
| `(dispatch-task work)` | The same, answering the new task's `I64` id. |
| `(yield)` | Let every other ready task run first. |
| `(sleep milliseconds)` | Wait for an `I64` number of milliseconds. |
| `(ticket)` | A fresh `I64` ticket, naming one wait. |
| `(await ticket)` | Wait until the ticket is woken. |
| `(through-host start finish)` | Wait on a host operation by ticket ([below](#waiting-on-the-host)). |
| `(make-mailbox)` | A new, empty `(Mailbox T)`: a queue of messages between tasks. |
| `(mailbox-post mailbox message)` | Add a message at the back. Posting never waits. |
| `(mailbox-receive mailbox)` | Take the message at the front, waiting until one is posted. |

```scheme
(import
 (snail core base)
 (snail core io)
 (snail shell task))

(dispatch-local
 (once (lambda ()
         (yield)
         (write-line "the child finishes after main returns"))))
```

A program's top level runs to completion before any task does: `main`
returns, and the host then drives the scheduler until no task is live,
before closing its external resources. A task runs until it finishes or
waits; a trap ends only the task that trapped, which the host reports,
and gives the run a failing exit status, while its siblings go on
(`tests/tasks/failure.sld`). A trap in `main` itself ends the run.
Whole-program builds and separately linked library builds share one
scheduler, the one in the program's copy of `(snail shell task)`. Library
initializers run in dependency order, and the tasks they dispatch run
once the last has returned.

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
  (Yielded ((next (FnOnce Step ! host))))
  (Sleeping ((delay I64) (next (FnOnce Step ! host))))
  (Waiting ((ticket I64) (next (FnOnce Step ! host)))))
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

## Effects and locality

The dispatcher must admit both `tasks` and the effects of the thunk, so
dispatching cannot hide an otherwise unhandled operation. The work may
yield only to `tasks`: its other handlers may have returned by the time
it runs, so `control.sld` refuses work that may yield to any other
control effect where it is dispatched.

`tasks` is an ordinary effect. A program can handle it itself, for a
simulated clock in a test or a scheduler of its own;
`tests/programs/tasks-handler.sld` runs a countdown under a handler whose
`sleep` advances a logical clock, then under the real scheduler.

Local dispatch may capture a mutable `Ref`, because the work stays in
this instance, which is single-threaded. Work for another instance travels
as bytes through a queue, never as a closure ([#553](https://github.com/tsnl/snail-scheme/issues/553), proposed).

Only `yield`, `sleep` and `await` let other tasks run. Console and
filesystem services remain synchronous; performing an arbitrary effect
does not by itself wait, and the scheduler does not preempt a CPU loop.

## Mailboxes

A `Mailbox` is how tasks hand each other values. Messages are received in
the order they were posted, and receivers are served in the order they
began to wait. Its queues are Snail-Core data, each in a `Ref`, one of
messages posted while no task waited and one of waiting receivers: tasks
share a mailbox, so its contents are the one piece of state this library
cannot thread through a single task. A post hands its message straight
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
(define (through-host start finish)
  (let ((id (ticket)))
    (start id)
    (await id)
    (finish id)))
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
the scheduler took the trapped task off its queue before running it, so
the host reports the trap under `tasks:running` and turns again. An
answer of -2 while no host operation is outstanding is a deadlock: no
completion will wake a ticket, so the run fails. The wasmtime host
completes no host operations, so there -2 always fails; a program that
uses sockets or processes runs on Node.

A host operation's start and finish are synchronous imports.
`host/browser/tasks.mjs` keeps each outcome under its ticket until the
finish takes it, and the finish builds the managed result through the
library's exposed helpers in the waiting task's own call. An outcome
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
