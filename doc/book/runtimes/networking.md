# Native networking

`(lofi socket)` provides concrete, interceptable `tcp` and `udp` effects. The Node
program runner binds them to `scripts/tcp.mjs` and `scripts/udp.mjs` through JSPI
and `scripts/socket-imports.mjs`. Static and separately linked programs use the
same binding. Browser sockets and the HTTP library are not implemented;
[the networking issue](https://github.com/tsnl/snail-scheme/issues/457) tracks the
remaining work.

## Lofi API

Import `(lofi socket)` and include `tcp` or `udp` in the effect row of code using it.
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
handler. They are reusable local values, neither `Send` nor `Sync`. Closing
revokes all aliases; closing the same native token again succeeds. Native
token types stay private to the library. A different handler's token reaching
the native binding reports `EBADF` instead of being cast to an integer handle.
TCP and UDP owners may issue the same numeric handle, but their private token
types differ. Tokens must remain with the runtime that issued them.

A replacement `handle tcp` supplies seven operations; `handle udp` supplies four.
They may create endpoint values with their own tokens. For example, a test
can put a `Ref Bytes` in a connection token or a `Ref Datagram` in a UDP token,
accessed through operation arguments. The reusable handler's captures still satisfy `Send + Sync` and
grade `omega`; this does not relax the language's handler rules.

## Wasm boundary

The binding borrows the program's synchronous constructor/projector exports
from `(lofi socket)`. Native I/O runs while the task is suspended. Only after its
scheduler gate returns the execution permit does the binding enter Wasm to
construct a typed `Result`. Ordinary JavaScript objects cannot substitute for
these managed values. Host code remains trusted to use the correct Lofi types.

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

## Ownership and cancellation

Node accepts eagerly. A listener retains at most 64 unclaimed connections in a
paused state, using native stream buffers. Overflow connections close immediately.
Revoked queued connections are skipped by accept. Cancelling accept leaves its
listener and unclaimed connections usable; closing a listener releases its queue
but leaves already handed-out connections independent.

Native ownership lasts from creation through the close callback. A public handle
exists only after successful listen/connect/accept and is removed when close
begins. Failed creation and rejected incoming sockets therefore participate in
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

`scripts/udp.mjs` owns IPv4 datagram sockets behind the `udp` effect. It is tested
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
