# Native networking

`(lofi tcp)` provides a concrete, interceptable TCP effect. The Node program
runner binds it to `scripts/tcp.mjs` through JSPI and `scripts/tcp-imports.mjs`.
Static and separately linked programs use the same binding. Browser TCP, UDP
and the HTTP library are not implemented;
[the networking issue](https://github.com/tsnl/snail-scheme/issues/457) tracks the
remaining work.

## Lofi API

Import `(lofi tcp)` and include `tcp` in the effect row of code using it.
Every operation returns `Result` with a `TcpError` whose `code` is a string
such as `"EBADF"`, `"EINVAL"` or a native network error code. Cancellation
unwinds the task; it is not a recoverable `TcpError`.

| Operation | Success value |
| --- | --- |
| `listen (Endpoint address port)` | `Listener`; `Listener-port` is the actual bound port. |
| `connect (Endpoint address port)` | `Connection`. |
| `accept listener` | `Connection`. |
| `read connection maximum` | `Some Bytes` containing an available nonempty prefix, or `None` at EOF. |
| `write connection bytes` | `I32` count accepted locally, possibly smaller than the input. |
| `close-listener listener` | `Unit`. |
| `close-connection connection` | `Unit`. |

Read limits are 1–65,536 bytes; one write accepts at most 65,536. Reads may
split or combine peer writes. Callers must loop to transfer an exact length.
Addresses are numeric IPv4 and ports are 0–65,535; listen port 0 selects a free
port. Hostnames, TLS and stream framing are outside this API.

`Listener` and `Connection` carry an opaque `Any` token belonging to their
handler. They are reusable local values, neither `Send` nor `Sync`. Closing
revokes all aliases; closing the same native token again succeeds. Native
token types stay private to the library. A different handler's token reaching
the native binding reports `EBADF` instead of being cast to an integer handle.
Tokens must remain with the runtime that issued them.

A replacement `handle tcp` supplies the same seven operations. It may create
`Listener` and `Connection` values with its own tokens. For example, a test
can put a `Ref Bytes` in the connection token and access it through operation
arguments. The reusable handler's captures still satisfy `Send + Sync` and
grade `omega`; this does not relax the language's handler rules.

## Wasm boundary

The binding borrows the program's synchronous constructor/projector exports
from `(lofi tcp)`. Native I/O runs while the task is suspended. Only after its
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
endpoint. The runner cancels/drains tasks, closes all TCP resources, then closes
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
