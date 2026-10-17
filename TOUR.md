# Languages are libraries

The compiler is a library. Language definitions are libraries. Reusable Lofi and
Scheme libraries live under `src/`, with paths matching their library names.
Programs use `.sld`; their imports select the forms and operations they use.
Lofi means **Low-level Functional IR**.

Start with [`examples/fibonacci.sld`](examples/fibonacci.sld), then compare
[`examples/scheme-fibonacci.sld`](examples/scheme-fibonacci.sld). Both print
`832040`. The first uses the typed Lofi kernel; the second imports the initial
[`(scheme base)`](src/scheme/base.sld), whose hygienic macros produce that kernel.
Both reach the same type checker, specialization pass and Wasm backend.

The public [`(lofi compiler)`](src/lofi/compiler.sld) is usable by either surface.
It supplies parsing, explicit library maps, compilation and Wasm execution through
the compiler service. The current implementation is Scheme hosted by Chibi:
[`(lofi compiler bootstrap)`](src/lofi/compiler/bootstrap.sld) composes the passes.
The compiler cannot compile its own implementation yet. `bootstrap/` is a loader
view of `src/lofi`, keeping Chibi's own `(scheme base)` separate from the product
library. Executable Chibi orchestration scripts retain `.scm`.

## Read the passes in this order

| Step | File | What to follow |
| --- | --- | --- |
| 1. Compilation | [`compiler/bootstrap.sld`](src/lofi/compiler/bootstrap.sld) | `compile` and `library-map->core` compose resolution, checking and emission. |
| 2. Description | [`frontend.sld`](src/lofi/frontend.sld) | `parse-library` retains located source and imports without loading dependencies. |
| 3. Resolution and expansion | [`library.sld`](src/lofi/library.sld), [`macros.sld`](src/lofi/macros.sld) | Resolve imported binding identities, expand `syntax-rules`, then parse the expanded kernel. |
| 4. Checking | [`infer.sld`](src/lofi/infer.sld) | `infer-program` checks bodies and records types, scopes and class evidence in [`checked.sld`](src/lofi/checked.sld). |
| 5. Concrete demand | [`specialize.sld`](src/lofi/specialize.sld) | `prepare-generation` chooses concrete implementations, storage and captures. |
| 6. Emission | [`emit-wasm.sld`](src/lofi/emit-wasm.sld) | `strict-core->wasm` emits WasmGC using established type and storage evidence. |

```text
located library source → imported identities and hygienic expansion
                       → resolved Lofi → checked program
                       → concrete demand and storage → WasmGC → Binaryen
```

Macro transformers retain definition-site bindings, including private helpers.
They can emit `library-begin` to introduce several declarations in one library
scope. Transformers and splices disappear before ordinary type checking and code
generation. Read the
[macro and Scheme chapter](doc/book/lofi/macros.md) for supported forms and limits.
Modules keep their decisions together; host unit tests live in final `Tests`
sections under the `snail-tests` feature.

Resolution examines every entry supplied in a library map. Checking examines
every body in the root's dependency closure, including unused functions.
Concrete demand selects the implementations and initializers needed for emitted
code. These scopes differ deliberately.

## Follow a file through the command

```sh
./lofi run examples/scheme-fibonacci.sld
```

[`lofi`](lofi) starts [`scripts/lofi.scm`](scripts/lofi.scm), which owns command
options and build directories. [`source-driver.sld`](src/lofi/source-driver.sld)
finds `.sld` dependencies, prepares a library map and calls the compiler. It can
also execute explicit `generate-library` recipes: producer and application maps
are separate, with shared source choices and cycle detection. Build scripts
optimize with Binaryen, link Rust scalar services and run on V8 or lower through
the independent [`wasm-native/`](wasm-native/README.md) package for native execution.

The map-based `compile` API reads no source files. It accepts library values and
a public export, and returns optimized artifact bytes with a checked scalar
entry signature. [`build.scm`](build.scm) shows direct bootstrap library
composition for a native build.

## Where things live

| Path | Responsibility |
| --- | --- |
| [`src/lofi/`](src/lofi/README.md) | Typed core, runtime libraries, public compiler API and bootstrap implementation modules. |
| [`src/scheme/`](src/scheme/) | Scheme language libraries; currently a typed subset of base forms. |
| [`src/lofi/tools/`](src/lofi/tools/) | Trace viewing and Unicode generation libraries. |
| [`bootstrap/`](bootstrap/README.md) | Chibi loader view of the implementation libraries. |
| [`examples/`](examples/) | Programs and explicit build/generation examples. |
| [`apps/`](apps/README.md) | Independent app composition and app-owned libraries; [Siegework](apps/siegework/README.md) composes Scheme simulation, typed reducers, shaders and a browser build. |
| [`src/application/`](src/application/reducer.sld) | Typed lexical handlers, immutable transitions, scalar snapshot bridge, serialized owner and single-authority durability. |
| [`src/browser/`](src/browser/application.sld) | Immutable view data, browser input/transport, artifact packaging and the local development server. |
| [`src/webgpu/`](src/webgpu/shader.sld) | Scheme shader AST/compiler and the real WebGPU quad adapter. |
| [`src/scheme/immutable.sld`](src/scheme/immutable.sld) | Functional record replacement and small immutable list operations. |
| [`wasm-native/`](wasm-native/README.md) | Independent Wasm-to-LLVM package, shared Rust scalar services and native collector. |
| [`scripts/`](scripts/) and [`tools/host/`](tools/host/) | Executable orchestration and host tool configuration. |
| [`tests/`](tests/README.md) | Integration fixtures, runners and shared assertions. |
| [`benchmarks/`](benchmarks/README.md) | All 57 workloads, controls and preserved measurement evidence. |

Use the [detailed compiler reference](doc/compiler.md) for pass contracts and
execution APIs, and the [language book](doc/book/lofi/index.md) for semantics.
