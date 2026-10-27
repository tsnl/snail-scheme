# Task operations

`(snail-core task)` exposes the runtime-owned `tasks` control effect:

| Operation | Meaning |
| --- | --- |
| `(dispatch-local work)` | Transfer a `Once` thunk into an independent local task. |
| `(yield)` | Suspend until an event-loop turn permits more work. |
| `(sleep milliseconds)` | Suspend for a timer, using an `I64` delay from 0 through 2147483647. |

```scheme
(import
 (snail-core base)
 (snail-core io)
 (snail-core task))

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
Its argument is consumed. There are no mailboxes, request/reply protocols
or supervisors. The runtime's host API can cancel individual tasks or
close the runtime; this first Snail-Core API does not expose task handles.

## Effects and locality

The dispatcher must admit both `tasks` and the thunk's latent effects.
Dispatching a thunk cannot hide an otherwise unhandled operation. A child
inherits the ordinary handler bindings present at dispatch, including
those whose installing parent returns before the child runs.

The runtime binds `tasks`; an ordinary `handle tasks` is rejected.
JSPI supplies these restricted control waits. User-defined control
handlers and first-class resumptions await the continuation work described
in [future work](future.md).

Local dispatch may capture a mutable `Ref`, because the work stays on
this execution agent. This does not certify the closure as `Send` or
`Sync`. Ordinary handlers still require both properties and grade `omega`.
An eventual API that can choose any worker must establish transfer safety
for the complete environment.

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
