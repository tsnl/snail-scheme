# A tour of Snail-Scheme

The compiler is Scheme, hosted by Chibi. WebAssembly is its portable output;
Rust provides host services and extensions through a named application Wasm
interface (AWI). Compiling the compiler sources does not switch the build host.

```text
snail-scheme driver
  -> Chibi: reader -> syntax parser -> expander -> library-grouped IR -> WAT
  -> Binaryen: assemble Scheme WasmGC
  -> Cargo: runtime + extension crates -> one Rust Wasm module
  -> Binaryen: link and optimize -> portable .wasm
  -> Node/WASI + host shim, or an optional separate native translator
```

## Entering the compiler

[`driver/src/main.rs`](driver/src/main.rs) owns modes, temporary artifacts,
subprocesses, and publication. A source path runs; `-o` builds without running;
`--emit-wat` stops before assembly. Arguments after `--` pass literally through
`Command`. Each invocation owns its temporary project. Completed artifacts are
staged and renamed into place so a failed build does not truncate prior output.

[`snail-compile`](snail-compile) invokes Chibi on
[`compile.scm`](src/snail-scheme/compile.scm), whose top-level call enters
[`compiler.sld`](src/snail-scheme/compiler.sld). `source-file->wasm-file` parses,
expands, and emits WAT. The loader maps `(scheme ...)` to `bootstrap/scheme/` and
project libraries to `src/`. Library and binding semantics stay in the expander.

[`trace.sld`](src/snail-scheme/trace.sld) and
[`trace/src/lib.rs`](trace/src/lib.rs) centralize coarse Chromium trace spans.
They are always enabled; `build/traces/` is the default directory and
`SNAIL_TRACE_DIR` overrides it. [Tracing](doc/tracing.md) describes decorators.

The older parser inspection entry [`main.scm`](src/snail-scheme/main.scm) defines
`main` without invoking it. Chibi's `-r` invokes that procedure. Compiling a
file containing only definitions correctly produces no printed output.

## Functional tree composition and UI experiment

[`react.sld`](src/snail-scheme/react.sld) is an independent Chibi-hosted prototype.
`element` records a type, arbitrary data, and unexpanded children; `resolve`
expands procedure-valued types and explicit fragments into a forest of element
records and opaque leaves. HTML conventions do not participate in this core.

[`ui.sld`](src/snail-scheme/ui.sld) stores model/update/view application values.
`dispatch` produces a new application through its reducer. [`html.sld`](src/snail-scheme/html.sld)
interprets trees as HTML and builds a matching action table. [`ui-server.sld`](src/snail-scheme/ui-server.sld)
owns the current application in a local Chibi server, preparing a complete page
before publishing a transition. These modules are separate from the compiler.

[`examples/react.scm`](examples/react.scm) prints generic document and GUI trees.
[`examples/ui.scm`](examples/ui.scm) renders one view as a static workbook or an
interactive HTML page. [Tree semantics](doc/react.md) and the [UI guide](doc/ui.md)
separate implemented behavior from the proposed browser/WASM host. Their Scheme
tests join the existing Chibi suite; [`scripts/test-ui`](scripts/test-ui) exercises
the real HTTP host, including stale actions and failed transitions.

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
`string-contains`, `collect-garbage`, and `gc-statistics` operations. This keeps
benchmark-specific runtime measurements separate from the standard libraries.

## Emitting WebAssembly

[`wasm.sld`](src/snail-scheme/wasm.sld) takes a library graph of resolved IR and
writes folded WAT. Its analysis records binding identity, assignment, lambda
captures, and initialization. It does not build MIR, bytecode, a managed operand
stack, or LLVM objects. Traversing the IR directly keeps conditionals and calls
visible in the generated code.

Each lambda has a fixed worker and a generic closure adapter. Known immutable
fixed callees pass arguments directly; unknown calls use a GC argument array.
Wasm tail-call instructions implement proper tail calls. Captures known to be
initialized and immutable travel by value; mutable or early captures use cells.
Recursive initialization preserves unreadable cells until each initializer
finishes. Single/multiple-value contexts are checked explicitly.

[`runtime/wasmgc.wat`](runtime/wasmgc.wat) defines the value representations and
checked primitives. Small integers are immediate `i31ref`; larger integers and
floats are boxes. Other values use structs and arrays. Type equivalence is
structural, so atom and text categories carry explicit tags. The engine owns
GC and stack roots. `apply` and `call-with-values` stay in Wasm for tail calls.

[`runtime/awi.wat`](runtime/awi.wat) exposes separately named scalar functions
for Rust: owned root handles, construction, extraction, and synchronous Scheme
callbacks. A reference table retains values; a free list reuses released slots.
The [`snail-awi` SDK](awi/src/lib.rs) expresses that ownership through `Root`:
clone retains, drop releases, return transfers. Raw handles are unsafe and bound
to their instance. The [`snail-abi` macro](abi/src/lib.rs) emits scalar export
wrappers; it does not infer Scheme types or hide conversions.

[`runtime/src/lib.rs`](runtime/src/lib.rs) implements Rust services: ports,
printing, numeric text conversion, substring search, Unicode classification,
process arguments, clocks, traces, and diagnostics.
[`host.rs`](runtime/src/host.rs) owns port data and UTF-8 stream handling.
Rust-owned external resources need explicit close. The additional JS
[`host.mjs`](runtime/host.mjs) registers WasmGC wrappers with
`FinalizationRegistry` for eventual resource cleanup. It is browser-compatible;
[`run-wasi.mjs`](scripts/run-wasi.mjs) supplies the Node WASIp1 runner.

[`examples/extension`](examples/extension/README.md) demonstrates Rust retaining
Scheme values, calling Scheme callbacks, and returning rooted values. The driver
puts runtime and extension dependencies in one generated Cargo cdylib, sharing
one linear memory, then links it with the Scheme module. This avoids merging
WASI imports whose pointers address different memories.

## Continuations and native translation

The production Wasm backend currently rejects `call/cc`. Single-shot, delimited
continuations are future work; multi-shot continuations are not a goal. Rust
callbacks work, but suspension and cancellation across Rust frames need an
explicit lifetime and unwinding contract. [AWI](doc/rust-interop.md) separates
implemented ownership from this planned support.

The [bounded Wasm-to-LLVM experiment](experiments/wasm-llvm/README.md) is a
separate executor, independent of Scheme IR. It lowers references to native
pointers and uses BDWGC. It does not yet translate full linked Rust programs.
Wastrel is a useful performance reference; its tested revision lacks stack
switching. `--native` invokes an explicitly configured external translator.
Both native and JavaScript hosts can implement the same finalization import.

## Tests and measurements

Scheme unit tests live in each module's final `Tests` section with one
conditional `test-<module>` export. `make test` enables the Chibi `snail-tests`
feature and invokes [`tests/snail-scheme/test.scm`](tests/snail-scheme/test.scm).
The compiler advertises `snail-scheme`, not its host's test features, so its own
sources compile without importing host-only test modules.

Rust unit tests remain in implementation modules. `scripts/test-backend`
executes linked Wasm semantic and diagnostic fixtures; `scripts/test-cli`
checks modes, traces, publication, arguments, extension linking, callbacks, and
root ownership. Native adapter checks require `SNAIL_WASM_NATIVE` and fail
clearly if none is configured; they are not counted as native passes.

[`benchmarks/`](benchmarks/README.md) contains frozen CPU, memory, IO, and GC
workloads plus historical measurement tools. CPU uses redundant recursive
Fibonacci with an independent oracle; memory uses a sieve; IO searches a frozen
corpus; GC builds cyclic trees. Historical stack/LLVM ablation tools and
reports describe their original backend. The GC workload's forced-collection
counters need engine instrumentation on WasmGC, which does not expose them.
Record execution time separately from compilation and startup, verify answers,
and retain raw samples and Chez/Chibi ratios when comparing backends.

## The actor platform

[`compiler.sld`](src/snail-scheme/compiler.sld) builds an actor facade from the
entry library's resolved exports and the codec. This preserves renamed binding
identity and dependency initialization. [`wasm.sld`](src/snail-scheme/wasm.sld)
emits scalar AWI wrappers; the driver's `--actor` entry initializes the library
once without invoking a Scheme main loop.

[`actor-wire.sld`](src/snail-scheme/actor-wire.sld) reads calls with the existing
reader and validates a limited portable datum subset. It never evaluates input.
[`actor-instance.mjs`](runtime/actor-instance.mjs) owns WASI initialization and
the AWI roots used during invocation. [`actor-worker.mjs`](runtime/actor-worker.mjs)
keeps that instance in one subprocess. [`actors.mjs`](runtime/actors.mjs)
separates worker lifetime from connection-owned pending calls. A fatal call
discards its worker; siblings remain usable. `scripts/test-actors` executes the
compiled artifact and checks isolation, root lifetimes, and shutdown behavior.
The [counter example](examples/actors/README.md) is runnable now; browser hosting,
typed record codecs, Scheme suspension, and GC policy controls remain future work.

[Why Snail-Scheme?](doc/why-snail-scheme.md) defines the actor, connection, and
artifact model. The [three tutorial projects](doc/tutorials/README.md) specify
game frame isolates, distributed chat, and GPU tensor training as integration
goals. [Reader generation](doc/generate-library.md) and
[staged programs](doc/staged-programs.md) remain planned features.
