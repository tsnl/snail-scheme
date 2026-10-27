# In-process assembler

`snail-assembler` turns WebAssembly text into a binary module inside a
WebAssembly instance, so a toolchain that runs as Wasm, under Node's WASI or
in a browser, needs no Binaryen. The parsing and encoding are the
[`wat`](https://crates.io/crates/wat) crate's; it accepts everything the
compiler emits, including recursion groups of GC types, casts and tail
calls.

The crate is built for `wasm32-wasip1` as a reactor, apart from the runtime,
so programs never carry it. `build-crate` in `host/chibi/snail-core/build.sld`
builds it, and `host/native/assemble.mjs` drives it through four exports over
its linear memory:

| Export | Meaning |
| --- | --- |
| `snail:assembler/input` (length → address) | Makes room for the text, which the host writes there. |
| `snail:assembler/assemble` (→ status) | Assembles the text: 0 when the output is the module, 1 when it is the parser's message, with line and column. |
| `snail:assembler/output` (→ address) | Where the output starts. |
| `snail:assembler/output-length` (→ length) | How long it is. |

```sh
cargo test --manifest-path crates/assembler/Cargo.toml --offline
cargo fmt --manifest-path crates/assembler/Cargo.toml --all -- --check
```
