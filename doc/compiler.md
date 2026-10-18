# Compiler reference

For a first reading, use the [short compiler tour](../TOUR.md). This reference
describes individual module contracts and the execution APIs in detail.

Chibi hosts the compiler implementation. Product libraries share located syntax,
hygienic expansion and typed Lofi checking. `(scheme base)` supplies initial
Scheme forms as macros; arbitrary procedural expansion and self-hosting remain
future work.

```text
Compiler: source → located library values → resolved imports and macro expansion
          → resolved Lofi source
          → binding/scope checking → concrete demand → source-based WasmGC → Binaryen
Build:    optimized Wasm → runtime Wasm linkage → Binaryen → V8/WASI
          optimized Wasm → native → LLVM opt/llc → native object
                         → Cargo + Rust runtime/providers → x86-64 Linux executable
```

The [language contract](lofi.md) describes intended language behavior. This
reference describes the current modules in `src/lofi/`.
The compiler emits Wasm only. Ordinary Chibi scripts independently import the
compiler and [`native`](../src/native/README.md) when composing a native build.
The standalone package contains the native lowering, shared Rust runtime and
neutral host utilities; it has no compiler dependency.

All product/compiler library paths follow their names under `src/lofi` and
`src/scheme`. The public `(lofi compiler)` is a product library calling the
compiler service. `(lofi compiler bootstrap)` is its current Chibi implementation;
other implementation modules remain Chibi-hosted too. Use `-I bootstrap` for
Chibi so its host `(scheme base)` is distinct from `src/scheme/base.sld`.
`native` remains the independent native backend and runtime package.

For a first read, start with `compile` and `entry-program` in
[`compiler.sld`](../src/lofi/compiler/bootstrap.sld), then the source records in
[`ir.sld`](../src/lofi/compiler/ir.sld). Follow `generate-call` in
[`specialize.sld`](../src/lofi/compiler/specialize.sld) alongside
`rule-call` in [`infer.sld`](../src/lofi/compiler/infer.sld) and
`emit-application-rule` in [`emit-wasm.sld`](../src/lofi/compiler/emit-wasm.sld).
These show how one source call becomes constraints, concrete demand and Wasm.

## Source and binding identity

[`source.sld`](../src/lofi/compiler/source.sld) defines filename, line and column.
[`reader.sld`](../src/lofi/compiler/reader.sld) provides immutable character cursors.
[`parser.sld`](../src/lofi/compiler/parser.sld) composes located parsers;
[`syntax-parser.sld`](../src/lofi/compiler/syntax-parser.sld) reads explicit
s-expressions and rejects quote abbreviations. These are implementation modules
written in Scheme; Chibi reads their own source.

Numeric tokens retain their original spelling through syntax and resolved IR.
[`numeric-literals.sld`](../src/lofi/compiler/numeric-literals.sld) decodes exact decimal
values and rounds directly to the selected IEEE width, including subnormals and
overflow boundaries. The reader also uses its exact decoding for bytevector
elements; host floating-point approximations cannot turn a fraction into a byte.
Inference fixes ordinary numeric literals at I32 or F64. Only an immediately
enclosing `ann` or a direct binding annotation selects another scalar width;
call, branch and result expectations check the fixed representation. `Any`
therefore stores the default width unless the literal explicitly selects one.

[`frontend.sld`](../src/lofi/compiler/frontend.sld) parses the small Lofi grammar into
`LofiLibrary` values without loading dependencies. `parse-library` accepts one
located `define-library`; `syntax-list->lofi-library` also accepts a script body.
A body using macros retains source until its imported transformers are known.
[`macros.sld`](../src/lofi/compiler/macros.sld) then expands declarative patterns with lexical
contexts, preserves private definition-site references and removes transformer
definitions. The resulting kernel parser reserves each block's bindings before
parsing initializers. Local references
carry binding identities; unresolved imports carry a name, the library's import
scope, a syntactic category and a location. `def` reserves a block-wide identity;
each sequential `let` introduces its identity after parsing its initializer.
Both become ordinary binding nodes in source order. Value and type scopes are
separate, so an argument name cannot hide an enclosing quantified type variable.
Library `begin` clauses concatenate before parsing; expression `begin` keeps
its own lexical scope. No step performs inference or executes user source.

[`lofi/library.sld`](../src/lofi/compiler/library.sld) records parsed library
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

[`resolved-library.sld`](../src/lofi/compiler/resolved-library.sld) records the resulting
resolved imports and exports. Dependency traversal initializes each library
identity once before its users. [`ir.sld`](../src/lofi/compiler/ir.sld) holds the shared
source expression and binding records. Expressions have no inferred type or
constraint fields; binding definitions retain attached declarations and schemes.
Immutable `LibraryId` and `BindingId` origins survive resolution and
checking copies; mutable definition objects are canonical within their own graph.
[`signatures.sld`](../src/lofi/compiler/signatures.sld) retains quantified source type
identities. A hole is missing compile-time information, never an implicit Any.
The internal solver and Wasm emitter still spell the universal type `Top`;
the source surface uses `Any`.

## Type evidence

[`types.sld`](../src/lofi/compiler/types.sld) owns inference holes,
rigid quantified variables, unification, substitution, schemes and subtyping.
[`checked.sld`](../src/lofi/compiler/checked.sld) records immutable source,
binding schemes, lexical scopes, lambda signatures, the program result type and
class evidence.
[`pass.sld`](../src/lofi/compiler/pass.sld) defines the small `pass` record
and shared source-arm dispatch. Typing rules receive returned child judgments;
the visitor owns scope and expected-type dependencies.

[`infer.sld`](../src/lofi/compiler/infer.sld) checks every body, including
unused functions, on an owned binding graph without mutating source expressions.
Transient judgments contain no child judgments; only binding and scope summaries
survive checking. Each lexical block
builds direct dependencies once and groups mutually recursive bindings. Group
members retain source order. Every overload row supplies an explicit signature,
so checking can use the complete family before checking implementation bodies.
Ordinary groups are checked once in dependency order. Mutable allocations obey
the value restriction. Concrete calls have a fixed list of positional arguments;
surface packing macros use ordinary lists. Declared initializer proofs retain their
lexical scope until enclosing monotypes settle. Their own quantified requirements
must then hold; obligations on captured monotypes remain with enclosing inference.

Recursive groups containing `All` first solve a private monomorphic template,
then check the original bodies with independent rigid interpretations. Fixed
recursive instantiation tuples include phantom parameters. Inferred groups keep
one checking pass; both paths freeze variables shared with expansive members
before generalization. Representable value cycles use ordinary source-order
initialization and retain premature-read traps.

[`overloads.sld`](../src/lofi/compiler/overloads.sld) resolves complete
argument/result constraints with coherent class requirements. Speculative trials
unify private copies with a boolean result, avoiding continuation capture on
ordinary mismatches. Classes cache family membership for an exact immutable
instance list; compatibility and instantiated solver views remain live.
[`types.sld`](../src/lofi/compiler/types.sld) avoids environment scans when no
holes can be generalized. Monomorphic declarations cannot introduce escaping
skolems.
[`data.sld`](../src/lofi/compiler/data.sld) prepares nominal data,
constructors and fields. Matching checks exhaustiveness and retains pattern binding
types; generation emits field reads and branches directly from source arms.
[`primitives.sld`](../src/lofi/compiler/primitives.sld)
assigns concrete operation signatures. Explicit Any conversions preserve the
checks required at dynamic boundaries.

## Concrete code and storage

[`specialize.sld`](../src/lofi/compiler/specialize.sld) reserves demanded
implementations in a persistent hash map and drains a pending list.
[`hashmap.sld`](../src/lofi/compiler/hashmap.sld) implements the compiler's
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
checks remain separate from code demand. After discovery settles, one pass
partitions values by activation owner in allocation order. Emission consumes
these buckets instead of scanning the graph for every function.

[`emit-wasm.sld`](../src/lofi/compiler/emit-wasm.sld) supplies emission operations
to the explicit source visitor. Each visit returns a transient typing judgment,
generated code and the next request context. Typing rules consume immediate child
judgments; separate emission rules consume generated children. Target code is
emitted after capture and storage summaries settle. Scalars, structs, arrays,
precise Any witnesses and tail calls retain their existing Wasm contracts.
Emission checks that demand is already complete. A concrete-type index finds
layouts while the ordered registry controls IDs and output. Layout reservation
precedes dependency traversal, preserving recursive types. Local declarations
accumulate in reverse and are reversed once when a function is emitted. The shared
[`wasm.sld`](../src/native/wasm.sld) serializes Wasm data.

[`wasm-strings.sld`](../src/lofi/compiler/wasm-strings.sld) owns the UTF-8 string
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
remain mutable. These [implementation tradeoffs](ir.md#current-tradeoffs) are
separate from language semantics and measured runtime performance.

[`compiler.sld`](../src/lofi/compiler/bootstrap.sld) composes the passes.
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

[`source-driver.sld`](../src/lofi/compiler/source-driver.sld) owns file selection,
independent library preparation and dependency collection, including compiled
`generate-library` recipes. Producer and application maps are separate; a shared
preparation chain diagnoses cycles and preserves each selected value's identity.
The older frontend convenience APIs remain adapters for already parsed source.
The source driver's `lofi.parse`, `lofi.check`, `lofi.specialize` and `lofi.emit-wasm`
trace spans expose the boundaries. [`chromium-trace.sld`](../src/native/chromium-trace.sld)
requires an explicit trace scope. [`scripts/view-traces`](../scripts/view-traces)
opens retained evidence in Perfetto.

`scripts/build-lofi` keeps its script behavior and `--export` selector for unique
flattened binding names. The library API uses public Entry selection.
Lofi producers can construct, inspect and transfer the complete library syntax
described below. [`(lofi compiler)`](../src/lofi/compiler.sld) also exposes explicit
map assembly, compilation, Wasm loading, independent instantiation and checked
scalar entry invocation as ordinary Lofi calls. Every fallible operation returns
an ordinary `CompilerResult` success or diagnostic string.

[`compiler-service.mjs`](../src/lofi/compiler/service.mjs) owns one Chibi
process, the matching builder arena, copied artifacts and runtime instances.
[`serve-lofi-compiler.scm`](../scripts/serve-lofi-compiler.scm) parses supplied source
once or receives constructed syntax and retains unresolved library values in
immutable maps. Compilation resolves only the supplied map; provider linkage
remains a separate execution operation. Failed initialization publishes no
instance; a trapped call retains its instance and preceding effects. A lost
compiler process invalidates map operations while copied artifacts and existing
runtime instances remain owned by the service scope. See the
[service API](lofi-compiler-service.md) for lifecycle rules, Wasm execution
and first-class parsed `LofiLibrary` values. The separate Scheme native
loading adapter is described below.

[`run-lofi-generator.mjs`](../scripts/run-lofi-generator.mjs) executes compiled
recipes through the checked builder boundary. An explicit provider factory
receives the selected descriptor's directory and owns its foreign services until
cleanup. The driver registers the returned syntax and separately obtains its
imports. See [source recipes](lofi-generation.md) for the API, command example,
source context and preparation errors.

## Parsed and constructed library values

[`compiler/builder.sld`](../src/lofi/compiler/builder.sld) lets compiled Lofi
producers compose nominal library, declaration, type, scope, binding and reference
values. Constructors use explicit operands; no ambient current library is mutated.
The API covers the book's types and binding signatures, literals, expressions,
ordered blocks, static definitions and existing extern/overload extensions.
Explicit type-variable identities carry generic scope alongside ordinary binding
identities. Typed inspection views expose all constructor fields and copy mutable
literal payloads. Binding references are distinct from expressions, and private
handles do not expose managed pointers.

[`library-builder.mjs`](../src/lofi/compiler/builder.mjs) supplies typed scalar
constructors in an invocation-owned arena. `invokeLibraryGenerator` initializes
and calls an ordinary compiled producer, copies its completed syntax graph into
an owned transfer, and closes the arena and producer instance on success or trap.
The same arena receives copied parse packets with checked structure and fresh
local identities; parsed and constructed values share all typed views.
The transfer has a versioned schema and preserves nodes and their local IDs.

[`library-transfer.sld`](../src/lofi/compiler/library-transfer.sld) receives that data
in Chibi, checks Unicode and structure, then reserves definitions and visits
statements in order, introducing each `let` after its initializer. Every reference
is checked against its lexical occurrence, including quantified type identities
and static binding roles. It shares the frontend's reserved binding-name rule
and creates an unresolved `LofiLibrary`. An explicit receiving context preserves
reuse of legitimate owned transfers; reading raw bytes again creates fresh
identities.
Its reverse writer traverses unresolved parser declarations with binder identity
maps, deriving scope owners from lexical structure. `def`/`let` evidence, attached
signature locations, quantified variables and numeric source spellings survive
that copy. Parsing still uses only `frontend.sld`; no types are inferred during
transfer. Output imports need their own supplied map. The receiver neither discovers
dependencies nor accepts inferred IR as evidence. See the [builder API and
executable example](lofi-builder.md) for ownership, supported constructors,
and typed inspection.

## Wasm artifacts, native composition and runtime

[`lofi`](../lofi) owns command parsing, private build directories,
publication and Wasm host invocation. [`build-lofi`](../scripts/build-lofi) and
[`build-native`](../scripts/build-native) preserve intermediates for module-level
work. The latter is an ordinary composition script that passes emitted Wasm to
the native package, then links its object with Cargo. [`build.scm`](../build.scm)
shows these library calls directly for an explicit public export and Rust entry
point. [`wasm-optimize.sld`](../src/native/wasm-optimize.sld)
requires Binaryen on both execution routes.

[`lofi/artifact.sld`](../src/lofi/compiler/artifact.sld) implements the Chibi
Entry and Artifact boundary. Compilation returns optimized, unlinked Wasm bytes
with a versioned `lofi.entry` custom section containing the public
Entry description and semantic scalar signature. The section is appended after
Binaryen optimization; loading verifies its schema and execution verifies the
actual exported signatures. Tool temporaries live in a private directory;
compilation reads no source files and returns artifact bytes for the caller to
write. Provider and runtime linking remain explicit build operations.

[`(native)`](../src/native.sld) exposes
`wasm-binary->llvm`, `llvm-object` and `link-native-object`. Its explicit provider
declarations are `(make-native-import module name c-symbol parameters result)`:
string names, physical `i32`/`i64`/`f32`/`f64` parameter types, and a scalar or
`void` result. Missing declarations and signature mismatches fail. Lowering
consumes the Wasm representation, physical imports and runtime ABI; it receives
no source bindings, inference state or compiler IR.

[`lofi/native.sld`](../src/lofi/compiler/native.sld) is the optional source-aware
adapter. `(artifact->native-object artifact imports directory output)` supplies
the saved scalar signature and source entry description to
[`scalar-entry.sld`](../src/native/scalar-entry.sld). That optional
protocol layer checks the actual optimized Wasm `main`/`entry` signatures and
emits a fixed scalar-bits bridge into the native LLVM module. An ELF `.lofi.entry`
section and signature-encoded bridge alias preserve the scalar tags, origin
description and required foreign declarations. Bool and Char remain distinct
protocol tags despite sharing physical `i32`. The native loader checks their
consistency; arbitrary native code remains trusted. Ordinary native builds with
a supplied Rust entry point need no scalar-entry metadata.

Artifact accessors expose the original Entry, semantic scalar parameter
and result types, and bytes. The fixed ABI exports `entry` for the selected
function and `main` for one-shot library initialization; native symbols are
`wasm.entry` and `wasm.main`, after `native_module_init`. Calling `entry` before
successful initialization traps. A public Lofi export named `main` is therefore
unambiguous. Native object bytes do not themselves represent a running instance.

[`lofi/compiler/execute.mjs`](../src/lofi/compiler/execute.mjs) is the explicit JavaScript
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

[`execute.sld`](../src/native/execute.sld) provides `load-native`,
explicit `link-native`, `instantiate`, `invoke-entry` and `close-instance` for
x86-64 Linux objects carrying the optional scalar protocol. Its fourth
`link-native` argument explicitly supplies the runtime root. It checks declared
Rust provider ABIs,
uses exact binary scalar transport, and gives each instance fresh native globals,
GC and provider state. [`native_worker.rs`](../src/native/native_worker.rs) supplies
a separate supervisor and guest worker; ownership precedes provider constructors.
Failed initialization publishes no instance. Native traps and interrupted calls
invalidate their instance; the supervisor reaps its owned descendants, including
after host death. The [native loading contract](lofi-native-loading.md)
describes the API, retained logs, unsafe native boundary and target limitations.

[`link-lofi-runtime`](../scripts/link-lofi-runtime) calls
[`runtime-wasm.sld`](../src/native/runtime-wasm.sld), which builds
the Rust runtime's Wasm form, links its scalar externs into a WASI reactor,
drops unused runtime exports and optimizes the result. This utility imports no
native lowering or execution code.
[`run-lofi.mjs`](../scripts/run-lofi.mjs) initializes once, invokes `main`, and drains
resource cleanup. The [Lofi libraries](../src/lofi/README.md) implement numeric,
container, datum and I/O behavior in Lofi; Rust externs supply concrete host
operations. Wasm owns managed collection.

[`src/native/Cargo.toml`](../src/native/Cargo.toml) defines the one runtime crate.
[`lib.rs`](../src/native/runtime/src/lib.rs) contains runtime initialization, diagnostics and shared
floating-point text. [`strict_io.rs`](../src/native/runtime/src/strict_io.rs) owns file IDs and terminal
cleanup; [`host.rs`](../src/native/runtime/src/host.rs) implements buffered Unicode streams. The datum
services retain temporary token text and stable symbol IDs, while Lofi owns the
reader and managed datum graph. These services accept scalars and never retain
guest GC roots. There is no boxed Scheme-value ABI or wrapper-finalizer bridge.

[`io.sld`](../src/lofi/io.sld) shares an owned file's pending input and closed
handle across aliases. Rust returns up to seven already-buffered ASCII characters
in one scalar packet; character, line and datum reads consume that same cursor.
Optional packet bytes never refill the native buffer or decode a later invalid
suffix. Borrowed stdin retains the native scalar read/peek cursor so direct
foreign reads interoperate. The [input contract](../src/lofi/README.md#text-input-cursor)
describes the representation, EOF behavior and execution checks.

[`text.sld`](../src/lofi/text.sld) owns string ordering and full case-fold output
storage. [`strict_text.rs`](../src/native/runtime/src/strict_text.rs) exposes Unicode operations as
scalar C/Wasm functions. [`unicode.rs`](../src/native/runtime/src/unicode.rs) keeps one generated
folding implementation with at most three stack-resident output scalars;
[`generate-unicode`](../scripts/generate-unicode) checks that bound against pinned
Unicode data and Rust's recorded casing baseline.

[`native.sld`](../src/native/native.sld) optimizes Wasm before lowering.
[`wasm-read.sld`](../src/native/wasm-read.sld) reads Binaryen's spelling;
[`wasm-resolve.sld`](../src/native/wasm-resolve.sld) resolves Wasm identities.
[`llvm.sld`](../src/native/llvm.sld) mechanically lowers those operations,
including checked array header loads and addressing with known storage widths;
[`llvmlite.sld`](../src/native/llvmlite.sld) writes LLVM text. Native uses the
same Rust extern implementations and resolves imports directly against
literal Rust `extern "C"` provider declarations. [`native_gc.rs`](../src/native/native_gc.rs) owns
native managed collection. Root and slot lifetime invariants live beside
the lowering and collector that rely on them.

[`process.sld`](../src/native/process.sld) owns concrete command
capture, files and evidence. [`json.sld`](../src/native/json.sld) reads one
complete JSON packet, preserves standard control escapes across the Chibi host
boundary, and emits escaped control characters in metadata and command evidence.
Trailing input is rejected. [`native-build.sld`](../src/native/native-build.sld)
checks scalar provider declarations, runs LLVM, and assembles a Cargo package
with the native runtime, shared scalar services and ordinary provider crates.
Rust target `cfg`s select scalar host behavior; the native crate alone contains
the collector. Retained guest bitcode participates in shared linker-plugin LTO
with Rust; saved ELF inputs are already machine code.

Repository Scheme entry points add `bootstrap/` to Chibi's search path.
The same loader view exposes `(native)` and its dependencies; package tests also
add `src/native/tests/`. The Wasm writer, Binaryen driver,
process, JSON and trace utilities are neutral modules with no native-lowering
imports, so Wasm builds can use them without loading the native backend.

## Checks and measurements

`make test` executes compiler host tests. `scripts/test-lofi` checks explicit
syntax, typing, module identity and actual V8 execution. `scripts/test-build`
checks the Wasm public command and the native composition script, including
cleanup and publication.
`scripts/test-lofi-entry` compiles supplied library maps, links public Entry
artifacts to foreign providers, and executes both Wasm and native64 aliases.
`scripts/test-lofi-native-loading` checks independent native instances, exact
scalar transport, forced collection, provider ABI errors and process cleanup.
`scripts/test-lofi-execution` exercises the Wasm adapter with typed providers,
independent state, failed initialization and checked scalar transport.
`scripts/test-lofi-builder` compiles an Lofi producer, transfers its structured
result into a separate Chibi host, and compiles and executes the received library.
Its complete-library fixture rebuilds syntax through typed inspection and compares
with ordinary source on linked Wasm and native execution with frequent collection;
malicious packets test lexical ownership, static roles, Unicode and unforgeable
checking evidence.
`scripts/test-lofi-compiler-service` executes compilation and the full Wasm
execution lifecycle from an Lofi build program. It checks recoverable diagnostics,
source and constructed dependencies, provider signatures, instance ownership and
continued artifact execution after the owned Chibi process is lost.
`scripts/test-lofi-integration` executes 322 authored Lofi fixtures retaining the
previous compiler contracts. `scripts/test-backend` combines these with extern,
library, scalar-service and Binaryen checks; `scripts/test-native` exercises
mechanical lowering, collection, C signatures and resource cleanup.

The [benchmark corpus](../benchmarks/README.md) keeps 57 workloads, authored Lofi,
Chez controls and Rust comparisons. Source availability, execution correctness
and clean measurement are distinct statuses. Compiler traces and instrumented
runs explain work; they are not substituted for clean timing runs.

`benchmarks/lofi/runner.scm` freezes the compiler, corpus inputs, selected Rust
installation and locked crate sources, then validates each target route.
Dynamic, Scheme and SLaTeX keep their complete workload and resource
contracts in local verifiers and native entries; the runner owns fixture copies,
tool invocation and artifact parity. Scheme's interpreter is benchmark code.
`benchmarks/lofi/timing.scm` prepares clean artifacts for all 57 registered
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

The [Lofi book](book/lofi/index.md) specifies the language, library
values and staged builds. [Its entry page](lofi.md) links the chapters and
preview commands. `scripts/book` builds or serves the book; shared rule snippets
keep the explanations and formal summary synchronized. The book specifies design
contracts, while this tour describes the installed implementation.
