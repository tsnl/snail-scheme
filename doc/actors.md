# Actors and their host

`createHost` in `src/app/actors.mjs` runs independent Wasm instances in Node
or a browser. It owns the actor registry, platform imports, startup work and
request mailboxes. `host.run(['client'])` starts the named roots and resolves
with the collected failures only when every actor has finished. A suspended
actor is still alive. Loading a child reserves its lifetime before any await,
and the child can outlive its parent. `spawn` also admits a root directly;
`drain` waits for the current actors, and the host may run another batch later.

Node uses `runHost(host, initial)` from `src/app/node-host.mjs`. It holds
one process-lifetime timer until drain, because an unresolved promise alone
does not keep Node alive. The timer does not poll or schedule actors.
Browser contexts and other embedders already own their platform lifetime.

The current backend uses one JavaScript execution agent and JSPI. Several
actors can wait concurrently and resume independently. It does not execute
Wasm instructions in parallel. A worker pool is a future host backend;
workers must use a transport suitable for their separate reference domains.

## A typed request and response

The [ping example](https://github.com/tsnl/snail-scheme/tree/main/examples/actors) declares `Ping` and `Pong` in one
library, both deriving `Serialize Deserialize`. Its server is:

```scheme
(: serve (-> (Mailbox Ping Pong) Unit ! actors))
(define (serve mailbox)
  (let ((ping (receive mailbox)))
    (reply mailbox (Pong (string-append "pong: " (Ping-text ping))))))

(define-actor Ping Pong serve)
```

The client uses `(ann (spawn "server") (Actor Ping Pong))` and
`(request server (Ping "hello"))`, which returns a `Pong`. `define-actor`
exports the entry and protocol check. Its optional effect list, as in
`(define-actor Unit Unit (console) run)`, declares the entry's additional
host effects. The host supplies the `actors` operations. Other defaults
come from its per-actor `imports(name)` and WASI `print(name, fd, line)`.

Spawning checks the requested protocol before entering the child. Actor
and mailbox constructors stay private. A mailbox has one current request;
other callers queue in arrival order. Replying twice or receiving another
request before replying fails. A server may request another actor while
handling a request. Cyclic requests can wait forever; no deadlock detector
or timeout is implied.

Every accepted request settles once. A server's return or trap rejects its
current and queued requests; failures propagate to waiting callers through
JSPI. Other actors continue until they finish, and `run` reports the failures
together. Parent completion does not cancel children.

## Transfer and platform requirements

The default local transport passes immutable WasmGC values directly. The
compiler's private `share-value` and `shared-value` primitives check concrete
types, recursively rejecting `Ref`, `Array`, `Any`, functions and fields
containing them. Unboxing checks the structural TypeId and the engine's
actual GC representation. Compatible modules preserve payload identity;
the integration tests compare the real GC objects on both sides.

A program descriptor with `transport: 'wire'` uses the derived binary codecs
automatically, copying borrowed bytes before suspension and decoding them
in the receiving instance. It reconstructs equal values with new identities.
No JSON conversion or hand-written field mapping is needed. Both paths use
the same immutable protocol restrictions, so choosing a transport cannot
introduce shared mutable state. Identity is not a portable protocol promise;
use an explicit identifier when the protocol needs one.

This is a trusted compiler and host boundary. Raw foreign imports,
`unsafe-cast`, and dishonest hand-written codec instances can bypass language
contracts. The actor API does not promise isolation against arbitrary Wasm
or JavaScript. Separate instances keep mutable globals and effect handlers
apart; they do not constitute a security sandbox.

`programs` maps names to functions that return `{module}` descriptors, or
`{read, manifest}` for separately compiled libraries. These functions may
be asynchronous: the host reserves the actor before calling them, so their
loading work has an owner from the start. A spawn
fails if the host lacks an imported platform operation. Linked programs use
strict host linking: every platform import in their library modules must
have a provider, including imports of otherwise unused library functions.
Application linking retains its existing optional-import behavior.

The host's imports are leaves. They enqueue work or resolve promises without
calling Wasm synchronously; actor execution begins in a later promise job.
One entry owns a set of effect-handler globals until it settles. Shared
entry helpers also restore the application runtime's handlers after return
or failure, before a reload can reuse them.

## Run the example

From the repository root, with the pinned JSPI-capable Node:

```sh
./lofi compile -I examples/actors -o build/actors/server.wasm examples/actors/server.sld
./lofi compile -I examples/actors -o build/actors/client.wasm examples/actors/client.sld
node examples/actors/run.mjs
python3 -m http.server 8000
```

Open `http://localhost:8000/examples/actors/` to run the same two actors in
the browser. Its small DOM adapter displays the client's console output;
the host has no dependency on DOM, frames, games or application macros.

Worker pools, network transport, cancellation, supervision, backpressure,
transferable resource handles and GPU packing remain proposed. This version
has one request/response protocol per actor and no session types.
