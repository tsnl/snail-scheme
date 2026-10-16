# The SFIR compiler

Chibi hosts the compiler implementation. The supported input is located SFIR,
with no Scheme expander or interpreter in the compilation pipeline.

```text
Compiler: SFIR text → located syntax → parsed library values → resolved source
          → binding/scope checking → concrete demand → source-based WasmGC → Binaryen
Build:    optimized Wasm → runtime Wasm linkage → Binaryen → V8/WASI
          optimized Wasm → wasm-native → optimized LLVM bitcode
                         → Cargo LTO + Rust runtime/providers → x86-64 Linux executable
```

The [language contract](doc/sfir.md) describes intended language behavior. This
tour describes the current modules; the `snail-scheme` and `strict-*` internal
filenames are being migrated and do not select a second source language.
The compiler emits Wasm only. Ordinary Chibi scripts independently import the
compiler and [`wasm-native`](wasm-native/README.md) when composing a native build.
The standalone package contains the native lowering, shared Rust runtime and
neutral host utilities; it has no compiler dependency.

The directory names separate responsibilities. `src/snail-sfir` contains the
public compiler API, library loading and frontend; `src/snail-scheme` contains
compiler internals under their historical name. Both are Scheme hosted by Chibi.
`lib/sfir` contains libraries written in SFIR, and `wasm-native` is the separate
native backend and runtime package.

For a first read, start with `compile` and `entry-program` in
[`compiler.sld`](src/snail-sfir/compiler.sld), then the source records in
[`ir.sld`](src/snail-scheme/ir.sld). Follow `generate-call` in
[`strict-specialize.sld`](src/snail-scheme/strict-specialize.sld) alongside
`rule-call` in [`strict-infer.sld`](src/snail-scheme/strict-infer.sld) and
`emit-application-rule` in [`strict-wasm.sld`](src/snail-scheme/strict-wasm.sld).
These show how one source call becomes constraints, concrete demand and Wasm.

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
source expression and binding records. Expressions have no inferred type or
constraint fields; binding definitions retain attached declarations and schemes.
Immutable `LibraryId` and `BindingId` origins survive resolution and
checking copies; mutable definition objects are canonical within their own graph.
[`signatures.sld`](src/snail-sfir/signatures.sld) retains quantified source type
identities. A hole is missing compile-time information, never an implicit Any.
The internal solver and Wasm emitter still spell the universal type `Top`;
the source surface uses `Any`.

## Type evidence

[`strict-types.sld`](src/snail-scheme/strict-types.sld) owns inference holes,
rigid quantified variables, unification, substitution, schemes and subtyping.
[`strict-core.sld`](src/snail-scheme/strict-core.sld) records immutable source,
binding schemes, lexical scopes, lambda signatures, the program result type and
class evidence.
[`strict-pass.sld`](src/snail-scheme/strict-pass.sld) defines the small `pass` record
and shared source-arm dispatch. Typing rules receive returned child judgments;
the visitor owns scope and expected-type dependencies.

[`strict-infer.sld`](src/snail-scheme/strict-infer.sld) checks every body, including
unused functions, on an owned binding graph without mutating source expressions.
Transient judgments contain no child judgments; only binding and scope summaries
survive checking. Each lexical block
builds direct dependencies once and groups mutually recursive bindings. Group
members retain source order. Every overload row supplies an explicit signature,
so checking can use the complete family before checking implementation bodies.
Ordinary groups are checked once in dependency order. Mutable allocations obey
the value restriction. Concrete calls have positional arguments
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
constructors and fields. Matching checks exhaustiveness and retains pattern binding
types; generation emits field reads and branches directly from source arms.
[`strict-primitives.sld`](src/snail-scheme/strict-primitives.sld)
assigns concrete operation signatures. Explicit Any conversions preserve the
checks required at dynamic boundaries.

## Concrete code and storage

[`strict-specialize.sld`](src/snail-scheme/strict-specialize.sld) reserves demanded
implementations in a persistent hash map and drains a pending list.
[`hashmap.sld`](src/snail-scheme/hashmap.sld) implements the compiler's
[SRFI 146](https://srfi.schemers.org/srfi-146/srfi-146.html) subset with a compressed
binary hash trie. Lookup follows an explicit tail loop;
update records and rebuilds the changed path while sharing untouched branches.
Collision buckets retain comparator equality, and old map snapshots remain valid.
Its supported operations are construction, lookup, functional set, folding,
membership, size and comparator access; it does not replace the host's full library.
Source identity, concrete quantifier substitutions and lexical instance identity
select stable IDs before recursive requests. A site owns initialization, a value
owns a concrete payload, and a function owns code. Summary discovery records
reads and nested closures, then settles capture requirements without constructing
a concrete expression tree. Source-order initialization and erased alias readiness
checks remain separate from code demand.

[`strict-wasm.sld`](src/snail-scheme/strict-wasm.sld) supplies emission operations
to the explicit source visitor. Each visit returns a transient typing judgment,
generated code and the next request context. Typing rules consume immediate child
judgments; separate emission rules consume generated children. Target code is
emitted after capture and storage summaries settle. Scalars, structs, arrays,
precise Any witnesses and tail calls retain their existing Wasm contracts.
An exact lexical self call reuses its current environment after the ordinary
operator read; concrete binding identity and a literal initializer establish
the proof. Emission checks that demand is already complete. The shared
[`wasm.sld`](wasm-native/scheme/wasm-native/wasm.sld) serializes Wasm data.

[`wasm-strings.sld`](src/snail-scheme/wasm-strings.sld) owns the UTF-8 string
layout and its emitted Wasm operations. Each owner retains a scalar count, used
byte length, packed backing array and cached scalar/byte boundary. Conversion
validates once and copies bytes; slicing and equality operate on encoded spans.
Width-changing mutation preserves owner identity and updates its backing storage.
Large literals are filled by module start before source execution. The mechanical
native lowering executes the same operations and publishes their managed roots.

Concrete signatures take the fused path without subtree typing. Unresolved call
arguments and branch results may require an explicit type-only constraint probe
before choosing their layouts. Source and nominal identities in request keys are
opaque; hashing a request never walks an expression body. Local procedures use
ordinary closures; direct primitive/foreign/data operations and known worker
calls remain. Closure elimination and proven-global
readiness-check elimination are deferred. Private target local/layout registries
remain mutable. These [implementation tradeoffs](doc/ir.md#current-tradeoffs) are
separate from language semantics and measured runtime performance.

[`compiler.sld`](src/snail-sfir/compiler.sld) composes the passes.
The Chibi-hosted `library-map->core` resolves the supplied parsed map and checks
the chosen root's dependency closure. It requires no tracing or source context.
`compile` takes that same map and `(make-entry library-key public-name)`, and
returns an optimized Wasm artifact. Selection follows the chosen library's public
interface through
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
trace spans expose the boundaries. [`chromium-trace.sld`](wasm-native/scheme/wasm-native/chromium-trace.sld)
requires an explicit trace scope. [`scripts/view-traces`](scripts/view-traces)
opens retained evidence in Perfetto.

`scripts/build-sfir` keeps its script behavior and `--export` selector for unique
flattened binding names. The library API uses public Entry selection.
SFIR producers can construct, inspect and transfer the complete library syntax
described below. [`(sfir compiler)`](lib/sfir/compiler.sfir) also exposes explicit
map assembly, compilation, Wasm loading, independent instantiation and checked
scalar entry invocation as ordinary SFIR calls. Every fallible operation returns
an ordinary `CompilerResult` success or diagnostic string.

[`compiler-service.mjs`](src/snail-sfir/compiler-service.mjs) owns one Chibi
process, the matching builder arena, copied artifacts and runtime instances.
[`serve-sfir-compiler.scm`](scripts/serve-sfir-compiler.scm) parses supplied source
once or receives constructed syntax and retains unresolved library values in
immutable maps. Compilation resolves only the supplied map; provider linkage
remains a separate execution operation. Failed initialization publishes no
instance; a trapped call retains its instance and preceding effects. A lost
compiler process invalidates map operations while copied artifacts and existing
runtime instances remain owned by the service scope. See the
[service API](doc/sfir-compiler-service.md) for lifecycle rules, Wasm execution
and first-class parsed `SfirLibrary` values. The separate Scheme native
loading adapter is described below.

[`run-sfir-generator.mjs`](scripts/run-sfir-generator.mjs) executes compiled
recipes through the checked builder boundary. An explicit provider factory
receives the selected descriptor's directory and owns its foreign services until
cleanup. The driver registers the returned syntax and separately obtains its
imports. See [source recipes](doc/sfir-generation.md) for the API, command example,
source context and preparation errors.

## Parsed and constructed library values

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
The same arena receives copied parse packets with checked structure and fresh
local identities; parsed and constructed values share all typed views.
The transfer has a versioned schema and preserves nodes and their local IDs.

[`library-transfer.sld`](src/snail-sfir/library-transfer.sld) receives that data
in Chibi, checks Unicode and structure, then reserves definitions and visits
statements in order, introducing each `let` after its initializer. Every reference
is checked against its lexical occurrence, including quantified type identities
and static binding roles. It shares the frontend's reserved binding-name rule
and creates an unresolved `SfirLibrary`. An explicit receiving context preserves
reuse of legitimate owned transfers; reading raw bytes again creates fresh
identities.
Its reverse writer traverses unresolved parser declarations with binder identity
maps, deriving scope owners from lexical structure. `def`/`let` evidence, attached
signature locations, quantified variables and numeric source spellings survive
that copy. Parsing still uses only `frontend.sld`; no types are inferred during
transfer. Output imports need their own supplied map. The receiver neither discovers
dependencies nor accepts inferred IR as evidence. See the [builder API and
executable example](doc/sfir-builder.md) for ownership, supported constructors,
and typed inspection.

## Wasm artifacts, native composition and runtime

[`snail-sfir`](snail-sfir) owns command parsing, private build directories,
publication and Wasm host invocation. [`build-sfir`](scripts/build-sfir) and
[`build-native`](scripts/build-native) preserve intermediates for module-level
work. The latter is an ordinary composition script that passes emitted Wasm to
the native package, then links its object with Cargo. [`build.scm`](build.scm)
shows these library calls directly for an explicit public export and Rust entry
point. [`wasm-optimize.sld`](wasm-native/scheme/wasm-native/wasm-optimize.sld)
requires Binaryen on both execution routes.

[`snail-sfir/artifact.sld`](src/snail-sfir/artifact.sld) implements the Chibi
Entry and Artifact boundary. Compilation returns optimized, unlinked Wasm bytes
with a versioned `sfir.entry` custom section containing the public
Entry description and semantic scalar signature. The section is appended after
Binaryen optimization; loading verifies its schema and execution verifies the
actual exported signatures. Tool temporaries live in a private directory;
compilation reads no source files and returns artifact bytes for the caller to
write. Provider and runtime linking remain explicit build operations.

[`(wasm-native)`](wasm-native/scheme/wasm-native.sld) exposes
`wasm-binary->llvm`, `llvm-bitcode`, `llvm-object` and `link-native-object`.
Its provider declarations are
`(make-native-import module name c-symbol parameters result)`:
string names, physical `i32`/`i64`/`f32`/`f64` parameter types, and a scalar or
`void` result. Missing declarations and signature mismatches fail. Lowering
consumes the Wasm representation, physical imports and runtime ABI; it receives
no source bindings, inference state or compiler IR.

[`snail-sfir/native.sld`](src/snail-sfir/native.sld) is the optional source-aware
adapter. `(artifact->native-object artifact imports directory output)` supplies
the saved scalar signature and source entry description to
[`scalar-entry.sld`](wasm-native/scheme/wasm-native/scalar-entry.sld). That optional
protocol layer checks the actual optimized Wasm `main`/`entry` signatures and
emits a fixed scalar-bits bridge into the native LLVM module. An ELF `.sfir.entry`
section and signature-encoded bridge alias preserve the scalar tags, origin
description and required foreign declarations. Bool and Char remain distinct
protocol tags despite sharing physical `i32`. The native loader checks their
consistency; arbitrary native code remains trusted. Ordinary native builds with
a supplied Rust entry point need no scalar-entry metadata.

Artifact accessors expose the original Entry, semantic scalar parameter
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
load native64 objects.

[`execute.sld`](wasm-native/scheme/wasm-native/execute.sld) provides `load-native`,
explicit `link-native`, `instantiate`, `invoke-entry` and `close-instance` for
x86-64 Linux objects carrying the optional scalar protocol. Its fourth
`link-native` argument explicitly supplies the runtime root. It checks declared
Rust provider ABIs,
uses exact binary scalar transport, and gives each instance fresh native globals,
GC and provider state. [`native_worker.rs`](wasm-native/src/native_worker.rs) supplies
a separate supervisor and guest worker; ownership precedes provider constructors.
Failed initialization publishes no instance. Native traps and interrupted calls
invalidate their instance; the supervisor reaps its owned descendants, including
after host death. The [native loading contract](doc/sfir-native-loading.md)
describes the API, retained logs, unsafe native boundary and target limitations.

[`link-sfir-runtime`](scripts/link-sfir-runtime) calls
[`runtime-wasm.sld`](wasm-native/scheme/wasm-native/runtime-wasm.sld), which builds
the Rust runtime's Wasm form, links its scalar externs into a WASI reactor,
drops unused runtime exports and optimizes the result. This utility imports no
native lowering or execution code.
[`run-sfir.mjs`](scripts/run-sfir.mjs) initializes once, invokes `main`, and drains
resource cleanup. The [SFIR libraries](lib/sfir/README.md) implement numeric,
container, datum and I/O behavior in SFIR; Rust externs supply concrete host
operations. Wasm owns managed collection.

[`wasm-native/Cargo.toml`](wasm-native/Cargo.toml) defines the one runtime crate.
[`lib.rs`](wasm-native/src/lib.rs) contains runtime initialization, diagnostics and shared
floating-point text. [`strict_io.rs`](wasm-native/src/strict_io.rs) owns file IDs and terminal
cleanup; [`host.rs`](wasm-native/src/host.rs) implements buffered Unicode streams. The datum
services retain temporary token text and stable symbol IDs, while SFIR owns the
reader and managed datum graph. These services accept scalars and never retain
guest GC roots. There is no boxed Scheme-value ABI or wrapper-finalizer bridge.

[`io.sfir`](lib/sfir/io.sfir) shares an owned file's pending input and closed
handle across aliases. Rust returns up to seven already-buffered ASCII characters
in one scalar packet; character, line and datum reads consume that same cursor.
Optional packet bytes never refill the native buffer or decode a later invalid
suffix. Borrowed stdin retains the native scalar read/peek cursor so direct
foreign reads interoperate. The [input contract](lib/sfir/README.md#text-input-cursor)
describes the representation, EOF behavior and execution checks.

[`text.sfir`](lib/sfir/text.sfir) owns string ordering and full case-fold output
storage. [`strict_text.rs`](wasm-native/src/strict_text.rs) exposes Unicode operations as
scalar C/Wasm functions. [`unicode.rs`](wasm-native/src/unicode.rs) keeps one generated
folding implementation with at most three stack-resident output scalars;
[`generate-unicode`](scripts/generate-unicode) checks that bound against pinned
Unicode data and Rust's recorded casing baseline.

[`native.sld`](wasm-native/scheme/wasm-native/native.sld) optimizes Wasm before lowering.
[`wasm-read.sld`](wasm-native/scheme/wasm-native/wasm-read.sld) reads Binaryen's spelling;
[`wasm-resolve.sld`](wasm-native/scheme/wasm-native/wasm-resolve.sld) resolves Wasm identities.
[`llvm.sld`](wasm-native/scheme/wasm-native/llvm.sld) mechanically lowers those operations,
including checked array header loads and addressing with known storage widths;
[`llvmlite.sld`](wasm-native/scheme/wasm-native/llvmlite.sld) writes LLVM text. Native uses the
same Rust extern implementations and resolves imports directly against
literal Rust `extern "C"` provider declarations. [`native_gc.rs`](wasm-native/src/native_gc.rs) owns
native managed collection. Root and slot lifetime invariants live beside
the lowering and collector that rely on them.

[`process.sld`](wasm-native/scheme/wasm-native/process.sld) owns concrete command
capture, files and evidence. [`json.sld`](wasm-native/scheme/wasm-native/json.sld) reads one
complete JSON packet, preserves standard control escapes across the Chibi host
boundary, and emits escaped control characters in metadata and command evidence.
Trailing input is rejected. [`native-build.sld`](wasm-native/scheme/wasm-native/native-build.sld)
checks scalar provider declarations, runs LLVM, and assembles a Cargo package
with one runtime dependency and ordinary provider crates. Rust target `cfg`s
select Wasm or native host behavior inside that shared runtime library. The
native executable build retains guest bitcode until linker-plugin fat LTO can
optimize it with the Rust entry, runtime and providers. `llvm-object` remains the explicit
machine-code path for saved ELF artifacts, which link without exposing guest
bodies to later optimization.

Repository Scheme entry points explicitly add `src/` and `wasm-native/scheme/`
to Chibi's search path. Standalone package consumers add only its `scheme/`
directory; package tests also add `tests/`. The Wasm writer, Binaryen driver,
process, JSON and trace utilities are neutral modules with no native-lowering
imports, so Wasm builds can use them without loading the native backend.

## Checks and measurements

`make test` executes compiler host tests. `scripts/test-sfir` checks explicit
syntax, typing, module identity and actual V8 execution. `scripts/test-build`
checks the Wasm public command and the native composition script, including
cleanup and publication.
`scripts/test-sfir-entry` compiles supplied library maps, links public Entry
artifacts to foreign providers, and executes both Wasm and native64 aliases.
`scripts/test-sfir-native-loading` checks independent native instances, exact
scalar transport, forced collection, provider ABI errors and process cleanup.
`scripts/test-sfir-execution` exercises the Wasm adapter with typed providers,
independent state, failed initialization and checked scalar transport.
`scripts/test-sfir-builder` compiles an SFIR producer, transfers its structured
result into a separate Chibi host, and compiles and executes the received library.
Its complete-library fixture rebuilds syntax through typed inspection and compares
with ordinary source on linked Wasm and native execution with frequent collection;
malicious packets test lexical ownership, static roles, Unicode and unforgeable
checking evidence.
`scripts/test-sfir-compiler-service` executes compilation and the full Wasm
execution lifecycle from an SFIR build program. It checks recoverable diagnostics,
source and constructed dependencies, provider signatures, instance ownership and
continued artifact execution after the owned Chibi process is lost.
`scripts/test-sfir-integration` executes 320 authored SFIR fixtures retaining the
previous compiler contracts. `scripts/test-backend` combines these with extern,
library, scalar-service and Binaryen checks; `scripts/test-native` exercises
mechanical lowering, collection, C signatures and resource cleanup.

The [benchmark corpus](benchmarks/README.md) keeps 57 workloads, authored SFIR,
Chez controls and Rust comparisons. Source availability, execution correctness
and clean measurement are distinct statuses. Compiler traces and instrumented
runs explain work; they are not substituted for clean timing runs.

`benchmarks/sfir/runner.scm` freezes the compiler, corpus inputs, selected Rust
installation and locked crate sources, then validates each workload's target
routes in a fresh process. It retains scheduler output and termination status,
records incomplete routes, and continues the remaining selected workloads.
Dynamic, Scheme and SLaTeX keep their complete workload and resource
contracts in local verifiers and native entries; the runner owns fixture copies,
tool invocation and artifact parity. Scheme's interpreter is benchmark code.
`benchmarks/sfir/timing.scm` prepares clean artifacts for all 57 registered
workloads, fixes the comparison schedule, supervises fresh execution processes
and summarizes complete sample
sets. Failed routes remain visible alongside measured routes.

`benchmarks/wasm-reference/suite.sld` runs the independent Rust/WASI and original
Chez correctness checks, retaining pinned inputs, complete file results and
negative checks. `audit.sld` reads serialized output without losing numeric
spellings and compares lexical alpha equivalence, complete graphs and nucleic
transformations. `compiler.sld` executes the four independent compiler-stage
probe groups against the original Chez algorithm. Their `.scm` entry points
and unit tests run in Chibi.

## Language specification

The [SFIR book](doc/book/sfir/index.md) specifies the language, library
values and staged builds. [Its entry page](doc/sfir.md) links the chapters and
preview commands. `scripts/book` builds or serves the book; shared rule snippets
keep the explanations and formal summary synchronized. The book specifies design
contracts, while this tour describes the installed implementation.
