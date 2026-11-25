# Wasm scalar services

`snail-scheme-support` supplies scalar math, Unicode properties, float text, console
and file I/O, directory and path operations, a monotonic clock, and panic
reporting. The linked runtime allocates shared Snail values in linear memory.
Generated code publishes roots across calls. The host holds exported values
through per-instance root cells. External resources have explicit scalar handles.

Real-number conversion is the exception: its results are scratch owned by the
runtime instance, with no handle and no part in cleanup, because the private
`snail-scheme` wrappers read them before returning and no user code runs in between.

The command-line driver (`host/chez/snail/stage0/build.sld`) builds this crate for
`wasm32-wasip1`. It merges the runtime into each statically linked program,
as stage 0 builds them, and connects terminal diagnostics and
resource cleanup. Each program built by `snail-scheme build` contains its
own runtime, layouts, memory and function table. Node's
WASI and the browser host in `host/browser/host.mjs` supply the platform
operations.

```sh
cargo test --manifest-path crates/snail-scheme-support/Cargo.toml --offline
cargo fmt --manifest-path crates/snail-scheme-support/Cargo.toml --all -- --check
```

Host compilation is used for unit tests.

## Later

*Proposed, not implemented* ([#566](https://github.com/tsnl/snail-scheme/issues/566)).
The crate is what lies beneath `(snail core …)`, and it can shrink:

- **I/O moves into `snail-scheme`.** Console, file and path I/O and the clock,
  about 900 lines, move once `snail-scheme` has load and store primitives on
  memory 0 to call WASI through externs itself. Those primitives generalize
  the shared-memory layer of #553.

The pure services have moved already
([scripts](../../doc/book/snail-scheme/scripts.md)). The crate's
`unicode-tables` example (`make unicode-tables`) writes the Unicode
properties and case mapping as constant arrays, `(snail shell text unicode)`;
the transcendental math is `(snail shell math)`, ported from fdlibm; and
`(snail core base)` prints reals itself, with Dragon4's shortest digits.
