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
view of `src/lofi` and `src/native`, keeping Chibi's own `(scheme base)` separate from the product
library. Executable Chibi orchestration scripts retain `.scm`.

The [native self-hosting investigation](doc/self-hosting.md) records Siegework
build costs, compatibility blockers and the proposed `snail run` / `snail build`
bootstrap. [`scripts/measure-siegework.mjs`](scripts/measure-siegework.mjs) measures
the original build or profiles a private loader view. Its Chibi-only
[`compiler/profile.sld`](src/lofi/compiler/profile.sld) owns bounded source-unit
spans, optional helper totals and checked instrumentation recipes. Self-hosting
remains proposed.

## Read the passes in this order

| Step | File | What to follow |
| --- | --- | --- |
| 1. Compilation | [`compiler/bootstrap.sld`](src/lofi/compiler/bootstrap.sld) | `compile` and `library-map->core` compose resolution, checking and emission. |
| 2. Description | [`frontend.sld`](src/lofi/compiler/frontend.sld) | `parse-library` retains located source and imports without loading dependencies. Attached schemes carry variables, requirements, and an ordinary type; static declaration forms establish their category without kind annotations. |
| 3. Resolution and expansion | [`library.sld`](src/lofi/compiler/library.sld), [`macros.sld`](src/lofi/compiler/macros.sld) | Resolve imported binding identities, expand `syntax-rules` and attached derive transformers, then parse the expanded kernel. |
| 4. Checking | [`infer.sld`](src/lofi/compiler/infer.sld) | `infer-program` checks bodies and records types, scopes and class evidence in [`checked.sld`](src/lofi/compiler/checked.sld). |
| 5. Concrete demand | [`specialize.sld`](src/lofi/compiler/specialize.sld) | `prepare-generation` chooses concrete implementations, storage and captures, then partitions values by activation owner. |
| 6. Emission | [`emit-wasm.sld`](src/lofi/compiler/emit-wasm.sld) | `strict-core->wasm` emits WasmGC using established type and storage evidence, indexed layouts and the prepared activation partition. |

```text
located library source → imported identities and hygienic expansion
                       → resolved Lofi → checked program
                       → concrete demand and storage → WasmGC → Binaryen
```

Macro transformers retain definition-site bindings, including private helpers.
They can emit `begin` to introduce several declarations in one library scope.
Scope lookup indexes names while retaining ordered binding objects; hygiene and
namespace visibility are checked when each name is used.
The expander normalizes named `data`, `typeclass` and `instance` declarations,
reserving their associated bindings together. Transformers and splices disappear
before ordinary type checking and code generation. Read the
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
options and build directories. [`source-driver.sld`](src/lofi/compiler/source-driver.sld)
finds `.sld` dependencies, prepares a library map and calls the compiler. It can
also execute explicit `generate-library` recipes: producer and application maps
are separate, with shared source choices and cycle detection. Build scripts
optimize with Binaryen, link Rust scalar services and run on V8 or lower through
the independent [`src/native/`](src/native/README.md) package for native execution.

The map-based `compile` API reads no source files. It accepts library values and
a public export, and returns optimized artifact bytes with a checked scalar
entry signature. [`build.scm`](build.scm) shows direct bootstrap library
composition for a native build.

## Where things live

| Path | Responsibility |
| --- | --- |
| [`src/lofi/`](src/lofi/README.md) | Typed core, standard libraries and the public `(lofi compiler)` API. |
| [`src/lofi/compiler/`](src/lofi/compiler/README.md) | Compiler implementation, library builders and execution adapters. |
| [`src/scheme/`](src/scheme/) | Scheme language libraries; currently a typed subset of base forms. |
| [`src/lofi/compiler/tools/`](src/lofi/compiler/tools/) | Trace viewing and Unicode generation libraries. |
| [`bootstrap/`](bootstrap/README.md) | Chibi loader view of the implementation libraries. |
| [`examples/`](examples/) | Programs and explicit build/generation examples. |
| [`examples/applications/`](examples/applications/README.md) | Runnable checkpoints for the [five application tutorials](doc/book/lofi/tutorials/index.md), including a minimal marker board assembled from the shared browser host. |
| [`apps/`](apps/README.md) | Independent app composition and app-owned libraries; the [Siegework tour](apps/siegework/TOUR.md) follows Scheme simulation, manual investment, automatic worker logistics, typed reducers, shaders and browser packages. |
| [`src/application/`](src/application/reducer.sld) | Typed lexical handlers, immutable transitions, derived snapshots and prior committed state, one async message lane, [local durable state](src/application/local.mjs), IndexedDB tab ownership and optional online checkpoint transfer. |
| [`src/browser/`](src/browser/application.sld) | Immutable view data, continuous input, typed forms, presentation/reload and static browser packaging. All game logic runs locally. |
| [`src/save/`](src/save/service.mjs) | Optional HTTP save/load service over opaque checkpoints, with conditional ETags and SQLite storage; no game simulation. |
| [`src/ui/`](doc/ui.md) | Immutable typed controls, one top-down Scheme rectangle allocation, copied endpoint events and stable DOM controls; [UI lab](apps/ui-lab/src/ui-lab/game.sld) is the standalone runnable example. |
| [`src/draw3d/`](src/draw3d/README.md) | Checked geometry, scene hierarchies, cameras and ray picking; Scheme declares retained batches, motion endpoints, radial reveals and inset views. One GPU device reuses geometry and advances display clocks independently of Scheme queries. |
| [`src/webgpu/`](src/webgpu/shader.sld) | Scheme shader AST/compiler, the quad adapter, and a depth-tested 3D adapter with display-frame motion interpolation and explicit buffer/texture lifetime. |
| [`src/scheme/immutable.sld`](src/scheme/immutable.sld) | Functional record replacement, attached deriving and small immutable list operations. |
| [`src/lofi/serialization.sld`](src/lofi/serialization.sld) | Separate checked serialization capabilities, derived data instances and traversal-local graph identities. |
| [`src/lofi/scalar-text.sld`](src/lofi/scalar-text.sld) | Owned scalar text tokens, interned symbols, diagnostics and exact I64 formatting without the dynamic datum/number layers. |
| [`src/lofi/sexp.sld`](src/lofi/sexp.sld) | Finite S-expression wire values with lossless readable text and compact binary encodings. |
| [`src/native/`](src/native/README.md) | Independent Wasm-to-LLVM package, shared Rust scalar services and native collector. |
| [`scripts/`](scripts/) and [`tools/host/`](tools/host/) | Executable orchestration and host tool configuration. |
| [`scripts/format-scheme`](scripts/format-scheme.el) | Scheme indentation with one import specification or record field per line; shared by the editor and `make format`/`make check`. |
| [`tests/`](tests/README.md) | Integration fixtures, runners, shared assertions, and the complete backend inventory and CI partition checks. |
| [`doc/spec/`](doc/spec/README.md) | Ott language syntax and formation rules, generated Rocq definitions, and checked formation proofs; an incremental draft alongside the book. |
| [`benchmarks/`](benchmarks/README.md) | All 57 workloads, controls and preserved measurement evidence. |

Within the native package, `src/native/llvm.sld` publishes live references
and reloads them after collecting calls. `src/native/native_gc.rs` owns the Immix block
allocator, tracing, opportunistic evacuation and weak cleanup. Its optional
`gc-trace` host recording exports collection pauses as Chromium events.
`src/native/native.rs`
defines writable roots and the scalar/runtime ABI; allocating helpers protect
their own reference arguments. Following the product compiler does not require
following these native lifetime rules. `src/native/runtime/` is the scalar-services
crate shared by Wasm and native; only the parent native crate includes the GC.
See [the native contract](doc/book/native/index.md).

Use the [detailed compiler reference](doc/compiler.md) for pass contracts and
execution APIs, and the [language book](doc/book/lofi/index.md) for semantics.
