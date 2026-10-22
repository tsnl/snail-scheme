# Wasm scalar services

`snail-runtime` supplies scalar math, Unicode properties, float text, console
and file I/O, and panic reporting. Lofi's managed values stay in WasmGC; Rust
retains external resources behind scalar handles and never stores guest GC
roots.

Real-number parsing and formatting use scratch results owned by each runtime
instance. The private Lofi wrappers read a successful parse or copy all the
formatted text synchronously before returning to user code. These temporary
results have no handles and do not participate in file-resource cleanup.

The command-line driver (`host/chibi/lofi/build.sld`) builds this crate for
`wasm32-wasip1`. It merges the runtime into each statically linked program,
as `lofi compile` and `lofi run` build them, and connects terminal
diagnostics and resource cleanup. A program linked when it runs, as
`lofi serve`, `lofi watch` and the IDE build it, instead loads the runtime
as its own instance beside the library modules (`src/app/load.mjs`). Node's
WASI and the browser host in `src/app/host.mjs` supply the platform
operations.

```sh
cargo test --manifest-path src/runtime/Cargo.toml --offline
cargo fmt --manifest-path src/runtime/Cargo.toml --all -- --check
```

Host compilation is used for unit tests.
