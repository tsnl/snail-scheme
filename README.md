# Snail Scheme

> 🚧 Work in progress, claims may change; the previous implementation lives on
> branch [`v3`](https://github.com/tsnl/snail-scheme/tree/v3).

Snail Scheme is a fast, modern, type-safe Scheme implementation with a framework
for distributed, heterogeneous applications. Its
[actors](https://en.wikipedia.org/wiki/Actor_model) model processes across
browsers, servers, GPUs, and database clusters, handling communication so you
can focus on your application's behavior and reuse logic across platforms.

Snail Scheme is faster than Chez Scheme and Guile
([benchmarks](BENCHMARKS.md)), combining broad R7RS compatibility with
portability wherever WebAssembly runs.

[![Recursive Fibonacci: Guile, Chez, and Snail execution times](benchmarks/results/2026-10-10-native-fibonacci/readme.svg)](BENCHMARKS.md)

## Getting started

Install Rust/Cargo, then run from the repository root
([toolchain setup](doc/backend.md#build-and-run)):

```sh
nix-shell
rustup target add wasm32-wasip1
chibi-scheme -I src build.scm
build/snail-scheme examples/fibonacci.scm
```

[Tour](TOUR.md) · [Build, tests, and limitations](doc/backend.md) ·
[Application framework](https://github.com/tsnl/snail-scheme/pull/9) ·
[Roadmap](https://github.com/tsnl/snail-scheme/issues/11) · [Apache-2.0](LICENSE)
