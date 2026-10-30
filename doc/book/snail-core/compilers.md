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

All compiler modules live in `src/snail/shell/compiler/` and are written in typed
Snail-Core: they import only `(snail core base)`, `(snail core table)` and `(snail core io)`, so the
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

- **[`read.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/read.sld)** turns text into `Syntax`:
  atoms, identifiers and forms, each with a `Loc`. It is a recursive descent
  over a vector of characters; a line table recovers line and column only
  when a location is needed. Its lexemes, what starts at an index and where
  it ends, never fail, and the reader reports what it rejects in them;
  `(snail shell highlight)` classifies text with the same functions. It also
  decodes the bytes a `generate-library` producer writes, the encoding
  `(snail shell syntax)` defines, straight into `Syntax`. It declares how
  any pass stops a compile: the `compile` effect, whose `fail` takes a
  `SourceDiagnostic`, a location and a message, and whose `need` takes a
  request for an input. `compile-error` performs `fail`, and each entry point
  handles the effect with `compiling`, which turns the compile into a
  `Result`.
- **[`core.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/core.sld)** defines the data the later
  passes share: `Type` (with effect rows), `Scheme`, class `Evidence`, the
  `Expr` tree, `Pattern`s, declared entities (`DataType`, `Class`,
  `Instance`, `Effect`), the `Program`, the global names of primitives,
  TypeIds for wire cases and `Any` values from one FNV-1a hash, the
  strongly connected components that the checker and the backend share, and
  the names of the core forms and builtin types that `(snail core forms)`
  provides. A `Program` is a value: the expander threads it through
  expansion, each addition handing back a larger one, and the later passes
  read it without effects.
- **[`expand.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/expand.sld)** is the only pass that
  knows binding forms. It loads libraries, replacing each `include-bytes`
  with the byte vector literal of its file, resolves every identifier through
  environments, and runs `syntax-rules`. Hygiene is renaming: each identifier
  a template introduces gets a mark that is unique to the expansion and, when
  unbound, resolves in the macro's own environment. Top levels expand in two
  passes so definitions may refer to later ones; local bodies are
  sequential. Declarations become entities in the program tables: a struct
  or enum is a `DataType` whose fields say whether they are mutable, with
  an accessor for each field and, depending on mutability, a pure
  replacement or a setter and a swapper. Derived
  wire instances are generated as ordinary instance syntax that resolves in
  the implicit libraries, `(snail shell wire)` among them, which the build's
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

  Every library is a file but `(snail core forms)`, which the expander
  serves from memory: the core forms, the builtin types, and the builtin
  `mut` and `host` effects. The operations the backend implements directly are
  declared in
  [`src/snail/core/primitive.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/core/primitive.sld),
  read and resolved like any library. `(primitive i32-add (-> I32 I32 I32))`
  declares one, as `extern` declares a foreign function: it binds the name to
  the global `prim:i32-add`, the name the checker, mono and `emit-primitive`
  know it by, whose value is a `Primitive` of the declared scheme. A generic
  primitive names its variables, `(All (A) (-> (Vector A) I64 A))`. The form
  is accepted only in that library, whose body holds nothing else, so it
  adds no items and has no module; a session replays its values.

  The core form `link-file`, which `link-bytes` in `(snail shell resource)`
  wraps, parses its path against the directory of the file it is written in
  and records a `LinkedFile` on the library: the name the payload ships it
  under, the library's key and the canonical path, and where the build finds
  it. Its value is a call to an import from `snail.runtime.link` under that name,
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
- **[`check.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/check.sld)** is Hindley-Milner inference
  with effect rows. Unannotated top-level definitions are checked in
  dependency order (core's `strong-components`). Each instantiation records its type
  arguments and an evidence hole per class constraint. While items are
  checked, constraints are only recorded; a group of functions quantifies
  the metavariables nothing else still mentions. Libraries are checked one
  at a time; when a library is checked, its literals default, and each
  class constraint is solved once, filling its hole. Rows unify as sets with
  open tails. Matches are checked with Maranget's usefulness algorithm.
  A use of a definition that requires `(Copy A)` asks that `A`'s
  instantiation be unrestricted, judged under the `Copy` variables of the
  definition containing the use. `(Drop e T)` and `(Clone e T)` are
  solved apart: the row is found from `T` (`lifecycle-rows`), and each row
  a drop or a clone performs is performed in `e`, at the call it was raised
  in once that call is checked, so a signature is held to what its drops
  and clones perform.

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
  can hold mutable storage. And once a library's types are final, it
  refuses a `type-convert` or `type-test` whose types hold a function that
  performs effects, or a type variable (core's `hidden-effects`): an `Any`'s
  TypeId keys its type without rows, and mono erases the ordinary ones
  next, so this is the last pass that could tell. It also refuses a
  closure that may not capture, a `fn` or a top-level function, that
  reads a local from around it (`check-closed`), so the backend knows such
  a closure has no environment. Those two are also all that `fit` gives
  the type `(Fn A B ! e)`, where an argument, an annotation or a signature
  expects one; every other value meets its expected type by unifying.
- **[`capabilities.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/capabilities.sld)** finds
  structural properties of types from their declared fields: whether a
  type is first-order data, which dynamic exports require; whether it
  is linear, given the type variables a definition requires `Copy` of,
  which the checker and ownership use; and what dropping a value of it
  runs. Ordinary arrows say nothing about their captures, and a mutable
  field, a `Ref`'s among them, is a shared handle whatever it holds. The
  linear search follows each declaration's immutable fields with its
  arguments bound, once per instantiation, so an argument held only in a
  `Ref` leaves the type unrestricted; a declaration that says
  `(deriving Move)`, or has a Drop instance, is linear whatever its fields.
  `lifecycle-plan` says what a drop or a clone runs: something trivial,
  which discards or shares the value, an instance's method, or glue, or
  why it cannot run, as for a clone of a `FnOnce`. The checker asks it for
  the rows, under the definition's `Copy` variables and requirements, and
  records the plan in the drop's evidence; mono asks again at the ground
  type, and `plan-covers?` checks that the ground plan runs no more than
  was charged. It cannot, since a `Copy` variable is bound only to an
  unrestricted type, where a signature or an instance is used, so grounding
  can only turn glue trivial, and instances are found by name in both. An
  instance that requires `(Drop e A)` performs its head's labels and what
  dropping the type it is given at `A` performs, and so does an instance
  of an ordinary class with that requirement, wherever it is used.
- **[`ownership.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/ownership.sld)** checks each
  library's linear values once its types are final, before
  specialization. It follows each path through a body: a use consumes a
  linear local, and a second use, or one still live where its scope ends,
  is an error. Alternatives must consume the same values, except those
  that panic or reach `Never`, which never return. It inserts nothing.
  Only one-shot closures can own linear captures. Records inherit the
  grade of their immutable fields, and a type variable is linear
  unless its definition requires `(Copy A)`, so each generic body is
  checked once, for every instantiation. A field operation applied to a
  linear local leaves it live, the place rule, and may not read or
  discard a linear value; a replacement instead consumes its record and
  answers it.
- **[`mono.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/mono.sld)** starts from the program's
  statements and values and copies each reachable definition once per ground
  instantiation. A method reference becomes the instance method its evidence
  names, and definitions that only rename another, such as
  `(define + i64-add)`, are replaced by their target. A drop becomes what
  releases its ground type: the primitive `discard`, an instance's method,
  or glue, a function made here once per type, which matches the value
  apart and drops each linear immutable field, the last in tail position.
  A clone becomes glue that pairs an omega value with itself, an
  instance's method, or glue that clones each linear immutable field and
  builds two values from the halves and the shared other fields. The
  pass's state, the copies requested and made and the glue, is a value
  that each step hands to the next, as the checker's is, so the order of
  the copies is the order of the steps, and the pass is a function of
  its input.
- **[`control.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/control.sld)** prepares the calls
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
  thunk, whose row the call discards; in dispatched work, which runs later
  under its task's own handler of `tasks` and may yield to `tasks` alone;
  in a procedure given to `inherit-handlers`, which may run after its
  handles have returned, unless a handle inside the procedure, or inside a
  function it calls, catches the yield, or the procedure is a `resume`
  closed in its own handler's implementation; and
  in the implementation
  of an operation declared without `ctl`, which returns into a handled
  body that tests for a yield there only to the control effects the
  operation's type names. Items are checked from the last back, since a
  copy of a generic comes before the code that made it, so a refusal
  names the call that made a copy. It checks, too, the one rule the backend relies
  on that needs specialized definitions: an exposed function's definition,
  this library's or an imported one, has a lambda as its value.
- **[`wasm.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/wasm.sld)** chooses representations and
  emits WebAssembly text. Scalars are Wasm numbers. An enum whose cases have
  no fields is an `i32`; other data are GC structs, and enum cases are final
  subtypes of a base holding the tag. A mutable field is a `mut` struct
  field, written with `struct.set`; a swap reads the old content and writes
  the new in one helper. Every field of a struct whose ground type is
  linear is `mut` too, since its reference has one owner: a replacement of
  one writes the field in place and answers the same reference, where an
  omega struct's is copied. Sequences are GC arrays. Functions are
  closures: a struct whose first field is a typed function reference, with
  captured variables in a subtype. An `Fn` is that function reference
  alone, `ref.func` of a top-level function or of a `fn` compiled to a
  function of the same type, and calling one is `call_ref` with the
  caller's evidence. Tail calls become `return_call`. Every
  function takes the handlers in scope as its first parameter, a list of
  evidence nodes; `handle` extends the list for its body, and an operation
  walks it for its effect's node and runs the implementation with the list
  outside that node, or the default past the last: a host import, or a
  Snail-Core function run with the performer's list. The implementation of
  an operation with a latent row runs under a forwarding node for each
  effect the row names, which sends that effect's operations, and re-aims
  its yields, to the performer's handlers. `inherit-handlers` makes a
  `FnOnce` of a closure that holds its caller's list and the procedure,
  and calls the procedure under that list, whatever list it is called
  with. A linear value is its payload: a `FnOnce` is a closure, and the
  ownership check, not the representation, makes it one-shot. A control operation
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
  A call that may yield only to effects whose control operations all
  answer `Never` saves no frame: its test only leaves, no join is built for
  what follows it, and its implementation is handed no `resume`.
  Nothing reads a placeholder, and a program without control effects
  declares no record and tests nothing. Each GC type sits in
  the smallest recursion group it can, ordered by name, so modules that
  declare the same
  type declare the same group. Compiled one library at a time, a module
  exports its monomorphic definitions under their global names and imports
  other libraries' definitions. At the host boundary it
  stages final String and Bytes arguments and wraps exposed `(Option Any)`
  as a nullable opaque handover. Other exposed managed values keep their normal
  representation; the checker rejects linear parameters/results at that boundary.
  The backend reports no source errors, since each rule it relies on is
  checked before it runs. The expander makes sure a host function takes a
  String or Bytes argument only last, and that no struct contains itself,
  so every placeholder is a finite constant. The checker makes sure a
  conversion goes to or from Any, and that an exposure names a
  definition.
  The host passes no evidence, so every exposed function has a wrapper that
  calls the definition with the empty evidence list; a function exposed with
  `dynamic` has a wrapper of `Any` values and a signature instead
  ([plugins](#plugins)).
- **[`session.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/session.sld)** keeps the compiler
  running between builds: the expander replays libraries whose declarations
  and imports' interfaces are unchanged, and only libraries whose expansion
  changed are checked, specialized and emitted again. Cached emissions keep
  their monomorphic items so handler capture proofs can be rechecked against
  current helper bodies without regenerating unchanged Wasm text. Input
  generators and immutable build inputs are passed to each build; sessions
  retain only compilation evidence. Each `Built` module carries the files its
  library links, compiled this build or not, so a build places them all.
- **[`plan.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/plan.sld)** orders a project build's
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
- **[`compiler.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler.sld)** composes the passes, from a
  program's path to WebAssembly text with the files it links, a
  `WholeProgram`, or to one module's text per library. The driver writes the
  files a compile links to `links.datum` in the compile's directory, one
  `("NAME" "PATH")` per file, for the Chibi build to place.

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
and again, as the development loop does, keeping everything in memory:

- The expander replays a library, adding what it added before, when its
  declarations read the same and its imports show the same interfaces. A
  library that derived instances loads the implicit libraries first, as its
  expansion did, so its run follows theirs in every build. Its instances
  are made of their names, so it replays only while their interfaces are
  the ones it derived against, which its checked-body key and its interface
  include, as they include the stamp of a library that embeds artifacts.
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
     ((Ok run) ((ann (unsafe-cast run) (-> I64 I64)) 41))
     ((Err error) (panic (load-error-message error)))))
  ((Err error) (panic (load-error-message error))))
```

`unsafe-cast` is a primitive. It wraps the reference in a closure whose
code casts it to the WebAssembly type of a Snail-Core function of the
expected type, which takes the evidence first, and calls it with the
handlers in scope where the closure is called. At an `Fn`, `(ann
(unsafe-cast run) (Fn I64 I64))`, the cast is the whole value, with no
closure around it. The cast is the only check: the engine traps when the
WebAssembly types differ, and nothing compares Snail-Core types, so the
unsafe assumption is visible where it is made.

### Plugins

A plugin is a program built apart from the one that loads it, compiled one
library at a time and named by its `modules.json`. Types cannot be loaded:
the plugin and the program share the types they pass by importing one
declaration of them, and only functions cross. The plugin marks each
function it offers:

```scheme
(: summarize (-> Project Report))
(define (summarize project) ...)
(expose summarize "summarize" dynamic)
```

and the program looks it up at the type it expects:

```scheme
(match (load-plugin "build/plugin/modules.json")
  ((Ok plugin)
   (match (ann (plugin-function plugin "summarize") (Result (-> Project Report) LoadError))
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
`Any`'s nothing of what it holds. And it is pure. Mono erases every effect
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
takes the result out of one. The policy is a Snail-Core function,
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
`snail.runtime.native.process` and `snail.runtime.native.develop` on Node,
and `snail.runtime.browser.screen`, `.events` and `.storage` on the page.
The Rust support module, built from `crates/snail-core-support`, is
`snail.core.support`, and the compiler's control module
`snail.core.control`. A library named under `(snail runtime …)`, or
`(snail core support)`, would have one of the hosts' names as its module
key, and the program's modules would import it in place of the host's
interface, so a loader refuses a library linked under such a name, at
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
(import (snail core base) (snail shell syntax) (sample knot-helper) ...)
```

A producer that imports, along any chain, the library it generates is then an
import cycle, `library import cycle through sample.knot`, rather than producers
nesting without end; `tests/programs/error-generated-cycle.sld` is that case.
The producer's key leaves the `generating` line out, since what it writes does
not depend on the chain that reached it. The Chibi driver also
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
source error into `(Err (Failed diagnostic))`. Artifact expansion and request
signaling have no filesystem effects; library loading and generated-source IO
still do.

A compile with no one to supply an input runs under `unsupplied`: a discovery
expansion, which records artifact uses instead of asking for them, and the
development loop, whose plan has run every producer its program reaches. There
a producer request is an internal error, and an artifact request is the
program's own error at its use, as in a standalone build; a source error goes
on to the caller's handler. The development loop's `build!` reports one as a
failed build, as it does a panic the host caught.

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

The resident compiler's entries handle `compile` too: a request sends its
`generate` or `artifact` record and the entry returns what it was given, so
`host/native/compiler.mjs` finds the record after a normal return and throws
`CompilerFailure` with it as `request`. No request file is written or parsed,
and nothing traps. Each invocation clears diagnostic state before work. Trusted exits preserve the instance but return no
successor Session. `dev` uses this boundary, and cold project builds call the
same compiler in their own process (`(snail shell project build)`). Neither
retries: each plans the build first, so a request from one of its compiles
names an input the plan missed, and is an internal error.

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

A source error is the `compile` effect's `fail`, which each entry handles:
it sends the diagnostic's record and returns what it was given, so
`host/native/compiler.mjs` finds the record after a normal return and throws
`CompilerFailure` with it as `diagnostic`, and nothing traps. The compiler's
own exit 1, from a panic or a checked IO path, follows resource cleanup too,
and allows another call with the last successful Session; it carries the
message the compiler printed and no diagnostic record. Arbitrary Wasm or
imported-function traps retire the instance. This distinction comes from the
runtime exit path, not from finding a familiar string. Failure to read the
printed diagnostics is terminal too: the worker cannot reuse a retired
compiler.

Native failures carry `{severity, message, source}`; `source` is null or
`{file, line, column}`. Lines and Unicode scalar columns start at one. IO and
producer-input requests have no source record; internal no-location sentinels
are unlocated. A failing dependency reports its own origin. Printed
producer programs report their actual scratch source, while decoded generated
syntax retains the recipe location already established by expansion. No source
mapping is invented. The command-line driver prints a diagnostic as the
compiler always has, `FILE:LINE:COLUMN: MESSAGE`, and exits with status 1, and
the compiler still stops at its first error. These operations are implemented and tested.

## Supporting modules

| Path | Responsibility |
| --- | --- |
| `src/snail/shell/compiler/driver.sld`, `bootstrap/compile.sld` | Typed source invocation shared by both hosts; compilation and post-exit request publication are separate entries. |
| `host/chibi/compile.scm`, `host/native/run-compiler.mjs` | Process unwind boundaries; publish missing-input requests only after trusted exit. |
| `crates/snail/` | `build/snail`, a native executable embedding wasmtime, which runs the compiled compiler by `run-compiler.mjs`'s protocol, and programs that need only WASI, linked files and module loading by `run-snail.mjs`'s, when `SNAIL_ENGINE=wasmtime`; it precompiles the compiler to a `.cwasm`. See [the bootstrap](bootstrap.md#the-native-executable). |
| `host/chibi/snail/stage0/build.sld`, `scripts/link.scm` | Bootstrap, standalone generated libraries, tool builds and Binaryen/runtime linking policy. Each compile has private scratch; rebuilding shared tools holds `build/lock`. |
| `host/chibi/snail/stage0/process.sld` | Synchronous tool capture through private output files and a constant shell script with positional arguments. The parent reaps before reading or deleting files; stdin is EOF. This avoids Chibi 0.12 pipe-finalizer and sequential pipe-draining failures. |
| `crates/snail-core-support/` | Rust scalar services: math, Unicode, float text, console and file IO, directory and path operations, the monotonic clock, panics. External resources use explicit handles; managed references remain engine-traced. Its `assembler` feature builds the toolchain's runtime, which tools written in Snail-Core link (`build-toolchain-tool`), with in-process assembly for `(snail shell assembler)`. |
| `crates/assembler/`, `host/native/assemble.mjs` | The `wat` crate compiled to Wasm for in-process text assembly by hosts in JavaScript. Programs do not carry the assembler. |
| `host/native/run-snail.mjs` | Node/WASI program execution, in a worker with a tuned GC heap, plus module loading; it drives the program's task scheduler through `host/browser/tasks.mjs`, as the page does. |
| `src/`, `host/chibi/snail/`, `bootstrap/chibi-include/` | Every library that ships with the language, the compiler among them, and the separate stage-0 implementations of the three it imports. Stage 0's only search root is `bootstrap/chibi-include/`, one symlink per library the compiler reaches. |

Running project build plans and publication belong to the [project builder](projects.md),
watching and editor services to the [development toolchain](toolchain.md), and
task scheduling and resource ownership to the [runtime](../runtimes/index.md).

## Following and checking a change

`make test` exercises emitted Wasm; `make test-chibi` runs the compiler source
on Chibi. `make bootstrap` rebuilds from Chibi alone and compares the compiled
compiler's successive Wasm stages. Keep both hosts working: differences in
integer overflow, table iteration or evaluation order must not change behavior.
Backend changes need execution tests, not only successful compilation.
`make check` checks formatting; `mdbook build` builds the book.
The [getting-started guide](https://github.com/tsnl/snail-scheme/blob/main/doc/getting-started.md)
lists pinned tools and the Rust/browser checks.
