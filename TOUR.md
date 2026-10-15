# A tour of Snail-Scheme

Chibi hosts the bootstrap compiler. It emits WasmGC for Node.js and native LLVM
lowering. Binaryen optimizes the program Wasm on both paths. Wasm engines own
Scheme memory in Wasm; the native path uses the in-house precise collector.
Both paths use the same Rust value and platform implementations.

```text
located Scheme -> resolved library IR -> WasmGC
  -> Binaryen optimization -> link common library + selected handlers + entry
  -> final Binaryen optimization -> application.wasm
  -> Node.js loader: WASI + JS host imports -> one running node

optimized program Wasm -> mechanical LLVM lowering
  -> Clang/LLD + native Rust archive + C providers -> native executable
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

[`scripts/build-native`](scripts/build-native) checks tools and exact C provider
signatures, invokes the existing frontend through
[`build-native.scm`](scripts/build-native.scm), and links/publishes a native
executable. [`native.sld`](src/snail-scheme/native.sld) always optimizes program
Wasm before native lowering, including supplied binary inputs.
[`wasm-read.sld`](src/snail-scheme/wasm-read.sld) reads Binaryen's text spelling;
[`wasm-resolve.sld`](src/snail-scheme/wasm-resolve.sld) resolves names, canonical
recursive type groups and instruction order. [`llvm.sld`](src/snail-scheme/llvm.sld)
lowers those typed operations with explicit roots and tail transfers;
[`llvmlite.sld`](src/snail-scheme/llvmlite.sld) writes LLVM text fragments.
These modules add no source-language optimization pass. See [native contracts](doc/native.md).

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

[`iverson-ghost.sld`](src/snail-scheme/iverson-ghost.sld) supplies concrete
`object`, `f64`, `f32`, and `i32` tensors, vector compatibility, and a Chibi
reference. [`iverson.rs`](src/iverson.rs) owns unboxed numeric buffers and kernels.
[`iverson-typed.sld`](src/snail-scheme/iverson-typed.sld) defines static eager and
symbolic instances of one tensor interface. See [Iverson Ghost](doc/iverson-ghost.md)
and [static typeclasses](doc/typeclasses.md).

## Checking types and recording evidence

The strict compiler is a separate, native path, selected with
[`scripts/build-strict`](scripts/build-strict). It reuses the located reader,
hygienic expander and resolved binding identities above. It checks all source
bodies, then instantiates concrete code and emits standalone WasmGC with a
native `main` export. Its current surface and limits are in
[the strict core guide](doc/strict-core.md); this is implemented behavior, not
a replacement of the existing command-line compiler yet.

[`strict-types.sld`](src/snail-scheme/strict-types.sld) owns inference holes,
rigid quantified variables, schemes and the bounded Never/concrete/Top lattice.
[`ir.sld`](src/snail-scheme/ir.sld) supplies the same located expression and
definition records to expansion, checking and specialization. Expansion gives
each expression and binding a fresh `Hole` and attaches declared syntax directly
to its definition. It performs no inference. The checker copies all compilation
roots together, preserving shared identities and cycles while isolating cached
libraries, then refines that owned graph. `Hole` is unresolved static information;
`Top` is a concrete universal value representation. Rigid `All` variables are a
separate type variant and cannot be solved by unification.
[`strict-core.sld`](src/snail-scheme/strict-core.sld) holds the checked program's
class and instance evidence; it defines no second expression or binding tree.
[`strict-overloads.sld`](src/snail-scheme/strict-overloads.sld) matches complete
function signatures with isolated candidate trials, commits unique generic row
views, and repeats improvement as argument and result information settles.
Unfinished rows remain possible candidates; only known arity can exclude them.
[`strict-infer.sld`](src/snail-scheme/strict-infer.sld) lowers free overload
declarations to classes and instances, checks source groups, generalizes eligible
values and retains class obligations. Omitted row signatures wait for relevant
family signatures and ordinary helper dependencies before their schemes become
available. Declared schemes can break signature cycles; all bodies still check.
Each dependency reachability query shares its visited identities across branches,
so repeated paths through shared dependencies are explored once. Testing the
target on an edge preserves the distinction between an isolated binding and a
cycle that returns to it.
Runtime initializer order stays in the original block sequence. Abstract obligations bound by a generalized
initializer stay in its template; concrete uses instantiate them. Call operands
are inferred in source order without using overload candidates to choose widths.
The checker also reserves closed `define-data` schemas before checking fields,
then assigns ordinary binding schemes to constructors and optional accessors.
Exhaustive shallow `match` lowers to the existing typed lets and conditionals,
with one subject binding. [`strict-data.sld`](src/snail-scheme/strict-data.sld)
defines nominal applications of resolved declaration identities and substitutes
their field types; recursive fields retain identities instead of expanding a tree.
[`strict-primitives.sld`](src/snail-scheme/strict-primitives.sld)
supplies complete concrete primitive signatures and opcodes, including unary
conversions, fixed-width bitwise intersection/exclusive-or, and logical right shifts.
[`(snail strict)`](src/snail/strict.sld) provides numeric overload
families with explicit I64/F64 promotion bodies, hygienic binding and control forms
and ordinary vector and Unicode string functions. Append, substring, copying,
content comparison and list conversions use the same pipeline as user functions; only
allocation, indexing, identity, length, and bulk copying are native primitives.

[`strict-specialize.sld`](src/snail-scheme/strict-specialize.sld) separates each
lexical initializer site from its required concrete instances, resolves class
methods, selects local procedures used only as call operators, and computes
their transitive capture dependencies. A `let` or block used as an operator
passes that invocation context only to its result; initializers and prefix
expressions keep their ordinary value uses. It makes concrete copies of the
shared IR, preserving checked templates and their external binding identities.
Site, value and function records describe initialization, storage and code;
they are not another expression representation. The same initializer policy serves
recursive definitions and typed lets, with their source scopes explicit. This
module also owns the enumeration of concrete site storage used by the emitter;
readiness tokens and payload copies therefore have one definition.
After concrete demand settles, it records global sites initialized before each
function's creation can execute. Nested functions inherit this conservative
proof; no function assumes later globals ready merely because it can be exported.
[`strict-wasm.sld`](src/snail-scheme/strict-wasm.sld)
assigns native signatures and GC layouts, preserves initialization readiness,
and emits explicit universal-value conversions. Immutable scalar literal reads
expose the constant payload while retaining the source binding's readiness check.
Function bodies omit global readiness checks only for the completed sites proved
by specialization. Ordinary closure reads, direct binding tokens and the export
initialization guard preserve the callable-entry guarantee behind that proof.
Direct local procedures receive
lexical state as native parameters. Parameters and nonrecursive let values are
initialized before capture and travel as concrete values. Recursive local
captures carry nullable payloads and readiness flags until the original read;
surviving closures retain shared cells wherever later initialization must remain
observable. A direct
procedure's binding still publishes readiness at its original source event.
Calls save operands before entering structured operators, then invoke the final
procedure inside its lexical scope. This also keeps named-let recursion direct
without changing the expanded or checked frontend forms.
Invariant vectors use native
array element storage; I64 index checks precede narrowing, while native array
instructions own bounds and overlapping-copy behavior. Each String has an
immutable owner containing writability, unsigned scalar length, a direct first
character block and an optional directory of remaining blocks. Its private i32
arrays each hold at most 8,192 Unicode scalars; short and empty strings omit the
directory. Constructors publish only fully initialized, independently owned
blocks. Copies validate both complete I64 ranges before traversing bounded native
array-copy spans in the overlap-safe direction. Readonly literal globals and
fresh mutable strings share the same layout.
Bytevectors use immutable owners with permission and private packed i8 arrays.
Their native operations check bytes and I64 indices before narrowing, and bulk
copy checks both complete ranges before mutation. Readonly literals are rooted
globals; mutable constructors and copies retain fresh identity. The ordinary
Scheme library [`(snail bytes)`](src/snail/bytes.sld) implements constructors,
copy/append helpers and strict UTF-8 conversions with scalar loops. It translates
between bytes and Unicode scalars without passing managed references to Rust or
allocating a product for each character. The native executor uses the declared
Wasm array storage widths, including packed bytes and four-byte character scalars.
Unicode scalar conversions reject surrogate and out-of-range values. Nominal records use immutable native fields;
closed sums add a constructor tag and typed case subtypes. The layout registry
reserves applications before following recursive fields, and accessors explicitly
check tags because Wasm can canonicalize cases with identical shapes.
Zero-field cases use private rooted globals named by those same concrete layout
identities. Their source calls still evaluate operators and enforce readiness;
payload-bearing constructors and explicit mutable identities remain runtime work.
Native foreign declarations retain their resolved identity in IR.
[`wasm-extern.sld`](src/snail-scheme/wasm-extern.sld)
validates the concrete scalar boundary shared by imports and selected worker
exports; the emitter adapts Unit results without introducing an object carrier.
[`strict-compiler.sld`](src/snail-scheme/strict-compiler.sld) composes these
passes without process effects. The build wrapper reuses the shared Binaryen
assembly and optimization path. [`scripts/test-strict`](scripts/test-strict)
executes native exports and checks located source rejections.
[`scripts/test-strict-extern`](scripts/test-strict-extern) links real Wasm
providers, checks mismatched signatures and exercises reusable worker captures
and one-shot initialization through raw and optimized modules.

[`(snail io)`](src/snail/io.sld) provides strict text files with concrete
`InputPort` and `OutputPort` wrappers, explicit close, Scheme character loops and
I64 decimal formatting. Its `LineResult` distinguishes EOF from empty lines;
Scheme constructs lines using a geometrically growing String buffer while Rust's
existing text reader owns UTF-8 decoding and one-character lookahead.
[`strict_io.rs`](src/strict_io.rs) receives scalar characters and resource IDs,
owns a temporary UTF-8 pathname and live files, and releases resources before
reporting fatal I/O errors. It reuses [`host.rs`](src/host.rs) buffered ports and
holds no Scheme roots. [`scripts/link-strict-runtime`](scripts/link-strict-runtime)
links these services from the ordinary Rust runtime, prunes private exports, and
rejects any remaining legacy value-ABI import. The host initializes WASI before
Scheme and invokes the retained cleanup export after traps. See
[strict file I/O](doc/strict-io.md) and the actual Node/WASI checks in
[`scripts/test-strict-io`](scripts/test-strict-io).

[`(snail datum)`](src/snail/datum.sld) gives strict programs concrete recursive
datums, interned symbols, exact I64/inexact F64/complex numeric variants,
structural equality and proper-list operations. Mutable datum identity names
backing storage; pair identity compares both explicit Ref fields. Equality
follows finite cyclic graphs with explicit continuations and a query-local
table of private recursive-view IDs. Those IDs do not replace storage identity
or add fields to Ref/vector storage; the scalar counter retains no objects.
The public constructors and read-only projections keep the private IDs
unforgeable. Decimal I64 formatting stays in Scheme. The module owns the shared
`ReadResult` data and interprets each ordinary atom through one staged text
handle, closing it or consuming it into a symbol before returning.
[`(snail read)`](src/snail/read.sld) re-exports the unchanged result API and consumes Unicode input
incrementally, owns token buffers and parsing in Scheme, and distinguishes a
datum, EOF and syntax failure. [`strict_datum.rs`](src/strict_datum.rs) supplies
owned scalar token handles, checked numeric conversion and a root-free strict
symbol identity domain. It shares the legacy numeric parser and symbol storage
implementation without importing legacy Scheme roots. Terminal file cleanup
also releases unfinished token handles. [The reader contract](doc/strict-reader.md)
states exactness, signed-zero/NaN equality, resource lifetimes and unsupported
syntax; [`scripts/test-strict-reader`](scripts/test-strict-reader) compares complete
datum streams with Chez on linked raw/optimized Wasm and native.

[`(snail integer)`](src/snail/integer.sld) implements immutable arbitrary-precision
exact integers in ordinary strict Scheme. Private I32 WasmGC arrays hold 30-bit
limbs; I64 intermediates bound carries, products and quotient estimates. Static
numeric methods add exact arithmetic without changing existing I64 semantics.
The same module owns checked decimal and machine conversions, normalized long
division, exponentiation and floor square root. Binary64 conversion distinguishes
exact integral input from explicit truncation; exact ratios choose the final
binary64 spacing and round once using their integer remainder. No managed number
crosses the Rust ABI. [`scripts/test-strict-integer`](scripts/test-strict-integer) checks
independent arithmetic and ownership oracles on raw/optimized Wasm and native64,
including an exhaustive small-radix copy of its module-local tests. See
[the integer contracts](doc/strict-integer.md).

[`(snail math)`](src/snail/math.sld) declares binary64 `sin`, `cos` and
one-argument `atan` as ordinary typed externs. Their scalar C signatures call
[`strict_math.rs`](src/strict_math.rs) in both the native and Wasm runtime;
neither side creates Scheme roots or delegates arithmetic to the JavaScript host.
[`scripts/test-strict-math`](scripts/test-strict-math) executes both linked Wasm
forms and the native worker, checking finite values, signed zeros and nonfinite
inputs. Mathematical accuracy follows the target's Rust standard library.

[`(snail typing)`](src/snail/typing.sld) reexports the compiler's opt-in type
syntax. Expansion preserves `:` declarations, `ann` expressions, `inst` views, and record
schemas in IR, with resolved binding identities and source locations. The
existing `define-record-type` macro also accepts typed fields; standard field
forms keep their meaning.

[`types.sld`](src/snail-scheme/types.sld) defines shallow categories, structural
unions, nominal records, rigid type variables, internal occurrence intersections,
and conservative type operations. [`type-inference.sld`](src/snail-scheme/type-inference.sld)
solves rank-one `All` instantiations from arguments and expected results. Its
lower-bound joins preserve the named `Boolean` and `Number` heads across calls
and function views; explicit instantiation retains its supplied types.
[`type-analysis.sld`](src/snail-scheme/type-analysis.sld) defines pure checking
rules that take child facts as arguments. One declaration scan collects assignments,
initializers, and nominal identities before narrowing. Typing, closure analysis,
and constant evaluation share its binding stability decisions; immutable scopes
retain declared types and verified contracts under binding identities. The visitor in `wasm.sld` passes
transient facts directly to these rules and to emission. There are no expression
type caches or separate signature and guard lookup tables. Checked callable views
retain implementation origins for recursive-instantiation checks.

[`typeclasses.sld`](src/snail-scheme/typeclasses.sld) elaborates class metadata
and constrained `All` functions before emission. Its traversal reuses the pure
checking rules, retaining overloaded uses and lambda signatures for specialization.
It checks one coherent instance universe, verifies generic bodies under abstract
method contracts, and clones concrete functions with fresh local identities.
Implementations retain their source initialization sites. The output is ordinary
resolved IR with class selection erased; the emitter checks it using transient facts.

A guard's postcondition can justify a later optimization, never removal of that guard.
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
Its kind-2 cleanup goes to the common numeric library's `snail:drop-array`
export; kind-1 cleanup goes to the selected platform's port provider.

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
The restored native path is validated by [`scripts/test-native`](scripts/test-native).
[`native.c`](src/native.c) implements checked Wasm operations, root frames and
terminal cleanup. Array operations receive their constant element stride from
[`llvm.sld`](src/snail-scheme/llvm.sld); references retain eight-byte storage,
while numeric arrays use their declared widths, including static initializers.
[`precise-gc.c`](src/precise-gc.c) traces only declared references,
reuses Immix line holes and grows through additional nonmoving regions when
collection cannot satisfy an allocation or leaves little headroom. Each region
owns its exact-start, block and line maps; an explicit heap-size setting remains
a hard total cap.
[`native.rs`](src/native.rs) closes the shared Rust
resources exactly once. [`abi.rs`](src/abi.rs) binds owned Rust roots directly to
generated native C adapters; it uses test stubs only in standalone Rust tests.

[`benchmarks/wasm-reference/`](benchmarks/wasm-reference/README.md) contains
standalone Rust/WASIp1 reference algorithms and their Node runner. Its suite
validator covers all 57 canonical source implementations, freezing source/tool/binary
hashes and preserving target failures separately from successful full-count
checks. The historical five-case measurement driver freezes original inputs and
compiled controls and records separate workload and process times. The [five-case report](benchmarks/results/2026-10-13-wasm-five-reference/README.md)
compares those references with Chez and a separately measured historical Snail
batch; it does not change the compiler or runtime.

The reference library's `boyer` module shares the full directional-unification,
rewrite and tautology machinery of the two prover executables. Their distinct
allocation rules remain visible: `sboyer` reuses unchanged argument and call
cells, while `nboyer` reconstructs them. Constructor identities refer into an
owned symbol-record table; quoted lemma data is preserved separately.
The `peval` executable retains mutable residual-program cells and lexical
specialization frames; its untimed `audit_alpha.py` comparator checks complete
programs modulo bound-variable renaming. The `parsing` executable independently
ports the generated scanner and LL(1) grammar, including temporary list-tail
copying and original action/error behavior.
The `scheme` executable recompiles each supplied expression before executing its
lexical closures; global binding mutation and escaped environment lifetimes
remain observable. The `dynamic` executable runs the original self-applied type
inference passes and materializes the complete tagged program, keeping its
primitive type graphs persistent across calls.

The benchmark's independent `compiler` executable compiles its supplied Scheme
program to the original 68000 assembly format on each iteration.
[`compiler.rs`](benchmarks/wasm-reference/src/compiler.rs) owns located syntax,
lexical identities and normalization;
[`compiler_gvm.rs`](benchmarks/wasm-reference/src/compiler_gvm.rs) builds register/
stack/closure graphs, and
[`compiler_blocks.rs`](benchmarks/wasm-reference/src/compiler_blocks.rs) purifies
those graphs and records backward slot requirements.
[`compiler_68000.rs`](benchmarks/wasm-reference/src/compiler_68000.rs) emits machine
instructions with explicit operand/frame lifetimes;
[`compiler_asm.rs`](benchmarks/wasm-reference/src/compiler_asm.rs) owns object words,
symbol/reference records, shared labels, relocation and branch tensioning.
Complete linked diagnostics accompany the unchanged 2,000-repeat, 497-line
predicate. These reference modules are separate from Snail's Chibi-hosted
WasmGC compiler.

[`benchmarks/string-reference-controls/`](benchmarks/string-reference-controls/README.md)
holds separate byte/u32 String diagnostics with four fresh buffers per growth
and explicit allocation-initialization controls. Complete untimed payload
oracles and a separate allocation/zero-fill probe check their work; these
controls do not change the canonical 57 references or claim measured speedups.

[`benchmarks/strict-cat/`](benchmarks/strict-cat/README.md) compiles a scalar copy
worker from strict Scheme and links it into the frozen cat harness. Preparation,
linked Unicode/error/ownership checks, and clean timing are separate operations.
Its [report](benchmarks/results/2026-10-13-strict-source-cat/README.md) preserves
both source-compiled and hand-written scalar controls with the same provider.

[`benchmarks/strict-suite/`](benchmarks/strict-suite/README.md) adapts arithmetic,
closure, typed-list, mutable-vector and nominal-data kernels to the strict compiler, keeping original inputs
and counts. It separates preparation/behavior checks, clean timing, explicit
Chez flonum controls, and artifact replay.
[`data_ports.py`](benchmarks/strict-suite/data_ports.py) owns the exact paraffins
and gcbench source edits, concrete representations and separate structural
oracles. Their canonical optimized artifacts are inspected independently:
paraffins can discard unobserved payloads; gcbench currently loses its intended
long-lived tree root and is excluded from timing.
[`enumeration_ports.py`](benchmarks/strict-suite/enumeration_ports.py) owns the
graphs/mperm source adaptations, complete-value encoders and independent finite
graph/permutation oracles. Their observer modules remain separate from canonical
workloads; mperm keeps initial queue construction before the timer. The
[`simplex_port.py`](benchmarks/strict-suite/simplex_port.py) module makes simplex's
mutable scalar bindings explicit and gives its three result forms a closed
nominal type. Separate probes compare the complete result, tableau and ordered
matrix stores. A small rational LP oracle distinguishes source equivalence from
mathematical correctness, including a preserved upstream equality-case failure.
[`deriv_port.py`](benchmarks/strict-suite/deriv_port.py) gives deriv's finite
atoms and recursive pairs a closed datum type while preserving its list spines,
input sharing and original quotient rule. It owns exact source edits and
separate complete-expression/failure probes; the runner also checks Chez
identity and the original current-result loop. Its scalar-only hiding boundary
requires separate optimized-work inspection before timing.
[`mbrotz_port.py`](benchmarks/strict-suite/mbrotz_port.py) expresses the original
complex Mandelbrot operations as a closed pair of F64 components while keeping
the complex escape and matrix loops intact. Separate probes expose every pixel
and ordered store, exact component bits and escape boundaries. Its scalar size
uses the value-returning hiding import; its source allocation structure and
optimized retained objects are documented separately.
[`string_port.py`](benchmarks/strict-suite/string_port.py) keeps the original
append/substring workload over the compiler's native Unicode String, changing
only its mutable global to Ref. It preserves the initial false result and
Boolean-or-I64 predicate through scalar inputs. Separate modules check complete
characters, replacement order and copy independence; canonical retained payload
work remains a separate evidence question from the original length predicate.
[`puzzle_port.py`](benchmarks/strict-suite/puzzle_port.py) keeps puzzle's complete
board search and both untimed setup regions. Its local escape becomes explicit
Boolean search control; mutable scalars use Ref and false-or-count results use a
closed variant. Separate probes compare every board/mask cell, retained row
identities, ordered effects and bounds-failure prefixes against original Chez
and an independent board model. This does not add continuation support.
[`lattice_port.py`](benchmarks/strict-suite/lattice_port.py) preserves lattice's
polymorphic enumeration with typed lattice/binding products and mutable list
tails. It keeps destructive reversal, branch-result lists and append sharing.
Separate complete-poset oracles, comparison traces and node-identity probes
check the source adaptation against both Chez forms.
[`destruc_port.py`](benchmarks/strict-suite/destruc_port.py) retains destructive
row splices with two concrete mutable-list instances, explicit head/tail Ref
cells and empty/integer items. Its separate graph oracle and node registries
check ordered effects, sharing and abandoned nodes; the canonical predicate
compares the complete nested result. The source explicitly selects the operand
order observed in the original Chez diagnostic control.

[`ray_port.py`](benchmarks/strict-suite/ray_port.py) preserves Ray's complete
sphere traversal, negative-root behavior, geometry and PGM formatting with
concrete products and optional results. It reuses scalar text output, retains
untouched and adapted Chez controls, and checks complete images, floating bit
patterns, tie order and file lifecycle. Its dedicated
[`ray-host.mjs`](benchmarks/strict-suite/ray-host.mjs) brackets initialization and
the timed worker with resource cleanup; runtime input decoding precedes timing.

[`mazefun_port.py`](benchmarks/strict-suite/mazefun_port.py) retains the functional
maze's persistent nested lists, deterministic shuffle and ordered cavity floods.
Coordinates are cavity labels in one closed variant; dimension products and
finite result variants keep the remaining pair/symbol roles concrete. A Chez
reader preserves complete expected mark lists before timing, and the timed
predicate checks their full shape and contents. Separate output and cavity-trace
probes cover both Chez forms and raw/optimized Wasm; persistent spine identity
is additionally checked in Chez.
[`nucleic_port.py`](benchmarks/strict-suite/nucleic_port.py) preserves the complete
nucleotide database and ordered geometry search. Counted reversible edits map
heterogeneous nucleotide vectors to concrete products and mutable assignment
identity to Ref; all coordinate vectors, constants and source setters remain.
Its original and adapted Chez controls share complete-value, ordered-solution
and mutation probes with linked Wasm and native execution. The dedicated
[`nucleic-host.mjs`](benchmarks/strict-suite/nucleic-host.mjs) supplies scalar
inputs and observations, checks the worker, and closes resources on every exit.

[`bv2string_port.py`](benchmarks/strict-suite/bv2string_port.py) preserves the
bytevector benchmark's RNG, three conversions, string comparisons and failure
diagnostics. Reversible ref edits and exact integer ties-to-even rounding keep
the original and adapted kernels reviewable. Separate preparation probes compare
the complete RNG and byte/character streams across Chez, Wasm, native and Rust;
the canonical timed source retains its original repetition count and work.

[`earley_port.py`](benchmarks/strict-suite/earley_port.py) prepares the complete
Earley parser, including forward closure, backward filtering, ordered tree
materialization and the separate counting API. Concrete grammar/token/parser
records retain callable fields, optional slots retain false-versus-index
semantics, and typed recursive tree elements retain the original list work.
The finite atom vocabulary covers the canonical grammar and explicit probes;
it does not implement general Scheme symbols. Preparation includes untouched
and adapted Chez controls, complete small-tree observations, mutable-state
identity probes and native execution. Its preparation does not add measured
coverage.

[`matrix_port.py`](benchmarks/strict-suite/matrix_port.py) preserves the complete
modular matrix search and ordered answers. Counted edits make lazy permutation
messages, GCD result alternatives, mutable prime tails and collector state
concrete. Original/adapted Chez, raw/optimized Wasm and native probes compare
full results, callback order and mutable aliases; independent small models
check finite-field spans and signed-permutation maximality. The existing Rust
reference is validated as a separate algorithm and layout control.

[`integer_ports.py`](benchmarks/strict-suite/integer_ports.py) preserves the
three complete pi algorithms and Chudnovsky binary splitting using `(snail
integer)`. Reversible source edits lift bounded constants explicitly and keep
scalar digit/count controls separate from arbitrary-precision arithmetic. The
preparation compares complete original-sized outputs on raw/optimized Wasm,
native64, original/adapted Chez and the identical limb Scheme body on Chez with
checked I64/I32 intermediates. Its scalar providers transport expected decimal
text and observed characters; all numerical work remains in Scheme.

[`integer_controls.py`](benchmarks/strict-suite/integer_controls.py) prepares the
eight comparison controls, including the exact native-final module on V8 and
separate native-bigint and same-limb Chez programs. It places input preparation
before the optional clock, the complete numerical predicate inside it, and
serialization afterward. Count and wrong-result controls exercise the production
artifacts; separate probes observe every complete repetition without changing
the measured kernels. Preparation never starts a measurement.

[`reader_ports.py`](benchmarks/strict-suite/reader_ports.py) preserves the complete
Sum1 and Read1 file-reading kernels. Reversible edits expose typed read results,
numeric conversion and the initial false datum. The Chez control uses the exact
Scheme parser body with explicit scalar/datatype compatibility. Separate hosts
observe full per-worker file lifecycles and time the unchanged count loops;
complete stream/result probes and the distinct Rust reader controls remain
separate from clean measurement.

[`browse_port.py`](benchmarks/strict-suite/browse_port.py) adapts the complete
Browse database and backtracking matcher through counted reversible source edits.
It keeps the association lists, copied cyclic pattern ring, destructive shuffle,
and all three matcher return classes. The empty-list result remains truthy.
Separate probes compare every recursive operand and return with original Chez;
the clean builds retain the original 2,000-invocation loop and complete predicate.
The datum library owns reusable list/identity operations, while the adapter owns
the workload's typed boundaries and its original-source compatibility controls.

[`boyer_port.py`](benchmarks/strict-suite/boyer_port.py) preserves the complete
NBoyer and SBoyer provers, including their post-harness definitions and numeric
rewrite-count predicates. Reversible edits expose existing `Datum` and `Ref`
types while retaining constructor-record cycles, association lists and SBoyer's
pair reuse rule. It prepares original/adapted Chez, linked raw/optimized Wasm,
native64 and the independent Rust controls. Separate structural and work-count
programs keep counter instrumentation out of constructor-order observations.
Native heap reservations and capacity failures remain explicit evidence, and
preparation starts no clean measurement.

[`conform_port.py`](benchmarks/strict-suite/conform_port.py) preserves Conform's
functional sort and sets, cyclic type graph, shared mutable memo tables, and
temporary red conformity assumptions through concrete records and Ref fields.
Its reversible ledger produces the same adapted kernel for strict and Chez.
The [probe fixture](tests/strict-conform/probe.scm) observes graph/table structure,
alias mutations, ordering, and every invocation's algorithmic work separately
from the original 500-invocation benchmark. Preparation freezes optimized Wasm,
its mechanical native translation, both Chez sources, and distinct Rust controls.

[`maze_port.py`](benchmarks/strict-suite/maze_port.py) retains Shivers's complete
hexagonal Maze workload, its recursive integer helpers, union-find compression,
wall order, DFS/rerooting, and full character-list output. Concrete records and
Refs replace mutable pairs and heterogeneous vectors. Its sole lexical escape
becomes a callback completion test that stops the reverse wall traversal at the
same point; it adds no general continuation support. Counted edits reverse to
the pinned source, and a separate observation program compares ordered walls,
mutations, identities, every output character, and full-count source operations.
The module prepares original/adapted Chez, raw/optimized linked Wasm, native64,
the exact native-final Wasm on V8, and the unchanged indexed Rust reference.

[`parsing_port.py`](benchmarks/strict-suite/parsing_port.py) keeps Parsing's
complete generated scanner and LL(1) parser. Counted reversible edits expose
the existing `Datum`, Symbol and eight `Ref` bindings without replacing the
grammar or character-list file loader. The full 2,500-parse worker retains its
actual timed file load, simultaneous updates, EOF quirks and complete result
predicate. Preparation compares original/adapted Chez, raw/optimized Wasm,
native and the independent Rust control. Separate token/datum streams, named
procedure counters and alias/reset checks remain outside clean timing. The
[observation fixture](tests/strict-parsing/probe.scm) and its native entry live
under `tests/`; preparation records them as driver inputs separately from the
historical compiler-source basis.

The
[vector report](benchmarks/results/2026-10-13-strict-vector-array1/README.md)
checks whether the allocation and element loops survive compilation; its
coverage table retains failed and unported workloads.
[`benchmarks/strict-wc/`](benchmarks/strict-wc/README.md)
extends the scalar-I/O experiment to Unicode character/word/line counting inside
the frozen legacy harness, with native counts and an owned input-port wrapper.
