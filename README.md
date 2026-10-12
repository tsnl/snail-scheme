# Snail Scheme

> 🚧 Work in progress, claims may change.
>
> We are still slower than Chez Scheme and Guile, but we very much aim to be
> faster.

Snail Scheme compiles Scheme to WebAssembly GC. The Wasm engine owns Scheme
memory. A common library supplies value operations; a selected platform supplies
named effect handlers for files, ports, clocks, diagnostics, and host services.
The available command runtime uses Node.js, WASI, and a small JavaScript adapter
for subprocesses and build publication.

The [book](doc/book/index.md) explains the longer-term model of nodes, artifacts,
spawn, connect, and messages. Node connections and browser GUI adapters are still
unimplemented; the book distinguishes that model from runnable examples.

## Getting started

```sh
nix-shell
rustup target add wasm32-wasip1
chibi-scheme -h512M -I src build.scm
node --no-warnings scripts/run-wasi.mjs build/snail-scheme.wasm examples/fibonacci.scm
```

Chibi remains the bootstrap host. Binaryen is a required build dependency,
provided by `nix-shell` and checked before compilation. See
[build and toolchain setup](doc/backend.md).

The [benchmark suite](BENCHMARKS.md) retains all 57 pinned R7RS workloads,
including unsupported cases. The completed Native/V8 comparison and compiler
baseline are in [the migration report](benchmarks/results/2026-10-12-native-v8/README.md).
The removed LLVM emitter and native collector remain on
[`archive/llvm-backend-20261012`](https://github.com/tsnl/snail-scheme/tree/archive/llvm-backend-20261012).

[Tour](TOUR.md) · [Effect interfaces](doc/book/effects.md) ·
[Build and tests](doc/backend.md) · [Apache-2.0](LICENSE)
