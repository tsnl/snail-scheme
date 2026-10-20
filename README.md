# Lofi

> 🚧 Work in progress. The Lofi migration and full benchmark campaign are complete;
> performance work and the extensions in the [roadmap](doc/roadmap.md) remain.

Lofi (Low-level Functional IR) is a typed functional language
and compiler target with an explicit s-expression surface. Type inference and
specialization determine concrete storage and calls before emitting WasmGC.
Binaryen optimizes that Wasm, and a WasmGC engine executes it. V8 is the
primary runtime; the engine owns managed memory and machine code generation.

Languages are libraries. The typed Lofi kernel, hygienic `syntax-rules` macros,
and an initial `(scheme base)` share one library system and backend. All language
and compiler libraries live under `src/`; `.sld` files use imports to select their
forms. The public `(lofi compiler)` works from either surface. Its implementation
remains Scheme hosted by Chibi; self-hosting and full R7RS support are future work.

The [Lofi chapters](doc/book/lofi/index.md) specify the typed language,
library values and compiler-as-library model, with examples and formal rules.
The [online book](https://tsnl.github.io/snail-scheme/) and
[Siegework](https://tsnl.github.io/snail-scheme/play/siegework/) are built from
`main` by the Book and Pages workflow. GitHub Actions uploads the generated site
as a Pages artifact; site output is not checked into the repository.
Build just the book with `scripts/book build`, or the complete site with
`node scripts/build-pages.mjs`. The complete site is written to `build/pages`
and checked under the `/snail-scheme/` URL prefix before upload.

## Start reading

For application development, start with the [five small tutorials](doc/book/lofi/tutorials/index.md).
They build up from a counter to a browser board with local saves and state-preserving reload.

Open [`examples/fibonacci.sld`](examples/fibonacci.sld), then
[`src/lofi/compiler/bootstrap.sld`](src/lofi/compiler/bootstrap.sld). The [short compiler tour](TOUR.md)
gives the reading order, follows a source file through the command and maps the
repository directories. Compiler passes live together in `src/lofi/`; the
[detailed compiler reference](doc/compiler.md) explains their contracts and the
execution APIs.

## Getting started

```sh
nix-shell
rustup target add wasm32-wasip1
./lofi run examples/fibonacci.sld
./lofi run examples/scheme-fibonacci.sld
./lofi compile -o fibonacci.wasm examples/fibonacci.sld
```

Binaryen is required and checked before compilation. Rust scalar services are
compiled to Wasm and linked with the program.
See [commands](doc/options.md) and [build requirements](doc/backend.md).

The [language book](doc/book/lofi/index.md) defines the surface and type model.
The [compiler tour](TOUR.md) follows source locations and type evidence through
the implementation. [The roadmap](doc/roadmap.md) separates current work from
further Scheme support and self-hosting.

[Apache-2.0](LICENSE)
