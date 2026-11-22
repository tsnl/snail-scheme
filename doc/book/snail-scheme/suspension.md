# Suspension

A computation can stop short of its result: an error ends it, a generator
hands over a value and waits to be asked for the next, a task waits for a
timer. `snail-scheme` has one mechanism for all three, of three functions
in `(snail core base)`:

```scheme
(make-prompt)                        ; (Prompt S R)
(with-prompt prompt body handler)    ; A
(suspend prompt value)               ; R
```

`(with-prompt prompt body handler)` calls `body`, a function of no
arguments, and answers its value. If the body, or anything it calls,
however deep, calls `(suspend prompt value)`, the body stops there, and the
call answers `(handler value resume)` instead. `resume` is the rest of the
body: `(resume answer)` goes on from the `suspend`, whose value is
`answer`, to the body's end, and answers the body's value.

A `Prompt S R` is what ties the two together: a suspension carries an `S`
out and is resumed with an `R`. Nothing between the `suspend` and its
`with-prompt` takes part: no function on the way says in its type that it
may be suspended, takes anything for it, or is written differently.

Every example is part of a program under `tests/programs/`, which
`make test` runs, and the output shown is that program's.

## Stopping

### Exceptions

A handler need not call `resume`. One that never does is an exception
handler (`tests/programs/prompts.sld`):

```scheme
{{#include ../../../tests/programs/prompts.sld:exception}}
```

```scheme
{{#include ../../../tests/programs/prompts.sld:run-exception}}
```

```text
123
not a digit: x
0
```

The handler's value is the value of the whole `with-prompt`, here
`default`. Nothing after the `fail` runs, in `digit`, in `number`'s fold,
or anywhere between them and the `with-prompt`. A procedure held across an
abandoned suspension is never called; there is no `finally` clause.

`failing` answers `Never`, the type with no values, so nothing could be
passed to its `resume`, and `(absurd never)`, of type
`(∀ (A) (Fn Never → A))`, gives the suspension whatever type the code
around it needs. Since nothing resumes such a suspension, it costs less:
it saves nothing of the computation it leaves, and only unwinds
(`tests/programs/prompt-exception.sld`). The compiler reports every source
error this way (`compile-error` in `(snail shell compiler read)`).

### The handler runs outside

A handler runs outside its `with-prompt`, so a suspension it makes goes to
the next `with-prompt` of that prompt, further out. A handler that fails
again is caught there:

```scheme
{{#include ../../../tests/programs/prompt-exception.sld:again}}
```

```text
failed: again, negative: -7
```

## Resuming

### Generators

`(resume answer)` runs the rest of the body, with `answer` as the
suspension's value, to the body's end, and answers the body's value, so
the handler may build on it:

```scheme
{{#include ../../../tests/programs/prompts.sld:collect}}
```

```scheme
{{#include ../../../tests/programs/prompts.sld:run-collect}}
```

```text
1 2 3 4 5
```

Each `yield` stops `range` and hands its value to the handler, which
conses it onto whatever the rest of the body produces. The body ends with
`(Nil)`, the answer when nothing more is yielded. A handler may also
choose, value by value, whether to resume:

```scheme
{{#include ../../../tests/programs/prompts.sld:first-above}}
```

```text
4
-1
```

### The `with-prompt` is around the rest again

Resumed, the body runs under its `with-prompt` again: its next suspension
reaches the same handler, with a new `resume` for what is left then.
`collect` above depends on it: each `(resume (unit))` runs to the next
`yield`, whose handler conses again.

### Keeping `resume`

`resume` is an ordinary function. A handler may return it inside a value,
and whoever holds that value may call it later, after the `with-prompt`
has returned:

```scheme
{{#include ../../../tests/programs/prompts.sld:step}}
```

```text
1 10 2 11 3 12 13 14
```

`start` runs a generator to its first `yield`, and the handler returns the
value with `resume` instead of calling it. `interleave` calls each `next`
long after `start` returned. Another task may call it just as well
(`tests/programs/prompt-handoff.sld`).

### Resuming once

The frames `resume` holds run at most once. The checker does not track
this: to it, `resume` is an `Fn` like any other. Instead the continuation
records that it has run, and a second call panics
(`tests/programs/prompt-resume-twice.sld`):

```scheme
{{#include ../../../tests/programs/prompt-resume-twice.sld}}
```

```text
{{#include ../../../tests/programs/prompt-resume-twice.out}}
```

A handler that never calls `resume` leaves its frames to the collector;
nothing in them runs. Multi-shot continuations are out of scope: they
would need every frame to be reachable twice, a cost paid by code that
never captures one.

### Loops in constant stack

A handler that calls `resume` in tail position runs in constant stack
(`tests/programs/prompt-tail-loop.sld`):

```scheme
{{#include ../../../tests/programs/prompt-tail-loop.sld:count-down}}
```

```text
10000100000
```

A hundred thousand suspensions grow neither the loop's stack nor the
handler's.

## Prompts

### Which `with-prompt` catches

A suspension goes to the nearest `with-prompt` of its own prompt that is
running around it, past those of other prompts. A `with-prompt` it passes
is kept with the rest of the body and is around it again when the body
resumes, so the two nest as calls do
(`tests/programs/prompt-nested.sld`):

```scheme
{{#include ../../../tests/programs/prompt-nested.sld:nested}}
```

```scheme
{{#include ../../../tests/programs/prompt-nested.sld:run-nested}}
```

```text
asking
doubling 1
doubling 20
42
```

Of two `with-prompt`s of one prompt, the inner one catches.

### A prompt is a value

A prompt made at the top level is one prompt for the whole program, which
any code that can name it may suspend to: `failing` and `yielding` above,
and the prompt every task waits on ([tasks](../runtimes/tasks.md)). A
prompt made inside a function is that call's own
(`tests/programs/prompt-local.sld`):

```scheme
{{#include ../../../tests/programs/prompt-local.sld:local}}
```

```text
("a" "b" "c")
(1 2 10 20 3)
```

The collection inside sees only its own values, though both prompts carry
an `I64`: nothing but the function a prompt was handed to can suspend to
it. `find-first` in the same file makes a prompt of its own for an early
exit that no caller's handler can intercept.

### No `with-prompt` running

A suspension needs a `with-prompt` of its prompt running around it. With
none, nothing could catch it, so `suspend` panics where it is called
(`tests/programs/prompt-unhandled.sld`):

```text
{{#include ../../../tests/programs/prompt-unhandled.out}}
```

## What a suspension passes through

A suspension unwinds through the calls between it and its `with-prompt`,
and resuming runs what they had left. Anything written in `snail-scheme`
can be left and resumed. Three places are the backend's own:

- **A function an array or string is generated by** (`array-generate`,
  `string-generate`, and what is built on them, such as `array-map`) is
  called by a loop that cannot go on from the middle. A suspension nothing
  resumes passes through it; one that may be resumed panics there
  (`tests/programs/prompt-generate.sld`).
- **A cache and a top-level value** keep a result. A call that suspended
  kept none: the next call with that key runs the function again, and the
  next read of the value runs its initializer again
  (`tests/programs/prompt-kept.sld`).
- **The host.** A suspension cannot leave through a function the host
  called to reach a `with-prompt` running beneath it; that panics.

## How the compiler knows

No type says which calls may suspend, so the compiler finds out. After
specialization, when every function is concrete, it computes what each
definition's call may suspend to, and what a call of a function value of
each type may, and tests for a suspension only after the calls that may
have one ([the compiler tour](compilers.md#suspension-and-frames)). A
prompt held by a top-level value is known by name, so a `with-prompt` of
it is known to catch its suspensions, and code that only stops, as the
compiler's passes do, pays for no frames. Code that never suspends is
compiled as if suspension did not exist.

Suspension is this translation, ordinary calls and explicit frames, and
not stack switching, so any WasmGC engine runs it and both hosts agree.
`call/cc`, `dynamic-wind` and multi-shot continuations are not language
features ([notable omissions](omissions.md)).
