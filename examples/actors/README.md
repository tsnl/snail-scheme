# Library actors on WasmGC

This runnable prototype compiles an ordinary Scheme library into an actor
artifact. A Node host starts a subprocess, initializes the library once, and invokes
its exported procedures. Each subprocess owns a separate WasmGC instance and globals.
Chibi hosts compilation; the handlers execute as compiled Wasm.

Read the application in [counter.sld](counter.sld) and its host in
[run.mjs](run.mjs). Read the reusable connection API separately in
[runtime/actors.mjs](../../runtime/actors.mjs), the Wasm embedding in
[runtime/actor-instance.mjs](../../runtime/actor-instance.mjs), and the Scheme
codec in [actor-wire.sld](../../src/snail-scheme/actor-wire.sld).

## Run it

Use the development tools described in the repository README, then:

```sh
./snail-scheme --actor examples/actors/counter.sld -o build/actors/counter.wasm
node --no-warnings examples/actors/run.mjs build/actors/counter.wasm
```

Expected output:

```text
first: 3
second: 0
first through another connection: 3
data stays data: (|set!| |count| 99)
```

The first actor retains its counter between calls. The second starts at zero.
Closing the first connection leaves its actor and the observer connection alive.
The `set!` list is returned as data; no received expression is evaluated.

## Follow a call

```js
const actor = await spawn('build/actors/counter.wasm');
const connection = actor.connect();
try {
  console.log(await connection.call('(add 3)')); // S-expression text: "3"
} finally {
  connection.close();
  await actor.stop();
}
```

`spawn` owns worker lifetime and resolves after initialization. `connect` creates
an independent endpoint to that existing actor. `call` accepts exactly one
`(method argument ...)` datum as text and returns a promise of result text.
Connections correlate outstanding calls; closing one rejects its pending calls.
It does not cancel work already sent, roll back effects, or destroy the actor.
`stop` rejects every connection's pending calls and waits for worker termination.
It is safe to call more than once.

The local transport uses S-expression frames containing a connection ID, request
ID, and payload. Only text crosses the worker boundary. The Scheme reader parses
the payload, and the host looks up the exact exported method name. Renamed exports
work; private definitions and macro exports are unavailable. Exported values must
be procedures to be invoked. Each handler returns one portable datum.

Inside the worker, AWI roots keep decoded arguments and results alive across
allocations and Rust callbacks. These handles never leave that instance. The
codec reads with the existing `reader.sld` / `syntax-parser.sld` and prints a
readable result, quoting symbols explicitly.

## What this establishes

Actors can compute concurrently in different subprocesses. Each Scheme call currently
runs synchronously to completion within its worker. A JavaScript promise lets
the supervisor continue; it does not provide Scheme suspension, reentrant
handlers, streams, or `task-run`. Those need the planned continuation support.

The initial portable subset is booleans, signed 64-bit exact integers, strings,
symbols, pairs (including dotted lists), and vectors. Sharing is copied as data;
cycles, procedures, records, ports, zero/multiple return values, and other kinds
are rejected. Type-derived record/variant codecs remain planned; this datum codec
does not introduce a second application schema. Message text is limited to 65,536
UTF-16 code units by the transport. Datum validation limits pair/vector edge depth
to 64 and tree weight to 16,384, counting nodes and string/symbol characters.
Depth and weight are checked **after reading**; the existing reader has no bounded
parsing allocation contract. These are codec limits, not a heap-budget proof.

Any worker-side decoding, dispatch, execution, or encoding failure terminates the
worker. All its connections fail, including calls whose effects may already have
happened. A trap can bypass Rust cleanup, so the host discards the instance without
calling back into it. Explicit Scheme cleanup is still necessary for application
resources with external lifetimes; worker shutdown does not promise finalizers,
device completion, or transactional rollback. The prototype grants WASI stdio
and a trace directory, with no application filesystem configuration yet.

This spawner uses subprocesses because terminating Node worker threads left WASI
trace descriptors open in retirement checks. Process termination lets the OS close
those descriptors, even if Scheme is looping. A future thread spawner needs an
explicit native resource teardown contract. This host requires explicit `stop`
from its supervisor; it does not yet provide OS-enforced child cleanup if the
supervisor itself crashes while a child is busy.

To replace code, build another artifact, spawn it, and connect to the new actor.
Existing actors retain their existing code and state until stopped. Automatic
rebuild, connection switching, and state migration are future work.

WasmGC owns collection. This host cannot enforce a 32-bit Scheme object layout,
per-actor GC budgets, or `no-gc`; worker isolation alone does not supply them.
Scheme-side connection operations, browser/DOM hosting, native actor providers,
network connectors, service discovery,
staged builds, and the three full tutorial applications remain planned.

## Check it

```sh
scripts/test-actors
```

The test compiles and executes linked Wasm, checking independent globals, renamed
exports, Unicode and exact integer transport, data-only decoding, root ownership,
connection closure, actor death, and stopping an infinite loop while a sibling
continues. It also verifies that startup failures reject the spawn operation.
