# A tour of Snail-Scheme

The compiler is an ordinary Scheme library. Chibi bootstraps the native CLI;
the resulting `snail-scheme` interpreter can run its own build script. Wasm is
the portable intermediate format. Rust provides runtime operations through the
application Wasm interface (AWI), with matching native C symbols.

```text
build.scm -> compile-native main.scm and its generated installation library
  -> reader -> syntax parser -> expander -> library-grouped IR -> Wasm datums
  -> name/type resolution -> LLVM
  -> Clang/LLD + native Rust runtime + BDWGC -> build/snail-scheme

Portable backend: Wasm datums -> write-simple -> Binaryen + Rust Wasm -> .wasm

snail-scheme [-I DIRECTORY ...] SCRIPT -> compile temporary native script -> run -> return status
```

## Entering the compiler

[build.scm](build.scm) owns the interpreter's output path. [main.scm](main.scm)
defines its zero-argument `main` handler: parse `-I` library directories, run the
supplied script, and return its status. Both `-Isrc` and `-I src` work; each
occurrence prepends a directory. `--` ends interpreter options, and arguments
after the script filename pass through literally.
[`options.sld`](src/snail-scheme/options.sld) supplies the reusable option reader.
`make-args-spec` validates a quoted list of type-headed declarations and stores
the program name, optional help text, option records, and unique alias lookup
in an `<args-spec>` record. Usage and help are generated from this record. The
`<args>` result holds positionals and a value for each declared option. Four canned
types handle boolean flags, counters, single values, and repeated values; grouped aliases
share one result key. Repeated values accumulate latest first.
Full parsing accepts options after positionals; the interpreter uses prefix
parsing to preserve script arguments. Both consume `--` and keep its remaining
tail literal. See [option parsing](doc/options.md).
[`native.sld`](src/snail-scheme/native.sld) composes source compilation,
the native runtime archive, and explicit CLI entry adapters. A normal script has
no special entry name: its forms execute once and normal completion returns zero.

[`build.sld`](src/snail-scheme/build.sld) supplies portable Wasm assembly/linking,
external tool invocation, and atomic artifact publication.
The publication operation checks its protected input paths before creating work
and again before renaming the completed artifact. Native compilation stages share
that one workspace. `build.scm` supplies the project recipe and generated
installation library; the native library does not know which program it builds.
[`build-host.sld`](src/snail-scheme/build-host.sld) selects the Chibi bootstrap
adapter or named native Rust operations from [`build_host.rs`](src/build_host.rs).
Both pass literal argv without a shell. Build tools receive EOF on stdin;
executed scripts inherit it. Successful builds clean private intermediates;
failed builds retain them and preserve the last published artifact. Cargo tracks
Rust dependencies and reuses the runtime archive.

[`compiler.sld`](src/snail-scheme/compiler.sld) exports
`source-file->wasm`: source filename to a complete in-memory Wasm datum.
`source-file->wat-file` additionally writes that datum as unlinked WAT. The loader
maps `(scheme ...)` to `bootstrap/scheme/`. Other imports search caller-provided
library directories in order, then `src/`; one search policy covers transitive
imports, and malformed first matches do not fall through.
The frontend does not launch processes. An optional CLI entry selects a root
module handler or the ordinary script adapter; build policy remains outside
the frontend.

[`compile-build.sld`](src/snail-scheme/compile-build.sld) installs the resolver for
`generate-library`. It compiles and runs each generator in a private workspace,
caches its result for one build, and collects its dependency artifacts.
[`generation.sld`](src/snail-scheme/generation.sld) owns the located-source and
artifact transport protocol. The wrapper's name and exports remain authoritative;
the generator returns import and begin declarations.

[`artifacts.sld`](src/snail-scheme/artifacts.sld) validates the dependency graph,
snapshots completed files, and writes the package manifest. A build with
dependencies publishes an executable and its files as one generation, then
atomically switches the public symlink. [`(snail artifacts)`](src/snail/artifacts.sld)
resolves companions beside the physical executable; old generations remain
available to running programs. [`runtime-artifact.sld`](src/snail-scheme/runtime-artifact.sld)
uses a generator to run Cargo and package `snail-runtime.wat` for the compiler.
See [generation and packaging](doc/build-artifacts.md).

[`chromium-trace.sld`](src/snail-scheme/chromium-trace.sld) decorates procedures
with `chromium-trace` and records spans only when calls return normally.
`with-chromium-trace-to` opens a file, initializes its JSON array with a metadata
event, and finalizes and closes it when the thunk returns. Compiler and build
operations use these decorators; executable scripts choose the destination and
establish the file scope. Calling a decorated procedure outside a file scope
raises an error. [`scripts/view-traces`](scripts/view-traces) serves a selected
trace and the Nix-provided Perfetto UI on loopback for viewing through an SSH
tunnel. Opening its URL loads that trace in dark mode. See [Tracing](doc/tracing.md).

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
hashing through owned AWI roots. Wasm's weak identity map and native pointer
hashing avoid a registry that would retain keys. See [hash tables](doc/hash-tables.md)
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
solves rank-one `All` instantiations from arguments and expected results.
[`type-analysis.sld`](src/snail-scheme/type-analysis.sld) defines pure checking
rules that take child facts as arguments. A declaration scan collects assignment
and nominal identities before narrowing; immutable scopes retain declared types
and verified contracts under binding identities. The visitor in `wasm.sld` passes
transient facts directly to these rules and to emission. There are no expression
type caches or separate signature and guard lookup tables. Checked callable views
retain implementation origins for recursive-instantiation checks. A guard's
postcondition can justify a later optimization, never removal of that guard.
The emitter checks local returns inline. The first guarded tail transfer owns
one checking frame; the private closure ABI shares its pending-check context
with subsequent tail calls. `wasm-runtime.sld` deduplicates recurring check sites in
inner-to-outer order and executes them when the logical invocation returns.
Ordinary calls and AWI callbacks start fresh; neither closures nor Rust roots
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
constructs folded Wasm datums in memory. Its declaration scans record binding identity, assignment, lambda
captures, and initialization. It does not build MIR, bytecode, a managed operand
stack, or LLVM objects. Traversing the IR directly keeps conditionals and calls
visible in the generated code. Runtime helpers are quoted datums too.
`write-wasm` prints each definition with standard `write-simple`; only import
string leaves need WAT-specific byte escaping. The portable backend passes
that WAT to Binaryen; the native backend consumes the datums directly.

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
Both Wasm constant initializers and LLVM static aggregates consume this graph.
Cycles still require reader datum-label support. The LLVM static path retains
the initial graph for the module lifetime and leaves unsupported initializers
on the ordinary runtime path.

Each lambda has a fixed worker and a generic closure adapter. Known immutable
fixed callees pass arguments directly; unknown calls use a GC argument array.
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

[`src/snail-scheme/wasm-awi.sld`](src/snail-scheme/wasm-awi.sld) exposes separately named scalar functions
for Rust: owned root handles, construction, extraction, and synchronous Scheme
callbacks. A reference table retains values; a free list reuses released slots.
The [Rust AWI module](src/awi.rs) expresses that ownership through `Root`:
clone retains, drop releases, return transfers. Raw handles are unsafe and bound
to their instance. Native imports bind to the translated module's AWI exports.
Rust uses ordinary `extern "C"` functions and the same explicit export names;
there is no procedural-macro crate or implicit argument conversion.

[`src/lib.rs`](src/lib.rs) implements Rust services: ports,
printing, numeric text conversion, inexact mathematics, substring search, Unicode classification,
process arguments, environment, binary IO/UTF-8, clocks, traces, and diagnostics.
The `(scheme inexact)` procedures operate on binary64 reals through this rooted
boundary. They accept exact integers, return inexact mathematical results, and
preserve NaNs, infinities, and signed zero; complex numbers remain unsupported.
[`host.rs`](src/host.rs) owns port data and UTF-8 stream handling.
Rust-owned external resources need explicit close. The additional JS
[`host.mjs`](src/runtime/host.mjs) registers WasmGC wrappers with
`FinalizationRegistry` for eventual resource cleanup. It is browser-compatible;
[`run-wasi.mjs`](scripts/run-wasi.mjs) supplies the Node WASIp1 runner.

[`src/interop_example.rs`](src/interop_example.rs) demonstrates Rust retaining
Scheme values, invoking callbacks, and returning rooted values. It is compiled
into the standard runtime; [its build script](examples/rust-interop/build.scm)
provides the Scheme name-to-Wasm-module declarations. All Rust code in a portable Wasm program
shares the runtime's one linear memory; native builds link a native Rust archive.

## Continuations and native translation

The production Wasm backend currently rejects `call/cc`. Single-shot, delimited
continuations are future work; multi-shot continuations are not a goal. Rust
callbacks work, but suspension and cancellation across Rust frames need an
explicit lifetime and unwinding contract. [AWI](doc/rust-interop.md) separates
implemented ownership from this planned support.

[`native.sld`](src/snail-scheme/native.sld) builds x86-64 Linux executables from
in-memory module datums. [`wasm-resolve.sld`](src/snail-scheme/wasm-resolve.sld)
resolves names, canonicalizes final singleton recursive types, and normalizes
each function into evaluation order. [`llvm.sld`](src/snail-scheme/llvm.sld)
consumes these numeric declarations and instructions without reading Scheme IR,
WAT, or Wasm binaries. Unsupported generated shapes fail explicitly. This
adapter handles the compiler's subset; it is not an arbitrary-Wasm validator.

Entry-block slots represent locals and structured branch results; LLVM promotes
them to SSA. Guest functions use `tailcc`, with `tail` on Wasm tail calls,
including calls with different argument counts. Optional function names with
the `cold.` prefix request LLVM's cold hint for wide-number fallbacks.
Immediate i31 values pack and unpack with i32 shifts; all reference storage
remains i64 so heap pointers retain their full width.

[`llvmlite.sld`](src/snail-scheme/llvmlite.sld) keeps names, integer operands and
escaped bytes structured until printing. Finite f64 literals use round-tripping
decimal spelling; infinities and NaNs use LLVM hex literals. Fragments compose as
nested lists and stream to the output port. Only one function's body is buffered
to place local and branch-result slots in its entry block.

[`native.c`](src/native.c) provides WasmGC mechanics, traps and BDWGC. Scheme
objects and the AWI reference table are scanned allocations. Rust links as a
native archive, uses its standard library for OS operations, and retains Scheme
values with owned AWI handles. The binary reader, translated Rust linear memory
and native WASIp1 adapter have been removed. One process currently owns one
Scheme instance. Finalizers queue scalar resource IDs; cleanup calls Rust only
after guest frames return, when no Rust host-state borrow is active. See
[native execution](doc/native.md) for the representation and host contract.

## Tests and measurements

[`doc/book/`](doc/book/index.md) is the mdBook source. Its first platforms are
native CLI, native GUI, and browser GUI, with AWI as a separate extension reference.
Function documentation lives inline in the included WAT interface files;
the native CLI contract is implemented and GUI contracts remain proposals. [`scripts/book`](scripts/book) builds or
serves the book using `book.toml`; the three tutorial chapters define future
integration milestones. Built HTML stays in the ignored `build/book/` directory.

Scheme unit tests live in each module's final `Tests` section with one
conditional `test-<module>` export. `make test` enables the Chibi `snail-tests`
feature and invokes [`tests/snail-scheme/test.scm`](tests/snail-scheme/test.scm).
The compiler advertises `snail-scheme`, not its host's test features, so its own
sources compile without importing host-only test modules.

Rust unit tests remain in implementation modules. `scripts/test-backend`
executes linked Wasm semantic and diagnostic fixtures; `scripts/test-build`
checks library imports, traces, publication, literal arguments, Rust callbacks, and
root ownership. `scripts/test-backend --target both` builds and executes each
fixture through both backends. `scripts/test-native` adds
cross-engine Wasm semantics, traps, bounded native stack use, forced collection,
Rust callbacks, and resource finalization. `scripts/test-self-host` exercises
the native CLI, blocks Chibi and Wasm assembly/optimization during a rebuild,
and runs its replacement. Runtime companion generation still uses `wasm-dis`.

`scripts/test-typing` compares fully guarded and optimized linked Wasm, including
diagnostics, effect order, mutation, record identity, numeric boundaries, and
proper tail calls. `benchmarks/typing/measure.py` measures check elimination and
i32 specialization against checked and unchecked C kernels.

[`benchmarks/`](benchmarks/README.md) contains CPU and allocation workloads.
CPU uses recursive Fibonacci with an independent oracle; memory uses a sieve.
Record execution time separately from compilation and startup, verify answers,
and retain raw samples and Chez/Chibi ratios when comparing backends. Retired
prototypes and measurements remain in Git history.

[`benchmarks/reproduce.py`](benchmarks/reproduce.py) rebuilds the recorded native
Fibonacci comparison in its pinned historical worktree, checks answers,
collects rotating samples, and renders
plots from saved JSON. [`benchmarks/r7rs.py`](benchmarks/r7rs.py) runs the
upstream R7RS suite across Snail native, Chez, Guile, and Chibi using the pinned
[`r7rs-benchmarks`](benchmarks/r7rs-benchmarks) submodule. Preparation,
measurement, and reporting are separate; failed and unavailable cases stay in
the result matrix. Its small [Chez adapter](benchmarks/r7rs-chez.scm) supplies
monotonic timing alongside upstream's language compatibility prelude.
[`benchmarks/plots.py`](benchmarks/plots.py) draws sorted duration bars for both
runners, with a compact README comparison and one chart per suite workload.
[`benchmarks/studio.scm`](benchmarks/studio.scm) is a deterministic color
ray-tracing showcase: rays, intersections, lighting, reflections, and pixels
follow one another in a single file. Its small
[renderer wrapper](benchmarks/render-studio.py) runs reference Scheme systems
and converts their PPM output into a PNG preview.
[`benchmarks/compile-self.py`](benchmarks/compile-self.py) freezes the compiler's
Scheme sources, builds its executable before timing, then measures it compiling
those same sources. The small [Scheme entry](benchmarks/compile-self.scm) owns
the clock boundary; Python checks output bytes and reuses the suite's process
and reporting utilities.
[BENCHMARKS.md](BENCHMARKS.md) provides the commands and measurement scope.
