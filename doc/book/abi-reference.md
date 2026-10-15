# ABI reference

This is the Rust module's view of the local ABI: it imports value operations
from compiled Scheme support and exports runtime procedures for Scheme to call.
The [ABI chapter](abi.md) explains call direction, value ownership, and failures.
The declarations retain the emitted module names so they can be compared with
compiled artifacts. Function bodies are documentation stubs. The root imports
match `src/abi.rs`; the service examples below are a selection. The complete
platform operation catalog is `src/snail-scheme/effects.sld`, including behavior,
Scheme signatures, and exceptional native signatures. Common library exports
are documented beside their implementations in `src/lib.rs`.

Numeric tensors use resource kind `2` and common-library storage in `src/iverson.rs`.
Their raw `snail:drop-array` export takes one `i32` resource ID and returns no
value. The host routes kind-2 collection notices there; kind-1 notices still go
to the selected `ports/drop-resource` provider. Replacing ports does not transfer
ownership of numeric buffers. Cleanup holds scalar IDs and never the watched
Scheme wrapper.

```wat
{{#include abi.wat}}
```
