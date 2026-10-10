# Snail Scheme

> 🚧 Rewrite WIP, for latest mature implementation see
> branch [`v3`](https://github.com/tsnl/snail-scheme/tree/v3).

Snail Scheme is a fast, modern, type-safe Scheme implementation with a framework
for distributed, heterogeneous applications. Its
[actors](https://en.wikipedia.org/wiki/Actor_model) model processes across
browsers, servers, GPUs, and database clusters, handling communication so you
can focus on your application's behavior and reuse logic across platforms.

Snail Scheme is faster than Chez Scheme and Guile
([benchmarks](benchmarks/README.md)), combining broad R7RS compatibility with
portability wherever WebAssembly runs. Proudly open source under [Apache-2.0](LICENSE).

## Getting started

Install Rust/Cargo, then run from the repository root
([toolchain setup](doc/backend.md#build-and-run)):

```sh
nix-shell
rustup target add wasm32-wasip1
./snail-scheme examples/fibonacci.scm
./snail-scheme examples/fibonacci.scm -o build/fibonacci.wasm
```

[Tour](TOUR.md) · [Build, tests, and limitations](doc/backend.md) ·
[Application framework](https://github.com/tsnl/snail-scheme/pull/9) ·
[Roadmap](https://github.com/tsnl/snail-scheme/issues/11)
