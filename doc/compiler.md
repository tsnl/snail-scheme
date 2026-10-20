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
          → checking → immutable typed/concrete trees → WasmGC → Binaryen
Build:    optimized Wasm → runtime Wasm linkage → Binaryen → V8/WASI
```

The [language book](book/lofi/index.md) describes intended language behavior. This
reference describes the current modules in `src/lofi/`.
The compiler emits WasmGC. Chibi host utilities live in `src/lofi/host/`;
Rust scalar services live in `src/runtime/`. The Wasm engine owns collection.

All product/compiler library paths follow their names under `src/lofi` and
`src/scheme`. `(lofi compiler bootstrap)` composes the Chibi-hosted passes. Use
`-I bootstrap` for Chibi so its host `(scheme base)` is distinct from
`src/scheme/base.sld`.

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
binding schemes, the program result type and class evidence.
[`typed.sld`](../src/lofi/compiler/typed.sld) carries checked expression types and
instantiation decisions in an immutable tree. Typing rules consume child judgments;
checking owns scope and expected-type dependencies.

[`infer.sld`](../src/lofi/compiler/infer.sld) checks every body, including
unused functions, on an owned binding graph without mutating source expressions.
Judgments construct provisional typed children. Once obligations settle, freezing
replaces remaining solver holes with immutable parameters and releases checking
scopes. Existing scheme binders determine which parameters may be instantiated;
freezing preserves their identities and does not add quantification. Each lexical block
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
owns a concrete payload, and a function owns code. Specialization constructs
[`concrete.sld`](../src/lofi/compiler/concrete.sld) trees while recording reads
and nested closures, then settles capture requirements. Source-order initialization and erased alias readiness
checks remain separate from code demand. After discovery settles, one pass
partitions values by activation owner in allocation order. Emission consumes
these buckets instead of scanning the graph for every function.

[`emit-wasm.sld`](../src/lofi/compiler/emit-wasm.sld) emits target code from
concrete expressions after capture and storage settle. Emission consumes the
recorded types and decisions directly; it cannot introduce implementation requests. Scalars, structs, arrays,
precise Any witnesses and tail calls retain their existing Wasm contracts.
A concrete-type index finds
layouts while the ordered registry controls IDs and output. Layout reservation
precedes dependency traversal, preserving recursive types. Local declarations
accumulate in reverse and are reversed once when a function is emitted. The shared
[`wasm.sld`](../src/lofi/host/wasm.sld) serializes Wasm data.

[`wasm-strings.sld`](../src/lofi/compiler/wasm-strings.sld) owns the UTF-8 string
layout and its emitted Wasm operations. Each owner retains a scalar count, used
byte length, packed backing array and cached scalar/byte boundary. Conversion
validates once and copies bytes; slicing and equality operate on encoded spans.
Width-changing mutation preserves owner identity and updates its backing storage.
Large literals are filled by module start before source execution.
The Wasm engine traces their managed references.

Specialization consumes checked evidence without probing source expressions or
replaying inference. Source and nominal identities in request keys are
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
trace spans expose the boundaries. [`chromium-trace.sld`](../src/lofi/host/chromium-trace.sld)
requires an explicit trace scope. [`scripts/view-traces`](../scripts/view-traces)
opens retained evidence in Perfetto.

`scripts/build-lofi` keeps its script behavior and `--export` selector for unique
flattened binding names. The library API uses public Entry selection.

[`run-lofi-generator.mjs`](../scripts/run-lofi-generator.mjs) executes compiled
recipes and collects the library source text they stream back. An explicit
provider factory receives the selected descriptor's directory and owns its
foreign services until cleanup. The driver parses the returned text and
separately obtains its imports. See [source recipes](lofi-generation.md) for the
API, command example, source context and preparation errors.

## Wasm artifacts, execution and scalar services

[`lofi`](../lofi) owns command parsing, private build directories, atomic
publication and Wasm invocation. [`build-lofi`](../scripts/build-lofi) retains
module intermediates. [`wasm-optimize.sld`](../src/lofi/host/wasm-optimize.sld)
assembles and optimizes the emitted module with Binaryen.

[`lofi/artifact.sld`](../src/lofi/compiler/artifact.sld) implements the Chibi
Entry and Artifact boundary. Compilation returns optimized, unlinked Wasm bytes
with a versioned `lofi.entry` custom section containing the public
Entry description and semantic scalar signature. The section is appended after
Binaryen optimization; loading verifies its schema and execution verifies the
actual exported signatures. Tool temporaries live in a private directory;
compilation reads no source files and returns artifact bytes for the caller to
write. Provider and runtime linking remain explicit build operations.

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
adapter discovers no files, constructs no WASI or Rust providers, and accepts Wasm bytes only.

[`runtime-wasm.sld`](../src/lofi/host/runtime-wasm.sld) builds and links
[`src/runtime/`](../src/runtime/README.md) scalar services. Rust owns external
resources behind handles; managed values remain in WasmGC. The host closes
resources after completion or traps. `host.rs` implements buffered Unicode
streams; `strict_io.rs` owns handles and cleanup; `strict_text.rs` and
`unicode.rs` implement Unicode scalar operations. Datum and number services
retain their existing scalar boundaries.

[`process.sld`](../src/lofi/host/process.sld) captures commands and evidence;
[`json.sld`](../src/lofi/host/json.sld) handles finite JSON protocols;
[`chromium-trace.sld`](../src/lofi/host/chromium-trace.sld) records scoped spans.
The Linux process supervisor under `tools/host/` enforces command deadlines and
reaps descendants without loading guest code.

Chibi imports implementation modules through `bootstrap/`, preserving its own
Scheme libraries. Tests add `tests/` for colocated unit-test assertions.
`scripts/test-backend` covers the current backend inventory, including raw and
optimized linked Wasm execution, generators and scalar services. `scripts/test-build` exercises command publication, failure
cleanup, standard input and literal arguments. See [build tools](backend.md) for
commands.
