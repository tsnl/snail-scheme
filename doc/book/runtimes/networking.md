# Native networking

`scripts/tcp.mjs` implements a concrete TCP resource owner for Node. It is tested
with real loopback sockets. **It is not yet bound to a Lofi effect or installed
in the program runner.** That integration, UDP and the HTTP library are tracked
in [the networking issue](https://github.com/tsnl/snail-scheme/issues/457).

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

Write borrows its bytes unchanged until settlement. The future Wasm binding must
copy staging memory before awaiting; native callers must not mutate or detach
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
the future binding must supply its disposer when a cancelled task cannot receive
a newly created handle. No native cleanup record retains a managed wrapper.
