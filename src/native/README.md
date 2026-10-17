# Wasm to native

`(native)` is a Chibi-hosted Scheme library that consumes WebAssembly and emits
LLVM bitcode, saved ELF objects or native executables. It supports x86-64 Linux.
Binaryen optimization is mandatory before lowering. This package does not
import source-language syntax, bindings, inference or specialization.

The [native chapters](../../doc/book/native/index.md) describe the build API,
provider ABI, root lifetimes, Immix collector and execution tests.

## Layout

| Path | Responsibility |
| --- | --- |
| `../native.sld` | Public Scheme API. |
| `wasm.sld`, `wasm-read.sld`, `wasm-resolve.sld` | Wasm representation, reading, canonical types and collection effects. |
| `llvm.sld`, `llvmlite.sld` | Mechanical lowering and LLVM emission. |
| `native-build.sld` | Scalar provider contracts, object generation and Cargo linking. |
| `native.rs`, `native_gc.rs` | Native Wasm execution ABI and Immix GC. |
| `native_worker.rs`, `execute.sld` | Isolated native instances and Scheme invocation. |
| `runtime/` | Shared Rust scalar-services crate for Wasm and native. |
| `runtime-wasm.sld` | Build and link only the scalar crate's Wasm form. |
| `tests/` | Authored Wasm, providers and execution checks independent of the source compiler. |

The `native-runtime` crate depends on `snail-runtime` in `runtime/`. The latter
never depends on the collector. Wasm selects `runtime/Cargo.toml`; native linking
selects the parent crate. Rust `cfg` handles scalar-service platform differences.
`src/lib.rs` only declares the native modules; their implementation lives beside
the lowering that calls them.

## Import and compose

The repository's `bootstrap/` directory exposes `(native)` and its dependencies
without shadowing Chibi's own Scheme libraries. From any working directory:

```sh
repo=/absolute/path/to/checkout
chibi-scheme -I "$repo/bootstrap" /absolute/path/to/build.scm
```

The package requires installed Chibi/SRFI libraries. The same include root also
exposes `(lofi compiler bootstrap)` if the recipe imports it. Product sources use
the public `(lofi compiler)`; the compiler always returns Wasm.

```scheme
(import
 (native))

(define imports
  (list (make-native-import "host" "read" "host_read" '(i32) 'i64)))
(wasm-binary->llvm "program.wasm" imports "build/program" "build/program/module.ll")
(llvm-bitcode "build/program/module.ll" "build/program/module.bc")
(link-native-object runtime-root "build/program/module.bc" "entry.rs"
                    '(("host" "provider.rs")) "build/program")
```

Here `runtime-root` is the absolute path to this directory. `make-native-import`
records the Wasm module/name, C symbol, parameter types and result (`void` for
none). `llvm-object` emits a saved ELF object instead of retained bitcode.
`link-native-object` returns the linked program path. It compiles the supplied
Rust entry and providers through Cargo, with shared LTO for bitcode inputs.
[`build.scm`](../../build.scm) shows complete compiler/native composition.

## Checks

From this package directory:

```sh
cargo test --offline
cargo fmt --all -- --check
chibi-scheme -D snail-tests -I ../../bootstrap -I tests tests/host.scm
chibi-scheme -D snail-tests -I ../../bootstrap -I tests tests/standalone.scm
```

The standalone test links and executes authored Wasm as both bitcode and ELF,
using normal and `gc-stress` Cargo builds. Collection policy has no environment
configuration. Repository integration checks are `scripts/test-native`,
`scripts/test-package-isolation`, `scripts/test-backend` and `scripts/test-build`.
