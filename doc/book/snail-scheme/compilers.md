# Compiler architecture

The compiler has four main phases: expand, check, prepare, and emit.
Reading supplies located syntax. Preparation closes specialization requests
and produces fixed concrete code.
Emission consumes that result without revisiting source semantics.

```text
text ──read───▶ located syntax
     ──expand─▶ resolved program   unique names, declarations, field paths
     ──check──▶ typed program      types, instances
     ──prepare▶ concrete code      suspensions known, yield points explicit
     ──emit───▶ WasmGC text ──assemble/link──▶ executable module
```

`Prepared` contains declarations, concrete function definitions, an optional
root entry, exports and host exposures. Every definition is function code.
A top-level value is one too: the expander wraps its initializer as
`(prim:cached-thunk (lambda () value))` and turns each read into a call, so
no later pass knows values exist. The backend emits that definition as a
function over two globals, a state and a slot: it runs the initializer on
the first call, panics if the initializer reads its own value, and answers
the slot afterwards. A value whose initializer is a literal needs no slot
and is the plain function that answers it.

The compiler is written in `snail-scheme` under `src/snail/shell/compiler/`.
Its host boundary consists of `(snail core base)`, `(snail core table)` and
`(snail core io)`.
[Chez](bootstrap.md) runs the source closure for stage zero; the normal
compiler is itself a linked Wasm program. Most passes thread state through
pure functions. The emitter uses a locally owned mutable `Module` to collect
Wasm declarations and intern types. Neither representation requires `Ref`.
A global or data segment that a module declares once, such as a string
literal's, comes from a function wrapped in `cache` and held
in a top-level value: its key is the module and the text that names the
item, so a second use skips the declaration. Those caches live as long as
the compiler process, and so does each module they were asked about.

Every build compiles the whole program to one module and links it with
the Rust scalar services, as stage 0 does the command line.
Start with `examples/fibonacci.sld`, inspect its output with
`./snail-scheme wat --target node examples/fibonacci.sld`, then follow the passes
below.

## The passes

### Reading and expansion

`read.sld` turns text into atoms, identifiers and forms, each carrying a
`Loc`. The reader's token boundaries are also used by syntax highlighting.
It decodes generated-library syntax directly from bytes. A pass stops a
compile by suspending to its prompt, `stopping`, with either diagnostics
or a typed request for a missing input; `compiling` is that boundary for
each compiler entry.

`core.sld` defines `Type`, `Scheme`, class evidence, expressions, patterns,
declarations and the program tables shared by the passes. `expr-children`
is the common structural inventory; each analysis still decides which
children execute, bind names or start a new scope. Data fields contain a
name and type, with no mutable/immutable flag. Every source field has one
runtime slot.

`library.sld` reads a library's file before any of it is expanded: where the
source is among the search directories, and what the file declares, a
`define-library`'s sections through its `cond-expand`s or a
`generate-library`'s producer program. It knows no binding and holds no
state.

`expand.sld` alone knows binding syntax. It loads libraries, resolves import
sets, expands hygienic `syntax-rules`, assigns unique names and converts
forms into expressions and declarations. Top-level names are discovered
before their bodies, allowing recursive and mutually recursive functions. Local bodies remain sequential. Typed `define` and bodyless `declare` share a header grammar here; `Fn` is the built-in callable type former.

Struct field paths remain unresolved only while the receiver type is
unknown. Once its nominal type is known, checking substitutes the record's
type arguments and resolves each label to a declared field. Each hop becomes
an ordinary accessor operation. Nested fields follow object references;
there is no inline-layout path to reconstruct. `set!` is a form, not a
function: `(set! (● receiver label ...) value)` resolves its last label the
same way and becomes a call of that field's writer, so no later pass sees a
place.

Expansion generates constructors and field operations. A derived instance
is a use of a `syntax-rules` macro that the class's library defines beside
the class, `derive-serialize` in `(snail shell wire)` for one; the expander
writes only that use, from the declaration's head, cases, field labels and
field types. `derive-pod` alone resolves where the declaration is, which
imports `(snail shell graphics pod)` to derive it.
Every body and its evidence then go through ordinary checking.
A program's entry is its `main`: a top level holds definitions alone, and
a producer recipe gets an explicit entry function. The expander writes the
entry's start, which calls `main` with what its target provides for each
of its parameters' types ("Entries").

### Named record construction

Resolution turns `new` into a constructor and a list of initializers in written
order. Each initializer carries its resolved slot and a fresh temporary name;
the slots form a complete permutation of the record's fields. The checker
supplies the instantiated field types before checking each value, so callbacks
and generic records retain contextual typing. It then erases named construction:
fields already in declaration order become an ordinary constructor call;
reordered fields become sequential typed bindings followed by that call.
Specialization and Wasm emission use their existing operations.
Chez performs the same ordering at macro expansion time, using private
constructor procedures and hygienic record descriptors, with no runtime keyword
lookup for construction.

### Types and conversions

`check.sld` infers types, solves class requirements and
records selected instance evidence at uses. Library checking is independent
of importers. Named functions state their parameter and result types;
polymorphic definitions state their quantifiers and requirements.

A function's type has no row: types unify, and nothing is subsumed. What
a function may reach of the host is in its parameters, and the checker
tracks nothing about what a call does.

Explicit `(Any value)` and `(downcast T boxed)` become `BoxAny` and
`Downcast` terms. Packaging preserves type identity; extraction returns `Some`
only for the requested type, and `None` on mismatch. Neither inserts conversions
at unrelated boundaries.
A top-level value's thunk takes nothing, so its initializer holds no
capability. The checker knows a value in one place: it does
not generalize the thunk's type, and refuses one its library leaves
undecided.

### Specialization and preparation

`specialize.sld` is one call, `specialize`: from the program's entry and
exposures it copies each definition reached once for each set of types it is
used at, and answers the copies with their declarations, each copy's type. It
reserves a copy's name, with its type, before copying the body, which
permits recursion. A copy's name keys its types. Asking for a
reserved name again does not spend the finite specialization budget.

`prepare.sld` specializes the whole reachable graph before reading any
body, and then finds what no type says: which calls may suspend. For each
definition, and for the function values of each type, it writes down what a
call may suspend to, in terms of the calls it makes, and solves those
equations to their least answer. A suspension is named by its prompt when a
top-level value holds it, so a `with-prompt` of that value is known to
catch it; any other prompt is known only by whether anything may resume it.

Lowering uses a subset of the same expression language, not a separate CPS
language. A call that may yield stays in tail position or is named by a
`let`; operands that execute before it are named first. The backend can
therefore test for a pending yield before executing the rest of the
expression. Code that never suspends is left as it was.

### WasmGC emission

`wasm.sld` selects one representation per concrete type. Numeric primitives
and booleans are Wasm scalars. A record is always a GC struct reference;
its field is one scalar or reference slot. An enum has a tagged base and
case subtypes. An array is an exact-sized WasmGC array; its length comes from
the array, and there is no capacity or replaceable storage. No object
carries a header beyond its fields. There is no inline record flattening or
reconstruction on field writes.

Completed source references are non-null. Internal Wasm storage and signatures
admit null so uninitialized slots and suspended results need no fabricated
source value. A control return leaves zero or null; its caller checks the yield
record before reading the result. Tail calls forward
that outcome directly. Normal construction and initialization establish when
a slot contains a source value. Host handovers keep their non-null contracts
except for the explicit nullable `Option Any` encoding, and dynamic type tests
still reject null. Linked modules must use the same internal calling convention.

A pure replacement creates a shallow copy of the record with one field
replaced. A mutable update writes the field in place, after both its receiver
and its value have run. Array copies support overlapping ranges. Strings
remain character arrays; conversions copy storage, and host byte staging
copies only an array's live prefix.

The emitter interns concrete Wasm types before traversing their fields,
allowing recursive object graphs. Finite budgets diagnose expanding type or
specialization families instead of exhausting the host. Ordinary recursive
nominal types reuse their existing type entry.

The `cache` and `lru-cache` primitives preserve their callback's parameter
types and result type. The checker requires a known function
signature at final inferred types, including when a primitive is used as a
function value.
Preparation rejects raw `Funcref` keys. The Wasm
backend builds an ordinary closure capturing its callback and a private typed
hash table; no module globals are involved. The Chez adapter implements the same wrapper and key
semantics. See [cached functions](terms.md#cached-functions).

### Suspension and frames

`suspend` sets a yield record: the prompt it is aimed at, its value, and
whether anything may resume it. As execution returns through named yield
points, the remainder of each scope becomes a frame: a closure of its join
function and the locals its body reads. The `with-prompt` of the record's
prompt takes the frames as a continuation and calls its handler with a
`resume` that holds it. Calling `resume` marks the continuation resumed,
detaches the frames and executes them from inside out, under the
`with-prompt` again; calling it again panics. A `with-prompt` a yield
passes on its way out is saved among the frames as one frame. A yield
nothing can resume saves no frame, and a resumption that is never called
is reclaimed like any other value.

A prompt counts its `with-prompt`s that are running, so `suspend` panics
when there is none to catch it. Three places are the backend's own code
and cannot be left as a frame: the loop that generates an array, which
lets through only a yield nothing resumes; a cache and a top-level value,
which keep nothing of a call that yielded; and a host entry, which a yield
may not leave.

This is ordinary calls and explicit frames, not stack switching: any
WasmGC engine executes the same linked code, and no JavaScript continuation
mechanism is required. `call/cc`, `dynamic-wind` and multishot continuation copying are
not language features.

## Whole programs

The unit of checking is a library, and the unit of compilation is the
program (`source->wat` in `src/snail/shell/compiler.sld`). The checker
settles each library's types before it checks the libraries that import it,
so a definition's type comes from its own library and not from how an
importer happens to use it. Emission then keeps only what the program
reaches from its entry and its exposures: each generic function is
specialized at the types it is used at, and every call is a direct call
within the one module. Capabilities travel as arguments, and the one global
of suspension is the yield record, which the module declares and exports.

Every invocation expands current sources, checks every library, specializes
and emits every reachable function again. There is no compiler Session,
interface fingerprint, invalidation graph or retained checked-code/Wasm cache.
Each build rebuilds its program and runs its producers. A program was once
also compiled a library at a time, each to a module of its own, linked when
it started; that went with the reload it served.

## Linking

A build fuses the program's module with the runtime's into one
(`link` in `(snail shell assembler)`, the Rust backend stage 0's
`snail-link` also uses), so calls into the runtime are ordinary calls, which
`wasm-opt` can inline in a release build.

WebAssembly treats two GC types as the same only when their whole
recursion groups match. The backend puts each type in the smallest
recursion group it can have: the strongly connected component of the graph
of references between types, ordered by name, with the groups it refers to
emitted first. A module a program loads while it runs that declares the
identical group shares the type, by the engine's canonicalization. A case
of an enum without fields declares no type of its own.

`snail-scheme` types are checked at compile time, each library against its
imports. A value crossing as `Any` keeps its nominal type identity for
explicit `downcast` checks.

### Linking by hand

A program loads modules while it runs with `(snail shell wasm)`.
`compile-bytes` compiles a module, `module-imports` lists its imports, and
`link-module` accepts one explicit `Provider` per import in order. A provider
is an instance's export, a host service, a constant function, or a function
that fails if called. Missing or incompatible providers return `LinkFailed`.
Linking runs `_initialize` when present; the loader calls `main` separately.

`module-export` returns an untyped `Funcref`. `unsafe-cast` wraps it in an `Fn`
closure at the requested type. The Wasm
cast checks representation, not `snail-scheme` nominal identity: the caller
must establish that contract. `run-export` calls a scalar export by name.

`loading-program` identifies the loader. `bind-runtime` selects the loaded
program's runtime for staging bytes and reporting errors without changing the
loader's identity. No host registry or plugin namespace participates in
linking.

`tests/programs/wasm-linking.sld` checks provider selection and failures.
`wasm-instance-identity.sld` verifies that existing imports keep their original
provider when a new link uses another instance, and that linking consumers
does not initialize their providers again. Both run on Node; the identity
test also runs in Chromium.

### Hosts

The host compiles bytes, lists imports, binds explicit providers and finds
exports. Node and the page install these operations; the page's
are exercised by the Chromium fixture.

Every import module a host provides is named for the runtime interface it
implements, `snail.runtime.…` (#566): `snail.runtime.link`,
`snail.runtime.resource` and `snail.runtime.gpu` on every host,
`snail.runtime.wasm`, `snail.runtime.native.socket`,
`snail.runtime.native.process`, `snail.runtime.native.files` and
`snail.runtime.native.develop` on Node,
and `snail.runtime.browser.events`, `.storage`, `.dom` and
`.fetch` on the page. A `(snail runtime …)` library declares one of these
interfaces as externs, and nothing else, so it has no items and emits no
code: the program's module imports from the host itself.
The Rust support module, built from `crates/snail-scheme-support`, is
`snail.core.support`, which a build fuses into the program's module.

## Compiler inputs

Each compiler invocation takes library directories, the current
generated-library provider and its target. The provider receives each
producer with the libraries loading when it was reached, and answers the
bytes of the syntax the producer wrote.

The builder's provider, `generated-syntax` in
`(snail shell compiler inputs)`, keys a producer by a hash of its text,
`producer-text`: the library directories its imports resolve in, then its
program, since two builds with different directories may resolve the same
recipe's imports to different libraries. It reads `KEY.syntax` from the
compile's scratch when a producer has already written it there. Otherwise it
prints the producer as `KEY.sld` and requests it. The producer names its
recipe after its imports, `(recipe "src/sample/blob.sld")`, and a path its
own forms write, as a `link-file` in the recipe's expression, resolves
against that file rather than the printed copy (`written-in` in
`expand.sld`), so a recipe links files beside itself wherever its producer
is printed. The recipe's path is part of the producer's text, and so of its
key, since the files it links depend on it. The producer computes the
recipe's expression in a task, as `(write-generated-library producer-fs
producer-arguments (lambda () EXPR))`, so the expression may read what the recipe links with
`read-resource`, run processes and build other scripts
([embedding](projects.md#embedding-a-build)).

Generated syntax is obtained before expanding its library. A build runs each
producer its compiles reach once, and the output serves every later compile
in that scratch. Persistent producer caching remains separate work.

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

The compiler cannot start a producer. A pass that needs a producer's output
it was not given stops the compile (`stop` in
`(snail shell compiler read)`) with `(Requested request)`, where the
`CompilerRequest` is `(GenerateInput key)`. The compile's prompt answers
`Never`, so nothing after it runs and its yields save no frames. No
signature on the way from the request to an entry point says so, and each
entry point takes it with `compiling`, which turns the compile into a
`Result`, here `(Err (Requested request))`, as it does a source error into
`(Err (Failed diagnostics))`.

The project builder, `(snail shell project build)`, calls the compiler in its
own process and takes each compile's `Result` (`producing`): a
failure stops the build with its diagnostics, and a request runs the printed
producer, which writes its output into the scratch, and compiles again. No
request file is written or parsed, and nothing traps.

The command-line driver, `(snail shell compiler driver)`, which stage 0 runs
to bootstrap the command line, runs no producer: a program that reaches a
generated library fails there, and is built by `snail-scheme build`.

### Linked files

A linked file's bytes are an input of the compile, as their digest: the
module imports its handle under that name. Each build binds the current linked
files during expansion. A missing file fails with the library and path;
changed bytes bind a new digest. The store remembers each digest a build
read, with the file's size and modification time, in
`build/.snail-store/digests`, and a compile trusts one while its file keeps
both, as make trusts a time, so a large file is hashed once rather than
every build. Every build compiles all libraries and
places every linked file as an object of the workspace's store,
`build/.snail-store/sha256/AB/DIGEST`, named again at the same path under
`store/` beside the program's module, checking that the bytes it places
have the digest the compile read; a file edited during the build fails it,
and the next build compiles against the new bytes. The bytes
under such a name never change, so a server can let a browser cache them
for good.

## Supporting modules

| Path | Responsibility |
| --- | --- |
| `src/snail/shell/compiler/driver.sld` | Typed source invocation shared by both hosts, `compile-arguments`: a compile that fails, or that needs an input after publishing its request, exits with status 1. The command line's `compile` action and Chez's `compile` mode call it; the command line's `wat` uses the same compiler. |
| `host/chez/load.scm` | Chez's unwind boundary, which turns a failure into the same status. |
| `crates/snail-scheme-support/src/bin/snail-link.rs` | Stage 0's linker, the assembler and `wasm-fuse` as a native program, which links the command line for the bootstrap. See [the bootstrap](bootstrap.md#running-and-linking). |
| `host/chez/snail/stage0/build.sld` | The bootstrap of the command line, and nothing else. Each compile has private scratch; rebuilding the command line holds `build/lock`. |
| `host/chez/snail/stage0/process.sls` | Synchronous tool capture through private output files and a constant shell script with positional arguments. The parent reaps before reading or deleting files; stdin is EOF. The host boundary uses Chez process and file primitives. |
| `crates/snail-scheme-support/` | Rust scalar services: math, Unicode, float text, console and file IO, directory and path operations, the monotonic clock, panics. External resources use explicit handles; managed references remain engine-traced. Its `assembler` feature builds the toolchain's runtime, which tools written in `snail-scheme` link (`build-toolchain-tool`), with in-process assembly and static linking for `(snail shell assembler)`, shared by the native executable. |
| `host/native/run-snail.mjs` | Node/WASI program execution, the compiled compiler's included, on Node's main thread, plus module loading; it drives the program's task scheduler through `host/browser/tasks.mjs`, as the page does. A trap is status 2 and a WASI exit its own, as on wasmtime. |
| `src/`, `host/chez/` | Typed language libraries and the explicit Chez adapters. `host/chez/load.scm` permits only the compiler's source closure and stage-zero tools. |

Builds and publication belong to the [builder](projects.md),
the language server to the
[development toolchain](toolchain.md), and
task scheduling and resources to the [runtime](../runtimes/index.md).

## Following and checking a change

`make test` runs the compiler's unit tests from source on Chez and exercises
emitted Wasm. `make bootstrap` rebuilds from Chez alone and compares the
compiled compiler's successive Wasm stages. Keep both hosts working: differences in
integer overflow, table iteration or evaluation order must not change behavior.
Backend changes need execution tests, not only successful compilation.
`make check` checks formatting; `mdbook build` builds the book.
The [getting-started guide](https://github.com/tsnl/snail-scheme/blob/main/doc/getting-started.md)
lists pinned tools and the Rust/browser checks.
