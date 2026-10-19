# Wasm scalar services

`snail-runtime` supplies scalar math, text, symbols, datum tokens and file I/O.
Lofi's managed values stay in WasmGC; Rust retains external resources behind
scalar handles and never stores guest GC roots.

`scripts/link-lofi-runtime` builds this crate for `wasm32-wasip1`, merges it with
the program, and connects terminal diagnostics and explicit resource cleanup.
The Node WASI host and browser provider adapters supply platform operations.

```sh
cargo test --manifest-path src/runtime/Cargo.toml --offline
cargo fmt --manifest-path src/runtime/Cargo.toml --all -- --check
```

Host compilation is used for unit tests. There is no Lofi native executor,
custom collector, LLVM lowering or native guest ABI.
