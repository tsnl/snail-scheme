# Capabilities

What a function may do to the world outside the program is in what it is
handed. A function reaches nothing of the host's unless one of its
arguments lets it: an output port, the file system, a clock, a device.
Such a value is a **capability**, and code that was handed none can reach
none.

There are no effect declarations, no handlers and no effect rows: a
function's type says what it takes and what it returns, and nothing about
what calling it does. What a program does to the world it does through
ordinary values, passed as ordinary arguments, and a program that wants a
different world, a port that keeps what is written or a clock that stands
still, makes a different value. [Suspension](suspension.md), the one way a
computation stops short of its result, is had the same way: a function
suspends to a prompt it can name.

Every example is part of a program under `tests/programs/`, which
`make test` runs, and the output shown is that program's. Run one with

```sh
./snail-scheme run --target node tests/programs/ports.sld
```

## What a signature does not say

Changing a value is not a capability. Every field of every record can be
written, and every element of an array, by whoever holds it:

```scheme
(set! (● record field) value)
(array-set! items index value)
```

So a signature says what of the host a function can reach, and not whether
it changes the values it is handed: that a function leaves its arguments
as they were is a convention, which a name ending in `!` breaks out loud
([values](values.md#mutable-records)). Two things follow.

- A capability that is a record is no exception. A function handed an
  `OutputPort` can write its field, and so change what the port does for
  everyone who holds it. Code that minds hands over a port it made for the
  purpose.
- A top-level value that is a mutable record is state every importer can
  change. A top-level value's initializer runs once, whenever the value is
  first read, so what it computes from such a record depends on when that
  is.

A type leaves out the rest of what a call may do as well: any function may
panic, loop forever, or stop at a `suspend`.

## Capabilities

### A capability is a value

`(snail core io)`'s output port is a record of the one function that
writes it, and `write-line` takes the port it writes to:

```scheme
(capability OutputPort
  ((write-string (Fn String → Unit))))

(define (write-line (out OutputPort) (text String)) (→ Unit)
  (write-string out (string-append text "\n")))
```

`capability` declares a record whose every field is a function and, for
each field, a function of the record that calls it: `(write-string out
text)` is `((● out write-string) text)`. It is a macro in
`(snail core base)` and adds nothing to the language: the type is an
ordinary record, made with `new` and read with `●`.

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

Each library decides what its capability is. Most are declared with
`capability`, records of their operations, so that another implementation
is another record. `Fs` holds nothing: it is the host's file system whole, and having
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
| both | `Host`, `Arguments`, `ProcessEnvironment`, `OutputPort`, `Clock`, `Resources`, `Wasm` |
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
and an `Fs` is made only from a `Host`. One function makes that authority
from nothing, `unsafe-host`, and is named for it: a target calls it, and
nothing else should. Nothing stops a library from declaring an extern of
its own; that a library takes what it uses as a parameter is what a reader
checks, by reading its imports and searching for `unsafe-host` and
`extern`.
