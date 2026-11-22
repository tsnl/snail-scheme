# Capabilities

What a function may do is in what it is handed. A function changes nothing,
and reaches nothing outside the program, unless one of its arguments lets
it:

- a **`Mut`**, to write;
- a **capability**, to reach the host: an output port, the file system, a
  clock, a device;
- a **prompt**, to stop short of its result
  ([suspension](suspension.md)).

There are no effect declarations, no handlers and no effect rows: a
function's type says what it takes and what it returns, and nothing about
what calling it does. What a program does to the world it does through
ordinary values, passed as ordinary arguments. A program that wants a
different world, a port that keeps what is written or a clock that stands
still, makes a different value, and a function that should not write is
not handed a `Mut`.

Every example is part of a program under `tests/programs/`, which
`make test` runs, and the output shown is that program's. Run one with

```sh
./snail-scheme run --target node tests/programs/writes.sld
```

## Writing

### A function handed nothing only computes

```scheme
{{#include ../../../tests/programs/writes.sld:compute}}
```

`square` takes a number, so a call can only compute its result. `report`
takes a port, so it may write to that port and to no other. Reading a
record field needs nothing, and neither does making a value. Traps,
non-termination and [suspension](suspension.md) are not in a function's
parameters: any function may panic, loop forever, or stop at a `suspend`
of a prompt it can name.

### `Mut`

Every field of every record can be written, and every element of an array.
A write names the `Mut` it was handed, before the place it writes:

```scheme
(set! mut (● record field) value)
(array-set! mut items index value)
(array-copy! mut to at from start count)
```

```scheme
{{#include ../../../tests/programs/writes.sld:mut}}
```

A write that names none does not compile
(`tests/programs/error-mutation-parameter.sld`):

```scheme
{{#include ../../../tests/programs/error-mutation-parameter.sld}}
```

```text
{{#include ../../../tests/programs/error-mutation-parameter.err}}
```

Nothing else stands in for one
(`tests/programs/error-mutation-token.sld`), and a function with none in
scope has nothing to name (`tests/programs/error-mutation-local.sld`),
even when the object is one it just made.

`Mut` is one token for all writing. It says that a function may write, not
which objects: a function handed a `Mut` and a record may write that
record and any other it can reach. What the token gives is the other
direction. A function handed no `Mut` writes nothing, so a signature
without one is a promise that its arguments come back unchanged.

### What a function value holds

A closure keeps what it captured, a `Mut` included:

```scheme
{{#include ../../../tests/programs/writes.sld:closure}}
```

`repeat` takes no `Mut`, and its type does not say whether `action`
writes: a function value does whatever it was made with. So what a
signature shows is this. A function whose parameters hold no `Mut`, no
capability and no function changes nothing. One that takes a function does
what that function does, as `repeat` does, and one that takes a record
holding any of these may use them.

### A `Mut` is asked for to be used

A function takes a `Mut` to write with or to hand on. A top-level
signature that asks for one its body never mentions is an error, so the
functions that take a `Mut` are the ones that may write
(`tests/programs/error-unused-mut.sld`):

```scheme
{{#include ../../../tests/programs/error-unused-mut.sld}}
```

```text
{{#include ../../../tests/programs/error-unused-mut.err}}
```

An instance method has its class method's signature, which one instance
may need less of than another: in `tests/programs/declared-mut.sld`, the
`Bool` instance of `note` takes a `Mut` and writes nothing. A definition
whose value is not a lambda is not held to the rule either.

### State with one owner

A value that is state, with one library that changes it, keeps the `Mut`
it was made with, so that using it takes none:

```scheme
{{#include ../../../tests/programs/writes.sld:owner}}
```

The holder of a `Tally` can change that tally and nothing else. A mailbox
is made this way, with `(make-mailbox mut)`, and so are the test doubles
that keep what was done to them: `(with-recorded-gpu mut work)` and
`(with-memory-dom mut script work)`.

### Storage nothing else can reach: `unsafe-mut`

```scheme
{{#include ../../../tests/programs/writes.sld:local}}
```

`(unsafe-mut)` makes a `Mut` from nothing, unchecked. It is for a
function that writes only storage it allocates, which nothing else can
reach, so that its callers need none: `(snail core base)`'s list and
string builders are written this way, and each use says in a comment why
nothing escapes. Two other places make one: a target, which is where a
program's `Mut` comes from, and a library's function that the host calls
directly, which no caller can hand one, as the scheduler's constructor is
([tasks](../runtimes/tasks.md)).

### Top-level values

A top-level value's initializer takes nothing, so it holds no `Mut` and no
capability: it can only compute
(`tests/programs/error-global-write.sld`).

```text
{{#include ../../../tests/programs/error-global-write.err}}
```

## Capabilities

### A capability is a value

`(snail core io)`'s output port is a record of the one function that
writes it, and `write-line` takes the port it writes to:

```scheme
(record OutputPort
  ((write-string (Fn String → Unit))))

(define (write-line (out OutputPort) (text String)) (→ Unit)
  (write-string out (string-append text "\n")))
```

A function that should print takes an `OutputPort`. One that takes none
cannot print, whatever it calls, unless something it is given can. A
capability is kept in a record, captured by a closure, handed to a task
and passed down like any other value.

The standard libraries' capabilities:

| Capability | Library | What holding one allows |
| --- | --- | --- |
| `Host` | `(snail core io)` | making any of the host's capabilities |
| `Arguments`, `ProcessEnvironment` | `(snail core io)` | reading what the program was started with |
| `OutputPort`, `InputPort` | `(snail core io)` | writing text; reading it |
| `Fs` | `(snail core io)` | the host's file system |
| `Clock` | `(snail core io)` | the monotonic clock |
| `Resources` | `(snail shell resource)` | reading the files a program links |
| `Wasm` | `(snail shell wasm)` | compiling and linking modules |
| `Files` | `(snail shell async-files)` | whole-file reads that wait as a task |
| `Processes`, `Signals` | `(snail shell process)` | child processes; termination signals |
| `Tcp`, `Udp` | `(snail shell socket)` | sockets |
| `Events`, `PageStorage` | `(snail shell page)` | a page's input; its saved state |
| `Gpu` | `(snail shell gpu)` | the WebGPU device |
| `Dom` | `(snail shell dom)` | a document |
| `Fetch` | `(snail shell fetch)` | requests to a server |
| `FilePicker` | `(snail shell files)` | the files a user chooses |

Each library decides what its capability is. Most are records of their
operations, each a function, so that another implementation is another
record. `Fs` holds nothing: it is the host's file system whole, and having
one is the permission.

### Making one's own

A program makes a capability as it makes any record. A port that keeps
what is written, and one that reads a text
(`tests/programs/ports.sld`):

```scheme
{{#include ../../../tests/programs/ports.sld:ports}}
```

So a test double is a value the test makes and passes: a `Clock` that
answers a fixed time, a `Tcp` whose connections are buffers
(`tests/programs/tcp-handler.sld`), the `Gpu` of
`(snail shell gpu record)`, which records each command instead of running
it, or the `Dom` of `(snail shell dom memory)`, a document in memory. Two
ports compose into one that writes both; a port over another adds a
prefix. None of this needs the language's help.

### `main` asks its target

A program's entry is its `main`, and the parameters of `main` are what the
program asks for:

```scheme
(define (main (out OutputPort) (fs Fs)) (→ Unit)
  (write-line out (read-file fs "greeting.txt")))
```

Each build names a target, `--target node` or `--target browser`, and a
target is a library, `(snail target node)` for one. A target **provides**
a type by exporting a function of no parameters that answers it:

```scheme
(define (provide-output-port) (→ OutputPort)
  (standard-output root))
```

The build calls `main` with what the providers of its parameters' types
answer, whatever the parameters' names or order. A parameter whose type
the target does not provide is a build error naming it
(`tests/programs/error-main-arguments.sld`), so a program that asks for
`Tcp` fails to build for `browser` instead of trapping when it connects.
A program names each thing it needs, and gets nothing it did not name.

| Target | Provides |
| --- | --- |
| both | `Mut`, `Host`, `Arguments`, `ProcessEnvironment`, `OutputPort`, `Clock`, `Resources`, `Wasm` |
| `node` | `InputPort`, `Fs`, `Files`, `Processes`, `Signals`, `Tcp`, `Udp` |
| `browser` | `Events`, `PageStorage`, `Gpu`, `Dom`, `Fetch`, `FilePicker` |

An exposed function of the program asks the same way: each parameter whose
type the target provides is supplied, and the rest are the host's
arguments (`tests/host-boundary/main.sld`). Only a signature asks: an
exposed function whose types are inferred is called with the host's
arguments alone. A `generate-library` recipe that needs capabilities is a
`lambda` over them, and its producer's `main` asks for those
([macros](macros.md)).

### `Host`

A `Host` is the ability to make the host's capabilities. Every function
that makes one takes it:

```scheme
(standard-output host)     ; OutputPort
(host-fs host)             ; Fs
(host-gpu host)            ; Gpu
(page-dom host events)     ; Dom
```

A target holds the one `Host` there is and makes what it provides from
it. Code that was handed neither a `Host` nor something made from one
reaches nothing of the host's, so whether a function can acquire a
capability it was not given is also in its parameters.

A `main` may ask for the `Host` itself, to make a capability later or not
at all. A program on Node makes its `Gpu` this way, so one that draws
nothing links no device
([scripts](scripts.md#targets-and-capabilities)):

```scheme
(define (main (host Host) (out OutputPort)) (→ Unit)
  (let ((gpu (host-gpu host)))
    ...))
```

### What the host itself is trusted with

The host's own capabilities answer by calling it through `extern` imports.
An extern's type is its library author's claim, trusted as written, and a
library keeps its externs behind its capability: the file externs of
`(snail core io)` are reached only through functions that take an `Fs`,
and an `Fs` is made only from a `Host`. Two functions make authority from
nothing, `unsafe-mut` and `unsafe-host`, and both are named for it: a
target calls them, and little else should. Nothing stops a library from
declaring an extern of its own; that a library takes what it uses as a
parameter is what a reader checks, by reading its imports and searching
for `unsafe-` and `extern`.
