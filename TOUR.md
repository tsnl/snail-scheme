# A tour of Snail-Scheme

The compiler is Scheme, hosted by Chibi. WebAssembly is its portable output;
Rust provides host services and extensions through a named application Wasm
interface (AWI). Compiling the compiler sources does not switch the build host.

```text
ordinary Scheme build.scm (run by Chibi)
  -> compiler library: reader -> syntax parser -> expander -> library-grouped IR -> WAT
  -> build library: Cargo builds the reusable Rust Wasm runtime
  -> Binaryen: assemble, link and optimize -> portable .wasm
  -> build script chooses execution or further artifact generation
```

## Entering the compiler

[build.scm](build.scm) is an ordinary Scheme script. It imports
[`build.sld`](src/snail-scheme/build.sld), which provides `build-runtime`,
`link-wasm`, `build-wasm`, and `run-wasm`. The script owns arguments and control
flow; importing compiler libraries has no build or execution side effects.
`run-command` passes an argv list directly to Chibi's process API without a shell.
Build intermediates have private directories, and only completed Wasm artifacts
replace existing outputs. Failed builds report their retained directory; successful
builds clean up. Cargo tracks Rust dependencies and reuses the runtime.

[`compiler.sld`](src/snail-scheme/compiler.sld) exports
`source-file->wat-file`: source filename to unlinked WasmGC text. The loader
maps `(scheme ...)` to `bootstrap/scheme/`. Other imports search caller-provided
library directories in order, then `src/`; one search policy covers transitive
imports, and malformed first matches do not fall through.
The frontend does not launch processes. The Chibi-specific build module is a
host adapter; compiling it for self-hosted execution is future work.

[`trace.sld`](src/snail-scheme/trace.sld) and [`src/trace.rs`](src/trace.rs)
centralize always-on Chromium trace spans. `build/traces/` is the default;
`SNAIL_TRACE_DIR` overrides it. See [Tracing](doc/tracing.md).

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

[`src/runtime/wasmgc.wat`](src/runtime/wasmgc.wat) defines the value representations and
checked primitives. Small integers are immediate `i31ref`; larger integers and
floats are boxes. Other values use structs and arrays. Type equivalence is
structural, so atom and text categories carry explicit tags. The engine owns
GC and stack roots. `apply` and `call-with-values` stay in Wasm for tail calls.

[`src/runtime/awi.wat`](src/runtime/awi.wat) exposes separately named scalar functions
for Rust: owned root handles, construction, extraction, and synchronous Scheme
callbacks. A reference table retains values; a free list reuses released slots.
The [Rust AWI module](src/awi.rs) expresses that ownership through `Root`:
clone retains, drop releases, return transfers. Raw handles are unsafe and bound
to their instance. Rust uses ordinary `extern "C"` functions and explicit Wasm export names;
there is no procedural-macro crate or implicit argument conversion.

[`src/lib.rs`](src/lib.rs) implements Rust services: ports,
printing, numeric text conversion, substring search, Unicode classification,
process arguments, clocks, traces, and diagnostics.
[`host.rs`](src/host.rs) owns port data and UTF-8 stream handling.
Rust-owned external resources need explicit close. The additional JS
[`host.mjs`](src/runtime/host.mjs) registers WasmGC wrappers with
`FinalizationRegistry` for eventual resource cleanup. It is browser-compatible;
[`run-wasi.mjs`](scripts/run-wasi.mjs) supplies the Node WASIp1 runner.

[`src/interop_example.rs`](src/interop_example.rs) demonstrates Rust retaining
Scheme values, invoking callbacks, and returning rooted values. It is compiled
into the standard runtime; [its build script](examples/rust-interop/build.scm)
provides the Scheme name-to-Wasm-module declarations. All Rust code in a program
shares the runtime's one linear memory.

## Continuations and native translation

The production Wasm backend currently rejects `call/cc`. Single-shot, delimited
continuations are future work; multi-shot continuations are not a goal. Rust
callbacks work, but suspension and cancellation across Rust frames need an
explicit lifetime and unwinding contract. [AWI](doc/rust-interop.md) separates
implemented ownership from this planned support.

Native library integration is being developed separately. The intended executor
translates linked Wasm independently of Scheme IR, lowering references to native
pointers collected by BDWGC.
Both native and JavaScript hosts can implement the same finalization import.

## Tests and measurements

Scheme unit tests live in each module's final `Tests` section with one
conditional `test-<module>` export. `make test` enables the Chibi `snail-tests`
feature and invokes [`tests/snail-scheme/test.scm`](tests/snail-scheme/test.scm).
The compiler advertises `snail-scheme`, not its host's test features, so its own
sources compile without importing host-only test modules.

Rust unit tests remain in implementation modules. `scripts/test-backend`
executes linked Wasm semantic and diagnostic fixtures; `scripts/test-build`
checks library imports, traces, publication, literal arguments, Rust callbacks, and
root ownership. Native adapter checks require `SNAIL_WASM_NATIVE` and fail
clearly if none is configured; they are not counted as native passes.

[`benchmarks/`](benchmarks/README.md) contains CPU and allocation workloads.
CPU uses recursive Fibonacci with an independent oracle; memory uses a sieve.
Record execution time separately from compilation and startup, verify answers,
and retain raw samples and Chez/Chibi ratios when comparing backends. Retired
prototypes and measurements remain in Git history.

[`benchmarks/reproduce.py`](benchmarks/reproduce.py) rebuilds the native
Fibonacci comparison, checks answers, collects rotating samples, and renders
plots from saved JSON. [`benchmarks/r7rs.py`](benchmarks/r7rs.py) runs the pinned
upstream R7RS suite across Snail native, Chez, Guile, and Chibi. Preparation,
measurement, and reporting are separate; failed and unavailable cases stay in
the result matrix. Its small [Chez adapter](benchmarks/r7rs-chez.scm) supplies
monotonic timing alongside upstream's language compatibility prelude.
[`benchmarks/plots.py`](benchmarks/plots.py) draws sorted duration bars for both
runners, with a compact README comparison and one chart per suite workload.
[BENCHMARKS.md](BENCHMARKS.md) provides the commands and measurement scope.
