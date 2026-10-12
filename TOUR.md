# A tour of Snail-Scheme

Chibi hosts the bootstrap compiler. The compiler emits WasmGC, and Node.js runs
linked command artifacts. Scheme memory belongs to the engine. The Rust library
provides common value operations; selected platform handlers provide effects.

```text
located Scheme -> resolved library IR -> WasmGC
  -> Binaryen optimization -> link common library + selected handlers + entry
  -> final Binaryen optimization -> application.wasm
  -> Node.js loader: WASI + JS host imports -> one running node
```

## Entering the compiler

[build.scm](build.scm) builds `build/snail-scheme.wasm`; [main.scm](main.scm)
parses options, compiles an ordinary script, runs it through Node, and returns
its status. [`options.sld`](src/snail-scheme/options.sld) supplies the shared
option parser, including literal script arguments and `-I` library paths.
See [option parsing](doc/options.md).

[`compiler.sld`](src/snail-scheme/compiler.sld) owns source loading, expansion,
and emission without launching processes. [`build.sld`](src/snail-scheme/build.sld)
composes source compilation, dependencies, publication, and script execution.
[`wasm-link.sld`](src/snail-scheme/wasm-link.sld) owns runtime construction,
Wasm linking, explicit entry adapters, and atomic artifact publication.
[`wasm-optimize.sld`](src/snail-scheme/wasm-optimize.sld) checks Binaryen and
optimizes Scheme modules. Help runs before the dependency preflight.

[`effects.sld`](src/snail-scheme/effects.sld) declares versioned interfaces,
complete handler maps, and platform collections. The compiler imports qualified
operations; the linker resolves a Wasm alias module to selected providers and
removes private default exports. [`build-host.sld`](src/snail-scheme/build-host.sld)
uses Chibi for bootstrap operations and selected build effects in compiled code.
[`build.mjs`](src/runtime/build.mjs) implements those effects in Node: literal
subprocess argv, paths, owned workspaces, and atomic publication. Failed builds
retain intermediates and preserve the previous output.

[`compile-build.sld`](src/snail-scheme/compile-build.sld) resolves generated
libraries by compiling and executing a Wasm generator in a private workspace.
[`generation.sld`](src/snail-scheme/generation.sld) transports located syntax and
explicit dependency artifacts. [`artifacts.sld`](src/snail-scheme/artifacts.sld)
validates and snapshots the dependency graph. Publishing switches one relative
symlink to a complete generation. The Node loader pins the physical payload once;
[`(snail artifacts)`](src/snail/artifacts.sld) finds companions in that generation.
[`runtime-artifact.sld`](src/snail-scheme/runtime-artifact.sld) packages the Rust
WAT library for the installed compiler. See [build artifacts](doc/build-artifacts.md).

[`chromium-trace.sld`](src/snail-scheme/chromium-trace.sld) records spans in an
explicit `with-chromium-trace-to` file scope. Build scripts own trace paths.
[`scripts/view-traces`](scripts/view-traces) serves a chosen trace and Perfetto
on loopback. See [tracing](doc/tracing.md).

## Reading source

[`source.sld`](src/snail-scheme/source.sld) defines `loc`: filename, one-based
line, and one-based column. Locations travel with syntax and later with IR and
resolved references. Wasm debug source mappings remain future work.

[`reader.sld`](src/snail-scheme/reader.sld) represents an immutable character
cursor. `file->reader` and `string->reader` establish the initial position;
`peek-reader` observes it, `next-reader` advances it, and `reader-loc` extracts a
location. Advancing returns another reader, so parser alternatives can retain
the original input without undoing mutations. Line tracking handles LF, CRLF,
and standalone CR.

[`parser.sld`](src/snail-scheme/parser.sld) builds parsers from functions of a
reader. A `parse-result` contains success or failure, a value, and the remaining
reader. `>>=` and `chain` sequence successful parses; `pmap` changes their values.
`choice` tries alternatives from the original position. `lookahead` and
`not-followed-by` inspect without consuming. `repeat` accumulates results and
rejects a parser that succeeds without advancing, preventing an infinite loop.
`tuple` and `named-tuple` gather the parts of a grammar rule. `named-tuple` runs
fields directly, retaining named values and skipping allocation of ignored
field pairs. Its construction captures procedures; names are observed after
each successful field, preserving the descriptor API. Both parsers return a
child's first failure unchanged and keep their accumulators local to each call.

[`syntax-parser.sld`](src/snail-scheme/syntax-parser.sld) is the grammar built
from those combinators. Named rules are parser values, constructed once in
dependency order; recursive references stay inside parsing callbacks. Use
`(s-file reader)` to run a parser and `(choice s-number s-symbol)` to compose
them. `s-file` accepts a complete sequence of forms; `s-expr`
chooses lists, vectors, quote abbreviations, and atoms. The remaining sections
handle delimiters, escapes, Unicode characters, identifier and numeric
spellings, and whitespace and comments. Numeric spelling recognition is wider
than the compiled runtime's current numeric subset; a successfully parsed datum
can still be rejected during lowering.

[`syntax.sld`](src/snail-scheme/syntax.sld) defines the three syntax containers:
`atom-syntax`, `list-syntax`, and `vector-syntax`. A list stores its proper prefix
and optional improper tail separately. Every node has a location. `syntax->datum`
removes that metadata when an operation needs an ordinary Scheme datum.

[`common.sld`](src/snail-scheme/common.sld) contains the lexical character
classes used by the grammar, small list and string helpers, assertions, and file
reading. Its predicates describe characters; the grammar decides how those
characters combine into tokens.

## Expanding names, libraries, and macros

[`ir.sld`](src/snail-scheme/ir.sld) defines the resolved high-level records.
A `value-definition` is a binding identity. A `name` refers to that identity,
and a `value-binding` attaches an initializer to it. Thus a renamed import, a
reference inside a closure, and the original definition can share one identity
even though their printed names differ. The expression records are literals,
applications, lambdas, blocks, conditionals, assignments, and names. The records
do not contain expansion environments.

[`library.sld`](src/snail-scheme/library.sld) owns compilation containers
independently of a backend. Named libraries and unnamed executable scripts
share one record: imports, exported identities, dependency names, a body and a
location. The current compiler pass owns the body representation. Import
declarations retain resolved libraries and local bindings directly, along with
original located syntax for diagnostics. Later passes do not peel `only`,
`except`, `prefix`, or `rename` nodes to reach a library.
`library-dependency-order` visits each dependency once before its importer.

[`expand.sld`](src/snail-scheme/expand.sld) constructs those records in three
steps. `syntax-list->ir-library` separates a script's initial imports from its body. Import
expansion loads and caches libraries, applies `only`, `except`, `prefix`, and
`rename`, and preserves the original definition identities. Library construction
resolves exports against the completed library environment, then concatenates
expanded body chunks in source order. Source-level export and `begin` wrappers
do not survive into the library container.

Body expansion first reserves directly declared identities, then discovers
body forms and installs transformers, then constructs expressions. Follow
`expand-body-chunks`, `reserve-direct-definitions`, `prepare-body-chunks`, and
`build-body-chunks` for this ordering. It lets recursive references point to
already reserved identities while macro visibility still follows source order.
`expand-expression` repeatedly expands the head and then handles a core form or
ordinary application. `expand-lambda` reserves parameter identities and expands
its body in the extended environment.

Transformer installation parses both patterns and templates.
`parse-transformer` builds rules; `parse-rule-template` records the roles of
introduced identifiers, captures, and repetitions. At a use site,
`apply-transformer` selects a rule and `instantiate-template` builds the result.
Introduced identifiers receive fresh keys, substituted syntax keeps its keys,
and free identifiers retain their definition-site fallback. These are the
pieces to follow when investigating hygiene rather than reasoning from symbol
spelling alone.

[`pattern.sld`](src/snail-scheme/pattern.sld) supplies the underlying datum
matcher. `pattern-dispatch` parses its patterns once, then tries them against
each input. `match-pattern` produces structured match records. Sequence matching
handles the fixed prefix, fixed suffix, repeated middle, and optional improper
tail; `flatten-match` creates capture alists only after a complete match succeeds.
Repeated matches retain nesting, including empty repetitions. A callback can
reject an otherwise matching branch by returning `#f`.

The expander's syntax-matching adapter connects these two modules.
`build-syntax-dispatcher` and `project-syntax` give the datum matcher a structural
view while preserving the original syntax for captures. Literal constraints use
resolved identifier identity. The datum matcher itself remains independent of
source locations and lexical environments. There is no general compile-time
Scheme evaluator here: transformer support is the dedicated `syntax-rules`
path.

## The Scheme library used by compiled programs

[`bootstrap.sld`](src/snail-scheme/bootstrap.sld) is the inventory of primitive names. The compiler supplies these through a synthetic
`(snail-scheme core)` library using `make-core-library`. It then loads the
bootstrap libraries as ordinary Scheme libraries. Chibi uses its own libraries
while hosting the compiler.

[`bootstrap/scheme/base.sld`](bootstrap/scheme/base.sld) implements derived
forms with `syntax-rules`, including binding forms, conditionals, quasiquotation,
multiple-value bindings, records, and parameterization. Its procedure sections
implement lists, association searches, multi-list `map` and `for-each`, container
conversion, and cycle-aware equality. The Wasm/Rust boundary supplies individual
object operations; higher-level traversal remains Scheme code that future
compiler optimizations can improve.

The remaining bootstrap modules are deliberately thin. `cxr.sld` defines the
longer `car`/`cdr` compositions. `file.sld` wraps file opening with
`call-with-port`. `char.sld`, `process-context.sld`, `time.sld`, and `write.sld`
expose their corresponding primitive groups. `parameterize` and port wrappers
preserve multiple values on normal returns; nonlocal exits and `dynamic-wind`
are outside this bootstrap subset.

[`runtime.sld`](src/snail-scheme/runtime.sld) exposes the explicitly nonstandard
`string-contains` operation, implemented by Rust's substring search.

[`hash-table.sld`](src/snail-scheme/hash-table.sld) implements collector-owned
R7RS-large hash tables behind `(scheme hash-table)`. Scheme owns buckets, cached
hashes, and callback mutation checks; [`hash.rs`](src/hash.rs) supplies structural
hashing through owned ABI roots. Wasm's weak identity map avoids a registry that would retain keys. See [hash tables](doc/hash-tables.md)
for the supported API and comparator limits.

## Checking types and recording evidence

[`(snail typing)`](src/snail/typing.sld) reexports the compiler's opt-in type
syntax. Expansion preserves `:` declarations, `ann` expressions, `inst` views, and record
schemas in IR, with resolved binding identities and source locations. The
existing `define-record-type` macro also accepts typed fields; standard field
forms keep their meaning.

[`types.sld`](src/snail-scheme/types.sld) defines shallow categories, structural
unions, nominal records, rigid type variables, internal occurrence intersections,
and conservative type operations. [`type-inference.sld`](src/snail-scheme/type-inference.sld)
solves rank-one `All` instantiations from arguments and expected results. Its
separate flexible variables support deterministic equality constraints without
solving rigid source binders. [`lambda-inference.sld`](src/snail-scheme/lambda-inference.sld)
builds conditional summaries for later optimization, deferring generalization
until an active inference group has settled. These summaries add no source
typing requirements; backend specialization is connected in the next stack layer.
[`type-analysis.sld`](src/snail-scheme/type-analysis.sld) defines pure checking
rules that take child facts as arguments. One declaration scan collects assignments,
initializers, and nominal identities before narrowing. Typing, closure analysis,
and constant evaluation share its binding stability decisions; immutable scopes
retain declared types and verified contracts under binding identities. The visitor in `wasm.sld` passes
transient facts directly to these rules and to emission. There are no expression
type caches or separate signature and guard lookup tables. Checked callable views
retain implementation origins for recursive-instantiation checks. A guard's
postcondition can justify a later optimization, never removal of that guard.
The emitter checks local returns inline. The first guarded tail transfer owns
one checking frame; the private closure ABI shares its pending-check context
with subsequent tail calls. `wasm-runtime.sld` deduplicates recurring check sites in
inner-to-outer order and executes them when the logical invocation returns.
Ordinary calls and ABI callbacks start fresh; neither closures nor Rust roots
capture this state.
See [the implementation report](doc/typing-prototype.md) for syntax, soundness
obligations, measurements, and the boundary between implemented and proposed rules.

[`wasm-i32.sld`](src/snail-scheme/wasm-i32.sld) optionally specializes closed
monomorphic i32 functions. Code and interval bounds travel together; unsupported
expressions or possible i64 overflow cause whole-function fallback. Public
closures keep the ordinary Scheme ABI, while eligible recursive workers use i32
parameters/results and checked, widened arithmetic. Self tail calls save every
operand before replacing parameters and branching to a local Wasm loop.

## Emitting WebAssembly

[`wasm.sld`](src/snail-scheme/wasm.sld) takes a library graph of resolved IR and
constructs folded Wasm datums in memory. It uses the shared declaration summary
and separately analyzes lambda captures and initialization order. It does not build MIR, bytecode, a managed operand
stack, or LLVM objects. Traversing the IR directly keeps conditionals and calls
visible in the generated code. Runtime helpers are quoted datums too.
`write-wasm` prints each definition with standard `write-simple`; only import
string leaves need WAT-specific byte escaping. The portable backend passes
that WAT to Binaryen. The Scheme-only module is optimized before linking.

[`partial-eval.sld`](src/snail-scheme/partial-eval.sld) attempts bounded evaluation
of closed scalar computations as the visitor checks and lowers each expression.
The visitor checks every source child before consuming a scalar fold; even a
discarded branch must typecheck. No fold index survives. Unknown values, effects,
typed boundaries, overflow, or exhausted fuel abandon an attempt. Private
temporary pairs and vectors may participate, but only scalar results become
replacements. The bounded interpreter retains private activation slots and fuel;
these are separate from the immutable typing scopes.
Each visitor result also says whether interpreting the original syntax could
bypass an inferred check. Children propagate that information directly; a guard
inside an immediate lambda blocks folding the whole call and publishing its raw
value. The interpreter still proves purity, successful execution, and bounded work.

Tail expressions delay code assembly until their enclosing result checks are
known. These small builders capture selected WAT fragments and explicit check
recipes, never inferred facts or type scopes. They are consumed once before the
enclosing procedure's code is published. Ordinary children already contain WAT.

[`wasm-literals.sld`](src/snail-scheme/wasm-literals.sld) turns compound literals
into a dependency-ordered object graph. Identity preserves shared objects without
merging equal mutable containers; an explicit work list handles long lists.
Wasm constant initializers consume this graph, including shared and cyclic
datums supported by the reader.

Each lambda has a fixed worker and a generic closure adapter. Known immutable
fixed callees pass arguments directly. Immutable core names call their existing
checked primitive adapters directly; those and unknown calls keep a GC argument
array. Adapter selection preserves the actual closure environment and result-check
context. Unknown calls retain runtime dispatch.
Wasm tail-call instructions implement proper tail calls. Captures known to be
initialized and immutable travel by value; mutable or early captures use cells.
Recursive initialization preserves unreadable cells until each initializer
finishes. Single/multiple-value contexts are checked explicitly.

Annotated functions also have a checked entry. A direct call bypasses it only
when every argument has sufficient evidence; generic adapters retain it.
Per-expression facts remove redundant single-value and category checks, while
initialization, field-content, arithmetic-overflow, and bounds checks require
their own evidence. The runtime provides integer-only and known-category
helpers without changing ordinary Scheme storage representations.

[`src/snail-scheme/wasm-runtime.sld`](src/snail-scheme/wasm-runtime.sld) defines the value representations and
checked primitives. Small integers are immediate `i31ref`; larger integers and
floats are boxes. Other values use structs and arrays. Type equivalence is
structural, so atom and text categories carry explicit tags. The engine owns
GC and stack roots. `apply` and `call-with-values` stay in Wasm for tail calls.

[`src/symbols.rs`](src/symbols.rs) owns one Rust `HashMap` from exact names to
31-bit symbol IDs, with a reverse name vector. It is global to the linked Wasm instance. Symbol atoms carry the sign bit plus the ID; equality
and identity hashing use that ID. `wasm-literals.sld` assigns the literal prefix
and emits its names as constant data. The registry copies that prefix on first
use, before assigning dynamic IDs. It never retains Scheme roots or reuses IDs;
its mutex is released before allocating Scheme values.
The Rust datum reader and `string->symbol` share this interning boundary.

[`src/snail-scheme/wasm-abi.sld`](src/snail-scheme/wasm-abi.sld) exposes separately named scalar functions
for Rust: owned root handles, construction, extraction, and synchronous Scheme
callbacks. A reference table retains values; a free list reuses released slots.
The [Rust ABI module](src/abi.rs) expresses that ownership through `Root`:
clone retains, drop releases, return transfers. Raw handles are unsafe and bound
to their instance. Imports bind to the linked Scheme module's ABI exports.
Rust uses ordinary `extern "C"` functions and the same explicit export names;
there is no procedural-macro crate or implicit argument conversion.

[`src/lib.rs`](src/lib.rs) implements common Rust-to-Wasm services:
printing, numeric text conversion, mathematics, substring search, Unicode classification,
and binary value/UTF-8 conversion.
Complex numbers have immutable real and imaginary GC references. Basic Wasm
arithmetic preserves exact integer components; Rust implements complex
transcendentals and polar operations with binary64 components. Exact integers
remain limited to signed 64 bits, and exact noninteger rationals are unsupported.

[`datum.rs`](src/datum.rs) implements `(scheme read)` in Rust compiled to Wasm. An iterative
parser builds a flat Rust graph, then allocates rooted Scheme objects and installs
their edges. This permits shared and cyclic datum labels without using the Rust
call stack or exposing unrooted Scheme references. Comments, abbreviations,
escaped strings/symbols, vectors, bytevectors, and numeric prefixes share one
streaming reader. [`host.rs`](src/host.rs) owns buffered ports and their UTF-8
cursor; `read`, `peek-char`, `read-char`, and `read-line` share its lookahead.
The port retains fold-case state between datums and never retains its GC wrapper.

[`text.rs`](src/text.rs) implements native Unicode casing and ordered comparisons.
[`unicode.rs`](src/unicode.rs) supplies generated Unicode 16 casing exceptions
and decimal digit ranges. Character operations use simple scalar mappings;
string operations can expand characters. [`scripts/generate-unicode`](scripts/generate-unicode)
rebuilds the exceptions from UnicodeData and CaseFolding against Rust's native
casing operations, preserving the module's final tests.
[`hash.rs`](src/hash.rs) uses those same full folds for case-insensitive text
keys, and hashes complex numeric components according to `eqv?`.
Rust-owned external resources need explicit close. The additional JS
[`host.mjs`](src/runtime/host.mjs) registers WasmGC wrappers with
`FinalizationRegistry` for eventual resource cleanup. It is browser-compatible;
[`run-wasi.mjs`](scripts/run-wasi.mjs) supplies the Node WASIp1 runner.

[`src/interop_example.rs`](src/interop_example.rs) demonstrates Rust retaining
Scheme values, invoking callbacks, and returning rooted values. It is compiled
into the standard runtime; [its build script](examples/rust-interop/build.scm)
provides the Scheme name-to-Wasm-module declarations. All Rust code in a portable Wasm program
shares the runtime's one linear memory.

## Platform implementation and ownership

[`platform.rs`](src/platform.rs) implements default WASI ports, command context,
clocks, and diagnostics. [`host.rs`](src/host.rs) owns buffered port resources;
[`artifacts.rs`](src/artifacts.rs) resolves pinned companions. They share the
link-time Rust artifact and memory with the common library. Provider selection
happens at link time; independently instantiated extension reactors are future work.
The [effect interface chapter](doc/book/effects.md) states the contracts and limits.

[`scripts/run-wasi.mjs`](scripts/run-wasi.mjs) loads one node, supplies WASI and
host imports, and executes its entry. The environment handler sets guest cwd
before Scheme runs. [`host.mjs`](src/runtime/host.mjs) supplies identity hashing
and finalizers. Cleanup holds only scalar resource IDs; explicit close remains
necessary for timely release. Fatal traps discard the node. `call/cc` and
suspension across Rust frames are unsupported.

## Tests, measurements, and the application model

[`doc/book/`](doc/book/index.md) contains the recovered node/runtime model,
connection diagrams, concrete build APIs, installed Node host, and GUI stubs.
The runtime runs a node using its selected platform. Spawn/connect/message
contracts are documented model behavior, not installed command capabilities.
[`scripts/book`](scripts/book) builds or serves the book.

Scheme unit tests live in module-local final `Tests` sections. `make test` enables
`snail-tests`; Rust helper tests run through `cargo test --offline`. Backend checks
execute linked Wasm. Build and generator checks cover publication, relocation,
callbacks, and root ownership. `scripts/test-effects` executes alternate providers
and rejects invalid bindings. `scripts/test-self-host` runs and rebuilds the Wasm
command while Chibi remains the bootstrap recipe. See [all checks](doc/backend.md).

`make benchmark` runs the pinned 57-workload [R7RS suite](benchmarks/r7rs.py).
[`compile-self.py`](benchmarks/compile-self.py) freezes sources and measures the
compiler separately. Preparation finishes before timing; reports retain every
failure. [The migration report](benchmarks/results/2026-10-12-native-v8/README.md)
compares the archived native path with V8 on identical optimized Scheme modules.
The LLVM emitter and collectors remain on
[`archive/llvm-backend-20261012`](https://github.com/tsnl/snail-scheme/tree/archive/llvm-backend-20261012).
