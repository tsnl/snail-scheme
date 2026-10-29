# Effects and handlers

A function's type says what it returns. Its **effect row** says what calling
it may do besides: write to the console, read a file, wait for a timer. This
chapter builds the effect system up the way
[Koka's tutorial](https://koka-lang.github.io/koka/doc/book.html) does, in
four steps:

- [Basic effects](#basic-effects): rows on function types, and how they are
  inferred and checked.
- [Handlers](#handlers): declaring an effect and deciding, around a piece of
  code, what its operations do.
- [Control handlers](#control-handlers): operations whose handler receives
  the rest of the computation, to resume now, later or never.
- [Latent handlers](#latent-handlers): operations whose implementations
  perform effects for their caller, such as waiting on the caller's
  scheduler.

Every example is part of a program under `tests/programs/`, which
`make test` runs, and the output shown is that program's. Run one with

```sh
./scripts/snail-tool run tests/programs/effects-basic.sld
```

## Basic effects

### Effect rows

A function type may end in `!` and a row of effects. A function without `!`
is total: a call can only compute its result.

```scheme
{{#include ../../../tests/programs/effects-basic.sld:rows}}
```

`write-line` performs `console`, so `report` does too. A total function may
not call it. `tests/programs/error-effect.sld`:

```scheme
{{#include ../../../tests/programs/error-effect.sld}}
```

fails to compile:

```text
{{#include ../../../tests/programs/error-effect.err}}
```

`mut` covers reading and writing mutable fields, `Ref` and `Array`. `(snail core io)`
declares `console`, `fs` and `clock`, and other libraries declare their own,
such as `tcp` in `(snail shell socket)`. A program declares more with
`effect`, in the [next section](#handlers). Traps and non-termination are
not tracked: a total function may still panic or loop forever.

### Inference and signatures

Rows are inferred by unification, as types are, Koka-style, so nothing
inside a definition needs a row written. A definition without a signature
gets the row its body performs:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:inferred}}
```

```text
squared 49
```

`report-square` performs `console`, through `report`. A call requires its
callee's effects to fit the row of the code around it, so a total function
could call `square` but not `report-square`.

A top-level signature states the row, and the body is checked against it
both ways: the body may perform only what the row names, and the row may
name only what the body performs.

### Claiming only what the body performs

The second half is the unused-effect rule. A top-level definition whose
signature names an effect, or a tail variable such as `e`, that no call in
its body performs is an error at the signature.
`tests/programs/error-unperformed-effect.sld`:

```scheme
{{#include ../../../tests/programs/error-unperformed-effect.sld}}
```

```text
{{#include ../../../tests/programs/error-unperformed-effect.err}}
```

A row is a promise to callers about what may happen, and each caller must
handle or pass on every effect in it. An effect that never happens would
cost every caller that work for nothing.

Some signatures have no body to hold them to. An instance method keeps its
class method's row, which one instance may need less of than another:
in `tests/programs/declared-effects.sld`, the `Bool` instance of
`announce` performs nothing and keeps `! console`. `extern` declarations,
class method signatures and definitions whose value is not a lambda are
not compared either. A signature that a macro writes is held to each
expansion, so a macro that cannot know a row takes the effects as an
argument. `define-application` cannot know what its reset binder performs,
so a reset that dispatches background tasks says `(effects: tasks)`
([application model](applications.md)); claiming `tasks` for a reset that
dispatches nothing is the same error
(`tests/programs/error-application-unused-effect.sld`).

### Effect polymorphism

A higher-order function performs whatever its argument performs. A row
variable, quantified like a type variable, stands for those effects:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:polymorphic}}
```

```text
squared 1
squared 4
squared 9
```

Here `e` is `console`; with a total `action`, `repeat` is total. `map` in
`(snail core base)` has the same shape:
`(All (A B e) (-> (-> A B ! e) (List A) (List B) ! e))`.

A row with a tail fits a larger row with the same tail: `e` fits
`console e`, and `fs e` fits `console fs e`. The reverse does not hold, and
two unrelated tails never fit each other
(`tests/programs/error-effect-row-tail.sld`). This check is about
permission to call; equality of function types still compares whole rows.
The [effects tutorial](tutorials/effects.md) shows a function that adds
`console` around its argument's row.

### Local mutation

A function whose signature has no `mut` may still mutate storage that it
allocates and that nothing keeps after it returns:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:local}}
```

```text
sum 14
```

The checker accepts such a body when nothing the function can reach from
outside can hold mutable storage: not its parameters, not its result, and
not any name it reads, including effect operations. Holding storage means
being a `Ref`, an `Array` or an `Any`, data with a mutable field or a field of
such a type, or a function that performs `mut`. Primitives, constructors and field operations are always
allowed. A helper defined elsewhere that mutates its argument is therefore
rejected even when the argument is local; define it inside the function.
`unsafe-total` runs a thunk and discards all its effects without a check, for
the cases this rule rejects; each use says in a comment why nothing escapes.
A `gc` effect, "may allocate traced memory", is proposed in
[issue #550](https://github.com/tsnl/snail-scheme/issues/550).

### Defaults from the host

`console`, `fs` and `clock` need no handler. Their declarations give a
`host` clause, naming a Wasm import for each operation, and an operation
performed where no handler of its effect is in scope calls the host. That
is why the programs above call `report` at their top level with no handler
around them. A handler can
still replace them: `tests/programs/files.sld` handles `fs` to answer
`file-exists?` and `list-directory` from memory. An effect without a
default must be handled: performing it where no handler is in scope is an
error (`tests/programs/error-unhandled.sld`).

`host` is the row of code that may run anything the host implements, such
as a program's top level, which may perform `mut` and every effect with
defaults, and a task scheduler. It is a builtin effect, like `mut`, imported
from `(snail core forms)`; no handler implements it, and a function whose
row names it can be called only where `host` is in the row too. Work closed
over its handlers performs it ([below](#closing-over-handlers)).

## Handlers

### Declaring an effect

`effect` declares an effect and its operations, each with a function type.
An operation is called like a function, and performing it charges the
caller its effect:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:declare}}
```

`log`'s type is `(-> String Unit)`, and calling it adds `Log` to the row,
so `total`'s row is `Log`. `Log` has no default, so something must say what
logging means before `total` can run. Effects take no type parameters, and
operations are monomorphic ([notable omissions](omissions.md)): a handler
implements an operation once, at one type, so an operation's type may not
quantify over types or rows
(`tests/programs/error-effect-operation-polymorphic.sld`).

### Handling an effect

`(handle Name ((operation implementation) ...) body ...)` runs the body with
each operation of `Name` implemented:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:handle}}
```

```text
adding 3
adding 4
7
```

A handler implements each operation of its effect exactly once
(`tests/programs/error-handler.sld`). It names operations within its effect,
so they need not be imported. An implementation is a function with the
operation's type. The implementation of an ordinary operation returns to
the operation's caller exactly once, as a function call would; Koka calls
these `fun` operations.

### A handler removes its effect

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:quietly}}
```

`quietly`'s argument may perform `Log` and anything else, `e`. The handler
removes `Log`, so `quietly` performs only `e`, and `quiet-total`, whose
action performs nothing else, is total. `(quiet-total (list 1 2 3))` is `6`.

### Implementations run outside their handler

An implementation runs with the handlers outside its own `handle`, so an
operation it performs goes to the next handler out:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:indented}}
```

```text
order
  adding 3
  adding 4
  total 7
```

`indented`'s implementation of `log` performs `log`, which reaches the
printing handler around it. Were it to reach its own handler, it would call
itself forever. Its row shows the rule: the handler removes the body's
`Log`, and its implementation adds `Log` back, for the handler outside. Of
two handlers of one effect, the inner one catches.

### A test double

A program written against an effect can run against a different handler in
a test:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:files}}
```

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:run-files}}
```

```text
bonjour, disk
hello, memory
```

`greeting` is the same in both runs. `from-disk`'s implementation calls
`read-file`, which performs `fs`; by the rule above that goes to the
handlers outside `from-disk`'s, here the host, so `from-disk`'s row names
`fs`. `from-memory`'s does not: the test touches no file system at all.

### Handlers may hold state

An instance of a program runs on one thread, so a handler's implementation
may capture mutable state and change it. That includes a cell, an alias of
a procedure that reaches one, a global, or a callback passed in
(`tests/programs/handler-shared-state.sld`):

```scheme
{{#include ../../../tests/programs/handler-shared-state.sld:counter}}
```

prints `23`. A handler must still be reusable, since a deep handler runs
its implementation again for each operation. Ordinary closures always are,
because they cannot capture a one-shot value. Fresh storage allocated
inside an invocation, and the operation's arguments, belong to that
invocation (`tests/programs/handler-captures.sld`).

### Defaults in Snail-Core

After its operations, an effect's declaration may give a `default` clause,
which implements operations in Snail-Core as a handler does:

```scheme
{{#include ../../../tests/programs/effects-handlers.sld:default}}
```

```text
shown by default
shown when verbose
```

A default runs when no handler of its effect is in scope. An ordinary
operation with a default works much like a Scheme parameter, with `handle`
in the role of `parameterize`. A default has its operation's type without
the operation's own effect, so it performs at most the operation's
[latent row](#latent-rows), here nothing: a default that writes to the
console is rejected (`tests/programs/error-default-effect.sld`). A default
is a lambda or a function's name, and an operation has at most one.

## Control handlers

### Control operations

An ordinary operation always returns to its caller. An operation declared
with `ctl` need not. Its implementation receives one more argument,
`resume`, the rest of the handled body, and decides what to do with it.
`resume` is linear, so the implementation uses it exactly once. The
simplest choice is to drop it, with `(drop resume)`, as an exception does
(`tests/programs/control-exception.sld`):

```scheme
{{#include ../../../tests/programs/control-exception.sld:parse-or}}
```

```text
123
not a digit: x
0
```

An implementation's result is the handler's answer: the value of the whole
`handle` expression. Its type, the answer type, is the type of the handled
body, here `I64`. `raise`'s own result type, also `I64`, is what `resume`
would take. This implementation drops `resume`, so nothing after the
`raise` runs, in `digit`, in `number`'s fold, or anywhere between them and
the handler, and `parse-or` answers `default`. A `Once` held across an
abandoned operation is dropped and never called; there is no `finally`
clause (`tests/programs/control-early-exit.sld`). An implementation that
raises again reaches the handler outside it, as an ordinary one does.

A control operation has no default: a default runs where no handler is,
and nothing there can be handed the rest of a computation
(`tests/programs/error-control-host-default.sld`). Its implementation runs
in the handler's outer context, like an ordinary one.

### Operations that never return

An exception's implementation never calls `resume`, but nothing in
`raise`'s type says so. An operation can say it: one that answers `Never`,
the type with no values in `(snail core base)`, cannot return to its
performer, so its implementation takes the operation's arguments alone
(`tests/programs/control-abortive.sld`):

```scheme
{{#include ../../../tests/programs/control-abortive.sld:fail}}
```

```text
added 1
added 2
added 3
6
added 1
failed: negative: -2
```

`(absurd never)`, of type `(All (A) (-> Never A))`, gives the call whatever
type the code around it needs, here `checked`'s `I64`. It is a `match` with
no clauses, which only a value of a type with no cases may have
(`tests/programs/error-match-empty.sld`). An implementation of such an
operation that takes `resume` is a type error
(`tests/programs/error-control-never-resume.sld`).

Since nothing resumes them, these operations cost less. A call that may
yield only to effects whose control operations all answer `Never` saves no
frame when it yields, and no code is compiled for resuming what follows
it. A failure inside a resumed computation still unwinds through every
handler between it and its own, as the fixture's generator shows.

### Resuming

`(resume answer)` runs the rest of the handled body, with `answer` as the
operation's result, to the handler's answer, and returns that answer, so
the implementation may build on it. A generator yields values to its
handler:

```scheme
{{#include ../../../tests/programs/effects-control.sld:collect}}
```

```scheme
{{#include ../../../tests/programs/effects-control.sld:run-collect}}
```

```text
1 2 3 4 5
```

Each `yield` stops `range` and hands its value to the implementation, which
conses it onto whatever the rest of the body produces. The body ends with
`(Nil)`, the answer when nothing more is yielded. An implementation may also
choose, value by value, whether to resume:

```scheme
{{#include ../../../tests/programs/effects-control.sld:first-above}}
```

```text
4
-1
```

### Storing `resume`

`resume` is a `Once`: a function that is called, or dropped, exactly once. It is
also first-class. An implementation may return it inside a value, and
whoever holds that value may call it later, after the `handle` has
returned:

```scheme
{{#include ../../../tests/programs/effects-control.sld:step}}
```

```text
1 10 2 11 3 12 13 14
```

`start` runs a generator to its first `yield`, and the implementation
returns the value with `resume` instead of calling it. `interleave` calls
each `next` long after `start` returned. A `Step` that holds a `Once` is
linear itself, used exactly once ([ownership](ownership.md)).

The handler is deep: resuming re-installs it around the rest of the body,
so the generator's next `yield` reaches the same implementation, and
`(next (unit))` returns the next `Step`. The resumed computation also runs
under the handlers in scope where `resume` is called, not those that were
in scope when it started: `tests/programs/control-stored-resume.sld`
resumes two logging generators under a different `Log` handler from the
one they began under.

### Closing over handlers

`inherit-handlers`, from `(snail core primitive)`, closes a one-shot thunk
over the handlers in scope where it is called, and `inherit-handlers-1`
closes a procedure of one argument, such as a `resume`. Wherever the `Once`
it makes is called, the procedure's operations reach those handlers, even
after their handles have returned:

```scheme
{{#include ../../../tests/programs/control-inherit.sld:thunk}}
```

```text
second log: before the thunk
first log: a thunk
```

The caller of `inherit-handlers` is charged the procedure's row, as if it
ran the procedure there. The `Once` it makes performs `host` instead: the
captured handlers answer the effects the row declares, and what remains,
`mut` and the effects the host implements, happens when it runs. So pure
code cannot call it (`tests/programs/error-inherit-pure.sld`), and one type
serves work of every row, as the steps of a scheduler need:

```scheme
{{#include ../../../tests/programs/control-inherit.sld:resume}}
```

Each step resumes under the log in scope where the generator yielded,
unlike `control-stored-resume`'s. A closed procedure cannot yield to a
control effect, whose handle may be gone by the time it runs.

### The type of `resume`

`resume` takes the operation's result and returns the handler's answer,
and it performs the row of the code around the `handle`, its **context
row**. For `(ctl yield (-> I64 I64))` handled in a function of row `Log`,
whose handler answers `Step`, `resume` is `(Once (-> I64 Step ! Log))`.

Calling `resume` runs under the caller's handlers everything the `handle`
would perform outward: the rest of the body, and, since the handler is
deep, each implementation that runs again when the body performs the
effect once more. Both are in the context row. So a `Step` that stores
`resume` must name the effects its implementation performs
(`tests/programs/error-control-resume-row.sld`):

```scheme
{{#include ../../../tests/programs/error-control-resume-row.sld:step}}
```

```text
{{#include ../../../tests/programs/error-control-resume-row.err}}
```

Typed `(Once (-> I64 Step ! Log))`, the stored `next` is resumed under a
`Log` handler, the one where it is called
(`tests/programs/control-resume-row.sld`):

```text
{{#include ../../../tests/programs/control-resume-row.out}}
```

The context row over-approximates, as Koka's does: a stored resumption
demands every effect of the handle's context row, even one that only the
code around the `handle` performs. And since calling `resume` performs
that whole row, a function whose control implementation calls `resume`
counts every effect of its signature as performed, so the
[unused-effect rule](#claiming-only-what-the-body-performs) cannot flag
one there. A row of the `handle`'s own, the body's and the
implementations' effects alone, would need row inclusion that the checker,
which decides inclusion by unification, cannot state once a rigid tail
such as `e` is involved.

### Loops in constant stack

An implementation that calls `resume` in tail position runs in constant
stack (`tests/programs/control-tail-loop.sld`):

```scheme
{{#include ../../../tests/programs/control-tail-loop.sld:count-down}}
```

```text
10000100000
```

A hundred thousand yields grow neither the loop's stack nor the handler's.

### One shot

`resume` is one-shot, so the checker rejects calling it twice, and a
second call that reaches run time traps.
`tests/programs/error-control-resume-twice.sld`:

```scheme
{{#include ../../../tests/programs/error-control-resume-twice.sld}}
```

```text
{{#include ../../../tests/programs/error-control-resume-twice.err}}
```

Multi-shot continuations are out of scope: they would need every frame to
be reachable twice, a cost paid by code that never captures one.

### Where control cannot reach

A yield returns through each frame between the operation and its handler,
so every frame on that path must expect it. A control row cannot reach a
`vector-generate` or `string-generate` callback, which a WAT loop calls; an
`unsafe-total` thunk, whose row the call discards; `dispatch-local` work,
which runs later on a task's own stack; a procedure closed over its
handlers, which may run after their handles have returned; or the
implementation of an operation declared without `ctl`, the subject of the
next section. Each is
an error after specialization. A generic function used where a control
operation may be performed is specialized at that row, so its callback rows
name the effect too: `vector-map`, which calls `vector-generate`, cannot be
used in such a body even with a callback that cannot abort.

Nor can a control row pass through `Any`, whose TypeId records no rows: a
yielding function converted to `Any` and back could be called as a total
one, with no test for its yield. No function that performs effects, of any
kind, converts to `Any`
(`tests/programs/error-any-control-function.sld`,
[dynamic values](types.md#dynamic-values)).

## Latent handlers

### One handler for every task

Suppose a program puts one handler of an effect `Io`, say for its sockets,
around everything it does, and runs each task under a scheduler of its own:
a handler of a control effect, `Async`, whose implementation of `await`
keeps the task's `resume` until its data arrives. `Io`'s operation `fetch`,
a read, must wait for data, and the wait must suspend the task that read,
not the whole program.

The implementation of `fetch` cannot just perform `await`. It runs outside
its own handler, where no task's scheduler is in scope. And the
implementation of an ordinary operation may not perform a control operation
its type does not name at all
(`tests/programs/error-control-implementation.sld`):

```scheme
{{#include ../../../tests/programs/error-control-implementation.sld}}
```

```text
{{#include ../../../tests/programs/error-control-implementation.err}}
```

### Latent rows

An ordinary operation's type may name effects besides its own, its
**latent row**: those its implementations perform where it is performed.
`tests/programs/control-latent.sld` has `fetch` name `Async`:

```scheme
{{#include ../../../tests/programs/control-latent.sld:effects}}
```

Performing `fetch` charges the caller `Io` and `Async`, so the call may
suspend. An implementation of `fetch` may perform `Async`, and those
operations go to the handlers **in scope where `fetch` was performed**, not
to those outside the `Io` handler. Its other operations go to the handlers
outside `Io`'s, as for any implementation. A yield leaves the
implementation through the performer, and `resume` comes back into it.

### A way to avoid sneaking effects into callers

The rule is a way to avoid sneaking effects into callers. The caller of
`fetch` is charged `Async` in its own type, so it can see that `fetch` may
wait, and it must provide the `Async` handler that `fetch` waits on.
Whatever `fetch` does to its caller, the caller's type says.

Suppose instead that `fetch`'s `await` went to an `Async` handler outside
the `Io` handler, where the caller cannot see it. Then `fetch` would suspend
more than its caller. It would also suspend the caller's own scheduler,
whose type says it never waits because it handles `Async` itself, and
everything between that scheduler and the outer handler. `Async` would
have been sneaked into code whose types do not mention it.

That code was also compiled believing `Async` was already handled: only a
call whose callee's row names a control effect checks for a yield
(`control.sld` in the [compiler tour](compilers.md)). A suspension aimed
further out would cut through frames that never expected to be suspended.
The error above closes the other way in: an operation whose type names no
control effect may not yield at all.

`tests/programs/control-latent-performer.sld` installs an `Async` handler
on each side of `Io`'s; the inner one answers:

```scheme
{{#include ../../../tests/programs/control-latent-performer.sld}}
```

```text
{{#include ../../../tests/programs/control-latent-performer.out}}
```

### Tasks with schedulers of their own

The rest of `control-latent.sld` is the program from the start of this
section. Each task runs under its own `Async` handler, which hands back the
rest of the task at each `await`:

```scheme
{{#include ../../../tests/programs/control-latent.sld:tasks}}
```

One `Io` handler surrounds both tasks. `alternate`, not shown, answers each
wait with ten times its ticket, switching between the tasks long after
their handlers returned:

```scheme
{{#include ../../../tests/programs/control-latent.sld:io}}
```

```text
task 1 fetches 10
task 2 fetches 20
waiting on 10
fetched 101
task 1 fetches 11
waiting on 20
fetched 201
task 2 fetches 21
waiting on 11
waiting on 21
done with 212
done with 412
```

Each `fetch` asks the task that performed it for its id, and its `await`
suspends that task alone.

Can an `Io` handler whose implementation performs `await` be installed
where no `Async` handler is in scope at all? Yes: this one is, at the top
level of the program. The `Async` that `fetch` performs is resolved where
`fetch` is called, so a later `handle Async` inside the `Io` handler, here
each task's, is what lets code call `fetch`. Calling `fetch` where no
`Async` handler is in scope is still an error, as for any unhandled effect
(`tests/programs/error-control-latent-unhandled.sld`).

### Ordinary effects in a latent row

An ordinary effect in a latent row goes to the performer's handler the same
way:

```scheme
{{#include ../../../tests/programs/control-latent.sld:notes}}
```

```text
outer log: before
inner log: note inside
```

`note`'s implementation logs to the `Log` handler in scope where `note` is
performed, the inner one, not to the one around the `Notes` handler.
Without `! Log` in `note`'s type, it would log to the outer one, as any
implementation does.

### Defaults that perform latent effects

A default runs under the handlers in scope where its operation is
performed, so it may perform its operation's latent row there
(`tests/programs/control-default.sld`):

```scheme
{{#include ../../../tests/programs/control-default.sld:clock}}
```

`sleep-until`'s default, `wait-for`, awaits on its caller's `Async`
handler. That program runs a task that sleeps twice under a scheduler that
wakes each sleeper at its deadline:

```text
waiting until 1005
woke at 1005
waiting until 1006
done at 1006
```

### The rules

- An implementation may yield only to the control effects its operation's
  type names (`tests/programs/error-control-latent-implementation.sld`).
- A control operation has no latent row, since its implementation runs
  where its handler is, once the body has unwound to it
  (`tests/programs/error-control-latent-ctl.sld`).
- No latent row names its operation's own effect.

The runtime's own tasks still suspend through JSPI
([scheduling](../runtimes/scheduling.md)); making them effects like `Async`
here is proposed in [issue #511](https://github.com/tsnl/snail-scheme/issues/511).
