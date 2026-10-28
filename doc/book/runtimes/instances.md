# Instances, queues and shared memory

*Proposed, not implemented. The design is
[#553](https://github.com/tsnl/snail-scheme/issues/553); ownership of the
handles it describes comes from [#550](https://github.com/tsnl/snail-scheme/issues/550).*

GC is the only heap, and each instance of a program is strictly
single-threaded: one Wasm instance, one GC heap, one thread. Parallel work
runs as several instances, which share nothing that the GC manages. They
talk the way processes do, through explicit queues, which makes the cost
of crossing between cores visible.

That follows from WebAssembly itself. Only linear memory can be shared
between threads; GC objects, tables and globals belong to one instance, and
a WasmGC object cannot be posted to another worker. So values cross as
bytes.

## Queues

`(snail-core queue)` copies, and works on every host, including a browser
page without cross-origin isolation.

- A queue has many senders and one receiver, like Rust's `mpsc`. Both
  endpoints are linear values. A second sender comes from an explicit
  `clone-sender`, and the receiver can tell when every sender has closed.
- Queues are bounded. A full queue makes `send` wait; `try-send` returns
  `Full`.
- Endpoints can travel inside messages, as file descriptors do.
- Typed messages through `(snail-core wire)` are a convenience on top. The
  fast path is bytes.

## Shared memory

`(snail-core shared)` is unsafe and zero-copy, and in a browser it needs
cross-origin isolation. It follows the owner's `mpmc_ndarray_queue`: a
fixed pool of equal slots in shared memory, with ordinary queues carrying
only slot indices. The queues do all the waking. Shared memory holds data
and slot headers only, never a lock or a queue, so an instance that dies
leaks its slots but cannot wedge the others.

A slot's header packs a state and a generation. Taking, publishing,
accepting and releasing a slot each move it one step, by compare-and-swap.
A copied or stale slot id therefore cannot be accepted twice, nor return
an index to the free list twice.

The runtime keeps its private memory; only programs that use the shared
tier import a second, shared memory. Programs that never share need no
isolation.

## Instances

`spawn-instance` starts another instance of the same program, from one of
its entry points, on a new worker. The host that started the program
supervises every instance. A child runs under its host's defaults and
inherits no handlers, because handlers are closures. On a reload, every
child is stopped and the shared memory is discarded before the program
relinks.
