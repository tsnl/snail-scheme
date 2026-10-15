# SFIR

> 🚧 Work in progress. The SFIR migration and benchmark validation are ongoing.

SFIR (Snail functional IR, pronounced “sphere”) is a typed functional language
and compiler target with an explicit s-expression surface. Type inference and
specialization determine concrete storage and calls before emitting WasmGC.
Binaryen always optimizes that Wasm. Run it on V8, or mechanically lower it to
LLVM for a 64-bit native executable with the in-house collector.

The compiler is written in Scheme and hosted by Chibi. Its input language is
SFIR. Scheme elaboration, macros and self-hosting are deferred.

The [SFIR chapters](doc/book/sfir/index.md) specify the typed language,
library values and compiler-as-library model, with examples and formal rules.

## Getting started

```sh
nix-shell
rustup target add wasm32-wasip1
./snail-sfir run examples/fibonacci.sfir
./snail-sfir run --target native examples/fibonacci.sfir
./snail-sfir compile -o fibonacci.wasm examples/fibonacci.sfir
```

Binaryen is required and checked before compilation. Native builds currently
test x86-64 Linux and use Clang, LLD and the same Rust extern implementations.
See [commands](doc/options.md) and [build requirements](doc/backend.md).

The [language design](doc/sfir.md) defines the surface and type model.
The [compiler tour](TOUR.md) follows source locations and type evidence through
the implementation. [The roadmap](doc/roadmap.md) separates current work from
future frontends and self-hosting. `build.scm` is outside this migration.

The [benchmark corpus](benchmarks/README.md) retains all 57 workloads and compares
SFIR, Chez and Rust. Source ports, target validation and clean measurements are
recorded separately. Historical Scheme reports remain historical evidence.

[Apache-2.0](LICENSE)
