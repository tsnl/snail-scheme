# The SFIR compiler

Chibi hosts the compiler implementation. The supported input is located SFIR,
with no Scheme expander or interpreter in the compilation pipeline.

```text
SFIR text → located syntax → parsed library values → resolved IR → inferred/checkable IR
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

Numeric tokens retain their original spelling through syntax and resolved IR.
[`numeric-literals.sld`](src/snail-sfir/numeric-literals.sld) decodes exact decimal
values and rounds directly to the selected IEEE width, including subnormals and
overflow boundaries. The reader also uses its exact decoding for bytevector
elements; host floating-point approximations cannot turn a fraction into a byte.
Inference fixes ordinary numeric literals at I32 or F64. Only an immediately
enclosing `ann` or a direct binding annotation selects another scalar width;
call, branch and result expectations check the fixed representation. `Any`
therefore stores the default width unless the literal explicitly selects one.

[`frontend.sld`](src/snail-sfir/frontend.sld) parses the small SFIR grammar into
`SfirLibrary` values without loading dependencies. `parse-library` accepts one
located `define-library`; `syntax-list->sfir-library` also accepts a script body.
It reserves each block's bindings before parsing initializers. Local references
carry binding identities; unresolved imports carry a name, the library's import
scope, a syntactic category and a location. `def` reserves a block-wide identity;
each sequential `let` introduces its identity after parsing its initializer.
Both become ordinary binding nodes in source order. Value and type scopes are
separate, so an argument name cannot hide an enclosing quantified type variable.
Library `begin` clauses concatenate before parsing; expression `begin` keeps
its own lexical scope. No step performs inference or executes user source.

[`snail-sfir/library.sld`](src/snail-sfir/library.sld) records parsed library
identities, descriptive imports, exports and located declarations. Its
`resolve-library-map` accepts an association list of library keys to parsed
values and returns an association list of keys to resolved libraries. This
Chibi-hosted API resolves every supplied map entry, including entries outside a
chosen root's dependency closure. It never loads dependencies. Aliases of one
value resolve once; reexports and overload
extensions retain the provider's binding identity. Missing providers, conflicting
names and dependency cycles are errors. Empty `only` selections retain their
provider's initialization and instances. Each resolution owns new IR, so the
same parsed consumer can be resolved against different provider maps.

[`snail-scheme/library.sld`](src/snail-scheme/library.sld) records the resulting
resolved imports and exports. Dependency traversal initializes each library
identity once before its users. [`ir.sld`](src/snail-scheme/ir.sld) holds the shared
expression and binding records, initially with type holes and attached declared
signatures. Immutable `LibraryId` and `BindingId` origins survive resolution and
checking copies; mutable definition objects are canonical within their own graph.
[`signatures.sld`](src/snail-sfir/signatures.sld) retains quantified source type
identities. A hole is missing compile-time information, never an implicit Any.
The internal solver and Wasm emitter still spell the universal type `Top`;
the source surface uses `Any`.

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
and an optional typed rest parameter. Declared initializer proofs retain their
lexical scope until enclosing monotypes settle. Their own quantified requirements
must then hold; obligations on captured monotypes remain with enclosing inference.

Recursive groups containing `All` first solve a private monomorphic template,
then check the original bodies with independent rigid interpretations. Fixed
recursive instantiation tuples include phantom parameters. Inferred groups keep
one checking pass; both paths freeze variables shared with expansive members
before generalization. Representable value cycles use ordinary source-order
initialization and retain premature-read traps.

[`strict-overloads.sld`](src/snail-scheme/strict-overloads.sld) resolves complete
argument/result constraints with coherent class requirements.
[`strict-data.sld`](src/snail-scheme/strict-data.sld) prepares nominal data,
constructors and fields. Matching checks exhaustiveness and lowers to ordinary
bindings and branches. [`strict-primitives.sld`](src/snail-scheme/strict-primitives.sld)
assigns concrete operation signatures. Explicit Any conversions preserve the
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

[`compiler.sld`](src/snail-sfir/compiler.sld) composes the passes.
The Chibi-hosted `library-map->core` resolves the supplied parsed map and checks
the chosen root's dependency closure. It requires no tracing or source context.
`compile` takes that same map, `(make-entry library-key public-name)`, and a
target value. Selection follows the chosen library's public interface through
renames and reexports. A private ABI binding references the selected identity
after the library initializers; checking and specialization retain that identity
even when unrelated private bindings have the same spelling. Entries require
monomorphic functions with fixed scalar parameters and a scalar or Unit result.
Inferred function signatures are accepted; an `All` entry needs type arguments
that this interface does not supply.

[`source-driver.sld`](src/snail-sfir/source-driver.sld) owns file selection,
independent library preparation and dependency collection, including compiled
`generate-library` recipes. Producer and application maps are separate; a shared
preparation chain diagnoses cycles and preserves each selected value's identity.
The older frontend convenience APIs remain adapters for already parsed source.
The source driver's `sfir.parse`, `sfir.check`, `sfir.specialize` and `sfir.emit-wasm`
trace spans expose the boundaries. [`chromium-trace.sld`](src/snail-scheme/chromium-trace.sld)
requires an explicit trace scope. [`scripts/view-traces`](scripts/view-traces)
opens retained evidence in Perfetto.

The source CLI keeps its existing script behavior and `--export` selector for
unique flattened binding names. The library API uses public Entry selection.
SFIR producers can construct, inspect and transfer the complete library syntax
described below. General compiler functions callable from SFIR remain
unimplemented. The Wasm execution adapter below provides loading, independent
instances and checked scalar invocation to JavaScript hosts; these operations
are not yet Chibi or SFIR library functions.

[`run-sfir-generator.mjs`](scripts/run-sfir-generator.mjs) executes compiled
recipes through the checked builder boundary. An explicit provider factory
receives the selected descriptor's directory and owns its foreign services until
cleanup. The driver registers the returned syntax and separately obtains its
imports. See [source recipes](doc/sfir-generation.md) for the API, command example,
source context and preparation errors.

## Constructed library values

[`compiler-builder.sfir`](lib/sfir/compiler-builder.sfir) lets compiled SFIR
producers compose nominal library, declaration, type, scope, binding and reference
values. Constructors use explicit operands; no ambient current library is mutated.
The API covers the book's types and binding signatures, literals, expressions,
ordered blocks, static definitions and existing extern/overload extensions.
Explicit type-variable identities carry generic scope alongside ordinary binding
identities. Typed inspection views expose all constructor fields and copy mutable
literal payloads. Binding references are distinct from expressions, and private
handles do not expose managed pointers.

[`library-builder.mjs`](src/snail-sfir/library-builder.mjs) supplies typed scalar
constructors in an invocation-owned arena. `invokeLibraryGenerator` initializes
and calls an ordinary compiled producer, copies its completed syntax graph into
an owned transfer, and closes the arena and producer instance on success or trap.
The transfer has a versioned schema and preserves nodes and their local IDs.

[`library-transfer.sld`](src/snail-sfir/library-transfer.sld) receives that data
in Chibi, checks Unicode and structure, then reserves definitions and visits
statements in order, introducing each `let` after its initializer. Every reference
is checked against its lexical occurrence, including quantified type identities
and static binding roles. It shares the frontend's reserved binding-name rule
and creates an unresolved `SfirLibrary`. An explicit receiving context preserves
reuse of legitimate owned transfers; reading raw bytes again creates fresh
identities.
Output imports need their own supplied map. The receiver neither discovers
dependencies nor accepts inferred IR as evidence. See the [builder API and
executable example](doc/sfir-builder.md) for ownership, supported constructors,
typed inspection and remaining compiler-service work.

## Targets and runtime

[`snail-sfir`](snail-sfir) owns command parsing, private build directories,
publication and host invocation. [`build-sfir`](scripts/build-sfir) and
[`build-native`](scripts/build-native) preserve intermediates for module-level
work. [`wasm-optimize.sld`](src/snail-scheme/wasm-optimize.sld) requires Binaryen
and optimizes program Wasm on every target.

[`snail-sfir/artifact.sld`](src/snail-sfir/artifact.sld) implements the Chibi
Entry, Target and Artifact boundary. `wasm-target` returns optimized, unlinked
Wasm bytes with a versioned `sfir.entry` custom section containing the public
Entry description and semantic scalar signature. The section is appended after
Binaryen optimization; loading verifies its schema and execution verifies the
actual exported signatures. `(native64-target imports)` returns an unlinked
x86-64 Linux relocatable object, using the existing Wasm-to-LLVM route followed
by Clang. Its explicit
provider declarations are `(make-native-import module name c-symbol parameters
result)`: string names, physical `i32`/`i64`/`f32`/`f64` parameter types, and a
scalar or `void` result. Missing declarations and signature mismatches fail.
Both targets require Binaryen. Tool temporaries live in a private directory;
compilation reads no source files and returns artifact bytes for the caller to
write. Provider and runtime linking remain separate target operations.

Artifact accessors expose the target, original Entry, semantic scalar parameter
and result types, and bytes. The fixed ABI exports `entry` for the selected
function and `main` for one-shot library initialization; native symbols are
`wasm.entry` and `wasm.main`, after `native_module_init`. Calling `entry` before
successful initialization traps. A public SFIR export named `main` is therefore
unambiguous. Native object bytes do not themselves represent a running instance.

[`snail-sfir/execute.mjs`](src/snail-sfir/execute.mjs) is the explicit JavaScript
Wasm execution adapter. `loadWasm(bytes)` snapshots a `Uint8Array`, validates the
module and saved scalar metadata, and returns loaded code with read-only
`entry`, `parameters` and `result` descriptions. It performs no library
initialization. It rejects automatic Wasm start functions and non-function
imports, which could otherwise execute or share mutable state before checking.

`instantiate(code, providers)` accepts a `Map` from import module names to
already instantiated `WebAssembly.Instance` providers. Their actual Wasm function
exports supply typed imports; plain JavaScript functions are not accepted as
provider values. The engine checks provider signatures during linking. A tiny
module containing only typed imports then checks the actual `entry` and `main`
exports against the saved ABI without calling them. Only then does the adapter
run `main`, once, and return an opaque instance. Each call creates fresh program
globals and managed state, including across separate loads of the same bytes.
Reusing a provider instance explicitly shares that provider's state. Mutating
the provider map later does not change already bound imports.

Initialization failure throws `InitializationError` with its cause and returns
no instance handle. Completed external effects remain, while dependent
initializers do not run. `invokeEntry(instance, arguments)` checks arity and
semantic scalar values before calling the saved entry. I32 uses integral
JavaScript numbers in signed 32-bit range; I64 uses signed 64-bit `BigInt` values
without a floating conversion. Bool uses booleans, encoded as canonical 0/1.
Char uses one Unicode scalar string, excluding surrogates. F32 uses numbers
rounded with `Math.fround`, rejecting finite values that round to infinity;
underflow and explicit infinities remain supported. F64 uses numbers directly.
Both preserve signed zero and NaN. Results receive the corresponding checks and
conversions; Unit returns `undefined`. Managed-reference parameters and results
remain unsupported.

Calls are synchronous; reentrant invocation or closing an executing instance
is rejected. An invocation trap retains prior effects and does not poison a
successfully initialized instance. `closeInstance` is idempotent, rejects future
calls and drops the adapter's reference to the program instance. Shared providers
and their external resources remain owned by the caller, including cleanup. The
adapter discovers no files, constructs no WASI or Rust providers, and does not
load native64 objects. Native loading still needs an isolation model that gives
each instance fresh native globals, such as a persistent process per instance.

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
`scripts/test-sfir-entry` compiles supplied library maps, links public Entry
artifacts to foreign providers, and executes both Wasm and native64 aliases.
`scripts/test-sfir-execution` exercises the Wasm adapter with typed providers,
independent state, failed initialization and checked scalar transport.
`scripts/test-sfir-builder` compiles an SFIR producer, transfers its structured
result into a separate Chibi host, and compiles and executes the received library.
Its complete-library fixture rebuilds syntax through typed inspection and compares
with ordinary source on linked Wasm and native execution with frequent collection;
malicious packets test lexical ownership, static roles, Unicode and unforgeable
checking evidence.
`scripts/test-sfir-integration` executes 307 authored SFIR fixtures retaining the
previous compiler contracts. `scripts/test-backend` combines these with extern,
library, scalar-service and Binaryen checks; `scripts/test-native` exercises
mechanical lowering, collection, C signatures and resource cleanup.

The [benchmark corpus](benchmarks/README.md) keeps 57 workloads, authored SFIR,
Chez controls and Rust comparisons. Source availability, execution correctness
and clean measurement are distinct statuses. Compiler traces and instrumented
runs explain work; they are not substituted for clean timing runs.

`benchmarks/sfir/runner.py` freezes the corpus inputs and validates each target
route. Dynamic, Scheme and SLaTeX keep their complete workload and resource
contracts in local verifiers and native entries; the runner owns fixture copies,
tool invocation and artifact parity. Scheme's interpreter is benchmark code.
`benchmarks/sfir/timing.py` prepares clean artifacts, fixes the comparison
schedule, supervises fresh execution processes and summarizes complete sample
sets. Failed routes remain visible alongside measured routes.

## Language specification

The [SFIR book](doc/book/sfir/index.md) develops the proposed language, library
values and staged builds. [Its entry page](doc/sfir.md) links the chapters and
preview commands. `scripts/book` builds or serves the book; shared rule snippets
keep the explanations and formal summary synchronized. The book specifies design
contracts, while this tour describes the installed implementation.
