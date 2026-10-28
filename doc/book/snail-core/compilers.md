# Compiler architecture

The compiler is a pipeline of six passes. Each pass consumes the previous
pass's output and nothing earlier:

```text
text ──read──▶ located syntax
     ──expand─▶ core program      unique names, resolved types, entity tables
     ──check──▶ typed program     every expression typed, instances chosen
     ──mono───▶ monomorphic program
     ──control▶ monomorphic program, each call that may yield a let's value
     ──wasm───▶ WasmGC text ──assemble──▶ module, linked with the Rust runtime
```

Static debug and release builds compile the whole program and merge the Rust
services into one module; release increases optimization. Development builds
compile one library per module and assemble with the `wat` crate in process.

Read [`examples/fibonacci.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/fibonacci.sld), run
`./scripts/snail-tool wat examples/fibonacci.sld` to see the WebAssembly it becomes, then
read the passes in order. The [language chapters](index.md) describe the
surface they implement.

## The passes

All compiler modules live in `src/snail-core/compiler/` and are written in typed
Snail-Core: they import only `(snail-core base)`, `(snail-core table)` and `(snail-core io)`, so the
compiler can compile itself. Chibi Scheme runs the same source through
`host/chibi/`, which implements those three libraries and erases the typed
forms.

Tables are immutable, so a pass can thread its state as a value rather than
mutate it. How far each pass has gone differs: checking is a pure function of
a program and expansion a function of the files it reads, while the backend
still keeps what grows over a pass in a `Ref`. Where a pass does thread
state, its type says so — neither the checker's `check-library` nor any
function of the expander has `mut` in its row — and where it does not, the
`Ref` is allocated by the pass and never escapes it.

- **[`read.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/read.sld)** turns text into `Syntax`:
  atoms, identifiers and forms, each with a `Loc`. It is a recursive descent
  over a vector of characters; a line table recovers line and column only
  when a location is needed. Its lexemes, what starts at an index and where
  it ends, never fail, and the reader reports what it rejects in them;
  `(snail-core highlight)` classifies text with the same functions. It also
  decodes the bytes a `generate-library` producer writes, the encoding
  `(snail-core syntax)` defines, straight into `Syntax`. `compile-error`
  preserves the source point and message at terminal failure; the resident
  caller resets and consumes this private diagnostic cell.
- **[`core.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/core.sld)** defines the data the later
  passes share: `Type` (with effect rows), `Scheme`, class `Evidence`, the
  `Expr` tree, `Pattern`s, declared entities (`DataType`, `Class`,
  `Instance`, `Effect`), the `Program`, the global names of primitives,
  TypeIds for wire cases and `Any` values from one FNV-1a hash, the
  strongly connected components that the checker and the backend share, and
  the names of the core forms and builtin types that `(snail-core core)`
  provides. A `Program` is a value: the expander threads it through
  expansion, each addition handing back a larger one, and the later passes
  read it without effects.
- **[`expand.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/expand.sld)** is the only pass that
  knows binding forms. It loads libraries, replacing each `include-bytes`
  with the byte vector literal of its file, resolves every identifier through
  environments, and runs `syntax-rules`. Hygiene is renaming: each identifier
  a template introduces gets a mark that is unique to the expansion and, when
  unbound, resolves in the macro's own environment. Top levels expand in two
  passes so definitions may refer to later ones; local bodies are
  sequential. Declarations become entities in the program tables, derived
  wire instances are generated as ordinary instance syntax that resolves in
  the implicit libraries, `(snail-core wire)` among them, which the build's
  first deriving clause loads, and expressions become core `Expr`s with
  unique names. Each library's build key, the text of its declarations with
  its imports' interfaces, lets a session replay it.

  The pass holds no mutable state. A `Context` is plain data, threaded
  through: each step takes one and hands back the one it learned in, and a
  private `expanding` form sequences steps as the checker's `learning` does.
  Its fields separate what the build is given; scope, which loading a
  library replaces and the importer gets back — the library's prefix, the
  libraries loading, the aliases being resolved, and what the library itself
  uses and makes: its artifact uses and links, whether it derived instances,
  and the items its body adds, which join the program as one run when the
  body is done, so a library loaded meanwhile, as the implicit libraries
  are, comes before that run and never inside it; and what the build has
  learned, which flows forward out of every library — the program, the
  libraries expanded, the counter behind fresh names, the scopes that marks
  refer to and the definitions of each top level. One `resumed` says which is which. A top
  level's definitions are the context's, under the top level's key, so an
  environment made before the scan bound a name resolves it as well as one
  made after. Pass 2 adds each declared entity to the program as it meets
  it, and returns one step for each definition and expression body; a single
  fold runs the steps in the order the scan found them. The expander's only
  effect is `fs`: it reads libraries, and the producer runner the driver
  supplies for `generate-library` reads and writes files. A use of
  `artifact-files` without its files requests the input, which exits as a
  compile error does.

  Every library is a file but `(snail-core core)`, which the expander
  serves from memory: the core forms, the builtin types, and the `mut` and
  `tasks` effects. The operations the backend implements directly are
  declared in
  [`src/snail-core/primitive.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/primitive.sld),
  read and resolved like any library. `(primitive i32-add (-> I32 I32 I32))`
  declares one, as `extern` declares a foreign function: it binds the name to
  the global `prim:i32-add`, the name the checker, mono and `emit-primitive`
  know it by, whose value is a `Primitive` of the declared scheme. A generic
  primitive names its variables, `(All (A) (-> (Vector A) I64 A))`. The form
  is accepted only in that library, whose body holds nothing else, so it
  adds no items and has no module; a session replays its values.

  The core form `link-file`, which `link-bytes` in `(snail-core resource)`
  wraps, parses its path against the directory of the file it is written in
  and records a `LinkedFile` on the library: the name the payload ships it
  under, the library's key and the canonical path, and where the build finds
  it. Its value is a call to an import from `snail.link` under that name,
  which answers the file's handle, so each module records the files it links
  where its host must see them. Once a library's body has expanded, each of
  its files must exist, or the build fails naming the library and the path.
  `library-links` and `program-links` give a build's files by library and in
  program order.

  The expander reads each library's file into a `LibraryFile`: a defined
  library's sections, or a generated library's producer program. The same
  reading serves `library-closure`, a walk that finds the generated
  libraries a program's imports reach without expanding anything. It
  follows imports as the expander loads them, adds the implicit libraries
  deriving loads, and reads on through each producer output the build
  supplied. Which targets a program embeds cannot be read that way, since
  macros may name them, so `discover-artifacts` runs the expander itself
  with no target files supplied and records each `artifact-files` use as
  expansion reaches it, in program order.
- **[`check.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/check.sld)** is Hindley-Milner inference
  with effect rows. Unannotated top-level definitions are checked in
  dependency order (core's `strong-components`). Each instantiation records its type
  arguments and an evidence hole per class constraint. While items are
  checked, constraints are only recorded; a group of functions quantifies
  the metavariables nothing else still mentions. Libraries are checked one
  at a time; when a library is checked, its literals default, and each
  class constraint is solved once, filling its hole. Rows unify as sets with
  open tails. Matches are checked with Maranget's usefulness algorithm.

  The pass holds no mutable state. A `Checker` is plain data, threaded
  through: each step takes one and hands back the one it learned in, so
  `check-library`'s type is a pure function from a program to a typed one.
  Its fields separate scope a sub-check may replace and the caller gets back
  — locals, givens, the confining and signed rows — from what it learned,
  which flows forward. One `resumed` says which is which. A function checked
  against its signature records what the calls in its body perform, so a
  signature that names an effect the body never performs is an error.

  It also decides where a function may mutate at all: a function whose type
  forbids `mut` may still mutate storage it allocates, provided nothing it
  can reach from outside — its parameters, its result, or a name it reads —
  can hold mutable storage.
- **[`capabilities.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/capabilities.sld)** establishes
  structural `Send` and `Sync` evidence from types and declared fields.
  The checker resolves these compiler-owned markers; user instances cannot
  override them. Ordinary arrows carry no proof about their captures.
- **[`handlers.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/handlers.sld)** checks that a handler's
  retained environment is reusable and satisfies `Send + Sync`. It follows
  closure aliases, named helpers and selected method evidence to their
  captures and globals, while keeping invocation arguments and fresh local
  storage separate. Unknown callback provenance is rejected.
- **[`mono.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/mono.sld)** starts from the program's
  statements and values and copies each reachable definition once per ground
  instantiation. A method reference becomes the instance method its evidence
  names, and definitions that only rename another, such as
  `(define + i64-add)`, are replaced by their target.
- **[`ownership.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/ownership.sld)** consumes affine
  locals once per path after specialization. Branches fork and intersect
  their live owners; a path drops a value when it has no remaining use.
  Only one-shot closures can own affine captures. Concrete records inherit
  their fields' grade; existing generic parameters remain unrestricted.
- **[`control.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/control.sld)** prepares the calls
  that may yield to a control handler. After specialization a row keeps
  only control effects, so a call may yield exactly when its callee's row
  names one, and a handle keeps what its body yields except to its own
  effect. An operation's row is its effect's and its latent row, so
  performing an operation whose type names a control effect is such a
  call. Such a call stays where it is when its value flows straight out
  of a function, a handle body or a let's value, so a tail call stays one;
  anywhere else a let names it, with the rest of the expression as the
  let's body, and names first each operand that runs before it, so those
  still run first. A program without control effects comes back as it went
  in, as does each item without such a call. The pass also refuses a
  control row where nothing could carry a yield: in a `vector-generate` or
  `string-generate` callback, which a WAT loop calls; in an `unsafe-total`
  thunk, whose row the call discards; in `dispatch-local` work, which runs
  later on a task's own stack; and in the implementation of an operation
  declared without `ctl`, which returns into a handled body that tests for
  a yield there only to the control effects the operation's type names.
- **[`wasm.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/wasm.sld)** chooses representations and
  emits WebAssembly text. Scalars are Wasm numbers. An enum whose cases have
  no fields is an `i32`; other data are GC structs, and enum cases are final
  subtypes of a base holding the tag. Sequences are GC arrays. Functions are
  closures: a struct whose first field is a typed function reference, with
  captured variables in a subtype. Tail calls become `return_call`. Every
  function takes the handlers in scope as its first parameter, a list of
  evidence nodes; `handle` extends the list for its body, and an operation
  walks it for its effect's node and runs the implementation with the list
  outside that node, or the default past the last: a host import, or a
  Snail-Core function run with the performer's list. The implementation of
  an operation with a latent row runs under a forwarding node for each
  effect the row names, which sends that effect's operations, and re-aims
  its yields, to the performer's handlers. A control operation
  instead leaves a yield record in one global: the node it is aimed at, the
  operation and its arguments, and returns a placeholder of its result type.
  After each let whose value may yield the record is tested, and while it is
  set the let saves its body on the record as a frame, a closure over the
  locals the body reads and its evidence whose code is the body compiled
  as a join function, named by the hash of its text, which runs only to
  the next yield point and continues in that point's frame; then each function
  returns a placeholder and each handle body branches to its handle site,
  until the handle whose node the record names. That handle clears the
  record and runs the implementation with `resume`, a closure over the
  frames and the node, and the implementation's result becomes the
  handle's; any other control handle the yield leaves saves itself as one
  frame holding the frames saved inside it. Calling `resume` sets the
  node's outer evidence to its caller's, rebasing the computation on the
  handlers in scope where it is resumed, runs the frames, innermost first,
  and ends in the handle's catch, as the handle site does, so handlers are
  deep and a tail-resumptive implementation runs in constant stack. A
  frame that yields again has the frames after it saved on the new record.
  Nothing reads a placeholder, and a program without control effects
  declares no record and tests nothing. Each GC type sits in
  the smallest recursion group it can, ordered by name, so modules that
  declare the same
  type declare the same group. Compiled one library at a time, a module
  exports its monomorphic definitions under their global names and imports
  other libraries' definitions. At the host boundary it
  stages final String and Bytes arguments and wraps exposed `(Option Any)`
  as a nullable opaque handover. Other exposed managed values keep their normal
  representation; the checker rejects affine parameters/results at that boundary.
  The host passes no evidence, so every exposed function has a wrapper that
  calls the definition with the empty evidence list.
- **[`session.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/session.sld)** keeps the compiler
  running between builds: the expander replays libraries whose declarations
  and imports' interfaces are unchanged, and only libraries whose expansion
  changed are checked, specialized and emitted again. Cached emissions keep
  their monomorphic items so handler capture proofs can be rechecked against
  current helper bodies without regenerating unchanged Wasm text. Input
  generators and immutable build inputs are passed to each build; sessions
  retain only compilation evidence. Each `Built` module carries the files its
  library links, compiled this build or not, so a build places them all.
- **[`plan.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler/plan.sld)** orders a project build's
  phases before any of them runs: building a target, and running a
  producer. A phase needs the producers its program's closure reaches, then
  the targets a discovery expansion finds it embeds. Nodes number in
  depth-first pre-order from the roots, `strong-components` puts each phase
  after what it needs, and a cycle is an error naming the targets around it
  from the one declared first, `artifact dependency cycle: client -> admin ->
  client`, with any producers on the way. A phase whose closure reaches a
  producer that has not run waits: `next-phases` hands out the steps of the
  order up to the first that waits, and `refine-plan` learns what the waiting
  steps need once those producers' outputs are supplied. `bootstrap/compiler.sld`
  resolves the project's targets, and the native builder runs the plan wave by
  wave. The development loop plans with no targets, which needs no discovery,
  and runs only the producers.
- **[`compiler.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail-core/compiler.sld)** composes the passes, from a
  program's path to WebAssembly text with the files it links, a
  `WholeProgram`, or to one module's text per library. The driver writes the
  files a compile links to `links.datum` in the compile's directory, one
  `("NAME" "PATH")` per file, for the Chibi build to place.

## Separate compilation

The unit of compilation is a library (`source->modules` in
`src/snail-core/compiler.sld`). In its module:

- each monomorphic definition is exported under its global name, as in
  `snail-core.base:map`;
- each generic definition and alias the library uses is copied in,
  specialized at the library's own types, as C++ instantiates a template in
  every translation unit that uses it;
- each monomorphic definition of another library is imported from that
  library's module;
- handlers travel as evidence, so no handler crosses a module boundary as a
  global; the one global modules share is the yield record of control
  operations, which a fixed module, `snail.control`, declares and exports.
  A build links it first when the program has control effects, and every
  module that tests or sets the record imports it, so a yield crosses
  modules as it crosses functions.

The checker settles each library's types before it checks the libraries
that import it, so a definition's type comes from its own library and not
from how an importer happens to use it.

A **session** (`src/snail-core/compiler/session.sld`) compiles a program again
and again, as the development loop does, keeping everything in memory:

- The expander replays a library, adding what it added before, when its
  declarations read the same and its imports show the same interfaces. A
  library that derived instances loads the implicit libraries first, as its
  expansion did, so its run follows theirs in every build.
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

Snail-Core types are checked at compile time, each library against the
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

`(snail-core wasm)` is `dlopen` and `dlsym`. It loads a module from a file,
linked against the runtime, the program's own modules and the modules
loaded before it, by name. A function the module exports comes out as a
`Funcref`, and `unsafe-cast` makes it a function of the type the context expects:

```scheme
(let* ((cell (load-module "cell" "build/cell.wasm"))
       (run (ann (unsafe-cast (module-export cell "cell:run")) (-> I64 I64))))
  (run 41))
```

`unsafe-cast` is a primitive. It wraps the reference in a closure whose
code casts it to the WebAssembly type of a Snail-Core function of the
expected type, which takes the evidence first, and calls it with the
handlers in scope where the closure is called. The cast is the only check:
the engine traps when the WebAssembly types differ, and nothing compares
Snail-Core types, so the unsafe assumption is visible where it is made.
`tests/dynamic/host.sld` runs this example on a module from another
program's build, and `tests/programs/wasm.sld` loads a module it writes
itself.

The Node runner provides the `wasm` effect for both builds. A statically
linked program exports nothing of its runtime, so what it loads can link
only against the host. Browser hosts do not provide it yet: loading is
synchronous, and a page reads files asynchronously.

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
producer's text, `producer-text` in `(snail-core compiler inputs)`: the
library directories its imports resolve in, then its program. One table can
serve every target of a build, and two targets with different directories may
resolve the same recipe's imports to different libraries, so the directories
belong to the producer. The entry keeps that text beside the bytes and a
lookup compares it, so a collision of keys is a miss, never another
producer's output. The expander looks a producer up there first; only a miss
reaches the provider, which prints the producer into scratch under the same
key and requests it. `add_generated` in `bootstrap/compiler.sld` reads a
printed producer back, checks that it has the key it was printed under, and
adds the output it wrote.

The planner owns target lookup, browser-kind checking, ordering and cycle
detection; the native builder runs the phases it hands out. A missing input
records a typed request and aborts the invocation. The Chibi driver services
the request after the compiler stack has unwound; the native builder, whose
compiles the plan has already supplied, never does.

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
(import (snail-core base) (snail-core syntax) (sample knot-helper) ...)
```

A producer that imports, along any chain, the library it generates is then an
import cycle, `library import cycle through sample.knot`, rather than producers
nesting without end; `tests/programs/error-generated-cycle.sld` is that case.
The producer's key leaves the `generating` line out, since what it writes does
not depend on the chain that reached it. The Chibi driver also
refuses a producer requested while it is being built, a backstop should the
stack ever miss a cycle.

### Missing inputs and retry

The compiler cannot start a producer or build another project target. It records
one pending `CompilerRequest` in memory and exits immediately, recording it
through the same unsafe bridge `compile-error` uses, so a pass that may need an
input keeps a pure signature. Artifact expansion and request signaling have no
filesystem effects; library loading and generated-source IO still do. The host
consumes the request after the compiler stack has unwound.

Standalone source builds service generated-library requests and reject artifact
requests with their source location: an artifact needs a project build. Chibi
and Node compiler entries publish the pending request in `request.datum` after
unwinding. `(snail-core compiler inputs)` owns this grammar:

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
successor Session. Cold project builds and `dev` use this boundary, but never
retry: `host/native/project.mjs` plans the build first, so a request from one of
its compiles names an input the plan missed, and is an internal error.

The builder passes each completed target's canonical file inventory to
`addArtifact` before the first phase that embeds it, and each producer's output
to `addGenerated` once the producer has run. Each reads the bytes once and
returns opaque immutable inputs. A failed read returns no replacement; the
preceding inputs remain usable. There is no artifact reply manifest or second
parsing step.

One table serves every phase of a build, and is passed to each `static`,
`modules` and `refine` call. These opaque values belong to their
originating compiler instance, like Sessions and Plans. Successful Sessions
retain only the per-library evidence already used for cache reuse.
Applications embed the bytes and need no runtime file access.

### Linked files

A linked file is an input of the build, but not of the compile: the module
depends on its name, which the source text spells and the build key already
holds, and on its presence, never on its bytes. A replayed library first
checks that each file it linked still exists; a missing one expands the
library again, which fails with the library and the path. Editing a linked
file therefore compiles nothing, while every build places every file from the
modules it returns, compiled or replayed: a project build copies them into its
new generation, and the development loop copies a file whose digest changed
and names each module's file for its text and its files' digests, so the page
relinks from the module that links the edited file and reads it again.

## Resident compiler boundary

`bootstrap/compiler.sld` exposes this compiler to a resident native caller.
`host/native/compiler.mjs` owns one Wasm instance and returns parsed project,
plan-phase and input-request records, static text, or modular text with a
successor Session. JavaScript retains Sessions, Plans and immutable build
inputs as opaque typed references; it cannot inspect them and must keep them with their originating compiler
instance. Each operation consumes its staged arguments
before doing work, and projected records become visible only on success.
Module text crosses directly through the runtime's existing String staging
buffer, alongside the other record fields; no temporary WAT files stand between
the resident compiler and assembler. A `module` record ends with the name and
path of each file its library links, and `static` answers a `link` record for
each file the program links, which the builder places beside the payload. The
host copies each field synchronously before another call can reuse the
buffer. Generated-library scratch remains
private to its build.

`plan` takes the project's directory, the standard libraries' directory, the
scratch directory producers are printed into, and the names of the roots to
build; `refine` takes the plan back with the build's current inputs. Each
returns an opaque Plan and the wave that can run now, in order: records
`produce INDEX KEY SOURCE` and `build INDEX NAME ENTRY`,
each followed by its library directories and the targets whose files it embeds,
then `waiting` if the plan goes on once this wave's producers have run. A
phase is compiled with the directories its record names, the same ones the
planner keyed its producers under.

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
trusted exit, before any other native work. Reset/projection traps retire
the instance too. Module initialization precedes the first reset.

Native failures carry `{severity, message, source}`; `source` is null or
`{file, line, column}`. Lines and Unicode scalar columns start at one. IO and
producer-input requests have no source record; internal no-location sentinels
are unlocated. A failing dependency reports its own origin. Printed
producer programs report their actual scratch source, while decoded generated
syntax retains the recipe location already established by expansion. No source
mapping is invented. CLI panic text is unchanged, and the compiler still stops
at its first error. These operations are implemented and tested.

## Supporting modules

| Path | Responsibility |
| --- | --- |
| `src/snail-core/compiler/driver.sld`, `bootstrap/compile.sld` | Typed source invocation shared by both hosts; compilation and post-exit request publication are separate entries. |
| `host/chibi/compile.scm`, `host/native/run-compiler.mjs` | Process unwind boundaries; publish missing-input requests only after trusted exit. |
| `host/chibi/snail-core/build.sld`, `scripts/link.scm` | Bootstrap, standalone generated libraries, tool builds and Binaryen/runtime linking policy. Each compile has private scratch; rebuilding shared tools holds `build/lock`. |
| `host/chibi/snail-core/process.sld` | Synchronous tool capture through private output files and a constant shell script with positional arguments. The parent reaps before reading or deleting files; stdin is EOF. This avoids Chibi 0.12 pipe-finalizer and sequential pipe-draining failures. |
| `crates/runtime/` | Rust scalar services: math, Unicode, float text, console and file IO, directory and path operations, the monotonic clock, panics. External resources use explicit handles; managed references remain engine-traced. |
| `crates/assembler/`, `host/native/assemble.mjs` | The `wat` crate compiled to Wasm for in-process text assembly. Programs do not carry the assembler. |
| `host/native/run-snail.mjs` | Node/WASI program execution, in a worker with a tuned GC heap, plus module loading and the task scheduler. JSPI stacks remain finite. |
| `src/`, `host/chibi/snail-core/`, `bootstrap/chibi-include/` | Every library that ships with the language, the compiler among them, and the separate stage-0 implementations of the three it imports. Stage 0's only search root is `bootstrap/chibi-include/`, one symlink per library the compiler reaches. |

Running project build plans and publication belong to the [project builder](projects.md),
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
