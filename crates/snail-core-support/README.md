# Wasm scalar services

`snail-core-support` supplies scalar math, Unicode properties, float text, console
and file I/O, directory and path operations, a monotonic clock, and panic
reporting. Snail-Core's managed values stay in WasmGC; Rust
retains external resources behind scalar handles and never stores guest GC
roots.

Real-number conversion is the exception: its results are scratch owned by the
runtime instance, with no handle and no part in cleanup, because the private
Snail-Core wrappers read them before returning and no user code runs in between.

The command-line driver (`host/chibi/snail/stage0/build.sld`) builds this crate for
`wasm32-wasip1`. It merges the runtime into each statically linked program,
as `snail build` and the internal source compiler build them, and connects terminal
diagnostics and resource cleanup. A program linked when it runs, as `snail dev`
builds it, instead loads the runtime as its own instance beside the library
modules (`host/browser/load.mjs`). Node's
WASI and the browser host in `host/browser/host.mjs` supply the platform
operations.

```sh
cargo test --manifest-path crates/snail-core-support/Cargo.toml --offline
cargo fmt --manifest-path crates/snail-core-support/Cargo.toml --all -- --check
```

Host compilation is used for unit tests.

## Later

*Proposed, not implemented* ([#566](https://github.com/tsnl/snail-scheme/issues/566)).
The crate is what lies beneath `(snail core …)`, and it can shrink:

- **I/O moves into Snail-Core.** Console, file and path I/O and the clock,
  about 900 lines, move once Snail-Core has load and store primitives on
  memory 0 to call WASI through externs itself. Those primitives generalize
  the shared-memory layer of #553.
- **The Unicode tables become generated.** The property tables, 765 lines,
  become a library generated at build time.
- **Float printing and the transcendental math stay,** as pure scalar
  services.
