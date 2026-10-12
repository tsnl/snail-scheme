# A chat application in two places

In this model example, two browser nodes keep local drafts and connect to one
server node. The server connects to an existing history node. Committed posts
are shared; each browser's draft belongs to that browser.

## Artifacts and startup

`build.scm` builds server and browser artifacts from separate entry points.
They share message declarations and pure application rules. Server credentials
and database code belong in the server artifact or its runtime configuration.
They do not belong in browser artifacts.

The server's runtime is configured with the browser artifacts and a browser
spawner. The server spawns each browser with its running identity in the initial
data. Browser navigation loads the artifacts and reports readiness. Each browser
then connects to the server; the server connects to the configured, already
running history node.

The server owns the browsers it spawns. Connecting to history gives it a way to
send messages, without ownership of history's lifetime.

## Connections across runtimes

The browser and server runtimes cooperate to establish each connection. They
check the nodes' identities and message contracts, encode and transfer messages,
and decode values for the receiving node. A client at each end handles replies,
timeouts, errors, and hang-up. Application code calls operations such as
`post` and `subscribe` without implementing WebSocket handling or codecs.

The message contract defines room ordering, committed post IDs, and the meaning
of a subscription. Bounded subscriber queues keep a slow browser from blocking
the other. Each browser retains its own draft while disconnected.

## Failure and reconnection

If a post commits but its reply is lost, retrying can post it twice. This
application avoids that by assigning an operation ID before sending and storing
the result with that ID in history. A retry uses the same ID; connection request
IDs alone cannot identify the operation across new connections.

Reloading a browser creates a new node and connection. Its workflow/session
supplies the server identity again and requests posts after its last stored
position. Persisting a draft across reload is a separate application rule.

When one browser leaves, its client hangs up. The server client closes that
connection, and the other browser continues. If the server fails, history
survives because the server never owned its lifetime. Recovery still requires a
workflow/session to start or find a server and give browsers its new identity.
