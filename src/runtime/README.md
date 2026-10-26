# Wasm scalar services

`snail-runtime` supplies scalar math, Unicode properties, float text, console
and file I/O, and panic reporting. Lofi's managed values stay in WasmGC; Rust
retains external resources behind scalar handles and never stores guest GC
roots.

Real-number conversion is the exception: its results are scratch owned by the
runtime instance, with no handle and no part in cleanup, because the private
Lofi wrappers read them before returning and no user code runs in between.

The command-line driver (`host/chibi/lofi/build.sld`) builds this crate for
`wasm32-wasip1`. It merges the runtime into each statically linked program,
as `lofi build` and the internal source compiler build them, and connects terminal
diagnostics and resource cleanup. A program linked when it runs, as
`./scripts/lofi-tool serve`, `./scripts/lofi-tool watch` and the IDE build it, instead loads the runtime
as its own instance beside the library modules (`src/app/load.mjs`). Node's
WASI and the browser host in `src/app/host.mjs` supply the platform
operations.

```sh
cargo test --manifest-path src/runtime/Cargo.toml --offline
cargo fmt --manifest-path src/runtime/Cargo.toml --all -- --check
```

Host compilation is used for unit tests.
