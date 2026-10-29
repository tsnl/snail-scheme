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

A receiver that finds the queue empty adds its task's id to the mailbox's
receivers and parks; a post wakes the receiver that has waited longest. A
parked task does not run again until it is woken, so waiting costs nothing
while nothing is posted, where a loop of `yield`s would run every event-loop
turn. A woken receiver looks again, since a receiver that was already
running may have taken the message first. A receiver whose task was
cancelled while it waited is skipped. `tests/programs/mailbox.sld` has two
tasks posting and one receiving.

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

Parking needs two more imports and a third to name the task. `park`
suspends the running task until `unpark` is called with its id, which
`current` gives as an `I64`. `unpark` returns whether a task with that id
was parked, and wakes nothing otherwise, so an id left behind by a
cancelled task cannot wake a different task. In the browser, ids are
numbered across the whole page, not per scheduler: a relink makes a new
scheduler while a `Mailbox` in the application's state keeps the ids of
the tasks the old one cancelled, and those must not name new tasks
(`tests/tasks/check.mjs`). Parking is safe without a
lock because a task runs until it waits: nothing else runs between a
receiver's finding the queue empty and its parking. The queue the waits
serve stays in Snail-Core; the host keeps only the parked tasks. When
tasks become effects, `park` becomes a wait on the Snail-Core scheduler
and the mailbox operations keep their types.

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
