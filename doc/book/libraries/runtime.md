# Runtime interfaces and targets

A `(snail runtime …)` library declares one host interface's WebAssembly
imports as externs, and nothing else, so it emits no module of its own. A
shell library imports it under the prefix `host-` and exports the function
that makes the host's capability, each operation an extern; a target
provides those capabilities to `main`. A program uses the shell libraries,
not these ([what the host is trusted with](../snail-scheme/capabilities.md#what-the-host-itself-is-trusted-with),
[the host boundary](../runtimes/tasks.md#the-host-boundary)).

Only scalars cross: a handle is an `I32` the host gives, a string crosses a
character or a scalar at a time, and a descriptor as staged `Bytes`. An
operation that waits starts with one call and finishes with another under
the ticket its completion wakes, through `(snail shell task)`'s
`through-host`.

## The page

`host/browser/` provides these on the page:

| Library | Declares | Made into a capability by |
| --- | --- | --- |
| `(snail runtime browser events)` | The page's event queue and its fields, the random seed, the canvas's size and the boot report | `(snail shell page)`'s `host-events` |
| `(snail runtime browser storage)` | Loading and storing the page's save, read back a byte at a time | `(snail shell page)`'s `host-storage` |
| `(snail runtime browser dom)` | The document's nodes and listeners as handles, text as UTF-8 | `(snail shell dom page)` |
| `(snail runtime browser fetch)` | Requests and event streams, staged a part at a time | `(snail shell fetch page)` |
| `(snail runtime browser files)` | The pickers, and the latest choice of files | `(snail shell files page)` |

## `(snail runtime gpu)`

The host's WebGPU device, as `host/browser/gpu.mjs` provides it on the page
and, over Dawn, on Node (`host/native/gpu.mjs`): each object an `I32` id the
host gives it when it makes it, a descriptor staged as `Bytes` of words and
texts, and the device, reads and image decodes waited for by ticket. A
submit lets go of each object destroyed since the last one.
`(snail shell gpu)` makes its `Gpu` over these.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/runtime/gpu.sld)

## Node's own

`host/native/` provides these on Node:

| Library | Declares | Made into a capability by |
| --- | --- | --- |
| `(snail runtime native socket)` | TCP and UDP sockets as handles, each wait started under its ticket and answered with numbers and held bytes | `(snail shell socket)` |
| `(snail runtime native process)` | Child processes and termination signals, answered as the sockets are; a command sent a character at a time | `(snail shell process)` |
| `(snail runtime native async-files)` | Bounded file reads, a path staged a character at a time | `(snail shell async-files)` |
| `(snail runtime native web)` | A file's length at a URL, and parts of it, answered as the sockets are; a URL sent a character at a time | `(snail shell web)` |

Each file's header tabulates what its operations answer
([the Wasm boundary](../runtimes/networking.md#wasm-boundary)).

## `(snail runtime resource)`

A linked file's bytes, read on every host when a task asks: `read` starts
under a ticket, `finish` answers the length and holds the bytes, and `byte`
reads them. `(snail shell resource)` makes its `Resources` over these.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/runtime/resource.sld)

## `(snail target node)`

The Node target, a program run by `host/native/run-snail.mjs`. `start` runs
the program's `main` as the first task of the host's scheduler, and `main`
asks for what it needs by its parameters' types; a function here of no
parameters provides each, made from the one `Host` the target holds. Every
host gives `Host`, `Arguments`, `ProcessEnvironment`, an `OutputPort`
(standard output), `Clock` and `Resources`. Node adds an
`InputPort` (standard input), `Fs`, `Files`, `Processes`, `Signals`, `Tcp`,
`Udp` and `Web`. A program that draws asks for `Host` and makes its `Gpu` with
`host-gpu` ([capabilities](../snail-scheme/capabilities.md)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/target/node.sld)

## `(snail target browser)`

The browser target, a page run by `host/browser`. As on Node, `start` runs
`main` as the first task, and `main` asks by its parameters' types. Beside
what every host gives (the `OutputPort` is the console), the page gives
`Events`, `PageStorage`, `Gpu`, `Dom`, `Fetch` and `FilePicker`.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/target/browser.sld)
