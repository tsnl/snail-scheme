# Native networking and processes

`(snail shell socket)` provides concrete, interceptable `tcp` and `udp` effects. The Node
program runner binds them to `host/native/tcp.mjs` and `host/native/udp.mjs` through
`host/native/socket-imports.mjs`: an operation that waits starts there and waits for its
ticket ([waiting on the host](tasks.md#waiting-on-the-host)), so its latent row names
`tasks`. [Child processes](#child-processes) follow the
same model, through `host/native/process.mjs` and `host/native/process-imports.mjs`. Static and separately linked programs use the
same binding. The [HTTP library](../snail-core/http.md) implements one complete
request/response exchange over TCP. Browser sockets are not implemented.
[The networking issue](https://github.com/tsnl/snail-scheme/issues/457) tracks the
remaining work.

## Snail-Core API

Import `(snail shell socket)` and include `tcp` or `udp` in the effect row of code using it.
Every operation returns `Result` with a `SocketError` whose `code` is a string
such as `"EBADF"`, `"EINVAL"` or a native network error code. Cancellation
unwinds the task; it is not a recoverable `SocketError`. TCP operations are:

| Operation | Success value |
| --- | --- |
| `listen (Endpoint address port)` | `Listener`; `Listener-port` is the actual bound port. |
| `connect (Endpoint address port)` | `Connection`. |
| `accept listener` | `Connection`. |
| `read connection maximum` | `Some Bytes` containing an available nonempty prefix, or `None` at EOF. |
| `write connection bytes` | `I32` count accepted locally, possibly smaller than the input. |
| `finish-connection connection grace` | `Unit` after ending output, discarding input and awaiting native closure; grace is an I32 millisecond deadline. |
| `close-listener listener` | `Unit`. |
| `close-connection connection` | `Unit`. |

TCP read limits are 1–65,536 bytes; one write accepts at most 65,536. Reads may
split or combine peer writes. Callers must loop to transfer an exact length.
Addresses are numeric IPv4 and ports are 0–65,535; listen port 0 selects a free
port. Hostnames, TLS and stream framing are outside this API.

UDP operations are:

| Operation | Success value |
| --- | --- |
| `bind (Endpoint address port)` | `UdpSocket`; `UdpSocket-port` is the actual bound port. |
| `send socket peer bytes` | `I32` count of the entire datagram accepted locally, including zero; never a partial prefix. |
| `receive socket maximum` | `Datagram` with an `Endpoint` peer and immutable bytes. |
| `close-udp socket` | `Unit`. |

UDP payloads and receive bounds are 0–65,507 bytes. Empty packets are messages,
not EOF. An oversized receive consumes and discards that packet with `EMSGSIZE`;
the next receive starts at the next packet. `Datagram-peer` supplies the sender's
address and port, and `Datagram-bytes` supplies the whole payload. Bind port 0
selects a free port; send destination ports are 1–65,535. UDP does not guarantee
delivery, order or uniqueness.

`Listener`, `Connection` and `UdpSocket` carry an opaque `Any` token belonging to their
handler. They are reusable values that stay within their instance. Closing
revokes all aliases; closing the same native token again succeeds. Native
token types stay private to the library. A different handler's token reaching
the native binding reports `EBADF` instead of being cast to an integer handle.
TCP and UDP owners may issue the same numeric handle, but their private token
types differ. Tokens must remain with the runtime that issued them.

A replacement `handle tcp` supplies eight operations; `handle udp` supplies four.
They may create endpoint values with their own tokens. For example, a test
can put a `Ref Bytes` in a connection token or a `Ref Datagram` in a UDP token,
accessed through operation arguments. Like any handler, the replacement
must be reusable, grade `omega`.

## Wasm boundary

The binding borrows the program's synchronous constructor/projector exports
from `(snail shell socket)`. Native I/O runs while the task is suspended. Only after its
scheduler gate returns the execution permit does the binding enter Wasm to
construct a typed `Result`. Ordinary JavaScript objects cannot substitute for
these managed values. Host code remains trusted to use the correct Snail-Core types.

Outgoing bytes are copied from staging before any other Wasm call or await.
Incoming bytes are written into a temporary managed array and copied to an
immutable vector; there is currently one helper call per byte. Endpoint text
uses bounded character projection. This simple bridge avoids a global reply
slot or callback protocol; bulk copying can be optimized separately.

A pending acquisition carries its native handle and bound-port metadata, where
applicable. The scheduler disposes a successful acquisition if cancellation wins
before delivery. A trap constructing its managed wrapper also closes the handle.
Successful delivery transfers responsibility to user code: close explicitly, or
leave cleanup to runtime shutdown. There is no implicit last-use socket drop or
task-scoped socket owner. Cancelling an unrelated task does not close a delivered
endpoint. The runner cancels/drains tasks, closes all socket resources, then closes
its scalar resources when execution ends or initialization fails.

## TCP operations

Each `createTcp()` owns one set of native resources and its own positive I32
handle namespace. Handles never repeat within that owner. They are not global
identities, transferable capabilities or references to Wasm-managed objects.
Every operation must use the owner that issued its handle.

| Operation | Result |
| --- | --- |
| `listen(signal, address, port)` | Listener handle after binding; port 0 chooses a free port. |
| `port(listener)` | The listener's bound port. |
| `connect(signal, address, port)` | Connected socket handle. |
| `accept(signal, listener)` | One connection, independent of its listener after delivery from this operation. |
| `read(signal, connection, maximum)` | A nonempty available byte prefix, or `null` at EOF. The limit is 1–65,536. |
| `write(signal, connection, bytes)` | A count of bytes accepted locally, at most 65,536; empty input returns 0. |
| `finish(signal, connection, grace)` | End output, discard input and await physical closure; grace bounds graceful progress in milliseconds. |
| `close(handle)` | Immediate revocation of aliases and initiation of native cleanup; repeated close does nothing. |
| `shutdown()` | Reject new work, close all resources, and await native cleanup. |

Addresses are numeric IPv4 and ports are 0–65,535. There is one pending accept
per listener and at most one pending read and one write per connection; a read
and write can overlap. Duplicate operations fail with `EBUSY`, revoked handles
with `EBADF`, and invalid arguments with `EINVAL`. Native network errors retain
their codes. Receiving EOF leaves the connection writable; available bytes are
read before EOF. No operation promises peer receipt or message framing.

Write borrows its bytes unchanged until settlement. The Wasm binding copies
staging memory before awaiting; native callers must not mutate or detach
the supplied storage. A cancelled write may already have transmitted bytes, so
retrying the whole buffer is not automatically safe.

### Finishing a connection

Snail-Core's `finish-connection` binds the native `finish` operation. It takes an idle
connection and a whole-number grace period from 0
through 2,147,483,647 milliseconds. Pending read or write rejects with `EBUSY`
without changing ownership. Invalid grace rejects with `EINVAL`.

Once accepted, `finish` ends output and consumes remaining input without keeping
it. Node's `writableEnded` state prevents aliases from starting further I/O;
`close` can still abort the connection. EOF plus completed output lets Node close
the socket naturally. This staged teardown avoids discarding a final HTTP
response when unread input remains; see [RFC 9112 §9.6](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.6).
Success reports local completion, not proof that the peer application processed
the response.

The deadline is elapsed time, not an idle timeout renewed by incoming data.
Expiry forces closure and reports `ETIMEDOUT`; zero means immediate expiry.
Cancellation preserves its exact reason. Transport failure, explicit close,
timeout or cancellation records the first cause; clean native closure records
success. A later cancellation cannot rewrite that native outcome, although the
task scheduler can still reject delivery to a cancelled task. Every accepted
finish waits for physical closure before settling. The grace bounds graceful
progress; forced cleanup still needs event-loop scheduling.

## Ownership and cancellation

Node accepts eagerly. A listener retains at most 64 unclaimed connections in a
paused state, using native stream buffers. Overflow connections close immediately.
Revoked queued connections are skipped by accept. Cancelling accept leaves its
listener and unclaimed connections usable; closing a listener releases its queue
but leaves already handed-out connections independent.

Native ownership lasts from creation through the close callback. A public handle
exists only after successful listen/connect/accept. Immediate close removes it;
graceful finish disables ordinary I/O but retains the handle for an explicit
abort until physical closure. Failed creation and rejected incoming sockets therefore participate in
shutdown without receiving a handle. Exhausting the handle namespace reports
`EMFILE`; an accept that cannot publish leaves its connection listener-owned.

Cancelling listen/connect closes the pending resource and waits for cleanup.
Cancelling an installed read or write closes that connection and wakes its other
pending operation. Completed operations detach cancellation. A success arriving
just before cancellation is checked again before it can publish a handle or
write count. Abort failures preserve the task's exact cancellation reason.

Ordinary close does not wait: Node can defer a listener's close callback until
its handed-out connections finish. Shutdown closes those connections too and
waits for all ownership, including late arrivals during listener closure.
The task scheduler separately owns successful native results until delivery;
the binding supplies its disposer when a cancelled task cannot receive a newly
created handle. No native cleanup record retains a managed wrapper.

## Native UDP owner

`host/native/udp.mjs` owns IPv4 datagram sockets behind the `udp` effect. It is tested
against real loopback sockets, including forced asynchronous native sends.
It uses Node's [synchronous numeric bind](https://nodejs.org/api/dgram.html#socketbindsyncoptions),
available from 26.4. Binding is a nonblocking local operation, so it needs no
opening state, DNS lookup or bind cancellation registration.

| Operation | Result |
| --- | --- |
| `bind(signal, address, port)` | Positive I32 handle; port 0 selects an available port. |
| `port(handle)` | The actual bound port. |
| `receive(signal, handle, maximum)` | One whole datagram: `{bytes, address, port}`, including the sender's endpoint. |
| `send(signal, handle, address, port, bytes)` | Entire payload length after local completion; no peer delivery guarantee. |
| `close(handle)` | Immediate alias revocation and initiation of cleanup; repeated close does nothing. |
| `shutdown()` | Stop new binds, close remaining sockets and await native cleanup. |

Handles never repeat within their owner, including after failed bind attempts.
Addresses must be numeric IPv4; send destination ports are 1–65,535. A payload
may contain 0–65,507 bytes. Zero-length datagrams are messages, not EOF.
Receive accepts a maximum in the same range. If the next datagram is too large,
it is consumed and discarded with `EMSGSIZE`; there is no partial result or
remainder to read. Oversized sends fail before native submission. UDP makes no
delivery, order or uniqueness guarantee.

Each socket queues at most 32 complete datagrams; excess arrivals are dropped,
preserving the queued messages. One receive and one send may be pending at a
time and may overlap; duplicates fail with `EBUSY`. Receive cancellation removes
its registration and preserves the socket and remaining queue. A datagram
already consumed before cancellation wins is not requeued.

Send borrows immutable bytes until its callback. The Wasm binding snapshots
staging before calling it. Cancelling send waits for native completion and
then rejects with the exact cancellation reason. It cannot retract the datagram.
A send callback failure affects that operation; a socket-level error closes
the socket. Closing wakes pending receives and discards queued datagrams.

Node still resolves numeric send addresses asynchronously. Closing during that
lookup can suppress the send callback, and a native close event can otherwise
precede pending send completion. The owner therefore revokes aliases immediately
but defers native close until the single send settles. The closed record remains
owned until its close event. Shutdown cannot finish while that send or cleanup
is outstanding. Failed bind closes and awaits cleanup before rejecting.

As for TCP, the scheduler owns successful acquisitions until delivery; the shared
binding supplies the existing native disposer. The owner adds no second
delivery protocol and retains no managed wrapper.

## Child processes

`(snail shell process)` provides the `process` effect: child processes with
their standard streams piped to the program. Import it and include `process`
in the effect row of code using it. Every operation returns `Result` with a
`ProcessError` whose `code` is a string such as `"EBADF"` or a native error
code. As for sockets, cancellation unwinds the task.

| Operation | Success value |
| --- | --- |
| `spawn (Command program arguments directory)` | `Process`; `Process-id` is the operating system's process id. |
| `read-output process stream maximum` | `Some Bytes`, an available nonempty prefix of `(Stdout)` or `(Stderr)`, or `None` at its end. |
| `write-input process bytes` | `I32` count of bytes the pipe took, at most 65,536. |
| `close-input process` | `Unit`; the child reads EOF once written bytes drain. |
| `send-signal process signal` | `Unit` after sending `(Terminate)`, `(Kill)` or `(Interrupt)`. |
| `wait-exit process` | `(Exited code)`, or `(Signaled name)` with the signal's name, such as `"SIGTERM"`. |
| `close-process process` | `Unit`. |

A `Command`'s program is found on `PATH` when it has no slash; its
arguments follow the name it is run as, and it runs in `directory`. The
program is a field of its own, so no command is empty. A missing executable
or directory is `ENOENT`, an argument the platform cannot pass (one with a
NUL) is `EINVAL`, and a signal to a child that has exited is `ESRCH`.
Writing after `close-input` is `EPIPE`.

Output stays in the pipe until it is read, even after the child exits, so
waiting first and reading after loses nothing. The pipes keep backpressure,
though: a child that writes more than a pipe and its stream buffer hold,
about 64 KiB each, blocks until it is read, so a program expecting more
output than that reads while it waits. Read limits are 1–65,536
bytes. There is one pending read per stream and one pending write; a read
of each stream and a write can overlap, and any number of `wait-exit`s may
be pending. A write waits until the pipe takes its bytes, so a child that
does not read holds it. Closing a process that is still running kills it
with SIGKILL and revokes the handle, as closing a socket does; closing it
again succeeds. A `Process` carries an `Any` token belonging to its handler,
and a different handler's token reaching the native binding is `EBADF`.
`tests/programs/process.sld` runs `/bin/sh` through each operation.

### Termination

The `signals` effect, also in `(snail shell process)`, has one operation,
`(termination)`, which waits for SIGINT or SIGTERM and returns
`(Interrupt)` or `(Terminate)`. A program opts in by waiting: a signal that
arrives while tasks wait in `termination` is the result of every such wait,
and one that arrives while none waits ends the program, as it always has.
A service runs a task that waits for termination and then shuts down in
order, here by terminating a child and waiting for it:

```scheme
(dispatch-local
 (once (lambda ()
         (termination)
         (send-signal child (Terminate))
         (wait-exit child))))
```

A wait ends with its signal, so a second Ctrl-C during that shutdown ends
the program at once, unless a task waits again. A second Ctrl-C that comes
so quickly it is still on its way while the first ends the wait is kept for
the program's next wait instead, at most one, so a double tap reaches a
program that waits again, and does not end one that does not. There is no window between
a task's starting to wait and the signal's reaching it: in Node only the
main thread receives signals, and the program runs on a worker, so the
worker counts its waiters in shared memory and the main thread reads the
count when a signal arrives. With waiters it forwards the signal to the
worker; without, it removes its handlers and raises the signal again, so
the process ends by that signal, with the status Node's default gives. A
signal forwarded to a worker whose last waiter was cancelled on the way is
raised again the same way. The worker tells the two apart by a second
count in the shared memory, of the deliveries that ended waits: the main
thread stamps each signal it forwards with the count it read, and a
signal that finds no waiter after a newer delivery came with that one.
`tests/termination/check.mjs` sends SIGTERM and SIGINT to a waiting
program, which observes each and exits cleanly, and SIGTERM to one that
does not wait, which it ends, and delivers a double tap with the stamps
the main thread would give it.

### The process boundary

`createProcesses()` in `host/native/process.mjs` owns one set of children
behind positive I32 handles, which never repeat within that owner. A child is
owned from spawn until it has exited and its pipes have closed; its public
handle exists from a successful spawn until close. `process-imports.mjs`
reads a command a character at a time through the library's exposed
projections, and builds every result in Wasm after the waiting task
reacquires the execution permit, as `socket-imports.mjs` does.

| Operation | Result |
| --- | --- |
| `spawn(signal, directory, program, arguments)` | `{handle, pid}` once Node reports the child running. |
| `read(signal, handle, descriptor, maximum)` | A nonempty prefix of stream 1 or 2, or `null` at its end. |
| `write(signal, handle, bytes)` | A count after the pipe accepts it. |
| `closeInput(handle)` | Ends input. |
| `kill(handle, number)` | Sends signal 15, 9 or 2, the numbers the library gives. |
| `wait(signal, handle)` | `{code}` or `{signal}` once the child exits. |
| `close(handle)` | Revokes the handle, kills a running child and destroys its pipes. |
| `shutdown()` | Rejects new spawns, closes every child and waits until each has exited. |

`createTermination(waiting)` in the same file holds the termination waiters
and publishes their number in `waiting`, the shared `Int32Array` the main
thread reads: `wait(signal)`
resolves with the signal's number, 2 or 15, and `deliver({name, deliveries})`
resolves every waiter, keeps a signal that came alongside the last
delivery, or raises the signal again.

Node discards a child's output when it exits unless a `'readable'` listener
is waiting for it, so each output stream keeps one, and its bytes wait in
the stream until `read`. A successful spawn waiting for delivery belongs to
the scheduler; if its task is cancelled first, the binding's disposer closes
the handle, which kills the child. Cancelling a read consumes nothing and
leaves the process usable; cancelling a pending write destroys the child's
input, since the bytes may be partly written. The runner shuts the owner down
with the socket owners when a program ends, so no child outlives a program
that ends normally. Only the child is killed: a process it started, as a
shell does for a command it does not `exec`, is the child's to end. No native record retains a managed wrapper. The browser has
no processes and no `snail.runtime.native.process` imports, so a program performing
`process` links only on the native runner.
