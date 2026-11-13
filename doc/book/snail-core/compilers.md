# Compiler architecture

The compiler has four main phases: expand, check, prepare, and emit.
Reading supplies located syntax. Preparation closes specialization and
cleanup requests and produces fixed concrete code.
Emission consumes that result without revisiting source semantics.

```text
text ──read───▶ located syntax
     ──expand─▶ resolved program   unique names, declarations, field paths
     ──check──▶ typed program      types, rows, instances, exact-once ownership
     ──prepare▶ concrete code      initializers, control and cleanup explicit
     ──emit───▶ WasmGC text ──assemble/link──▶ executable module
```

`Prepared` contains declarations, concrete function definitions, an optional
root entry, exports and host exposures. Nonfunction definitions become
zero-argument initializer bodies, lowered through the same ownership and
control passes as functions. Emission puts each behind a lazy cache getter;
there is no startup initializer list or top-level statement execution.

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

`annotations.sld` parses documentation metadata once. The expander attaches
it to canonical declarations, fields and methods. It affects neither type
identity nor object layout.

`core.sld` defines `Type`, `Scheme`, class evidence, expressions, patterns,
declarations and the program tables shared by the passes. `expr-children`
is the common structural inventory; each analysis still decides which
children execute, bind names or start a new scope. Data fields contain a
name and type, with no mutable/immutable flag. Every source field has one
runtime slot.

`expand.sld` alone knows binding syntax. It loads libraries, resolves import
sets, expands hygienic `syntax-rules`, assigns unique names and converts
forms into expressions and declarations. Top-level names are discovered
before their bodies, allowing recursive functions and references to later
constants. Local bodies remain sequential. Typed define headers are parsed
here; `Fn`, `FnOnce` and lowercase `fn` are type formers, not classes.

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

`conversions.sld` resolves concrete `Any` boundaries. Packaging preserves a
value's type identity; extraction checks it and performs `dyn-cast` on a
mismatch. It does not promote numbers or reinterpret collections.
`dynamic.sld` expands explicitly declared finite instance dispatch into
ordinary type tests, conversions and calls. The old dynamic Scheme runtime
and numeric-tower libraries are gone; typed code needs none of those adapters.

A top-level nonfunction initializer must have an empty effect row. A handler
can discharge an effect locally, and an intentional `unsafe-total` can hide
private mutation. The resulting initializer is compiled as ordinary runtime code.

### Ownership and lifetimes

`capabilities.sld` determines whether a type is linear and how it is dropped
or cloned. Every stored field participates. A struct or enum with a linear
member is linear, regardless of its mutability. Explicit `Move` or `Drop`
instances can also make a type linear. A generic parameter is linear unless
its contract requires `Copy`.

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

### Lazy value initialization

Preparation keeps the original source classification: a function is callable
code; a value may itself contain a callable closure. Only the emitted value
body is wrapped as a zero-argument function. Contextual control analysis still
sees the original body, so it distinguishes the initializer's effect row from
the effects of invoking a returned procedure.

`wasm.sld` emits one getter and two private globals per monomorphic value:
its cached storage and a state of uninitialized, initializing or ready. A read
calls the getter with ordinary evidence. The getter rejects initializing,
sets that state before running the body, stores the result, marks ready, and
returns an owned read. Reference storage starts nullable; ready proves it is
non-null. Initializer emission is non-tail so publication cannot be skipped by
a tail call. No scheduler, dependency graph or synchronization is needed.

Publishing transfers the initializer's owner into the cache. Every returned
counted value receives the usual retain, including the first read. The cache
is a root for the module lifetime; collection does not run source finalizers.
A fatal trap leaves the initializing state in place; there is no retry protocol.
Importers call the defining instance's getter, sharing the same cache. New
instances start empty; retained old closures may still call old getters.

A value-global read can initialize or panic. Control preparation therefore
preserves it before a later yielding operand. Tail-call lowering evaluates a
cached procedure before its arguments and outgoing-owner releases, just like
other computed callees. Ordinary named functions keep their direct call path.

Quantified functions specialize normally. The checker permits only stateless
literal/nullary enum templates as other quantified values; specialization
expands those directly. Mutable generic cache instances would require a shared
registry across separately compiled libraries, so they are deliberately absent.

### WasmGC emission

`wasm.sld` selects one representation per concrete type. Numeric primitives
and booleans are Wasm scalars. A struct is always a GC struct reference;
its field is one scalar or reference slot. An enum has a tagged base and
case subtypes. Every vector has a stable holder containing its logical length
and replaceable backing array. The active prefix owns its scalar or reference
elements; spare reference slots are null. Growth replaces the backing array,
and pop clears its removed slot. Source code cannot name that storage or its
capacity. There is no inline struct flattening or reconstruction on field writes.

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
- each generic definition and alias the library uses is copied in,
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

A **session** (`src/snail/shell/compiler/session.sld`) compiles a program again
and again, as the development loop does, retaining checked code and Wasm:

- Each build expands current sources, producer outputs and artifacts from
  scratch. Expansion itself selects instance providers, so an old expansion
  cannot safely stand in for the current declarations. No saved expansion,
  scope or replay log survives into another build.
- A library's **interface** fingerprints all its declarations and imported
  interfaces, conservatively including monomorphic function bodies. This may
  rebuild more importers than necessary. Derived instances also depend on their
  implicit libraries. Artifact bytes, linked files, expanded declaration
  identities and the final fresh-name counter complete the key. The counter
  prevents cached local names from colliding after an earlier library changes.
- Each library's checked items, type schemes and module text are kept
  under that key and the final program's instance-provider interfaces.
  Instances can come from a sibling outside a library's imports; named
  policies participate too. A build checks, specializes and emits only
  libraries whose combined key changed. A provider edit conservatively
  invalidates every checked library; an ordinary body edit invalidates its
  importers. Unchanged builds reuse checked code and module text.

Sessions retain compilation evidence, not a build's providers or files. The
[input boundary](#compiler-inputs) defines how current inputs validate reuse.

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

Snail Scheme types are checked at compile time, each library against the
interfaces it imports. Nothing checks them at load time: every module of a
link comes from one build of one session, which recompiles importers
whenever an interface changes. The engine still checks the WebAssembly
type of every import, and a value that crosses as `Any` keeps its own
check at `type-convert`. A plugin comes from another build, so its
functions are checked when they are looked up ([plugins](#plugins)).

Replacing a library's module means linking it and every module after it
in program order again (`relinkProgram` in `load.mjs`); the modules before
it cannot import from it. That
costs the instantiation of a few modules, and keeps debug code free of the
indirection that a table of mutable globals, like ELF's global offset
table, would add to every call across libraries.

### Loading modules at run time

`(snail shell wasm)` is `dlopen` and `dlsym`. `load-module` loads a module
from a file into the program's own namespace, linked against the runtime,
the program's modules and the modules loaded before it, by name, and runs
its `main`. A function the module exports comes out as a `Funcref`, and
`unsafe-cast` makes it a function of the type the context expects:

```scheme
(match (load-module "cell" "build/cell.wasm")
  ((Ok cell)
   (match (module-export cell "cell:run")
     ((Ok run) ((ann (unsafe-cast run) (Fn I64 → I64)) 41))
     ((Err error) (panic (load-error-message error)))))
  ((Err error) (panic (load-error-message error))))
```

`unsafe-cast` is a primitive. It wraps the reference in a closure whose
code casts it to the WebAssembly type of a Snail Scheme function of the
expected type, which takes the evidence first, and calls it with the
handlers in scope where the closure is called. At an `Fn`, `(ann
(unsafe-cast run) (fn I64 → I64))`, the cast is the whole value, with no
closure around it. The cast is the only check: the engine traps when the
WebAssembly types differ, and nothing compares Snail Scheme types, so the
unsafe assumption is visible where it is made.

### Linking by hand

`load-module` and `load-plugin` link by the host's rules: the runtime, the
modules of the namespace by name, the host's services, and a stub for a
host function the host lacks. A loader written in Snail Scheme, such as an
engine linking a program from its manifest
([#660](https://github.com/tsnl/snail-scheme/issues/660)), decides those
rules itself with four operations, which the two hosts must answer alike
(`tests/programs/wasm-linking.sld` runs on both). `compile-bytes` compiles
a module; `module-imports` lists what it imports, each a module and field
name with its kind, function, table, memory or global, which the host
holds and Snail Scheme reads back a character at a time, as names go the
other way; `link-module` links it against one `Provider` per import, in
import order, an export of an instance, the host's own function of that
name, a function answering a constant, as a linked file's handle is
imported, or nothing, a function that fails if called, and answers the
instance, initialized when it exports `_initialize`, or `LinkFailed` when
a provider is missing or not of the import's type; `run-export` calls an
export of no argument or one `I64`, such as `main` or a scheduler's
`tasks:turn`, for its result. `loading-program` is the instance of the
program that loads, whose exports a loaded module may import, and
`name-instance` puts a linked instance in the program's namespace, where
`load-module` sees it. Nothing but initialization runs when a module is
linked this way: the loader runs its `main` when it chooses.

### Plugins

A plugin is a program built apart from the one that loads it, compiled one
library at a time and named by its `modules.json`. Types cannot be loaded:
the plugin and the program share the types they pass by importing one
declaration of them, and only functions cross. The plugin marks each
function it offers:

```scheme

(define (summarize (project Project)) (→ Report) ...)
(expose summarize "summarize" dynamic)
```

and the program looks it up at the type it expects:

```scheme
(match (load-plugin "build/plugin/modules.json")
  ((Ok plugin)
   (match (ann (plugin-function plugin "summarize") (Result (Fn Project → Report) LoadError))
     ((Ok summarize) (summarize project))
     ((Err error) (panic (load-error-message error)))))
  ((Err error) (panic (load-error-message error))))
```

The backend emits two exports for a dynamic function. `"summarize"` takes
the evidence and an `Any` for each parameter, takes each argument out of
its `Any`, which tests its TypeId, calls the definition and returns the
result as an `Any`; every dynamic export of one arity has one WebAssembly
type. `"summarize:signature"` returns the signature as a `(Vector I64)`:
the arity, then the identity of each parameter's type and of the result's,
in 64 bits (`wide-type-id`, FNV-1a over the same text as the 32-bit TypeId,
kept in two halves so that both hosts compute it alike). The signature is
compared once, when the function is looked up, so it is worth the wider
hash; the TypeId an `Any` carries is tested on every call.

The checker adds two rules to `expose`'s for a dynamic function. Its
parameters and result are data, with no function, `Funcref` or `Any`
inside: a function type's TypeId says only that it is a function, and an
`Any`'s nothing of what it holds. And it is pure. Specialization erases every effect
but the control effects before the backend runs, so neither side's backend
knows the function's effects and the signature cannot carry them; a
program that declared fewer effects than the plugin performs would go
unchecked. Passing the importer's evidence is mechanical once effect
identities, with their operations' types, reach the backend.

`load-plugin` reads the manifest, makes a namespace and links the plugin's
modules there in program order, each against those before it, then the
runtime the program shares with it and the host's modules, as a
child-first class loader resolves, and runs each module's `main`. The
namespace is private: a library's module text depends on the program it
was compiled for, its set of control effects among it, so a plugin has its
own instances, and its own globals, even of a library the program imports
too. So a plugin that imports `(snail shell task)` has its own scheduler,
which no host drives: a task its top level dispatches never runs, and its
dynamic functions, being pure, cannot dispatch one. The runtime its
manifest names is not loaded.

`plugin-function` finds `NAME` and `NAME:signature` in the plugin's own
module, its program's, and calls the signature through `unsafe-cast`: that
an export so named is a signature is the boundary's one unsafe assumption.
Then the primitive `dynamic-cast` calls a policy with the signature of the
type the context expects and, if the policy accepts it, holds the export
in a closure of that type, which passes each argument as an `Any` and
takes the result out of one. The policy is a Snail Scheme function,
`same-signature?`, so loosening it is a library change: strict identity,
under which a plugin built from another declaration of `Project` is
refused with `SignatureMismatch` before anything is called. A versioned
identity, as the JVM's binary compatibility allows, would need every type
to be non-final, its history kept in source and an append-only checker,
and an enum could never gain a case, since an old exhaustive `match` would
reach `unreachable`.

Values cross by reference, with no copy. Every module that declares a type
declares the same recursion group, so the engine makes them one type across
the namespaces, and the plugin's casts succeed on the program's values.
Both checks are needed: WebAssembly's equality is only shape, so
`Point {x, y}` and `Range {lo, hi}` are one WebAssembly type, while their
TypeIds differ. `wire` is for where references cannot go: workers, Rust in
linear memory, native code, disks and networks.

A failure is a `LoadError` value: a file that cannot be read, a manifest
or module that is not one, a name already linked, an import with no
provider of its type, an export that is missing or not dynamic, and a
signature that differs. There is no fault isolation: a trap inside a
plugin, its `main` included, ends the program.

### Hosts

The host keeps the operations only it can do, as the `wasm` effect: it
compiles a module from the Bytes the program read, makes a namespace,
instantiates a module in one under a library name and runs its `main`, and
finds the functions an instance exports (`wasmImports` in `load.mjs`).
Namespace 0 is the program's own. Each answers a failure with a negative
code rather than a throw. A `main` runs inside the host call, so it cannot
wait for a task, and a plugin cannot yet read the files it links.

The Node runner provides the `wasm` effect for both builds. A statically
linked program exports nothing of its runtime, so what it loads can link
only against the host, and it cannot load a plugin. Browser hosts do not
provide it yet: loading is synchronous, and a page reads files
asynchronously. `tests/dynamic/host.sld` loads a library's module from a
plugin's build, and the plugin itself built twice, once from a stale
declaration of the type it takes; `tests/programs/wasm.sld` loads modules
it writes itself.

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
(`emit-libraries` in `session.sld`).
The Rust support module, built from `crates/snail-core-support`, is
`snail.core.support`, and the compiler's control module
`snail.core.control`. A module linked under a `(snail runtime …)` name, or
`(snail core support)`, would have one of the hosts' names as its module
key, and the program's modules would import it in place of the host's
interface, so a loader refuses one, at
startup and when the program loads one (`hostProvided` in `load.mjs`,
`host_provided` in `crates/snail/src/modules.rs`).

## Compiler inputs

The compiler entry points and `build-session` take the current generated-library
provider, which receives each producer with the libraries loading when it was
reached, and an `Inputs` value, what the build supplies to each of its
compiles. `make-session` takes only library directories; a retained session
owns evidence, never a provider closure:

```scheme
(struct Generated ((text String) (bytes Bytes)))
(struct Inputs ((artifacts (Table ArtifactFiles)) (generated (Table Generated))))
```

`artifacts` maps target names to ordered file snapshots, each a
`(List (Pair String Bytes))`. The native builder establishes
unique, canonical relative paths sorted by path, with bytes loaded from one
completed immutable output. Artifact expansion performs only memory lookups;
it has no filesystem capability. Inputs belong to the current invocation, not
the retained session. `no-inputs` supplies nothing.

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
it. The recipe's `include-bytes` were replaced when it was read, so their
bytes are in the text already. The producer computes the recipe's
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
input fails the build before cached checked code can be reused.

Artifact fingerprints include target names, canonical file paths, byte lengths
and content hashes. They enter the library's completed interface, so changed
bytes invalidate both the library and its importers. These are deterministic
content keys; restarting expansion's fresh-name counter cannot accidentally
reuse an old artifact revision. Failed builds publish no replacement session.

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
compile and to `refine-plan`. Successful Sessions retain only the per-library
evidence already used for cache reuse. Applications embed the bytes and need
no runtime file access.

### Linked files

A linked file's bytes are an input of the compile, as their digest: the
module imports its handle under that name. Each build binds the current linked
files during expansion. A missing file fails with the library and path;
changed bytes bind a new digest. Digests enter the library's interface and
checked-code keys, so an edit recompiles the library and its importers, which
may specialize a generic function that uses one of its handles. Every build
places every linked file, including those of cached modules, as an
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
program in a child process, which keeps each target's compiler Session from
one build to the next ("The resident builder" in `bootstrap/cli.sld`). The
service writes it one JSON request a line and reads one reply a line: a
`build` answers the project's description, a candidate with how long the
build took and each target's generation, digest, how many of its modules it
compiled and the digest of each file but its modules, which the reload
client compares, and any diagnostics; the resident holds the candidate until a `publish` or a
`discard` names it. Sessions, Plans and inputs stay in the resident and never
cross. A development build assembles each module the session compiled
again with `(snail shell assembler)`, in the same process; a module the
session reused keeps the bytes it was assembled into, and their digest,
which names its object (`Retained`). The service, `(snail shell project service)`, writes the
requests and reads the replies.

A build's failures reach the service as `{severity, message, source}`;
`source` is null or `{file, line, column}`. Lines and Unicode scalar columns start at one. IO and
producer-input requests have no source record; internal no-location sentinels
are unlocated. A failing dependency reports its own origin. Printed
producer programs report their actual scratch source, while decoded generated
syntax retains the recipe location already established by expansion. No source
mapping is invented. The command-line driver prints each diagnostic as the
compiler always has, `FILE:LINE:COLUMN: MESSAGE`, or `FILE: MESSAGE` for the
file as a whole, a line each, and exits with status 1. A reply carries every
diagnostic of the failed compile, which reports each failed body of the
library that failed to expand, or each failed definition and statement of
the library that failed to check. These operations are implemented and tested.

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
