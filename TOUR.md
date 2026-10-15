# The SFIR compiler

Chibi hosts the compiler implementation. The supported input is located SFIR,
with no Scheme expander or interpreter in the compilation pipeline.

```text
SFIR text → located syntax → resolved IR → inferred/checkable IR
          → concrete specializations → WasmGC → Binaryen
          → linked Wasm reactor → Binaryen → V8/WASI
          → mechanical LLVM lowering → native linker → 64-bit executable
```

The [language contract](doc/sfir.md) describes intended language behavior. This
tour describes the current modules; the `snail-scheme` and `strict-*` internal
filenames are being migrated and do not select a second source language.

## Source and binding identity

[`source.sld`](src/snail-scheme/source.sld) defines filename, line and column.
[`reader.sld`](src/snail-scheme/reader.sld) provides immutable character cursors.
[`parser.sld`](src/snail-scheme/parser.sld) composes located parsers;
[`syntax-parser.sld`](src/snail-scheme/syntax-parser.sld) reads explicit
s-expressions and rejects quote abbreviations. These are implementation modules
written in Scheme; Chibi reads their own source.

[`frontend.sld`](src/snail-sfir/frontend.sld) resolves the small SFIR grammar.
It reserves each block's bindings before resolving initializers. Every reference
names a binding identity; imports and aliases retain that identity. Library
cycles and conflicting imports are errors. `let` becomes direct lambda
application with its initializers in the outer scope. `begin` keeps a lexical
scope and ordered initialization events. No step performs inference or executes
user source.

[`library.sld`](src/snail-scheme/library.sld) records resolved imports and
exports. Dependency traversal initializes each imported library once before its
users. [`ir.sld`](src/snail-scheme/ir.sld) holds the shared expression and binding
records, initially with type holes and attached declared signatures.
[`signatures.sld`](src/snail-sfir/signatures.sld) retains quantified source type
identities. A hole is missing compile-time information, never an implicit Top.

## Type evidence

[`strict-types.sld`](src/snail-scheme/strict-types.sld) owns inference holes,
rigid quantified variables, unification, substitution, schemes and subtyping.
[`strict-core.sld`](src/snail-scheme/strict-core.sld) records the checked program
and its class evidence.

[`strict-infer.sld`](src/snail-scheme/strict-infer.sld) checks every body, including
unused functions, on an owned copy of the resolved graph. Each lexical block
builds direct dependencies once and groups mutually recursive bindings. Group
members retain source order. Overload-row readiness is checked separately as
signatures become known; this never reorders runtime initializers. Mutable
allocations obey the value restriction. Concrete calls have positional arguments
and an optional typed rest parameter.

[`strict-overloads.sld`](src/snail-scheme/strict-overloads.sld) resolves complete
argument/result constraints with coherent class requirements.
[`strict-data.sld`](src/snail-scheme/strict-data.sld) prepares nominal data,
constructors and fields. Matching checks exhaustiveness and lowers to ordinary
bindings and branches. [`strict-primitives.sld`](src/snail-scheme/strict-primitives.sld)
assigns concrete operation signatures. Explicit Top conversions preserve the
checks required at dynamic boundaries.

## Concrete code and storage

[`strict-specialize.sld`](src/snail-scheme/strict-specialize.sld) copies demanded
concrete implementations. A source site owns initialization, a value owns a
concrete payload, and a function owns code. Sharing code does not duplicate
initialization. Captures, forward-read guards, class evidence and export
signatures remain explicit. Unsupported specialization is a compilation error.

[`strict-wasm.sld`](src/snail-scheme/strict-wasm.sld) maps these concrete types to
Wasm scalars, structs, arrays and function references. It emits operations and
checks directly, using typed storage for container elements. The shared
[`wasm.sld`](src/snail-scheme/wasm.sld) only serializes Wasm data; the old Scheme
emitter has been removed.

[`compiler.sld`](src/snail-sfir/compiler.sld) composes the passes and library
lookup. Its `sfir.resolve`, `sfir.infer`, `sfir.specialize` and `sfir.emit-wasm`
trace spans expose the boundaries. [`chromium-trace.sld`](src/snail-scheme/chromium-trace.sld)
requires an explicit trace scope. [`scripts/view-traces`](scripts/view-traces)
opens retained evidence in Perfetto.

## Targets and runtime

[`snail-sfir`](snail-sfir) owns command parsing, private build directories,
publication and host invocation. [`build-sfir`](scripts/build-sfir) and
[`build-native`](scripts/build-native) preserve intermediates for module-level
work. [`wasm-optimize.sld`](src/snail-scheme/wasm-optimize.sld) requires Binaryen
and optimizes program Wasm on every target.

[`link-sfir-runtime`](scripts/link-sfir-runtime) links the Rust scalar externs
into a WASI reactor, drops unused runtime exports and optimizes the result.
[`run-sfir.mjs`](scripts/run-sfir.mjs) initializes once, invokes `main`, and drains
resource cleanup. The [SFIR libraries](lib/sfir/README.md) implement numeric,
container, datum and I/O behavior in SFIR; Rust externs supply concrete host
operations. Wasm owns managed collection.

[`lib.rs`](src/lib.rs) contains runtime initialization, diagnostics and shared
floating-point text. [`strict_io.rs`](src/strict_io.rs) owns file IDs and terminal
cleanup; [`host.rs`](src/host.rs) implements buffered Unicode streams. The datum
services retain temporary token text and stable symbol IDs, while SFIR owns the
reader and managed datum graph. These services accept scalars and never retain
guest GC roots. There is no boxed Scheme-value ABI or wrapper-finalizer bridge.

[`text.sfir`](lib/sfir/text.sfir) owns string ordering and full case-fold output
storage. [`strict_text.rs`](src/strict_text.rs) exposes Unicode operations as
scalar C/Wasm functions. [`unicode.rs`](src/unicode.rs) keeps one generated
folding implementation with at most three stack-resident output scalars;
[`generate-unicode`](scripts/generate-unicode) checks that bound against pinned
Unicode data and Rust's recorded casing baseline.

[`native.sld`](src/snail-scheme/native.sld) optimizes Wasm before lowering.
[`wasm-read.sld`](src/snail-scheme/wasm-read.sld) reads Binaryen's spelling;
[`wasm-resolve.sld`](src/snail-scheme/wasm-resolve.sld) resolves Wasm identities.
[`llvm.sld`](src/snail-scheme/llvm.sld) mechanically lowers those operations;
[`llvmlite.sld`](src/snail-scheme/llvmlite.sld) writes LLVM text. Native uses the
same Rust extern implementations and resolves imports directly against
authoritative C provider declarations. [`precise-gc.c`](src/precise-gc.c) owns
native managed collection. Root and slot lifetime invariants live beside
the lowering and collector that rely on them.

## Checks and measurements

`make test` executes compiler host tests. `scripts/test-sfir` checks explicit
syntax, typing, module identity and actual V8 execution. `scripts/test-build`
checks the public command, cleanup and publication on Wasm and native.
`scripts/test-sfir-integration` executes 307 authored SFIR fixtures retaining the
previous compiler contracts. `scripts/test-backend` combines these with extern,
library, scalar-service and Binaryen checks; `scripts/test-native` exercises
mechanical lowering, collection, C signatures and resource cleanup.

The [benchmark corpus](benchmarks/README.md) keeps 57 workloads, authored SFIR,
Chez controls and Rust comparisons. Source availability, execution correctness
and clean measurement are distinct statuses. Compiler traces and instrumented
runs explain work; they are not substituted for clean timing runs.

`benchmarks/sfir/runner.py` freezes the corpus inputs and validates each target
route. `benchmarks/sfir/timing.py` prepares clean artifacts, fixes the comparison
schedule, supervises fresh execution processes and summarizes complete sample
sets. Failed routes remain visible alongside measured routes.
