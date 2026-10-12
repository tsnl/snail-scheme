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

```wat
{{#include abi.wat}}
```
