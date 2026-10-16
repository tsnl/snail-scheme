# Reading the Lofi compiler

Start with [`examples/fibonacci.lofi`](examples/fibonacci.lofi), then open
[`src/lofi/compiler.sld`](src/lofi/compiler.sld). Its `compile` function is the
map of the compiler: resolve library identities, check types, prepare concrete
code, emit Wasm and package the optimized artifact.

Lofi means **Low-level Functional IR**. Programs and standard libraries are
`.lofi` files. The compiler itself is Scheme hosted by Chibi, in `.sld` files.
There is one source language and one compiler implementation directory.

## Read the passes in this order

| Step | File | What to follow |
| --- | --- | --- |
| 1. Compilation | [`compiler.sld`](src/lofi/compiler.sld) | `compile` and `library-map->core`: the public entry and the composition of passes. |
| 2. Parsing | [`frontend.sld`](src/lofi/frontend.sld) | `parse-library`: located syntax becomes a `LofiLibrary` with binding identities and unresolved imports. |
| 3. Resolution | [`library.sld`](src/lofi/library.sld) | `resolve-library-map`: supplied library values become resolved imports, exports and source expressions. [`ir.sld`](src/lofi/ir.sld) defines those expressions. |
| 4. Checking | [`infer.sld`](src/lofi/infer.sld) | `infer-program`: check bodies and retain binding schemes, scopes and class evidence in [`checked.sld`](src/lofi/checked.sld). [`types.sld`](src/lofi/types.sld) supplies the type operations. |
| 5. Concrete demand | [`specialize.sld`](src/lofi/specialize.sld) | `prepare-generation` and `prepare-entry-generation`: choose concrete implementations and settle storage and captures. |
| 6. Emission | [`emit-wasm.sld`](src/lofi/emit-wasm.sld) | `strict-core->wasm`: visit source with established type and storage evidence and emit WasmGC. |

Each module keeps its decisions and supporting operations together. Scheme unit
tests live in the final `Tests` section under the `snail-tests` feature.

```text
located syntax → parsed libraries → resolved source → checked program
               → concrete demand and storage → WasmGC → Binaryen
```

Resolution examines every entry in the supplied map. Checking examines every
body in the selected root's dependency closure, including unused functions.
Concrete demand selects the implementations and initializers needed for emitted
code. These scopes differ deliberately.

## Follow a file through the command

```sh
./lofi run examples/fibonacci.lofi
```

This prints `832040`. [`lofi`](lofi) starts
[`scripts/lofi.scm`](scripts/lofi.scm), which owns command options, private build
directories and publication. [`scripts/build-lofi.scm`](scripts/build-lofi.scm)
calls [`source-driver.sld`](src/lofi/source-driver.sld):

1. `collect-source-file` finds and parses source dependencies into a library map.
2. `source-file->core` resolves that map and checks the root through
   `library-map->core` in the compiler module.
3. `source-file->wasm` prepares concrete demand and emits the script's Wasm.

The build scripts optimize with Binaryen, link the Rust scalar services and run
the resulting module on V8. The file path can also execute `generate-library`
recipes during preparation. Read that machinery after the ordinary source path;
producer and application maps are separate, with shared source choices and cycle
detection.

The map-based `compile` API starts with parsed library values and a public export.
It reads no source files and returns optimized artifact bytes with a checked
scalar entry signature. The script path emits a body result for build drivers to
optimize and link. [`build.scm`](build.scm) shows a complete library-based native
build once those boundaries are familiar.

## Where things live

| Path | Responsibility |
| --- | --- |
| [`src/lofi/`](src/lofi/) | Chibi-hosted compiler passes and its Wasm execution/service adapters. |
| [`lib/lofi/`](lib/lofi/README.md) | Standard libraries written in Lofi, including the guest compiler service API. |
| [`examples/`](examples/) | Small programs and explicit build/generation examples. |
| [`wasm-native/`](wasm-native/README.md) | Independent Wasm-to-LLVM package, shared Rust scalar services and native collector. Start here only when following execution below Wasm. |
| [`scripts/`](scripts/) | Commands for builds, integration tests, formatting and the book. |
| [`tests/`](tests/README.md) | Integration fixtures, runners and shared assertions. |
| [`benchmarks/`](benchmarks/README.md) | The 57-workload corpus, controls and recorded evidence. |
| [`src/lofi-tools/`](src/lofi-tools/) and [`tools/host/`](tools/host/) | Trace viewing and Unicode generation tools. |
| [`doc/`](doc/) | Language contracts, build instructions and detailed implementation references. |

The Scheme import `(lofi compiler)` loads `src/lofi/compiler.sld`. The same
spelling in a Lofi program selects `lib/lofi/compiler.lofi`, the guest service
API. The host's module path and Lofi's library search path are separate.

## Go deeper when needed

- [Compiler reference](doc/compiler.md): module contracts, library builders,
  artifact lifetimes and execution adapters.
- [Language book](doc/book/lofi/index.md): syntax, types and library semantics.
- [IR and checking](doc/ir.md): representations and implementation tradeoffs.
- [Build and test requirements](doc/backend.md), [commands](doc/options.md) and
  [native execution](doc/native.md).
- [Roadmap](doc/roadmap.md): proposed work, separate from implemented behavior.

Use `make test` for compiler host tests and `make check` for formatting checks.
`scripts/test-backend` runs linked Wasm and native contracts; `scripts/test-build`
exercises the public command and native build composition.
