# Wasm scalar services

`snail-runtime` supplies scalar math, Unicode properties, float text, console
and file I/O, and panic reporting. Lofi's managed values stay in WasmGC; Rust
retains external resources behind scalar handles and never stores guest GC
roots.

The compiler driver (`src/lofi/compiler/build.sld`) builds this crate for
`wasm32-wasip1`, merges it with each program, and connects terminal
diagnostics and resource cleanup. Node's WASI and the browser host in
`src/app/host.mjs` supply the platform operations.

```sh
cargo test --manifest-path src/runtime/Cargo.toml --offline
cargo fmt --manifest-path src/runtime/Cargo.toml --all -- --check
```

Host compilation is used for unit tests.
