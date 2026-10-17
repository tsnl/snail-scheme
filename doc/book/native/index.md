# Native execution

The [native package](../../../src/native/README.md) consumes Binaryen-optimized
WebAssembly and produces LLVM and native artifacts. Lofi always emits Wasm;
a build script explicitly composes the compiler and native libraries.

```text
Lofi → Wasm → Binaryen → (native) → LLVM bitcode → Cargo / rust-lld
```

The tested native platform is **64-bit x86-64 Linux**. The implementation is
Scheme hosted by Chibi, with Rust runtime support built by Cargo. It depends on
Wasm types, operations and declared imports, independently of source-language
syntax, inference or specialization.

The package contains two Rust crates. `snail-runtime` supplies the same scalar
services on Wasm and native. `native-runtime` depends on those services and adds
the native collector, Wasm execution support and process supervisor. Wasm builds
select only `src/native/runtime/Cargo.toml`; they do not compile or ship the GC.

- [Building and linking](building.md): library composition, include paths and artifacts.
- [ABI and representation](abi.md): providers, packed arrays and supported Wasm.
- [Roots and tail calls](roots.md): relocation and foreign-reference lifetime.
- [Immix collector](collector.md): allocation, tracing, evacuation and growth.
- [Failures and testing](failures.md): cleanup and explicit stress builds.
