# Chat acceptance criteria

All criteria are **planned**. Follow the [tutorial](README.md) for the intended
reading order. C07 is an authoring extension; the initial chat milestone is C01–C06.

| ID | Exercise | Required evidence |
| --- | --- | --- |
| C01 | Encode/decode all argument, result, error, and stream-item types across same-process and WebSocket actor boundaries. | One typed declaration source derives schemas/codecs; S-expressions throughout, no JSON or same-heap delivery shortcut. Unknown versions/variants, malformed data, and size/depth limits fail before dispatch. Received forms are never evaluated. |
| C02 | Supply one model snapshot to Chibi static rendering and to the browser reducer/view. | Equivalent content, text escaping, HTML/DOM as first backend, and the generic element/fragment API separated from the renderer. Reducer messages are typed records. DOM updates preserve focus/selection and no hook-slot state is required. |
| C03 | Build and run native server plus browser WASM from distinct roots in one source. | Two real browser instances execute Scheme UI handlers, one can edit a draft while offline, and a submitted post travels through the native server and returns to both clients. Database code/credentials are absent from the browser artifact. WASI or a server-only demo is insufficient. |
| C04 | Import the app from a separate consumer project; select a provider and use discovery at startup. | Vendored library exports compose all targets and dependencies. Build outputs declare contracts/discovery, not secrets/live connections. Bindings reach newly spawned workers. Local and remote provider configurations work; connecting to a service does not confer lifecycle ownership. |
| C05 | Post concurrently, interrupt an append, replay from a cursor, and stall one subscriber. | The chosen store's per-room ordering and operation-ID deduplication are tested. Snapshot/replay/live transition loses no committed post. Each subscriber sees its own stream; queue limits and reconnect policy keep the other subscriber responsive. Retry is explicit and provider-specific. |
| C06 | Kill a worker, close each side of a connection, restart the server, and reload compatible/incompatible code. | Durable history remains in a native provider; each endpoint cleans up its pending exchanges. Outstanding calls do not lock the actor. The session supervisor contains failures. Reload pins old versions and validates schema compatibility or reports a required migration/reconnection. |
| C07 | Generate a guide library from explicit foreign paths and publish static and interactive workbooks. | One generator `begin`, generator-only imports, separate generated imports, and no reader lookup. Embedded runtime expressions have no generation-time effects. Hygiene and original source diagnostics survive generation; changed dependencies rebuild only affected artifacts. Both outputs reuse the Scheme tree API. |

## Test profiles

The **host profile** exercises pure reducers, view construction, and later reader
generation under Chibi. The **distributed profile** runs the compiled native server,
a native store, and two real browser WASM clients. A local mock is useful for
failure injection but cannot substitute for that run. A second deployment profile
places the same store protocol across a process/network boundary with discovery.

Record loaded artifact IDs, browser-executed handler traces, schema fingerprints,
committed room sequences, stream cursors, queue bounds, and resources after teardown.
The integration harness must prove that the view runs in the browser; merely
checking HTTP output or a generated `.wasm` file is insufficient.

## Dependencies and remaining choices

Required work includes typed record/variant metadata, derived codecs, browser
embedding and DOM effects, native actor hosting, connection-owned futures/streams,
WebSocket transport, supervision, multi-target builds, and a native store protocol.
The existing Chibi HTTP UI provides functional composition, not these facilities.

Before implementation, choose the native persistent store, authentication/session
mechanism, discovery adapters, schema compatibility rules, and initial queue limits.
Self-hosted and serverless hosting should be possible adapter configurations; the
first tutorial need not require a commercial cloud account. C07 additionally
requires staged syntax generation and a specified markup grammar. None of those
language features follows automatically from adding actors.
