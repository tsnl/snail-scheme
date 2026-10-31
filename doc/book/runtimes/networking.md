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
unwinds the task; it is not a recoverable `SocketError`.

An `Endpoint` is an IPv4 address and a port, and only `(endpoint address
port)` makes one, from dotted text: four decimal octets from 0 to 255
without leading zeros, and a port from 0 to 65,535, or `EINVAL`. The type
is exported without its constructor, so holding an `Endpoint` is evidence
that both are usable, and no host checks them again. `Endpoint-address`
gives the dotted text and `Endpoint-port` the port. Hostnames are outside
this API. TCP operations are:

| Operation | Success value |
| --- | --- |
| `listen endpoint` | `Listener`; `Listener-port` is the actual bound port. |
| `connect endpoint` | `Connection`. |
| `accept listener` | `Connection`. |
| `read connection maximum` | `Some Bytes` containing an available nonempty prefix, or `None` at EOF. |
| `write connection bytes` | `I32` count accepted locally, possibly smaller than the input. |
| `finish-connection connection grace` | `Unit` after ending output, discarding input and awaiting native closure; grace is an I32 millisecond deadline. |
| `close-listener listener` | `Unit`. |
| `close-connection connection` | `Unit`. |

TCP read limits are 1–65,536 bytes; one write accepts at most 65,536. Reads may
split or combine peer writes. Callers must loop to transfer an exact length.
Listen port 0 selects a free port. TLS and stream framing are outside this
API.

UDP operations are:

| Operation | Success value |
| --- | --- |
| `bind endpoint` | `UdpSocket`; `UdpSocket-port` is the actual bound port. |
| `send socket peer bytes` | `I32` count of the entire datagram accepted locally, including zero; never a partial prefix. |
| `receive socket maximum` | `Datagram` with an `Endpoint` peer and immutable bytes. |
| `close-udp socket` | `Unit`. |

UDP payloads and receive bounds are 0–65,507 bytes. Empty packets are messages,
not EOF. An oversized receive consumes and discards that packet with `EMSGSIZE`;
the next receive starts at the next packet. `Datagram-peer` supplies the sender's
address and port, and `Datagram-bytes` supplies the whole payload. Bind port 0
selects a free port; a send to port 0 fails with `EINVAL` before it reaches
the host. UDP does not guarantee
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

`(snail runtime native socket)` declares the interface, and only numbers
cross it. A listener, connection or UDP socket crosses as its handle, and
an endpoint as two I32s: its port, and its address, whose four octets are
the I32's unsigned bits, most significant first. The host enters no Wasm
and builds no managed value. `(snail shell socket)` builds every `Result`
itself, in the waiting task's own call, from what the host answers.

Native I/O runs while the task waits on its ticket. The task's `finish`
then answers with a number: -1 for a failure, and otherwise the
operation's own number, such as a handle or a count. The host holds what
else the answer carries until it answers again
(`host/native/answers.mjs`):
- a number, such as a listener's port;
- byte strings, such as the bytes read or a failure's error code.

The shell reads them at once, before its next host call, a call per byte.
The runtime library's header has the table of what each operation answers.
A datagram's sender is held as Node's dotted text, which `endpoint` parses.
Outgoing bytes are copied from staging before any other Wasm call or await.

A pending acquisition carries its native handle and bound-port metadata, where
applicable. The scheduler disposes a successful acquisition if cancellation wins
before delivery. Once `finish` answers with a handle, the handle is the shell's.
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
| `listen(signal, address, port, backlog)` | Listener handle after binding; port 0 chooses a free port. |
| `port(listener)` | The listener's bound port. |
| `connect(signal, address, port)` | Connected socket handle. |
| `accept(signal, listener)` | One connection, independent of its listener after delivery from this operation. |
| `read(signal, connection, maximum)` | A nonempty available byte prefix of at most `maximum` bytes, or `null` at EOF. |
| `write(signal, connection, bytes)` | A count of bytes accepted locally, at most 65,536; empty input returns 0. |
| `finish(signal, connection, grace)` | End output, discard input and await physical closure; grace bounds graceful progress in milliseconds. |
| `close(handle)` | Immediate revocation of aliases and initiation of native cleanup; repeated close does nothing. |
| `shutdown()` | Reject new work, close all resources, and await native cleanup. |

The arguments are the library's, which decided them, and the host checks
none of them again: the address is the dotted text of an `Endpoint`'s and
the port its port, a read's maximum is 1–65,536, a grace is not negative,
and the backlog is how many unclaimed connections the listener keeps, 64.
There is one pending accept
per listener and at most one pending read and one write per connection; a read
and write can overlap. Duplicate operations fail with `EBUSY` and revoked
handles with `EBADF`. Native network errors retain
their codes. Receiving EOF leaves the connection writable; available bytes are
read before EOF. No operation promises peer receipt or message framing.

Write borrows its bytes unchanged until settlement. The Wasm binding copies
staging memory before awaiting; native callers must not mutate or detach
the supplied storage. A cancelled write may already have transmitted bytes, so
retrying the whole buffer is not automatically safe.

### Finishing a connection

Snail-Core's `finish-connection` binds the native `finish` operation. It takes an idle
connection and a grace period in milliseconds, which the library refuses
with `EINVAL` when it is negative. Pending read or write rejects with `EBUSY`
without changing ownership.

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

Node accepts eagerly. A listener retains at most its backlog of unclaimed
connections in a paused state, using native stream buffers. Overflow connections close immediately.
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
| `bind(signal, address, port, queued)` | Positive I32 handle; port 0 selects an available port. |
| `port(handle)` | The actual bound port. |
| `receive(signal, handle, maximum)` | One whole datagram: `{bytes, address, port}`, including the sender's endpoint. |
| `send(signal, handle, address, port, bytes)` | Entire payload length after local completion; no peer delivery guarantee. |
| `close(handle)` | Immediate alias revocation and initiation of cleanup; repeated close does nothing. |
| `shutdown()` | Stop new binds, close remaining sockets and await native cleanup. |

Handles never repeat within their owner, including after failed bind attempts.
Addresses and ports come from `Endpoint`s, as for TCP. The library limits a
payload and a receive's maximum to 0–65,507 bytes, refusing an oversized
send with `EMSGSIZE` before it reaches the host. Zero-length datagrams are
messages, not EOF. If the next datagram is larger than a receive's maximum,
it is consumed and discarded with `EMSGSIZE`; there is no partial result or
remainder to read. UDP makes no delivery, order or uniqueness guarantee.

`queued` is how many complete datagrams the
socket queues, 32 from the library; excess arrivals are dropped,
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
| `run (Command …) input` | `(Captured exit stdout stderr)`, once the command has run to its end with `input`, a `Bytes`, as its standard input. |
| `exec (Command …)` | Nothing: the command replaces the program. It returns a `ProcessError`, not a `Result`, and only when the command could not start. |

A `Command`'s program is found on `PATH` when it has no slash, as execvp
finds it: in the first entry holding a regular file the process may
execute, where an empty entry is the command's directory and a relative
one is taken from it. `(snail shell process)` searches, for `spawn`, `run`
and `exec` alike, and the program still runs as the name it was given.
Its arguments follow that name, and it runs in `directory`. The
program is a field of its own, so no command is empty. A missing executable
or directory is `ENOENT`, an argument the platform cannot pass (one with a
NUL) is `EINVAL`, and a signal to a child that has exited is `ESRCH`.
Writing after `close-input` is `EPIPE`.

Output stays in the pipe until it is read, even after the child exits, so
waiting first and reading after loses nothing. The pipes keep backpressure,
though: a child that writes more than a pipe and its stream buffer hold,
about 64 KiB each, blocks until it is read, so a program expecting more
output than that reads while it waits. Read limits are 1–65,536
bytes, which the library checks. There is one pending read per stream and one pending write; a read
of each stream and a write can overlap, and any number of `wait-exit`s may
be pending. A write waits until the pipe takes its bytes, so a child that
does not read holds it. Closing a process that is still running kills it
with SIGKILL and revokes the handle, as closing a socket does; closing it
again succeeds. A `Process` carries an `Any` token belonging to its handler,
and a different handler's token reaching the native binding is `EBADF`.
`tests/programs/process.sld` runs `/bin/sh` through each operation.

`run` and `exec` are for a tool that runs once, such as a command line
program, not for a service. `run` blocks the program: no task runs until the
child exits. Its outputs are kept whole, with no pipe to fill, so a child may
write any amount before it exits. `exec` replaces the program as `execve`
does: the command takes over the process, its id and its standard streams,
its exit status becomes the process's, and nothing of the program runs
after, not even its tasks; children it spawned keep running. Both find a
program and report failures as `spawn` does
(`tests/programs/process-run.sld`, `tests/programs/process-exec.sld`).

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
program that waits again, and does not end one that does not. The program
runs on Node's main thread, which receives the signals. The runner handles
them only while a task waits, from the moment the wait starts, or has yet
to finish a wait a signal ended; a signal then is kept when it finds no
waiter. At any other time Node's default ends the process by the signal at
once, even while a turn computes, when no handler could run. A task that
waits for termination while another computes without yielding hears of a
signal when that turn ends. `tests/termination/check.mjs` sends SIGTERM and
SIGINT to a waiting program, which observes each and exits cleanly, SIGTERM
to one that does not wait and SIGINT to one that computes without end,
which they end, and delivers a double tap by calling the handlers as two
signals would.

### The process boundary

`createProcesses()` in `host/native/process.mjs` owns one set of children
behind positive I32 handles, which never repeat within that owner. A child is
owned from spawn until it has exited and its pipes have closed; its public
handle exists from a successful spawn until close. `(snail runtime native process)`
declares the interface. A command is sent a character at a time, as the
strings of a host command are: its directory, the program's path, the name
it runs as, then its arguments. While it searches `PATH`, the library asks
`executable` about each candidate, a directory and a path sent the same
way, and the host answers with `access(2)` and a regular-file test, which
WASI lacks. A process crosses as its handle and a stream as its descriptor,
and the operations answer as the socket operations do.

| Operation | Result |
| --- | --- |
| `spawn(signal, directory, program, name, arguments)` | `{handle, pid}` once Node reports the child running. |
| `read(signal, handle, descriptor, maximum)` | A nonempty prefix of stream 1 or 2, or `null` at its end. |
| `write(signal, handle, bytes)` | A count after the pipe accepts it. |
| `closeInput(handle)` | Ends input. |
| `kill(handle, number)` | Sends signal 15, 9 or 2, the numbers the library gives. |
| `wait(signal, handle)` | `{code}` or `{signal}` once the child exits. |
| `close(handle)` | Revokes the handle, kills a running child and destroys its pipes. |
| `shutdown()` | Rejects new spawns, closes every child and waits until each has exited. |

`runChild(directory, program, name, arguments, input)` in the same file is
`run`'s `spawnSync`, which blocks the program until the child exits; a
signal sent meanwhile reaches the program once it returns.
`replaceProcess(directory, program, name, arguments)` is `exec`: it changes
to the command's directory and calls `process.execve` with the path the
library found. Only a failure answers, with its code, after the directory
is changed back.

`createTermination()` in the same file holds the termination waiters and
the process's handlers for SIGINT and SIGTERM while they are needed:
`wait(signal)` resolves with the signal's number, 2 or 15; `settled()` says
a task finished or dropped the wait a signal ended; and a signal resolves
every waiter or keeps itself while a delivery is unsettled.

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
