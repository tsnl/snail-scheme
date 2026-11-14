# Compiler architecture

The compiler has four main phases: expand, check, prepare, and emit.
Reading supplies located syntax. Preparation closes specialization and
cleanup requests and produces fixed concrete code.
Emission consumes that result without revisiting source semantics.

[Query-driven incremental compilation](incremental-compiler.md) proposes a common
query implementation, compiler performance improvements and simpler orchestration
for applications, generators and editor requests, with separate build and LSP
workspaces. That design remains under review;
the pass descriptions here document the implemented compiler.

```text
text ──read───▶ located syntax
     ──expand─▶ resolved program   unique names, declarations, field paths
     ──check──▶ typed program      types, rows, instances, exact-once ownership
     ──prepare▶ concrete code      functions, control and cleanup explicit
     ──emit───▶ WasmGC text ──assemble/link──▶ executable module
```

`Prepared` contains declarations, concrete function definitions, an optional
root entry, exports and host exposures. Every definition is function code;
there are no value getters, initializer functions or cached global values.

The compiler is written in Snail Scheme under `src/snail/shell/compiler/`.
Its host boundary consists of `(snail core base)`, `(snail core table)` and
`(snail core io)`.
[Chez](bootstrap.md) runs the source closure for stage zero; the normal
compiler is itself a linked Wasm program. Most passes thread state through
pure functions. The emitter uses a locally owned mutable `Module` to collect
Wasm declarations and intern types. Neither representation requires `Ref`.

Static builds compile the complete program and link Rust scalar services
into one module. Development builds compile individual libraries and link
them when loaded. The same checking and preparation contracts serve both.
Start with `examples/fibonacci.sld`, inspect its output with
`./scripts/snail-tool wat examples/fibonacci.sld`, then follow the passes
below.

## The passes

### Reading and expansion

`read.sld` turns text into atoms, identifiers and forms, each carrying a
`Loc`. The reader's token boundaries are also used by syntax highlighting.
It decodes generated-library syntax directly from bytes. The `compile`
effect carries either diagnostics or a typed request for a missing input;
`compiling` handles that boundary for each compiler entry.

`core.sld` defines `Type`, `Scheme`, class evidence, expressions, patterns,
declarations and the program tables shared by the passes. `expr-children`
is the common structural inventory; each analysis still decides which
children execute, bind names or start a new scope. Data fields contain a
name and type, with no mutable/immutable flag. Every source field has one
runtime slot.

`expand.sld` alone knows binding syntax. It loads libraries, resolves import
sets, expands hygienic `syntax-rules`, assigns unique names and converts
forms into expressions and declarations. Top-level names are discovered
before their bodies, allowing recursive and mutually recursive functions. Local bodies remain sequential. Typed `define` and bodyless `declare` share a header grammar here; `Fn` and `FnOnce` are built-in callable type formers.

Struct field paths remain unresolved only while the receiver type is
unknown. Once its nominal type is known, checking substitutes the record's
type arguments and resolves each label to a declared field. Each hop becomes
an ordinary accessor operation. Nested fields follow object references;
there is no inline-layout path to reconstruct. `set!` and `replace!` use the
same resolved field and differ in whether the old value is released or
returned.

Expansion generates constructors, field operations and requested derived
instances. Their bodies and evidence then go through ordinary checking.
No runtime top-level expression is admitted: a producer recipe gets an
explicit entry function, and a program starts at its root `main`.

### Named record construction

Resolution turns `new` into a constructor and a list of initializers in written
order. Each initializer carries its resolved slot and a fresh temporary name;
the slots form a complete permutation of the record's fields. The checker
supplies the instantiated field types before checking each value, so callbacks
and generic records retain contextual typing. It then erases named construction:
fields already in declaration order become an ordinary constructor call;
reordered fields become sequential typed bindings followed by that call.
Ownership, specialization and Wasm emission use their existing operations.
Chez performs the same ordering at macro expansion time, using private
constructor procedures and hygienic record descriptors, with no runtime keyword
lookup for construction.

### Types, effects and conversions

`check.sld` infers types and effect rows, solves class requirements and
records selected instance evidence at uses. Library checking is independent
of importers. Named functions state their parameter and result types;
polymorphic definitions state their quantifiers and requirements.

An effect row names operations a function may perform. Calls and callbacks
add row-inclusion obligations, which remain pending while a latent row is
unknown. The checker also defers escape cleanup and unused-effect decisions
until those rows have enough information. This avoids either closing a
callback row too early or granting effects absent from its implementation.
Finalizers contribute their effects at the scope or write that can release
the last owner.

Explicit `(Any value)` and `(downcast T boxed)` become `BoxAny` and
`Downcast` terms. Packaging preserves type identity; extraction returns `Some`
only for the requested type, and `None` on mismatch. Neither inserts conversions
at unrelated boundaries or performs an effect.
Expansion rejects top-level nonfunctions. Local expressions retain their
ordinary inference and effect checking.

### Ownership and lifetimes

`capabilities.sld` determines whether a type is linear and how it is dropped. Every stored field participates. A record or enum with a linear
member is linear, regardless of its mutability. A `Drop` instance also makes a type linear. A generic parameter is linear unless
its contract requires `Copy`.

These questions are asked of a few types throughout a program, and each
answer searches the type's declarations. No type variable reaches the fields
of a declaration without parameters, so its answers do not depend on the
`Copy` variables or requirements in scope. When expansion has every type, the
program records each such declaration's facts: whether it is linear, whether
it is counted, and what dropping it performs. The queries read them; adding a
type to the program forgets them.

`Rc T` is the sole owning exception: it can share a linear `T` without
becoming linear. `WeakRc T` does not own the payload. Shared aggregates that
contain counted owners retain and release those members recursively.
Lifecycle plans retain the selected finalizer and its effect obligations
through specialization.

`ownership.sld` checks exact-once consumption along each returning path.
Alternatives must agree about the owners they consume. Matching a linear
aggregate transfers its fields; observing an unrestricted field does not
consume the receiver. A mutable slot may exchange owners, but cannot lose a
linear value. There is no borrow type, loan table, frozen-owner state or
borrow checker.

`Fn` captures unrestricted values and can be shared. `FnOnce` moves its
captures into either execution or cancellation. A saved resumption is a
`FnOnce` and may be stored in a linear aggregate or owned through `Rc`.
Calling a reusable closure does not grant permission to consume its captures.

`reference-counting.sld` then makes shared ownership explicit in concrete code. Reads
that create counted owners retain them; scope exit, overwritten slots and
abandoned branches release them. The pass distinguishes an observed receiver
from a transferred argument. It keeps a local's owner until its lexical
scope ends, so replacing one alias does not prematurely finalize another.
The Wasm collector manages memory reachability; these operations determine
resource lifetime and finalizer order.

The pass carries pending releases through the result positions of the original
expression tree. A nested binding prepends its owner; branches inherit the same
pending releases, and pattern bindings add theirs. Each result is secured before
these owners are released. An ordinary tail call evaluates its callee and arguments
first, releases the caller's owners, then transfers. Operands and nested functions
start their own release contexts; a handler keeps its caller's cleanup outside its
evidence scope. There is no separate walk over a lowered suffix for every enclosing
binding, and no source-level lifetime or borrow analysis.

### Specialization and preparation

`specialize.sld` owns one registry and worklist for concrete source functions
and generated cleanup glue. It reserves an identity before expanding its
body, which permits recursion. Specialization keys contain types and chosen
class evidence, not runtime handler identities. Cache hits do not spend the
finite specialization budget again.

`prepare.sld` closes each newly discovered batch before inspecting its
original concrete bodies. It folds constants, checks control restrictions,
inserts reference counts, names yield points, and builds cancellation
code. Cleanup can request more definitions; those form the next batch.
An old definition's body and call contract do not change while another batch
is being checked.

Control lowering uses a subset of the same expression language, not a
separate CPS language. A call that may yield stays in tail position or is
named by a `let`; operands that execute before it are named first. The
backend can therefore test for a pending yield before executing the rest
of the expression. `with-cleanup` carries ordered cancellation code for that
suspended scope; its second operand is code, not an evaluated argument.
A one-shot closure carries the cleanup for captures not
transferred into its body.

Cleanup uses one rewriting traversal of each body. It requests a concrete `Drop`
reference when it encounters an owned capture and builds the cleanup code
immediately. The specialization registry reserves the name and signature;
later batches build the requested body. Branches share the same initial
lexical scope while threading that registry, so requests deduplicate without
mixing ownership between paths. There is no preliminary type collection or
second traversal to resolve missing cleanup entries.

Some execution boundaries cannot propagate a yield: raw Wasm loops used by
sequence generators, arbitrary `unsafe-total` thunks, or work closed over
handlers whose delimiters may already have returned. Preparation inspects
concrete callees under the appropriate context and rejects unsupported
control escape. These checks use the original bodies, before lowering has
hidden their structure.

### WasmGC emission

`wasm.sld` selects one representation per concrete type. Numeric primitives
and booleans are Wasm scalars. A record is always a GC struct reference;
its field is one scalar or reference slot. An enum has a tagged base and
case subtypes. A vector is an exact-sized GC array. Only vectors with counted
elements add a holder: an ownership header and an immutable reference to that
array. Its length comes from the array; there is no capacity or replaceable
storage. There is no inline record flattening or reconstruction on field writes.

Completed source references are non-null. Internal Wasm storage and signatures
admit null so uninitialized slots and suspended results need no fabricated
source value. A control return leaves zero or null; its caller checks the yield
record before reading, retaining or releasing the result. Tail calls forward
that outcome directly. Normal construction and initialization establish when
a slot contains a source value. Host handovers retain their non-null contracts
except for the explicit nullable `Option Any` encoding, and dynamic type tests
still reject null. Linked modules must use the same internal calling convention.

A shared object that contains counted ownership has an owner header and a
destructor. Copying its reference retains that owner; the final release
releases its fields. Linear objects have one statically checked owner. A
pure replacement of a linear record may reuse it; a replacement of a shared
record creates a shallow copy. A mutable update publishes the incoming
field before releasing the old one, so a reentrant finalizer sees the new
state. Vector copies snapshot incoming owners before replacing destination
slots, including overlapping ranges, then release displaced owners. Counted
vector destructors visit only the live prefix. Strings remain character arrays;
conversions copy storage, and host byte staging copies only a vector's live prefix.

An `Rc` control cell owns its payload and selected finalizer. The last
strong release makes the payload unavailable before running that finalizer.
A weak upgrade either takes a new strong reference or reports that the
payload has gone. Cleanup must not retain the managed wrapper whose payload
it releases. Strong cycles need explicit breaking or weak edges; WasmGC
reachability collection cannot supply deterministic finalization for them.

The emitter interns concrete Wasm types before traversing their fields,
allowing recursive object graphs. Finite budgets diagnose expanding type or
specialization families instead of exhausting the host. Ordinary recursive
nominal types reuse their existing type entry.

The `cache` and `lru-cache` primitives require a closed, empty callback effect row.
The checker enforces this at final inferred types before specialization erases
ordinary effects, including when a primitive is used as a function value.
`unsafe-effectful-cache` and `unsafe-effectful-lru-cache` instead preserve the
callback's effect row. All four preserve its parameter and result types.
Preparation checks concrete key and result types for trivial cleanup and rejects
suspending callbacks. The Wasm backend builds an ordinary closure capturing its
callback and a private typed hash table; no module globals or new ownership
representation are involved. Its destructor releases the callback through the
existing closure machinery. The Chez adapter implements the same wrapper and key
semantics. See [cached functions](terms.md#cached-functions).

### Effects, control and frames

Every compiled function receives `$ev`, the evidence for handlers in scope.
An ordinary operation searches that chain and calls its implementation
outside the matching handler. Latent effects get forwarding evidence from
the performer. Handler identity is never a specialization key.

A control operation sets a yield record. As execution returns through named
yield points, the remainder of each scope becomes a frame holding resume and
cancel entry points, evidence, and one environment. Its captures include both
the continuation's reads and cleanup-only owners that a `Never` continuation
does not mention. Each owner moves into the frame once; execution and cancellation
consume the same credits on mutually exclusive paths. There is no backup
cancellation closure or extra retain/release pair for its captures.
The matching handler receives
a one-shot resumption. Calling it executes the frames from inside out;
dropping it runs their cleanup without executing their continuation code.
A handled scope saved among those frames preserves its delimiter.
Both paths detach the frames before calling user code. Cancellation uses the
frame's renewed evidence and preserves cleanup order; evidence stays owned
until the chosen entry finishes. An abort that cannot resume runs cleanup
directly, without allocating a frame or cleanup closure.

Resumption creates a fresh handler activation whose outside context is the
caller of `resume`. A memoized renewal walks parent and forwarding-origin
edges, then updates compiler-owned frame evidence and nested delimiters to
use the corresponding new identities. Its map owns old and fresh nodes
until all slots are consistent. Existing source closures and independently
owned resumptions retain their original contexts.

`inherit-handlers` captures an explicit context for later invocation *and
cancellation*. Ordinary evidence copies share their implementation closures;
forwarding copies rebuild closures over the renewed origin. Nested handled
frames execute or cancel their already renewed continuation without activating
it again. The invariants beside these helpers are part of their contract.

This is ordinary calls and explicit frames, not stack switching. V8 and
Wasmtime execute the same linked code; no JavaScript continuation mechanism
is required. `call/cc`, `dynamic-wind` and multishot continuation copying are
not language features.

## Separate compilation

The unit of compilation is a library (`source->modules` in
`src/snail/shell/compiler.sld`). In its module:

- each monomorphic definition is exported under its global name, as in
  `snail.core.base:map`;
- each generic function the library uses is copied in,
  specialized at the library's own types, as C++ instantiates a template in
  every translation unit that uses it;
- each monomorphic definition of another library is imported from that
  library's module;
- handlers travel as evidence, so no handler crosses a module boundary as a
  global; the one global modules share is the yield record of control
  operations, which a fixed module, `snail.core.control`, declares and exports.
  A build links it first when the program has control effects, and every
  module that tests or sets the record imports it, so a yield crosses
  modules as it crosses functions.

The checker settles each library's types before it checks the libraries
that import it, so a definition's type comes from its own library and not
from how an importer happens to use it.

Every invocation expands current sources, checks every library, specializes
and emits every reachable function again. There is no compiler Session,
interface fingerprint, invalidation graph or retained checked-code/Wasm cache.
The development loop rebuilds all configured targets and runs their producers
on each attempt. Content-addressed output files still let the browser decide
which module instances must be relinked.

## Linking

A module imports each function of another library by the library's name,
and the loader (`host/browser/load.mjs`) instantiates the runtime, then the
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

Snail Scheme types are checked at compile time, each library against its
imports. Every rebuild checks and emits the complete dependency closure. The
engine also checks the WebAssembly type of every import. A value crossing as
`Any` keeps its nominal type identity for explicit `downcast` checks.

Replacing a library's module means linking it and every module after it
in program order again (`relinkProgram` in `load.mjs`); the modules before
it cannot import from it. That
costs the instantiation of a few modules, and keeps debug code free of the
indirection that a table of mutable globals, like ELF's global offset
table, would add to every call across libraries.

### Linking by hand

The engine uses `(snail shell wasm)` to link a program from its manifest.
`compile-bytes` compiles a module, `module-imports` lists its imports, and
`link-module` accepts one explicit `Provider` per import in order. A provider
is an instance's export, a host service, a constant function, or a function
that fails if called. Missing or incompatible providers return `LinkFailed`.
Linking runs `_initialize` when present; the engine starts `main` separately.

`module-export` returns an untyped `Funcref`. `unsafe-cast` wraps it in an `Fn`
closure at the requested type, passing the caller's effect evidence. The Wasm
cast checks representation, not Snail Scheme nominal identity: the caller
must establish that contract. `run-export` calls a scalar export by name.

`loading-program` identifies the loader. `bind-runtime` selects the loaded
program's runtime for staging bytes and reporting errors without changing the
loader's identity. The engine carries library providers in a local list; no
second host registry or plugin namespace participates in linking.

`tests/programs/wasm-linking.sld` checks provider selection and failures.
`wasm-instance-identity.sld` verifies that existing imports keep their original
provider when a new link uses another instance, and that linking consumers
does not initialize their providers again. Both run on Node and Wasmtime;
the identity test also runs in Chromium.

### Hosts

The host compiles bytes, lists imports, binds explicit providers and finds
exports. Node and Wasmtime install these operations for the engine. The browser
adapter also implements them and is exercised by the Chromium fixture; normal
browser applications still use the JavaScript manifest loader. Resource fetching
and scheduling remain explicit responsibilities of the engine or browser host.

Every import module a host provides is named for the runtime interface it
implements, `snail.runtime.…` (#566): `snail.runtime.link` and
`snail.runtime.resource` on every host,
`snail.runtime.wasm`, `snail.runtime.native.socket`,
`snail.runtime.native.process`, `snail.runtime.native.files` and
`snail.runtime.native.develop` on Node,
and `snail.runtime.browser.screen`, `.events`, `.storage`, `.dom` and
`.fetch` on the page. A `(snail runtime …)` library declares one of these
interfaces as externs, and nothing else, so it has no items and emits no
module: each of its importers imports from the host itself
(`emit-libraries` in `(snail shell compiler)`).
The Rust support module, built from `crates/snail-core-support`, is
`snail.core.support`, and the compiler's control module
`snail.core.control`. A module linked under a `(snail runtime …)` name, or
`(snail core support)`, would have one of the hosts' names as its module
key, and the program's modules would import it in place of the host's
interface, so a loader refuses one, at
startup and when the program loads one (`hostProvided` in `load.mjs`,
`host_provided` in `crates/snail/src/modules.rs`).

## Compiler inputs

Each compiler invocation takes library directories, the current generated-library
provider, and an `Inputs` value supplied by the build. The provider receives each
producer with the libraries loading when it was reached:

```scheme
(record Generated ((text String) (bytes Bytes)))
(record Inputs ((artifacts (Table ArtifactFiles)) (generated (Table Generated))))
```

`artifacts` maps target names to ordered file snapshots, each a
`(List (Pair String Bytes))`. The native builder establishes
unique, canonical relative paths sorted by path, with bytes loaded from one
completed immutable output. Artifact expansion performs only memory lookups;
it has no filesystem capability. Inputs belong to the current invocation.
`(no-inputs)` constructs an empty input set.

`generated` maps a producer's key to what it wrote. The key hashes the
producer's text, `producer-text` in `(snail shell compiler inputs)`: the
library directories its imports resolve in, then its program. One table can
serve every target of a build, and two targets with different directories may
resolve the same recipe's imports to different libraries, so the directories
belong to the producer. The entry keeps that text beside the bytes and a
lookup compares it, so a collision of keys is a miss, never another
producer's output. The expander looks a producer up there first; only a miss
reaches the provider, which prints the producer into scratch under the same
key and requests it. The producer names its recipe after its imports,
`(recipe "lib/sample/blob.sld")`, and a path its own forms write, as a
`link-file` in the recipe's expression, resolves against that file rather
than the printed copy (`written-in` in `expand.sld`), so a recipe links files
beside itself wherever its producer is printed. The recipe's path is part of
the producer's text, and so of its key, since the files it links depend on
it. The producer computes the recipe's
expression in a task, as `(write-generated-library (lambda () EXPR))`, so
the expression may read what the recipe links with `read-resource`. The project builder reads a printed producer back
(`printed-producer-text`), checks that it has the key it was printed under,
and adds the output it wrote (`supply-generated`).

The planner owns target lookup, browser-kind checking, ordering and cycle
detection; the native builder runs the phases it hands out. A missing input
records a typed request and aborts the invocation. The Chez driver services
the request after the compiler stack has unwound; the native builder, whose
compiles the plan has already supplied, never does.

Each build expands current declarations and requests only their current inputs.
Removing an artifact invocation therefore removes its dependency. Every input
comes from the supplied snapshot; no lookup rereads a backing file. A missing
input fails that build.

Artifact files carry canonical paths, byte lengths and content hashes. The
build supplies their current bytes before compilation, and successful output
records which resources it links. Failed builds publish no replacement generation.

Generated syntax is obtained before expanding its library.
The native project builder runs each producer once per build, as a phase of its
plan, and its output serves every later compile of that build. Persistent
producer caching remains separate work.

A producer is compiled as a program of its own while the library it generates
is still loading, so the expander's stack of loading libraries crosses into
that compile. `generated-syntax` prints it as the producer's first form,
innermost first, and `expand-program` starts a program that begins with it
with those libraries loading:

```scheme
(generating "sample.knot")
(import (snail core base) (snail shell syntax) (sample knot-helper) ...)
```

A producer that imports, along any chain, the library it generates is then an
import cycle, `library import cycle through sample.knot`, rather than producers
nesting without end; `tests/programs/error-generated-cycle.sld` is that case.
The producer's key leaves the `generating` line out, since what it writes does
not depend on the chain that reached it. The Chez driver also
refuses a producer requested while it is being built, a backstop should the
stack ever miss a cycle.

### Missing inputs and retry

The compiler cannot start a producer or build another project target. A pass
that needs an input it was not supplied performs `need`, an operation of the
`compile` effect in `(snail shell compiler read)`, with its `CompilerRequest`.
The operation answers `Never`, so nothing after it runs and its yields save no
frames. Each signature on the way from the request to an entry point names
`compile`, and each entry point handles it with `compiling`, which turns the
compile into a `Result`, here `(Err (Requested request))`, as it does a
source error into `(Err (Failed diagnostics))`. Artifact expansion and request
signaling have no filesystem effects; library loading and generated-source IO
still do.

Discovery records artifact uses instead of asking for their files. The plan
has already supplied every producer's output; reaching a missing one is an
internal error. Discovery therefore cannot request inputs and needs no
separate request handler. Source diagnostics propagate through `compile` to
the project builder's handler.

Standalone source builds service generated-library requests and reject artifact
requests with their source location: an artifact needs a project build. The
command-line driver, `(snail shell compiler driver)`, writes its request to
`request.datum` in the compile's generated directory, then exits with status 1.
`(snail shell compiler inputs)` owns this grammar:

```scheme
(generate "123456")
(artifact "client" "server/main.sld" 12 8)
```

Each attempt deletes the preceding request before starting the compiler. Only
exit status 1 permits a request. A request that cannot be written is an
ordinary failure, status 1 with a diagnostic naming the file and no request
left behind; any other exit or signal cannot fulfill work from a leftover
file. Success with a pending
request and a request already answered are errors. Scratch directories are
created exclusively, so stale files cannot become inputs. Stderr carries only
diagnostics. Standalone builds have no artifact resolver or reply accumulation.

The project builder, `(snail shell project build)`, calls the compiler in its
own process and handles `compile` around each compile (`compiled`): a `fail`
stops the build with its diagnostics, and a request is an internal error,
since the builder plans the build first, so a request names an input the plan
missed. No request file is written or parsed, and nothing traps.

The builder supplies each completed target's canonical file inventory
(`supply-artifact`) before the first phase that embeds it, and each producer's
output (`supply-generated`) once the producer has run. Each reads the bytes
once and returns new immutable inputs; the preceding inputs remain usable.

One `Inputs` value serves every phase of a build, and is passed to each
compile and to `refine-plan`. It belongs to that build attempt. Applications
embed the bytes and need
no runtime file access.

### Linked files

A linked file's bytes are an input of the compile, as their digest: the
module imports its handle under that name. Each build binds the current linked
files during expansion. A missing file fails with the library and path;
changed bytes bind a new digest. Every build compiles all libraries and
places every linked file as an
object of the build's store, `store/sha256/DIGEST` beside a linked program
or the store a project's development builds share, checking that the bytes
it copies have the digest the compile read; a file edited during the build
fails it, and the next build compiles against the new bytes. Modules and
objects are named for their contents, so a generation's digest takes only
their names, and the browser reload client sees an edited file as a changed
module, from which it relinks. The bytes under such a name never change, so
the development server lets a browser cache them for good, and the page's
loader keeps the bytes it has read, by digest, across relinks.

## The resident builder

`snail dev` builds with `snail resident PROJECT`, the command line's Snail
program in a child process ("The resident builder" in `bootstrap/cli.sld`). The
service writes it one JSON request a line and reads one reply a line: a
`build` answers the project's description, a candidate with how long the
build took and each target's generation, digest, how many of its modules it
compiled and the digest of each file but its modules, which the reload
client compares, and any diagnostics; the resident holds the candidate until a `publish` or a
`discard` names it. The resident holds only its current job and unpublished
candidate; each attempt owns its plan and inputs. Every module is compiled
and assembled anew. Publishing installs the completed candidate atomically;
a failed or discarded attempt leaves the previously accepted generation
available.

## Supporting modules

| Path | Responsibility |
| --- | --- |
| `src/snail/shell/compiler/driver.sld`, `bootstrap/compile.sld` | Typed source invocation shared by both hosts: a compile that fails, or that needs an input after publishing its request, exits with status 1. `bootstrap/compile.sld` is the compiled compiler, an ordinary program. |
| `host/chez/load.scm` | Chez's unwind boundary, which turns a failure into the same status. |
| `crates/snail/` | `build/snail`, a native executable embedding wasmtime, which runs programs that need only WASI, linked files and module loading by `run-snail.mjs`'s protocol, the compiled compiler among them, when `SNAIL_ENGINE=wasmtime`; it precompiles the compiler to a `.cwasm`. See [the bootstrap](bootstrap.md#the-native-executable). |
| `host/chez/snail/stage0/build.sld` | Bootstrap, standalone generated libraries, tool builds and the native assembler/linker entry point. Each compile has private scratch; rebuilding shared tools holds `build/lock`. |
| `host/chez/snail/stage0/process.sls` | Synchronous tool capture through private output files and a constant shell script with positional arguments. The parent reaps before reading or deleting files; stdin is EOF. The host boundary uses Chez process and file primitives. |
| `crates/snail-core-support/` | Rust scalar services: math, Unicode, float text, console and file IO, directory and path operations, the monotonic clock, panics. External resources use explicit handles; managed references remain engine-traced. Its `assembler` feature builds the toolchain's runtime, which tools written in Snail Scheme link (`build-toolchain-tool`), with in-process assembly and static linking for `(snail shell assembler)`, shared by the native executable. |
| `host/native/run-snail.mjs` | Node/WASI program execution, the compiled compiler's included, on Node's main thread, plus module loading; it drives the program's task scheduler through `host/browser/tasks.mjs`, as the page does. A trap is status 2 and a WASI exit its own, as on wasmtime. |
| `src/`, `host/chez/` | Typed language libraries and the explicit Chez adapters. `host/chez/load.scm` permits only the compiler's source closure and stage-zero tools. |

Running project build plans and publication belong to the [project builder](projects.md),
watching and editor services to the [development toolchain](toolchain.md), and
task scheduling and resource ownership to the [runtime](../runtimes/index.md).

## Following and checking a change

`make test` exercises emitted Wasm; `make test-chez` runs the compiler source
on Chez. `make bootstrap` rebuilds from Chez alone and compares the compiled
compiler's successive Wasm stages. Keep both hosts working: differences in
integer overflow, table iteration or evaluation order must not change behavior.
Backend changes need execution tests, not only successful compilation.
`make check` checks formatting; `mdbook build` builds the book.
The [getting-started guide](https://github.com/tsnl/snail-scheme/blob/main/doc/getting-started.md)
lists pinned tools and the Rust/browser checks.
