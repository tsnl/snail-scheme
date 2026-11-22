# Capabilities and rows

A function's type says what it returns. Two more things say what calling it
may do besides:

- its **row**, after `!`, says whether it may change anything outside its
  own values: `mut`, the one effect;
- its **parameters** say what it may change. A function writes to the
  output port it is given, reads the files of the file system it is given,
  and draws on the device it is given. Such a value is a **capability**,
  and code that was handed none can reach none.

There are no effect declarations and no handlers. What a program does to
the world it does through ordinary values, passed as ordinary arguments,
and a program that wants a different world, a port that keeps what is
written or a clock that stands still, makes a different value.
[Suspension](suspension.md), the one way a computation stops short of its
result, is a separate mechanism and is not in rows at all.

Every example is part of a program under `tests/programs/`, which
`make test` runs, and the output shown is that program's. Run one with

```sh
./snail-scheme run --target node tests/programs/effects-basic.sld
```

## Rows

### `mut`

A function type may end in `!` and a row. A function without `!` is total:
a call can only compute its result.

The empty row is written `(!)` when used as a row argument or definition
header clause. In a function type, `(Fn I64 → I64)` and `(Fn I64 → I64 !)`
mean the same closed, empty row. An omitted effect clause in an otherwise
typed definition also means empty; a definition with no signature infers
its row. An empty row is not a row variable such as `e`: it cannot acquire
`mut` through instantiation.

```scheme
{{#include ../../../tests/programs/effects-basic.sld:rows}}
```

`write-line` performs `mut`, so `report` does too. A total function may not
call it, even when it holds the port. `tests/programs/error-effect.sld`:

```scheme
{{#include ../../../tests/programs/error-effect.sld}}
```

fails to compile:

```text
{{#include ../../../tests/programs/error-effect.err}}
```

`mut` covers writes to object fields, mutable sequence operations, and
every use of a capability: writing a port, reading a file or a clock,
asking the host anything. Reading a record field is pure, and so is making
a value. Traps, non-termination and [suspension](suspension.md) are not
tracked: a total function may still panic, loop forever, or stop at a
`suspend`.

### Inference and signatures

Rows are inferred by unification, as types are, so nothing inside a
definition needs a row written. A definition without a signature gets the
row its body performs. A top-level signature states the row, and the body
is checked against it both ways: the body may perform `mut` only if the row
names it, and the row may name it only if the body performs it.

```scheme
{{#include ../../../tests/programs/effects-basic.sld:inferred}}
```

```text
squared 49
```

A call requires its callee's row to fit the row of the code around it, so a
total function could call `square` but not `report-square`.

### Claiming only what the body performs

The second half is the unused-effect rule. A top-level definition whose
signature names `mut`, or a tail variable such as `e`, that no call in its
body performs is an error at the signature.
`tests/programs/error-unperformed-effect.sld`:

```scheme
{{#include ../../../tests/programs/error-unperformed-effect.sld}}
```

```text
{{#include ../../../tests/programs/error-unperformed-effect.err}}
```

A row is a promise to callers about what may happen. Some signatures have
no body to hold them to. An instance method keeps its class method's row,
which one instance may need less of than another: in
`tests/programs/declared-effects.sld`, the `Bool` instance of `announce`
performs nothing and keeps `! mut`. `extern` declarations, class method
signatures and definitions whose value is not a lambda are not compared
either. A signature that a macro writes is held to each expansion.

### Row polymorphism

A higher-order function performs whatever its argument performs. A row
variable, quantified like a type variable, stands for that:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:polymorphic}}
```

```text
squared 1
squared 4
squared 9
```

Here `e` is `mut`; with a total `action`, `repeat` is total. `map` in
`(snail core base)` has the same shape:
`(∀ (A B e) (Fn (Fn A → B ! e) (List A) → (List B) ! e))`.

A row with a tail fits a larger row with the same tail: `e` fits `mut e`.
The reverse does not hold, and two unrelated tails never fit each other
(`tests/programs/error-effect-row-tail.sld`).

### Subsumption

A function value fits a function type whose row includes its own: a pure
function can run wherever `mut` is allowed. This holds wherever a value
meets a type, as an argument, a result, or a field it initializes or is
written to:

```scheme
{{#include ../../../tests/programs/effect-subsumption.sld:subsumption}}
```

Rows widen through the parts of a type that only hand values out:

- A function type widens its result and its row and narrows its
  parameters. A function that accepts any writing thunk fits where only
  pure thunks will be passed.
- An enum's type arguments widen, since an enum's fields are never
  written: `(List (Fn → Unit))` fits `(List (Fn → Unit ! mut))`.
- A record's type arguments must be equal. Its fields can be written, so
  a pair widened to hold writing functions could have one written into it
  that a reader of the original pair would call as pure
  (`tests/programs/error-subsumption-record.sld`).

Nothing but rows ever differs, so a value keeps its representation when
it fits a wider type, and nothing converts it at run time. Fitting a
narrower row is a type mismatch
(`tests/programs/error-subsumption-narrow.sld`). A type or row still being
inferred is unified, as everywhere else.

### Local mutation

Mutation is explicit even when the storage never leaves the function that
allocates it:

```scheme
{{#include ../../../tests/programs/effects-basic.sld:local}}
```

```text
sum 14
```

Allocation and field reads do not perform `mut`; a write does, whatever is
written to. `unsafe-total` runs a thunk and discards its row without a
check, for a function that mutates only storage nothing else can reach and
should read as total, as `(snail core base)`'s list and string builders do;
each use says in a comment why nothing escapes.

### What a row cannot hide

An `Any`'s TypeId records no rows, so a function that performs `mut`
converted to `Any` and back could be called as a total one. No function
that performs `mut` converts to `Any`
(`tests/programs/error-downcast-function.sld`,
[dynamic values](types.md#dynamic-values)). A top-level value's
initializer has no row at all, so it performs nothing
(`tests/programs/error-global-effect.sld`).

## Capabilities

### A capability is a value

`(snail core io)`'s output port is a record of the one function that
writes it, and `write-line` takes the port it writes to:

```scheme
(record OutputPort
  ((write-string (Fn String → Unit ! mut))))

(define (write-line (out OutputPort) (text String)) (→ Unit) (! mut)
  (write-string out (string-append text "\n")))
```

A function that should print takes an `OutputPort`. One that takes none
cannot print, whatever it calls, unless something it is given can: what a
function may do to the world is in its parameters and in what they hold.
A capability is kept in a record, captured by a closure, handed to a task
and passed down like any other value.

The standard libraries' capabilities:

| Capability | Library | What holding one allows |
| --- | --- | --- |
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
(`tests/programs/port-effects.sld`):

```scheme
{{#include ../../../tests/programs/port-effects.sld:ports}}
```

So a test double is a value the test makes and passes: a `Clock` that
answers a fixed time, a `Tcp` whose connections are buffers
(`tests/programs/tcp-handler.sld`), the `Gpu` of
`(snail shell gpu record)`, which records each command instead of running
it, or the `Dom` of `(snail shell dom memory)`, a document in memory. Two
ports compose into one that writes both; a port over another adds a
prefix. None of this needs the language's help.

### `main` asks its target

A program's entry is its `main`, and the parameters of `main` are the
capabilities the program asks for:

```scheme
(define (main (out OutputPort) (fs Fs)) (→ Unit) (! mut)
  (write-line out (read-file fs "greeting.txt")))
```

Each build names a target, `--target node` or `--target browser`, and a
target is a library, `(snail target node)` for one. A target **provides** a
type by exporting a function of no parameters that answers it:

```scheme
(define (provide-output-port) (→ OutputPort)
  (standard-output))
```

The build calls `main` with what the providers of its parameters' types
answer, whatever the parameters' names or order. A parameter whose type the
target does not provide is a build error naming it
(`tests/programs/error-main-arguments.sld`), so a program that asks for
`Tcp` fails to build for `browser` instead of trapping when it connects.
There is no object that holds everything a host has: a program names each
thing it needs, and gets nothing it did not name.

| Target | Provides |
| --- | --- |
| both | `OutputPort`, `Clock`, `Resources`, `Wasm` |
| `node` | `InputPort`, `Fs`, `Files`, `Processes`, `Signals`, `Tcp`, `Udp` |
| `browser` | `Events`, `PageStorage`, `Gpu` |

A capability made from others is made by the program: a page's `Dom` comes
from its `Events` (`page-dom` in `(snail shell dom page)`), and its
`Fetch` and `FilePicker` from nothing (`page-fetch`, `page-file-picker`).
A program on Node makes its `Gpu` itself, `(host-gpu)`, so one that draws
nothing links no device ([scripts](scripts.md#targets-and-capabilities)).

An exposed function asks the same way: each parameter whose type the
target provides is supplied, and the rest are the host's arguments
(`tests/socket-boundary/main.sld`). A `generate-library` recipe that needs
capabilities is a `lambda` over them, and its producer's `main` asks for
those ([macros](macros.md)).

### What the host itself is trusted with

The host's own capabilities answer by calling it through `extern` imports.
An extern's type is its library author's claim, trusted as written, and a
library keeps its externs behind its capability: the file externs of
`(snail core io)` are reached only through functions that take an `Fs`.
The functions that make a host's capability, `standard-output`, `host-fs`,
`host-gpu` and the like, are for targets and for the few programs that
make one deliberately. Nothing stops a library from calling them, as
nothing stops it from declaring an extern; that a library takes what it
uses as a parameter is the convention every library here follows, and what
a reader checks.
