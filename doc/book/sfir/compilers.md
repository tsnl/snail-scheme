# Compilers as libraries

A library is data describing code. Compilation turns an assembled collection
of those values into a Wasm artifact. The compiler is an ordinary library
function: its caller supplies the libraries and an entry point. A command-line
compiler is one program that calls this function. Build scripts can separately
pass the emitted Wasm to a Wasm-to-native library and link its object with Rust
providers.

## Building a program

`compile` takes a map from library keys to `SfirLibrary` values and an `Entry`,
and returns a Wasm `Artifact`. It resolves imports, checks types, specializes
generic definitions, emits Wasm and runs Binaryen optimization. An entry identifies
an exported function. A missing dependency is an error; the compiler itself
does not search directories or invoke a language frontend.

```scheme
(def Entry
  (datatype ()
    (entry (library LibraryKey) (export Name))))

(let math (parse-library (read-source "demo/math.sfir")))
(let app (parse-library (read-source "demo/app.sfir")))
(let libraries
  (map-insert (map-insert base-libraries math-key math) app-key app))
(let artifact (compile libraries (entry app-key main-name)))
```

This build fragment assumes imported map and source operations, a supplied map `base-libraries`,
keys for `(demo math)` and `(demo app)`, and the name `main`. `parse-library` reads a
`define-library` description. A source driver additionally recognizes generation recipes and
collects dependencies. Source reads and artifact writes are explicit operations around compilation.
The implemented [SFIR compiler
service](https://github.com/tsnl/snail-scheme/blob/main/doc/sfir-compiler-service.md) spells parsing
as `(parse-library source-name source-text)` and returns an ordinary `CompilerResult SfirLibrary`;
its [syntax views](https://github.com/tsnl/snail-scheme/blob/main/doc/sfir-builder.md) allow
inspection and transformation before map insertion.

Libraries retain type information and polymorphic implementations so the
compiler can specialize calls across their boundaries. They are translation
units, but not machine object files with their implementations already erased.
Linking emitted code to foreign providers is a separate build or execution operation.

## Loading and running

The resulting artifact can be saved, transferred to another machine, or run
immediately. Loading it makes executable code available. Instantiating that
code creates state and runs initializers. Invoking an export calls a function
in that instance.

```scheme
(let code (load artifact))
(let first (instantiate code providers))
(let second (instantiate code providers))
(invoke-entry first arguments)
```

`first` and `second` have separate library state even though they share code.
Each library identity initializes once within an instance, after its
dependencies, with statements in source order. Aliases and re-exports do not
initialize it again. A failed initialization makes that instance unusable;
effects already performed are not rolled back.

Sharing state means explicitly sharing an instance or providing a shared
service. An implementation can reuse immutable code internally, but it cannot
silently turn two instantiations into one. Separate `load` calls have no implicit
shared-state semantics. The caller chooses a loader appropriate to the artifact;
there is no global file-extension registry.

`providers` supplies the foreign interfaces expected by the code. The execution
adapter checks export signatures and transports arguments and results according
to its ABI. `invoke-entry` denotes that adapter operation; it is not an unchecked
cast from an arbitrary runtime function to the caller's preferred type.

A source-running command can now be described in three lines. Here the entry,
search directories, providers and arguments are already supplied:

```scheme
(let libraries (collect-libraries entry search-paths))
(let instance (instantiate (load (compile libraries entry)) providers))
(invoke-entry instance arguments)
```

This offers an interpreter-like experience while compiling the source before
executing it. It does not require a separate SFIR interpreter implementation.

## Running a generator

A `generate-library` recipe has a body returning a `SfirLibrary`. To run it,
the driver packages that body as an exported function with the recipe's imports.
It obtains those dependencies, compiles the generator to Wasm, loads it, creates
an instance, and invokes the function.

```scheme
(let producer-code
  (load (compile producer-libraries producer-entry)))
(let producer (instantiate producer-code build-providers))
(let generated (invoke-generator producer inputs))
(let application-libraries (map-insert dependencies generated-key generated))
(let artifact (compile application-libraries application-entry))
```

`invoke-generator` is the adapter for a producer returning library data. If the
producer runs in a separate execution context, this operation transfers that
data through an explicit serialization or builder protocol and checks the
received structure. It does not export raw pointers into the producer's heap.
Generated imports still have to be supplied in `application-libraries`, just
as for a parsed library. The generated application's Wasm may run on a Wasm
engine or pass through the separate native build sequence; that choice does not
change the compiler API.

The recipe is a convenience supplied by the driver. A build program can instead
call a producer function already available in its own execution context. Neither
case requires a language-wide distinction between compile-time and runtime
bindings. One execution produces data used by a later execution.

## Dependencies and stages

A generator has two different dependency relationships. Its own imports must
be available to run it. Its result describes imports needed to compile the
generated program. These graphs may overlap, but an import in one does not
automatically become an import in the other.

Generators can themselves depend on generated libraries. Each chain must reach
source or executable code available without further generation. The driver
detects cycles in that preparation graph and reports the dependency chain;
recursively requesting the same unfinished generator cannot produce a result.
If a producer also emits auxiliary artifacts, it reports them through an
explicit build context or result protocol rather than hiding them in a cache.

A live closure or mutable reference belongs to the execution that created it.
Putting a function's syntax in a library describes a future closure; it does
not capture a live producer closure across executions. Cross-context services
need explicit handles and transport. Within one execution, ordinary function
calls and shared references keep their usual meanings.

## Other languages and macros

A future Scheme frontend could implement `scheme->sfir` as a function returning a
`SfirLibrary`. It performs macro expansion and semantic translation, preserving
source locations. Its output can import functions and types written directly
in SFIR. The common checker verifies their interaction, and the common optimizer
performs specialization and eliminates redundant checks. Lowering itself need
not perform those optimizations.

Scheme expansion may require transformer values and helper functions from
other Scheme libraries. The frontend defines how it obtains them before
producing SFIR. Compiling a module's ordinary functions does not by itself
preserve its macros for a later expansion. A reusable macro interface would
need to retain transformer code or data together with the binding information
and dependencies required by the expander. The SFIR library interface does not
prescribe that frontend-specific protocol. Scheme elaboration, macro staging and
self-hosting remain deferred; Chibi hosts the current compiler implementation.

## Compiler responsibilities

Preserve original source locations and established type facts through checking,
specialization and emission. Parsing establishes structure and local identities;
it does not infer types or optimize. Optimization acts on proved facts and keeps
runtime checks where those facts are unavailable.

Wasm is the compiler's output boundary, with mandatory Binaryen optimization.
The separate native library consumes Wasm and declared physical import/provider
ABIs, without source syntax, bindings or inference state. Ordinary Scheme build
scripts compose compilation, native lowering and linking directly. The current
native platform is x86-64 Linux; unsupported operations produce diagnostics.
The optional typed execution adapter retains semantic scalar tags such as Bool
and Char, which cannot be recovered from their common physical `i32` type.
One Rust runtime crate supplies both routes: Wasm engines trace managed values,
while native execution uses the in-house collector. Scalar filesystem services
share their implementation.

Performance comparisons use equivalent SFIR, Chez and Rust workloads with the
same inputs, algorithms and correctness checks. Reports separate compilation
from execution and instrumented measurements from clean timings. These are
implementation criteria; they do not add new language semantics.
