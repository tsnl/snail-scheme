# Task operations

`(snail shell task)` exposes the runtime-owned `tasks` control effect:

| Operation | Meaning |
| --- | --- |
| `(dispatch-local work)` | Transfer a `Once` thunk into an independent local task. |
| `(yield)` | Suspend until an event-loop turn permits more work. |
| `(sleep milliseconds)` | Suspend for a timer, using an `I64` delay from 0 through 2147483647. |
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

The CLI waits for all tasks, including suspended children, before closing
its external resources. A child failure lets siblings finish and gives
the invocation a failing exit status. Whole-program builds and separately
linked library builds use the same scheduler. Library initializers run
in dependency order; their children need not finish before the next
initializer runs.

`dispatch-local` returns `Unit`, not an actor or an application object.
Its argument is consumed. There are no request/reply protocols or
supervisors. The runtime's host API can cancel individual tasks or
close the runtime; this first Snail-Core API does not expose task handles.

## Mailboxes

A `Mailbox` is how tasks hand each other values. Messages are received in
the order they were posted, and receivers are served in the order they
began to wait. Its queues are Snail-Core data, each a pair of lists in a
`Ref`, one of messages and one of waiting receivers: tasks share a
mailbox, so its contents are the one piece of state this library cannot
thread through a single task. A message may be linear, such as a work
item: it moves into the mailbox and out to the one receiver that takes
it. The name is `mailbox-receive`,
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
would run every event-loop turn. A woken receiver looks again, since a
receiver that was already running may have taken the message first. A
receiver whose task was cancelled while it waited is skipped.
`tests/programs/mailbox.sld` has two tasks posting and one receiving.

## Waiting on the host

A host operation that completes later, such as a socket read, waits the
same way. Its default takes a ticket, starts the operation on the host,
which reads its arguments and returns at once, awaits the ticket, and
finishes by taking the result the host built for it:

```scheme
(define (through-host start finish)
  (let ((ticket (ticket-task)))
    (start ticket)
    (await-task ticket)
    (finish ticket)))
```

`(snail shell socket)`, `(snail shell process)` and the application's
event and storage waits all wait through `through-host`, so each waiting
operation's latent row names `tasks`: a program that reads a socket can
see that it waits. A handler can still replace the effect, and its
implementations may perform `tasks` there too.

## Effects and locality

The dispatcher must admit both `tasks` and the effects of the thunk.
Dispatching a thunk cannot hide an otherwise unhandled operation. A child
inherits the ordinary handler bindings present at dispatch, including
those whose installing parent returns before the child runs.

The runtime binds `tasks`; an ordinary `handle tasks` is rejected.
JSPI supplies these restricted control waits. User-defined control
handlers, with first-class one-shot resumptions, compile to evidence
passing instead ([control handlers](../snail-core/effects.md#control-handlers)).
[Future work](future.md) records research on continuations and parallel
execution.

Local dispatch may capture a mutable `Ref`, because the work stays in
this instance, which is single-threaded. Work for another instance travels
as bytes through a queue, never as a closure ([#553](https://github.com/tsnl/snail-scheme/issues/553), proposed).

Only explicit waits release the execution permit. Existing scalar console
and filesystem services remain synchronous; performing an arbitrary effect
does not by itself suspend. The runtime does not preempt a CPU loop.

## The host boundary

Wasm passes the host an opaque owner cell and invocation and discard
function references. The invocation entry takes and clears that cell
before executing the thunk. The discard entry clears queued work without
running it. JavaScript neither inspects the closure nor constructs Snail-Core
objects. These entries also enforce one-shot use at the trusted host
boundary.

Tickets need three more imports. `ticket` gives the running task a fresh
ticket as an `I64`, `await` suspends the task until the ticket is woken,
and `wake` wakes the task awaiting a ticket and answers whether one was,
waking nothing otherwise, so a ticket left behind by a cancelled task
cannot wake a different task. In the browser, tickets are numbered across
the whole page, not per scheduler: a relink makes a new scheduler while a
`Mailbox` in the application's state keeps the tickets of the receivers
the old one cancelled, and those must not name new waits
(`tests/tasks/check.mjs`). Waiting needs no lock because a task runs until
it waits: nothing else runs between a task's taking a ticket and awaiting
it, so neither a post nor a host completion can come first. The queue the
waits serve stays in Snail-Core; the host keeps only the waiting tasks.

A host operation's start and finish are synchronous imports. The host
keeps each outcome under its ticket until the finish takes it
(`host/browser/completions.mjs`), and builds the managed result through
the library's exposed helpers inside the finish, in the waiting task's own
call. An outcome whose task was cancelled, before the wake or after it,
is disposed of instead: an accepted connection is closed. When tasks
become effects, `await` becomes a wait on the Snail-Core scheduler, and
the host wakes a ticket through an export instead of the JavaScript
scheduler; the mailbox and the operations keep their types.

Optimization must preserve those external calls. The build no longer
enables Binaryen's `--closed-world`: that mode assumes outgoing function
references will not be called by the host. This is a correctness
requirement of the task ABI. See [Binaryen's world-mode contract](https://github.com/WebAssembly/binaryen/blob/main/src/pass.h).

The CLI's existing Node worker provides V8 heap settings for
one execution agent. It is not a worker pool; all tasks in this runtime
still execute cooperatively on that one agent.

JSPI uses finite, engine-managed stacks. Deep non-tail recursion can
overflow; use tail calls for loops requiring constant stack space. The
previous CLI-only million-depth non-tail recursion guarantee and its large
native-stack setting have been removed. Ordinary recursion and tail calls
remain supported.
