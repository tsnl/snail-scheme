# Lofi

> 🚧 Work in progress. The Lofi migration and full benchmark campaign are complete;
> performance work and the extensions in the [roadmap](doc/roadmap.md) remain.

Lofi (Low-level Functional IR) is a typed functional language
and compiler target with an explicit s-expression surface. Type inference and
specialization determine concrete storage and calls before emitting WasmGC.
Binaryen always optimizes that Wasm. Run it on V8, or pass it to the separate
[Wasm-to-native package](wasm-native/README.md) for LLVM lowering and a native
executable with the in-house collector.

The compiler is written in Scheme and hosted by Chibi. Its input language is
Lofi. Scheme elaboration, macros and self-hosting are deferred.

The [Lofi chapters](doc/book/lofi/index.md) specify the typed language,
library values and compiler-as-library model, with examples and formal rules.

## Getting started

```sh
nix-shell
rustup target add wasm32-wasip1
./snail-lofi run examples/fibonacci.lofi
./snail-lofi compile -o fibonacci.wasm examples/fibonacci.lofi
scripts/build-native examples/fibonacci.lofi build/fibonacci
build/fibonacci
```

Binaryen is required and checked before compilation. Native builds currently
test x86-64 Linux and use LLVM, Cargo, Rust’s bundled linker and the same Rust extern implementations.
See [commands](doc/options.md) and [build requirements](doc/backend.md).

The [language design](doc/lofi.md) defines the surface and type model.
The [compiler tour](TOUR.md) follows source locations and type evidence through
the implementation. [The roadmap](doc/roadmap.md) separates current work from
future frontends and self-hosting. [`build.scm`](build.scm) is a concrete Chibi
recipe that imports the compiler and Wasm-to-native package separately, then
links the generated object with a Rust entry point. Its first comment gives an
example that works from outside the checkout and prints `42`.

The [benchmark corpus](benchmarks/README.md) retains all 57 workloads and compares
Lofi, Chez and Rust. Source ports, target validation and clean measurements are
recorded separately. The [completed full-suite report](benchmarks/lofi/evidence/20261015-full57.md)
retains Ack's Wasm failures and a separately corrected Mperm timer identity.
Its frozen Lofi baseline trails Chez and Rust on every aggregate comparison;
the later [packet-input results](benchmarks/lofi/evidence/20261015-input-packets.md)
describe a separate implementation and campaign. Historical Scheme reports
remain historical evidence.

[Apache-2.0](LICENSE)
