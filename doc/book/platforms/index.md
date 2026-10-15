# Runtimes

The runtime runs a node using a selected [platform](../effects.md). The platform
is a collection of effect handlers; the loader supplies the host imports its
modules need. **Node.js** names the JavaScript host; **node** names a running
Snail instance.

| Runtime | Implementation |
| --- | --- |
| [Command line](native-cli.md) | Available: a linked WasmGC command with ordinary Scheme build scripts. |
| [Node.js host](nodejs.md) | Available: WASI preview 1, finalizers, and JavaScript build effects. |
| [Native GUI](native-gui.md) | Stub: no window/event platform implementation. |
| [Browser GUI](browser-gui.md) | Stub: no browser IO/UI platform implementation. |

The installed command runs one node. It implements the local [ABI](../abi.md)
but has no node identities, node `spawn` or `connect`, message codecs, or
connection clients. The [runtime contracts](../runtime-contracts.md) define the
behavior those capabilities must provide when implemented.

Runtime contracts have two directions: imported effect operations supplied by
the platform, and application handlers exported for the runtime to call.
Artifacts must match their imports, entry, root ABI, and Wasm features. Platform
selection checks interface descriptors and binary signatures before execution.

Cooperating runtimes must agree on node identities, message contracts, encoding,
and transport. A browser platform and a command platform can supply different
IO while honoring the same connection contract. Compatibility and failure
handling remain explicit in the connection model.
