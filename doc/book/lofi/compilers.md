# Compiler architecture

The compiler is a pipeline of five passes. Each pass consumes the previous
pass's output and nothing earlier:

```text
text ──read──▶ located syntax
     ──expand─▶ core program      unique names, resolved types, entity tables
     ──check──▶ typed program     every expression typed, instances chosen
     ──mono───▶ monomorphic program
     ──wasm───▶ WasmGC text ──assemble──▶ module, linked with the Rust runtime
```

Static debug and release builds compile the whole program and merge the Rust
services into one module; release increases optimization. Development builds
compile one library per module and assemble with the `wat` crate in process.

Read [`examples/fibonacci.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/fibonacci.sld), run
`./scripts/lofi-tool wat examples/fibonacci.sld` to see the WebAssembly it becomes, then
read the passes in order. The [language chapters](index.md) describe the
surface they implement.

## The passes

All compiler modules live in `src/lofi/compiler/` and are written in typed
Lofi: they import only `(lofi base)`, `(lofi table)` and `(lofi io)`, so the
compiler can compile itself. Chibi Scheme runs the same source through
`host/chibi/`, which implements those three libraries and erases the typed
forms. `(lofi table)` is an immutable table, so a pass threads its tables
as values where their scope is clear, such as the checker's local types,
and keeps state that grows over a whole pass in a `Ref`.

- **[`read.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/read.sld)** turns text into `Syntax`:
  atoms, identifiers and forms, each with a `Loc`. It is a recursive descent
  over a vector of characters; a line table recovers line and column only
  when a location is needed. It also decodes the bytes a `generate-library`
  producer writes, the encoding `(lofi syntax)` defines, straight into
  `Syntax`. `compile-error` preserves the source point and message at terminal
  failure; the resident caller resets and consumes this private diagnostic cell.
- **[`core.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/core.sld)** defines the data the later
  passes share: `Type` (with effect rows), `Scheme`, class `Evidence`, the
  `Expr` tree, `Pattern`s, declared entities (`DataType`, `Class`,
  `Instance`, `Effect`), the `Program`, the primitive table, TypeIds for
  wire cases and `Any` values from one FNV-1a hash, and the strongly
  connected components that the checker and the backend share. A `Program`
  is a value: the expander builds it in one cell, and the later passes read
  it without effects.
- **[`expand.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/expand.sld)** is the only pass that
  knows binding forms. It loads libraries, replacing each `include-bytes`
  with the byte vector literal of its file, resolves every identifier through
  environments, and runs `syntax-rules`. Hygiene is renaming: each identifier
  a template introduces gets a mark that is unique to the expansion and, when
  unbound, resolves in the macro's own environment. Top levels expand in two
  passes so definitions may refer to later ones; local bodies are
  sequential. Declarations become entities in the program tables, derived
  wire instances are generated as ordinary instance syntax, and expressions
  become core `Expr`s with unique names. Each library's build key, the text
  of its declarations with its imports' interfaces, lets a session replay
  it.
- **[`check.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/check.sld)** is Hindley-Milner inference
  with effect rows. Unannotated top-level definitions are checked in
  dependency order (core's `strong-components`). Each instantiation records its type
  arguments and an evidence hole per class constraint. While items are
  checked, constraints are only recorded; a group of functions quantifies
  the metavariables nothing else still mentions. Libraries are checked one
  at a time; when a library is checked, its literals default, and each
  class constraint is solved once, filling its hole. Rows unify as sets with open tails. Matches are checked
  with Maranget's usefulness algorithm. A function whose type forbids `mut`
  may mutate storage it allocates; once types are final, nothing it can
  reach from outside, its parameters, result or names it reads, may hold
  mutable storage.
- **[`capabilities.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/capabilities.sld)** establishes
  structural `Send` and `Sync` evidence from types and declared fields.
  The checker resolves these compiler-owned markers; user instances cannot
  override them. Ordinary arrows carry no proof about their captures.
- **[`handlers.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/handlers.sld)** checks that a handler's
  retained environment is reusable and satisfies `Send + Sync`. It follows
  closure aliases, named helpers and selected method evidence to their
  captures and globals, while keeping invocation arguments and fresh local
  storage separate. Unknown callback provenance is rejected.
- **[`mono.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/mono.sld)** starts from the program's
  statements and values and copies each reachable definition once per ground
  instantiation. A method reference becomes the instance method its evidence
  names, and definitions that only rename another, such as
  `(define + i64-add)`, are replaced by their target.
- **[`ownership.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/ownership.sld)** consumes affine
  locals once per path after specialization. Branches fork and intersect
  their live owners; a path drops a value when it has no remaining use.
  Only one-shot closures can own affine captures. Concrete records inherit
  their fields' grade; existing generic parameters remain unrestricted.
- **[`wasm.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/wasm.sld)** chooses representations and
  emits WebAssembly text. Scalars are Wasm numbers. An enum whose cases have
  no fields is an `i32`; other data are GC structs, and enum cases are final
  subtypes of a base holding the tag. Sequences are GC arrays. Functions are
  closures: a struct whose first field is a typed function reference, with
  captured variables in a subtype. Tail calls become `return_call`. Each
  effect has a global handler stack. Each GC type sits in the smallest
  recursion group it can, ordered by name, so modules that declare the same
  type declare the same group. Compiled one library at a time, a module
  exports its monomorphic definitions under their global names and imports
  other libraries' definitions. At the host boundary it
  stages final String and Bytes arguments and wraps exposed `(Option Any)`
  as a nullable opaque handover. Dynamic handler globals are exported so
  the runtime can restore each task's context across suspension.
- **[`session.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler/session.sld)** keeps the compiler
  running between builds: the expander replays libraries whose declarations
  and imports' interfaces are unchanged, and only libraries whose expansion
  changed are checked, specialized and emitted again. Cached emissions keep
  their monomorphic items so handler capture proofs can be rechecked against
  current helper bodies without regenerating unchanged Wasm text. Input
  generators and immutable artifact inputs are passed to each build; sessions
  retain only compilation evidence.
- **[`compiler.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/lofi/compiler.sld)** composes the passes, from a
  program's path to WebAssembly text, or to one module's text per library.

## Separate compilation

The unit of compilation is a library (`compile->modules` in
`src/lofi/compiler.sld`). In its module:

- each monomorphic definition is exported under its global name, as in
  `lofi.base:map`;
- each generic definition and alias the library uses is copied in,
  specialized at the library's own types, as C++ instantiates a template in
  every translation unit that uses it;
- each monomorphic definition of another library is imported from that
  library's module;
- each effect's stack of handlers is a global that the declaring library's
  module exports and the others import.

The checker settles each library's types before it checks the libraries
that import it, so a definition's type comes from its own library and not
from how an importer happens to use it.

A **session** (`src/lofi/compiler/session.sld`) compiles a program again
and again, as the development loop does, keeping everything in memory:

- The expander replays a library, adding what it added before, when its
  declarations read the same and its imports show the same interfaces.
- A library's **interface** is what importers depend on: its imports and
  exports, every declaration except the bodies of definitions whose
  signatures are monomorphic, and its imports' interfaces, since its
  generic code carries theirs into importers. It is hashed, as GHC uses
  interface hashes to avoid recompilation.
- Each library's checked items, type schemes and module text are kept
  under the expansion they came from. A build checks, specializes and
  emits only the libraries whose expansion changed.

Sessions retain compilation evidence, not a build's providers or files. The
[input boundary](#compiler-inputs) defines how current inputs validate reuse.

## Linking

A module imports each function of another library by the library's name,
and the loader (`src/app/load.mjs`) instantiates the runtime, then the
modules in program order, so every module comes after those it imports
from. Calls across libraries are direct calls to imported functions.

WebAssembly treats two GC types as the same only when their whole
recursion groups match. The backend therefore puts each type in the
smallest recursion group it can have: the strongly connected component of
the graph of references between types, ordered by name, with the groups it
refers to emitted first. Every module that uses a type declares the
identical group, and the engine's canonicalization makes them one type
across modules. A case of an enum without fields declares no type of its
own, since only the modules that build or match it would declare one.

Lofi types are checked at compile time, each library against the
interfaces it imports. Nothing checks them at load time: every module of a
link comes from one build of one session, which recompiles importers
whenever an interface changes. The engine still checks the WebAssembly
type of every import, and a value that crosses as `Any` keeps its own
check at `type-convert`.

Replacing a library's module means linking it and every module after it
in program order again (`relinkProgram` in `load.mjs`); the modules before
it cannot import from it. That
costs the instantiation of a few modules, and keeps debug code free of the
indirection that a table of mutable globals, like ELF's global offset
table, would add to every call across libraries.

### Loading modules at run time

`(lofi wasm)` is `dlopen` and `dlsym`. It loads a module from a file,
linked against the runtime, the program's own modules and the modules
loaded before it, by name. A function the module exports comes out as a
`Funcref`, and `unsafe-cast` makes it a function of the type the context expects:

```scheme
(let* ((cell (load-module "cell" "build/cell.wasm"))
       (run (ann (unsafe-cast (module-export cell "cell:run")) (-> I64 I64))))
  (run 41))
```

`unsafe-cast` is a primitive. It wraps the reference in a closure whose
code casts it to the WebAssembly type of a function of the expected type
and calls it. The cast is the only check: the engine traps when the
WebAssembly types differ, and nothing compares Lofi types, so the unsafe
assumption is visible where it is made. `tests/programs/wasm.sld` loads a
module it writes itself.

The Node runner provides the `wasm` effect for both builds. A statically
linked program exports nothing of its runtime, so what it loads can link
only against the host. Browser hosts do not provide it yet: loading is
synchronous, and a page reads files asynchronously.

## Compiler inputs

The compiler entry points and `build-session` take the current generated-library
provider and an `ArtifactInputs` value. `make-session` takes only library
directories; a retained session owns evidence, never a provider closure:

```scheme
(Table (List (Pair String Bytes)))
```

The table maps target names to ordered file snapshots. The native builder establishes
unique, canonical relative paths sorted by path, with bytes loaded from one
completed immutable output. Artifact expansion performs only memory lookups;
it has no filesystem capability. Inputs belong to the current invocation, not
the retained session. `no-artifacts` is an empty input table.

The project implementation owns target lookup, browser-kind checking,
serial traversal and cycle detection. A missing input records a typed request
and aborts the invocation. The native builder obtains the request only after
the compiler stack has unwound.

Each library's expansion records its direct requests and the exact file values
embedded. Ordinary source/import eligibility is checked before replaying those
requests, so an edited body can remove an obsolete dependency. A cache hit
still looks up every recorded input and compares paths and every byte using the
reader's byte comparison. A missing input fails the build; changed contents cause
fresh expansion. No lookup rereads a backing file.

An artifact-bearing expansion receives a fresh revision stamp from the
session's existing expansion counter. Replaying it preserves that stamp. Its compiled
key is constructed once with its source key and stamp; its interface also
includes the stamp, so changed bytes also
invalidate generic importers that embed specialized bodies. These stamps are
local to one session lineage, not persistent content identities. Failed builds
publish no replacement session. This keeps bundle bytes out of string keys
without trusting a content checksum.

Generated syntax is obtained before deciding whether to replay its library.
The native project builder uses the same target traversal while compiling
producer programs. Persistent producer caching remains separate work; current
producer output lasts only for its enclosing compile.

### Missing inputs and retry

The compiler cannot start a producer or build another project target. It records
one pending `CompilerRequest` in memory and exits immediately. Artifact expansion
and request signaling have no filesystem effects; library loading and
generated-source IO still do. The host consumes the request after the compiler
stack has unwound.

Standalone source builds service generated-library requests and reject artifact
requests with their source location: an artifact needs a project build. Chibi
and Node compiler entries publish the pending request in `request.datum` after
unwinding. `(lofi compiler inputs)` owns this grammar:

```scheme
(generate "123456")
(artifact "client" "server/main.sld" 12 8)
```

Each attempt deletes the preceding request before starting the compiler. Only
exit status 1 permits a request. Publication failures use status 2; any other
exit or signal cannot fulfill work from a leftover file. Success with a pending
request and a request already answered are errors. Scratch directories are
created exclusively, so stale files cannot become inputs. Stderr carries only
diagnostics. Standalone builds have no artifact resolver or reply accumulation.

The resident compiler returns the pending request in `CompilerFailure.request`;
no request file is written or parsed. Each invocation clears pending request and
diagnostic state before work. Trusted exits preserve the instance but return no
successor Session. Both cold project builds and `dev` use this boundary.

Only `scripts/project.mjs` resolves named browser targets, including during
producer compilation. It passes each completed target's canonical file inventory
to `addArtifact`, which reads the bytes once and returns an opaque immutable
input table. A failed read returns no replacement; the preceding table remains
usable. There is no artifact reply manifest or second parsing step.

Each logical compilation retains its table through retries and passes it to
`check`, `static` or `modules`. Nested producers own separate inputs and scratch while
sharing the builder's active/completed target traversal. These opaque values
belong to their originating compiler instance, like Sessions. Successful
Sessions retain only the per-library evidence already used for cache reuse.
Applications embed the bytes and need no runtime file access.

## Resident compiler boundary

`bootstrap/compiler.sld` exposes this compiler to a resident native caller.
`scripts/compiler.mjs` owns one Wasm instance and returns parsed project and
input-request records, static text, or modular text with a successor Session.
JavaScript retains Sessions and immutable artifact inputs as opaque `Any`
values; it cannot inspect them and must keep them with their originating compiler
instance. Each operation consumes its staged arguments
before doing work, and projected records become visible only on success.

Each native call starts with empty diagnostic storage. The trusted compiler's
code-1 diagnostic exits follow resource cleanup and allow another call with
the last successful Session. Arbitrary Wasm or imported-function traps retire
the instance. This distinction comes from the runtime exit path, not from
finding a familiar string or a diagnostic record. Failure to read diagnostic
storage is terminal too: the worker cannot reuse a retired compiler.
`compile-error` keeps its
`Loc` and message in a compiler-private cell before the existing terminal panic.
This explicitly unsafe bridge avoids adding an abort effect to every compiler
pass; it does not prove the mutation pure. The serial native caller resets the
request and diagnostic cells before entry, then takes and projects each after a
trusted exit, before compiling a producer. Reset/projection traps retire
the instance too. Module initialization precedes the first reset.

Native failures carry `{severity, message, source}`; `source` is null or
`{file, line, column}`. Lines and Unicode scalar columns start at one. IO and
producer-input requests have no source record; internal no-location sentinels
are unlocated. An artifact wrapper preserves a failing child's origin. Printed
producer programs report their actual scratch source, while decoded generated
syntax retains the recipe location already established by expansion. No source
mapping is invented. CLI panic text is unchanged, and the compiler still stops
at its first error. These operations are implemented and tested.

The resident `check` entry has no output filename. It expands, checks and
specializes one source, including concrete handler and ownership checks, then
discards the IR. It returns no emitted code or publishable candidate.

## Supporting modules

| Path | Responsibility |
| --- | --- |
| `src/lofi/compiler/driver.sld`, `bootstrap/compile.sld` | Typed source invocation shared by both hosts; compilation and post-exit request publication are separate entries. |
| `host/chibi/compile.scm`, `scripts/run-compiler.mjs` | Process unwind boundaries; publish missing-input requests only after trusted exit. |
| `host/chibi/lofi/build.sld`, `scripts/link.scm` | Bootstrap, standalone generated libraries, tool builds and Binaryen/runtime linking policy. Each compile has private scratch; rebuilding shared tools holds `build/lock`. |
| `host/chibi/lofi/process.sld` | Synchronous tool capture through private output files and a constant shell script with positional arguments. The parent reaps before reading or deleting files; stdin is EOF. This avoids Chibi 0.12 pipe-finalizer and sequential pipe-draining failures. |
| `src/runtime/` | Rust scalar services: math, Unicode, float text, console and file IO, panics. External resources use explicit handles; managed references remain engine-traced. |
| `src/assembler/`, `scripts/assemble.mjs` | The `wat` crate compiled to Wasm for in-process text assembly. Programs do not carry the assembler. |
| `scripts/run-lofi.mjs` | Node/WASI program execution, in a worker with a tuned GC heap, plus module loading and the task scheduler. JSPI stacks remain finite. |
| `lib/`, `host/chibi/lofi/` | The typed standard library and its separate stage-0 host implementations. Chibi never loads `lib/`. |

Project traversal and publication belong to the [project builder](projects.md),
watching and editor services to the [development toolchain](toolchain.md), and
suspension/resource ownership to the [runtime](../runtimes/index.md).

## Following and checking a change

`make test` exercises emitted Wasm; `make test-chibi` runs the compiler source
on Chibi. `make bootstrap` rebuilds from Chibi alone and compares the compiled
compiler's successive Wasm stages. Keep both hosts working: differences in
integer overflow, table iteration or evaluation order must not change behavior.
Backend changes need execution tests, not only successful compilation.
`make check` checks formatting; `mdbook build` builds the book.
The [getting-started guide](https://github.com/tsnl/snail-scheme/blob/main/doc/getting-started.md)
lists pinned tools and the Rust/browser checks.
