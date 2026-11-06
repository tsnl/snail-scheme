# Compiler architecture

The compiler has four main phases: expand, check, prepare, and emit.
Reading supplies located syntax to expansion. Preparation closes concrete
specialization and cleanup requests; emission consumes their fixed result.

```text
text ──read───▶ located syntax
     ──expand─▶ core program      unique names, resolved types, entity tables
     ──check──▶ typed program     every expression typed, instances chosen
     ──prepare▶ concrete code     fixed declarations, explicit control/cleanup
     ──emit───▶ WasmGC text ──assemble──▶ module, linked with the Rust runtime
```

Preparation has one registry and worklist for source definitions and generated
cleanup. It reserves each identity before visiting its body, then constructs
that concrete body once. Contextual restriction checks read these cached
originals. Control lowering may request further cleanup definitions; each new
batch closes before its bodies are checked and lowered. Existing bodies and
contracts stay fixed, so earlier checks remain valid.

`Prepared` contains fixed declaration metadata, concrete function definitions,
source-ordered initializers, statements and exports. Its expressions use a
restricted subset of the existing typed language: calls that may suspend have
named evaluation points and explicit cleanup. There is no separate CPS
language. The emitter receives neither source recipes nor a specialization
state, and reports no source-level errors. It selects Wasm representations and
constructs target instructions from those established facts.

This boundary deliberately retains concrete bodies during preparation rather
than reconstructing them during analysis. The [proposal below](#proposed-specialization-directly-to-wasmgc)
adds static provider contracts and tagged saved frames; those features remain
unimplemented. Reader and surface-syntax work is separate from these backend
phases.

Lexical borrowing uses these same passes. `with-borrow` expands to a local
binding of the borrow primitive; `Borrow<T>` remains a type in the checked
program. Checking recognizes immutable field projections, and ownership
checking freezes owners, confines aliases to lexical scopes and forbids
continuation capture while a loan is active. Generic instantiations accept
owned type arguments, preventing a borrow from being hidden in generic
storage. The emitter gives a borrow its referent's representation and emits
introduction and Copy extraction as identities. The
[ownership chapter](ownership.md#lexically-scoped-borrows) gives the contract.

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
  any pass stops a compile: the `compile` effect, whose `fail` takes
  `Diagnostics`, the first `SourceDiagnostic` (a location and a message) and
  any more, and whose `need` takes a request for an input. `compile-error`
  performs `fail` with one, and each entry point handles the effect with
  `compiling`, which turns the compile into a `Result`. A pass that can go on
  past an item that failed runs the item under `recovering`, which answers
  the item's diagnostics and passes a `need` on to the entry point. A location in line 0 is a file as a whole: a source that is not
  there, such as an entry an editor just deleted, fails with one
  (`read-source-file` in `inputs.sld`), so a resident builder reports it
  rather than stopping.
- **[`annotations.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/annotations.sld)** parses the optional
  annotation list into typed metadata with source locations. Each annotation
  owns its argument grammar; `doc` accepts literal strings and preserves
  repeated fragments. Unknown annotations fail here. The expander attaches
  metadata to canonical declarations and fields, and retains it through
  library replay. Annotations do not enter type identity or generated layouts.
- **[`core.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/core.sld)** defines the data the later
  passes share: `Type` (with effect rows), `Scheme`, class `Evidence`, the
  `Expr` tree, `Pattern`s, declared entities (`DataType`, `Class`,
  `Instance`, `Effect`), the `Program`, the global names of primitives,
  TypeIds for wire cases and `Any` values from one FNV-1a hash, the
  strongly connected components that the checker and the backend share, and
  the names of the core forms and builtin types that `(snail core forms)`
  provides. A `Program` is a value: the expander threads it through
  expansion, each addition handing back a larger one, and the later passes
  read it without effects. `expr-children` names the immediate structural
  children in traversal order, including lambda bodies. The checker,
  ownership pass, control analysis and reference collector share this
  inventory; each pass still decides which children execute or bind names.
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
  fold runs the steps in the order the scan found them. A step that fails
  leaves the context as it was, and the fold goes on, since pass 1 bound
  every name the later steps could miss; the library then fails with every
  failed step's diagnostics, before it joins the program. The first two
  passes stop at their first error. An instance's `dispatch` clause goes
  through `dynamic.sld`: its finite list of accepted types becomes a
  `Dispatch`, and each generated method recovers its first erased argument,
  checks all arguments of that type and calls an ordinary class method.
  Generated dispatch uses immediate `try-convert` matches, passing the
  recovered typed operands directly to the selected method. Binary policies
  recover both operands together when both are erased. Conversion lowering
  removes the temporary results and discarded errors; the final failure
  still reports the accepted domain and offending argument.
  Checking and specialization supply the same evidence as for a written
  instance; separate compilation needs no dynamic registry.
  Associated members become hidden trailing class arguments. Projections
  read the corresponding argument of an enclosing requirement, so no
  projection evaluator reaches later passes. `define-instance-set` gives
  instances a set identity; `with-instances` leaves a `ScopedInstances`
  node for checking. Binary `dynamic-instances` clauses resolve their
  finite source relation at declaration and emit ordinary instance methods
  that call those fixed implementations. One-sided and fully erased heads
  are grouped separately, each with its established output and effect union.

  The expander's only
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
  the global `prim:i32-add`, the name the checker, specialization and `emit-primitive`
  know it by, whose value is a `Primitive` of the declared scheme. A generic
  primitive names its variables, `(All (A) (-> (Vector A) I64 A))`. The form
  is accepted only in that library, whose body holds nothing else, so it
  adds no items and has no module; a session replays its values.

  The core form `link-handle`, which `link-file` in `(snail shell resource)`
  wraps, parses its path against the directory of the file it is written in,
  records a `LinkUse` on the library, and evaluates to a call to a global of
  the library's. Expanding an expression reads no file, so once the
  library's body has expanded, `bind-links` reads each file, which must
  exist or the build fails naming the library and the path, and binds the
  global to an import from `snail.runtime.link` named for the SHA-256 of
  its bytes, which answers the file's handle. Each module so records the
  content it links where its host must see it; the host reads a file only
  when a task asks for its bytes. The library's `LinkedFile`s, each a digest
  and where the build finds the file, enter its keys (see "Linked files"
  below). `library-links` and `program-links` give a build's files by
  library and in program order. The digest is
  [`sha256.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/sha256.sld)'s,
  computed over 64-bit words masked to 32 bits, so stage 0, whose integers
  do not wrap, names each file as Wasm does.

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
  Expected-type boundaries insert `Convert` nodes to or from `Any`, with
  the same final effect and ownership checks as explicit conversions.
  Unification itself remains structural. Call arguments constrain shared
  type variables from non-`Any` arguments first; numeric literals retain
  their constraints until ordinary defaulting.
  A use of a definition that requires `(Copy A)` asks that `A`'s
  instantiation be unrestricted, judged under the `Copy` variables of the
  definition containing the use. A class whose methods perform one of its
  parameters as a row, as `(Drop e T)` and `(Store e S)` do, is solved
  apart: its rows are found from its types rather than matched, from the
  structure of `T` for a drop or a clone (`lifecycle-rows`) and from the
  requirement or instance its types select otherwise
  (`determined-evidence`), whose requirements are solved with each
  variable its rows end with standing for a fresh row. Each row found is
  charged to the constraint's row at the call it was raised in, once that
  call is checked, so a signature is held to what its drops, clones and
  methods perform. Associated outputs use the same input-only selection:
  selected evidence establishes ordinary type equalities. Improvement runs
  to a fixed point when one output supplies another constraint's input;
  prerequisite resolution retains an active-goal path to reject cycles.
  Pending constraints keep their lexical instance-set identities, including
  constraints delayed until after leaving that scope. Checking consumes
  `ScopedInstances`; later passes see only the chosen evidence. Neither
  expected outputs nor effect rows select among candidates.

  The expander records a class's row parameters, those
  its methods write after `!` (`class-rows`), and checks that an instance
  writes each as a row, closed or ending with a variable its requirements
  give (`check-head-rows`).

  A library's checking goes on past a group, definition or statement that
  fails (`each-recovered`): the checker goes on from where it was before the
  item, and records the item's diagnostics and the names an unannotated
  group defines. An item that refers to one of those is not checked, since
  without its type its errors would only echo the first, and its names
  fail with it; a definition with a signature fails nothing else, as its
  users need only the signature. A library with a failure stops with every
  diagnostic in source order, before its constraints are solved, since a
  constraint may mention a type a failed item would have decided. So one
  compile reports every independent type error, and an instance error once
  they are gone. The checks that follow once the types are final, of
  conversions, closed functions, ownership and confinement, are each
  item's own (`check-final`), so they too report every item that fails.
  Nothing is emitted from a library that failed, and checking stops at the
  first such library.

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
  TypeId keys its type without rows, and specialization erases the ordinary ones
  next, so this is the last pass that could tell. It also refuses a
  closure that may not capture, a `fn` or a top-level function, that
  reads a local from around it (`check-closed`), so the backend knows such
  a closure has no environment. Those two are also all that `fit` gives
  the type `(Fn A B ! e)`, where an argument, an annotation or a signature
  expects one. At established Any boundaries `fit` inserts a conversion
  and charges `dyn-cast` for a fallible extraction; other types still
  unify strictly. Explicit conversion follows the same rule. Cleanup
  effects of owned values at yields are charged before lambda
  generalization, including when a local handler catches the yield but
  leaves a drop's effects unhandled. A selected class instance supplies
  its declared rows directly: cleanup inference and ownership share core's
  `selected-method-arguments`, so a pure method's open use row does not
  invent a suspension.
  Handler implementations and the handled body meet
  their result boundary through the same directed fitting rule.
- **[`conversions.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/conversions.sld)** lowers
  solved conversions before ownership checking. A single evaluation
  binds the Any; a type test guards extraction. Failure constructs a
  `CastError` and performs the already charged abortive operation, or
  returns `Err` for `try-convert`. The successful arm contains the
  checked value; `try-convert` is gone before specialization. Ownership
  and control see ordinary branches and calls,
  rather than a backend-only exception protocol.
  An immediate match with an `Ok` variable and an unbound fallback needs
  neither the temporary `Result` nor its discarded error. The same applies
  to a `Pair` of two such probes: both inputs are evaluated in source order
  before testing, and successful projections bind the typed operands.
  The fallback is emitted once. Escaping results, observed errors, and
  nested success patterns retain ordinary conversion and matching.
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
  records the plan in the drop's evidence; specialization asks again at the ground
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
- **[`specialize.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/specialize.sld)** owns
  concrete executable identities. Its immutable registry holds checked source,
  binding signatures, recipes, and pending names. A recipe is a source
  definition with concrete type arguments and selected class evidence, or
  generated drop, clone, or share glue. Reserving a name before visiting its
  recipe makes recursive functions and recursive cleanup finite. Imported
  monomorphic definitions retain their signatures and need no local body.

  `next-definition` consumes one recipe. A method reference becomes the
  instance method its evidence names; an alias such as `(define + i64-add)`
  becomes its target. A drop becomes `discard`, an instance method, or glue
  that drops linear fields in order, the last in tail position. A clone
  becomes a shared pair, an instance method, or glue that reconstructs two
  values from the cloned and shared fields. Glue recipes join the same queue;
  their bodies are built during preparation. A consumed recipe becomes its
  completed body. Original source bodies remain available to contextual
  checks; completed glue needs only a marker because its contract suffices
  for those checks. Freezing the registry projects binding metadata alone
  and removes the program's syntax items.
- **[`prepare.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/prepare.sld)** closes specialization,
  checks each fresh batch, and lowers the calls that may yield to a control
  handler. After specialization a row keeps
  only control effects, so a call may yield exactly when its callee's row
  names one, and a handle keeps what its body yields except to its own
  effect. An operation's row is its effect's and its latent row, so
  performing an operation whose type names a control effect is such a
  call. Such a call stays where it is when its value flows straight out
  of a function, a handle body or a let's value, so a tail call stays one;
  anywhere else a let names it, with the rest of the expression as the
  let's body, and names first each operand that runs before it, so those
  still run first. Each let whose value may yield is then marked with the
  dropper of the owners retained across its value, including owners an
  aborting branch never mentions. A tail call with otherwise abandoned
  owners receives a cleanup frame too. Ordered ownership lists preserve
  reverse binding order. `once` of a lambda with linear captures is marked
  with their dropper: a thunk closed over those values, whose drops join the
  specialization worklist, so a dropped
  resume or lambda releases what it held ("Droppers"). Abortive exits run
  the same droppers while unwinding, before entering the catch handler.
  `prepare-batches` drains all currently requested recipes before any
  contextual check reads a body. It checks the original expressions, then
  lowers them and queues any cleanup they discover. A later batch can inspect
  an earlier original under a new context, but cannot change its signature or
  body. Initializers are grouped by their source definition and ordered before
  emission, including total polymorphic initializers instantiated by another
  library. An item without control effects needs no rewrite. Preparation also refuses a
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
  operation's type names. Statements are checked before the definitions
  they request, and a requested body before its callees, so errors can point
  at the caller. Restrictions that depend on a helper's locally handled
  effects read its cached concrete original; inspection never instantiates
  another body or changes discovery. Context-sensitive answers are not cached.
  Recursive inspection falls back to the declared row, and runtime-selected or imported
  callees remain conservative. An exposed function must have a lambda as
  its definition, established from its reserved binding.
- **[`wasm.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/wasm.sld)** chooses representations and
  emits WebAssembly text from `Prepared`. Its module holds immutable
  `Declarations` plus Wasm output builders. It imports only the declaration
  types and control queries it uses; it cannot request source specialization.
  Function emission and the two main functions share that fixed metadata.
  Initializer execution order is already explicit, so the emitter has no
  initializer grouping table or changing semantic snapshots. Every monomorphic
  global initializes even when unused; all initializers precede statements.
  Library builds export monomorphic definitions and prepare imported generics
  locally. Scalars are Wasm numbers. An enum whose cases have
  no fields is an `i32`; other data are GC structs, and enum cases are final
  subtypes of a base holding the tag. A field holding a struct is laid out
  inline, as that struct's fields, so a nested value costs no second
  object and a cell's content lies in the cell; reading it whole builds
  one, and a nested pattern or a chain of accessors reads the fields where
  they lie ("Inline fields"). `Ref`'s content is a `mut` struct field, or
  several; `set!` and `replace!` write a place, a chain of field reads from
  a cell, into the slots of the cell, and a swap reads the old content
  before writing the new. Every field of a struct whose ground type is
  linear is `mut` too, since its reference has one owner: a replacement of
  one writes the field in place and answers the same reference, where an
  omega struct's is copied. Sequences are GC arrays. Functions are
  closures: a struct whose first field is a typed function reference and
  whose second is a nullable dropper, the thunk that drops its linear
  captures, with captured variables in a subtype; a frame saved at a yield
  point is such a closure too, and dropping a `FnOnce` runs its dropper
  ("Droppers"). An `Fn` is that function reference
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
  A module's `main` initializes its definitions and runs its body, and the
  two are exported apart as well, `main:init` and `main:body`, the body
  taking the evidence: a program's statements are one function the body
  calls, which the expander made of them (`with-one-body`), so a host that
  gives `main:body` to the scheduler's `tasks:start-main` runs them as the
  first task, where a yield saves the rest of the program as a frame.
  The host passes no evidence, so every exposed function has a wrapper that
  calls the definition with the empty evidence list; a `Unit` result is no
  result, as a foreign import of the function declares, so a module that
  imports an exposed function of another, as those the engine serves,
  links. In a program with
  control effects the wrapper first clears the yield record: the task loop
  goes on after a trap, and one that struck while a yield was in flight
  would otherwise leave the record set for the next task. A function
  exposed with `dynamic` has a wrapper of `Any` values and a signature
  instead ([plugins](#plugins)).
- **[`session.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/session.sld)** keeps the compiler
  running between builds: the expander replays libraries whose declarations
  and imports' interfaces are unchanged, and only libraries whose expansion
  changed are checked and compiled again. Its cache holds checked items,
  schemes, and emitted text. Checked generic bodies remain available when a
  new importer requests another specialization; cached concrete bodies are
  unnecessary. Input generators and immutable build inputs are passed to
  each build. Each `Built` module carries the files its
  library links, compiled this build or not, so a build places them all.
- **[`plan.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/project/plan.sld)** orders a project build's
  phases before any of them runs: building a target, and running a
  producer. A phase needs the producers its program's closure reaches, then
  the targets a discovery expansion finds it embeds. Nodes number in
  depth-first pre-order from the roots, `strong-components` puts each phase
  after what it needs, and a cycle is an error naming the targets around it
  from the one declared first, `artifact dependency cycle: client -> admin ->
  client`, with any producers on the way. A phase whose closure reaches a
  producer that has not run waits: `next-phases` hands out the steps of the
  order up to the first that waits, and `refine-plan` learns what the waiting
  steps need once those producers' outputs are supplied. The project builder,
  `(snail shell project build)`, resolves the project's targets and runs the
  plan wave by wave for cold and development builds alike. Planning is a
  project-tooling consumer of compiler discovery APIs; the compiler itself
  does not import it, so planner edits do not rebuild the bootstrap compiler.
  Chibi reaches the project parser and planner only through test-local
  symlinks; neither is in the bootstrap include tree.
- **[`compiler.sld`](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler.sld)** composes the passes, from a
  program's path to WebAssembly text with the files it links, a
  `WholeProgram`, or to one module's text per library. The driver writes the
  files a compile links to `links.datum` in the compile's directory, one
  `("DIGEST" "PATH")` per file, for the Chibi build to place.

<a id="proposed-lowering-to-typed-snail-core-subsets"></a>

## Proposed specialization directly to WasmGC

**Design for review, not implemented.** Lower the proposed
[capability model](effects.md#proposed-parameterized-effects) through the same
preparation/emission boundary. Preparation makes providers, continuation
entries and cleanup explicit in a restricted subset of typed Snail-Core;
emission chooses their Wasm functions and GC layouts. The original fused
emitter sketch is replaced by this boundary. No separate general-purpose CPS
language or compiler-owned optimizer is required.

```text
source
  -> expand       resolved Snail-Core
  -> typecheck    checked generic Snail-Core
  -> prepare      concrete definitions, explicit control and cleanup
  -> emit         Wasm functions, types and imports
  -> assemble     module bytes
```

Reading belongs to expansion. Assembly serializes the target; a Wasm
validator or engine checks its types. Preparation reserves a concrete code
identity before constructing its body. Functions, provider methods,
continuation entries and cleanup routines use the same discovery mechanism.
Emission receives the closed result rather than requesting source definitions
while choosing target instructions.

Type checking comes first because capability selection, field projection,
control requirements and ownership depend on types. It checks each generic
body against its declared constraints, including entry and resumption
requirements. Preparation consumes that evidence and concrete instantiations.
Use fixed representation and control rules, with ordinary instruction
optimization left to the Wasm engine. This removes a compiler-owned optimizer,
control summary solver and continuation-recovery analysis from the baseline.

### Wasm as the lower representation

Build Wasm declarations and instruction trees with symbolic references.
They are ordinary Wasm, with no source effect rows, typeclass operations,
`ctl`, `handle`, or implicit provider lookup. Provider captures become
explicit parameters or GC fields. Places become managed roots, fixed field
indices and, where permitted, one runtime array index. Closure code becomes
functions with explicit environment parameters; environments use GC types.
Source matches become tag tests, projections and structured branches.

Keep function signatures, locals, type references and source locations
available while constructing each body. The current `Wat` tree and module
builder provide a starting point. Emit instructions in the checked evaluation
order and retain their structure until assembly. Substitution resolves types,
providers and field indices; it does not evaluate arbitrary source functions
at compile time. Correctness and the promised representations must hold
without engine inlining or any other optional optimization.

The following is a schematic grammar for the target bodies in folded WAT
notation. It identifies the constructs the builder needs; the
[WebAssembly grammar](https://webassembly.github.io/spec/core/text/instructions.html)
defines their full syntax and typing. `name` is a symbolic identity,
`ValueType` is a concrete Wasm value type, `*` means zero or more, and `?`
marks an optional form.
Imports, exports, globals and recursive GC type declarations use the standard
Wasm forms.

```text
Function  ::= (func name TypeUse Local* Instruction*)
TypeUse   ::= (type name) Param* Result*
Param     ::= (param name ValueType)
Result    ::= (result ValueType)
Local     ::= (local name ValueType)
BlockType ::= (param ValueType*)? Result*

Instruction ::= (local.get name)
              | (local.set name Instruction)
              | (call name Instruction*)
              | (return_call name Instruction*)
              | (call_ref name Instruction*)
              | (return_call_ref name Instruction*)
              | (block name BlockType Instruction*)
              | (loop name BlockType Instruction*)
              | (if BlockType Instruction
                    (then Instruction*) (else Instruction*))
              | (br name Instruction*)
              | (return Instruction*)
              | (op immediate* Instruction*)
```

`op` ranges over the supported Wasm numeric, reference, struct and array
instructions, constants, and other required target instructions. It cannot
hide a source-level handler or continuation-capture operation. Resource
cleanup uses explicit generated or imported calls; Wasm `drop` alone only
discards an operand. Calls must satisfy the recorded signatures, including
the compatible result types required by tail calls.

### Stage invariants

| Output | Established facts |
| --- | --- |
| Expanded program | Macros are expanded and names and declarations are resolved. |
| Checked program | Generic value types, provider and control contracts, ownership, paths and foreign boundaries are checked. Source effect information is still available. |
| Compiled Wasm | Every referenced instance has a concrete signature and representation. Provider arguments, control transfer, capture storage and cleanup are explicit Wasm. No source effect types remain in target signatures. |

Only the checked program and the accumulating Wasm module need persistent
program representations. An entry for a continuation references a point in
the checked body and its remaining expression context. It does not require
copying that body into a CPS tree. Captures and layouts are definition
metadata; preserve source locations through generated code.

### A worklist of specializations

Seed requests from initialization, entry points, exports and required
adapters. A key contains the checked code identity and its static arguments:
concrete value types, provider implementations, their control families and
callable identities, plus the current frame family when compiling suspending
code.
Captured values and dynamic delimiter identities are runtime arguments.
Providers with the same implementation and different captured strings
therefore share code.

The orchestration is schematically:

```text
request(key, state):
    if key is reserved: return its symbol, state
    reserve a symbol and an interface from the instantiated checked contract
    return the symbol, state with this definition queued

prepare(checked):
    state = request_roots(checked)
    while state has pending definitions:
        definitions, state = instantiate_pending_graph(state)
        check_original_bodies(definitions, state)
        lowered, state = lower_control_and_cleanup(definitions, state)
        retain(lowered)
    return fixed_declarations_and_ordered_code(state)

compile(checked):
    return emit(prepare(checked))
```

Thread reservations, pending requests and prepared code through preparation.
An ordinary recursive call finds its existing identity. Concrete source bodies
are constructed once and retained while contextual checks may inspect them;
those checks do not cache answers across different resumption contexts.
Cleanup discovery can extend the graph without changing an existing body or
contract. Reaching the fixed point means every requested definition is
prepared. Emission then constructs target helpers and GC types from fixed
contracts; finishing orders GC recursion groups and resolves module indices.

Instantiate the checked control contract before emitting callers. If that
contract permits escaping control, use the yield protocol even when body
analysis might prove a more efficient interface. This gives recursive calls
stable interfaces without another call-graph analysis. `fun` syntax alone
does not establish direct return, and locally handled control still needs
lowering inside an outwardly direct function.

### Selective control lowering

Keep unsplit branches, loops and direct calls as Wasm control flow. At a
non-tail call whose instantiated contract permits escape, give its remaining
computation a named entry. Use the same entry on the normal and resuming
routes, specialized for the providers each route supplies:

| Route | Generated behavior |
| --- | --- |
| Normal return | Tail-call the remaining computation with the result and its live inputs as arguments. |
| Yield | Store those inputs in a GC environment, append a frame to the pending yield, and propagate it to the delimiter. |
| Resume | Read the saved inputs and invoke the entry specialized for the resumer's outstanding providers. |

This allocates a continuation environment only on the yielding route. Use
free variables of the remaining computation, including cleanup obligations,
to determine captures. Share entries at joins instead of copying suffixes.
Compile each delimiter body as a separate entry, keeping its catcher outside
the suffix tail calls. An entry and its suffixes share a result interface.
When a split crosses a loop, give the loop header an entry too: a resumed
iteration tail-calls it instead of branching into a different Wasm function.
A tail call with no pending work forwards the transfer and needs no frame;
delimiter handling and cleanup count as pending work.

The checker must establish which routes exist. A transition that cannot
return normally needs no entry specialized for the original providers.
For example, `yield(); write(...)` can require IO only on resumption when
every path to the write passes through that transition. If normal return is
possible, its context must also satisfy the suffix's requirements. The
emitter consumes this evidence; it cannot guess that a missing provider
makes a route unreachable.

Use the implemented yield-bubbling protocol as the baseline: a pending
record identifies the delimiter and operation, carries its arguments and
collects frames while calls return. Callers check the record before using
the returned placeholder; the matching delimiter consumes it before invoking
the handler. Static selection fixes handler code, while the delimiter token
still distinguishes recursive installations. The runtime must isolate this
pending transfer across execution contexts and host entry, and never expose
a placeholder as a source value.

This uses join sharing and allocation on yield from
[Koka's generalized evidence passing, sections 2.9–2.11](https://www.microsoft.com/en-us/research/wp-content/uploads/2021/08/genev-icfp21.pdf).
The simpler baseline pays a tail call on normal return rather than duplicating
and optimizing the suffix into that path. It requires no escape analysis,
contification or inference that a `ctl` handler happens to resume in place.
Static provider specialization and effect transitions still need their own
correctness argument.

The compiler already emits `return_call` and `return_call_ref`, and the
native engine enables tail calls. These
[instructions](https://webassembly.github.io/spec/core/syntax/instructions.html#control-instructions)
bound stack use for tail transfers; generated code remains responsible for
capture, deep reinstatement and cleanup. A handler that resumes and then
does more work uses an ordinary call or saves that remaining work in turn.

Foreign functions keep their declared host ABI. Initialization, exports and
foreign callbacks need checked adapters where they meet the internal control
protocol. No suspension may cross a foreign boundary that lacks such a
protocol.

### Saved frame representation

Use **tagged GC frames with typed, provider-specialized dispatchers**.
This is a restricted use of
[defunctionalization](https://www.brics.dk/RS/01/23/BRICS-RS-01-23.pdf): a
saved code point becomes a constructor, and a dispatcher selects its code.
It applies to saved control frames, not all source callables, and introduces
no additional program representation or whole-program transformation pass.

Assign a nominal family `F` to each checked provider-scope instantiation
whose body can be suspended, including control delimiters. Its members are
the frame templates that can reach that boundary, discovered by the emission
worklist. Recursive installations reuse the family. A frame
kind identifies a source continuation point, concrete value types and capture
layout. Neither the dynamically accumulated chain nor the resumer's
outstanding provider implementations are part of that identity. Different
resume sites therefore agree on stored data even when they request different
code specializations. A template may belong to several families. Assign its
kind tag once for the linked program; the checked control targets determine
which families register it. A statically selected control provider identifies
its nominal family as well as its method code and contract. Its runtime
installation token remains an ordinary parameter.

Compilation carries the current segment family as a static argument. Calls
that can save frames inherit it; entering a provider scope replaces it with
that scope's nominal family. A crossed scope is represented in its parent's
family by a scope frame. The dynamic list of ancestor scopes is never a
static argument.

The logical typing is:

```text
Frame_F<A, B>       a member of F accepting A and producing B
Chain_F<A, R>   ::= End                              when A = R
                 | Link(Frame_F<A, B>, Chain_F<B, R>) for some B
Saved_F<A, R, C>    a one-shot chain, its deep delimiter and its contract C
```

`C` retains invocation, resumption and cleanup requirements. Intermediate
`B` is existential: each generated constructor fixes it. These are compiler
invariants, not a proposed source GADT feature. Only generated constructors
can create or splice chains, and they must match the adjoining value types,
scope and effect contracts. The runtime cannot manufacture arbitrary chains.

The physical layout is a finite set of WasmGC struct types, schematically:

```text
Frame:
    kind: i32
    next: mutable nullable reference to Frame

Frame_k extends Frame:
    capture_1: concrete Wasm storage type
    ...

Scope_h extends Frame:
    inner_first: mutable nullable reference to Frame
    inner_last: mutable nullable reference to Frame
    delimiter: installation token, for control scopes only
    handler_captures: concrete fields for that handler

Saved_F:
    first: mutable nullable reference to Frame
    last: mutable nullable reference to Frame
    delimiter: reference to the captured installation's token
    handler_captures: concrete fields for this family's handler
```

The link and captures occupy one allocation per frame. A null link ends the
chain. The last pointer permits constant-time append while unwinding and
splicing when resumption yields again; the last node's link is always null.
Runtime ownership permits updating these links. Frame subtypes have fixed
fields and use ordinary
[Wasm recursive types](https://webassembly.github.io/spec/core/syntax/types.html#recursive-types).
An arbitrarily deep recursive call creates more nodes of the same types.

Frame storage contains no entry pointer specialized for the creator's ambient
providers. Instead, an invocation requests `run<F, A, R, P>`, where `P` is
the statically selected mapping from required capabilities to implementations.
Their runtime captures are ordinary parameters. For each admissible frame
kind with input `A`, its dispatcher casts to the concrete subtype, moves out
the captures, and calls the suffix specialized for `P`:

```text
case k:                         // k accepts A and produces B
    rest = detach_first(chain)
    value = suffix_k<P>(captures, input, provider_values)
    if a yield is pending:
        append_chain_to_pending_yield(rest)
        return placeholder<R>
    return_call run<F, B, R, P>(rest, value, provider_values)
```

Each runner has concrete Wasm argument and result types. Intermediate values
travel as typed parameters, including multiple Wasm values when required;
they need no universal box between frames. Every tail-called runner returns
the same `R`. An empty chain returns its input only in the `A = R` entry;
other empty-chain cases and invalid tags trap as compiler-invariant failures.
The private common frame reference hides a capture layout, not the value type
of an ordinary source callable or place.

For example, a continuation can contain `AfterYield(n)` with input `Unit`
and result `I64`, followed by `AfterStep` with input `I64` and result `Unit`.
The first runner computes `n + 1` and tail-calls the second with an `i64`.
The second calls the worker's selected IO implementation. Choosing another
IO implementation creates another runner specialization over the same frame
layouts. The tag selects a saved code point; effect method calls inside that
case have statically selected targets.

#### Nested scopes and ownership

A provider scope crossed by a yield to an outer delimiter saves one **scope
frame**. Its payload is the inner saved chain and the provider's ordinary
captures; a control scope also retains its installation token. Running the
scope frame reinstalls that provider around the inner chain, then continues
the outer chain under the outer providers. This preserves ordinary local
providers as well as control handlers. The root `Saved_F` reinstalls its own
delimiter in the same way. Outer outstanding providers come from the current
invocation. Repeated control installations have distinct tokens, even when
their code and frame family are identical. This is a chain of segments with
explicit scope boundaries; flattening all segments would lose those scopes.

Each scope frame is another typed member, accepting the inner continuation's
input and producing its delimiter answer. Its inner family is a nominal
reference, so nested scopes form a finite recursive type graph. The runner
requests the inner dispatcher with the appropriate static provider override
and explicit captured values, then restores the outer mapping. It does not
build a runtime provider lookup dictionary.

For a control scope, its reentry helper catches pending operations aimed at
its token and invokes the selected clause in its checked outer context.
The clause receives a fresh one-shot wrapper for the saved remainder;
resuming it reinstalls the handler again. A yield aimed elsewhere rebuilds
the scope frame and propagates outward. Ordinary provider scopes need only
the override and restoration, without a token test or a control clause.

Invoking or dropping `Saved_F` moves its chain out and clears both stored
links before executing user code. Static one-shot ownership distinguishes a
consumed handle from a valid empty continuation. Frames are detached as they
are consumed; capture ownership transfers to the suffix. If it yields again,
the new pending chain receives the still-unconsumed tail, without copying or
dropping that tail. When a nested scope is crossed, it is packaged again as
a scope frame before propagation continues outward.

Cancellation dispatches generated cleanup for each frame's owned captures,
in the checked unwinding order. Scope frames reinstall the same internal
providers for cleanup and then release the scope's owned captures. Outstanding
cleanup providers are supplied at the drop site and checked against the
separate cleanup contract. If cleanup may suspend, its generated continuation
owns the unprocessed tail through the same protocol. GC reclaims storage;
it does not run source cleanup or discharge linear ownership.

#### Finite discovery and storage boundaries

A family is closed for a linked program version. Imported generic bodies
carry frame descriptors and scope dependencies so downstream resume sites
can request their provider specializations. The worklist registers each
frame kind and each requested runner; a new member schedules a case for
compatible requested runners, and a new runner schedules its existing cases.
Each case is emitted once. Finalization assigns tags consistently across
producers and consumers and assembles the dispatch bodies. Family membership
is a cache dependency; adding a member rebuilds the affected dispatchers.

Keys use nominal families, source type instantiations and provider mappings.
Scope entry replaces bindings in a mapping; it does not add dynamic nesting
depth to the key. Runtime chain length and the sequence of previous frames
never enter keys. This terminates when the program has finitely many source
instantiations and provider combinations; unbounded polymorphic specialization
still needs a diagnostic.

At a heterogeneous queue boundary, explicitly package a closed sum of job
adapters with a common contract. Packaging instantiations register their
concrete saved families with the named package boundary, and the worklist
builds its cases. The worker switches on the case and calls its adapter and
family dispatcher specialized for the worker's providers. This is the
selected [queue representation](effects.md#queuing-a-continuation), not an
implicit universal `Fun` or `Ref`. Unknown runtime-loaded frame kinds are
outside this ABI; extending a family requires recompiling its consumers.

### Effect erasure and stored continuations

Source effect rows guide checking and emission, then disappear from Wasm
signatures. Their obligations become provider arguments, control paths and
cleanup calls. Preserve the checked source interfaces and diagnostic
provenance. The emitter follows checked evaluation and cleanup order, so it
needs no second effect analysis over Wasm. Wasm validation cannot establish
the source ownership or effect invariants.

An ordinary closure or resumption obtains its outstanding providers at its
invocation site. Internal handler scopes captured with the computation are
restored. Compiling a suspension under provider A must not hardwire its
outstanding calls to A if its resumer will supply B. Keep a checked
continuation template and its capture layout until invocation requests the
appropriate provider specialization, using the same request mechanism as
an ordinary generic closure. Its emitted entry points must agree with the
stored environment's representation.

Separate compilation therefore retains the checked generic bodies and
implementation identities needed to request downstream specializations.
Cache keys include the selected implementations, body dependencies, frame
families, layouts and calling interfaces. Runtime-loaded code cannot silently
substitute an erased provider ABI or extend a saved family's dispatch table.

### Recursion and representation

Ordinary recursion reuses a reserved specialization. Recursive continuation
chains require finite types with runtime links; do not put their dynamically
growing history into specialization keys. True growth in type instantiations
also needs a termination policy and a diagnostic. Finite keys and stable
interfaces are prerequisites for reaching the worklist fixed point;
optimizing emitted code later cannot repair nonterminating specialization.

The [place](types.md#proposed-places-and-locators) and
[queue](effects.md#queuing-a-continuation) contracts still apply. All
place-backed storage uses the GC heap, including locals; required backing
allocations cannot be replaced with Wasm locals. Paths have at most one
dynamic index at the leaf, and arrays reject unsupported struct-value
representations. Passing continuation inputs directly on a normal return
avoids a compiler-generated environment, not any required source allocation.

### Review points and validation

The saved-frame layout and dispatch policy above are the proposed baseline.
The source transition rules still need a soundness argument, as do the
generated chain constructors and scope-preserving splice operations. Specify
pending-yield isolation across execution contexts before implementation.
A memoized emitter reduces backend machinery; it does not make the language's
type system trivial.

Check a direct and a control provider for one generic consumer, internal
handlers in outwardly direct functions, nested delimiters, and callbacks
that propagate control. Test queued resumptions with different invocation
providers, cleanup after cancellation, and rejection of effect-transition
mismatches. Exercise recursive specialization, bounded native-stack use on
tail transfers, runtime captures shared across calls, source-to-Wasm
locations, separate compilation and foreign adapters. Validate generated
Wasm and execute the baseline without relying on optimization. Inspect normal
paths for unnecessary continuation environments; measure tail-call overhead,
code size, compile time and allocations before adding compiler optimizations.
Exercise long recursive chains without growing the set of frame types, mixed
intermediate value types without boxing, different resumer providers over the
same layouts, nested scope reinstatement, re-yield with an unconsumed tail,
and one-shot cancellation. A queue must reject an undeclared family or a job
outside its invocation or cleanup bounds. Check that adding a family member
invalidates the dispatchers that depend on it.
Bootstrap and compiled execution must agree.

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
  generic code carries theirs into importers. It also includes the expanded
  global and instance identities: rebuilding an instance-bearing library
  gives its methods fresh names, so checked callers must select the new
  evidence and Wasm symbols even when only a signed helper body changed.
  It is hashed, as GHC uses interface hashes to avoid recompilation.
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

### Linking by hand

`load-module` and `load-plugin` link by the host's rules: the runtime, the
modules of the namespace by name, the host's services, and a stub for a
host function the host lacks. A loader written in Snail-Core, such as an
engine linking a program from its manifest
([#660](https://github.com/tsnl/snail-scheme/issues/660)), decides those
rules itself with four operations, which the two hosts must answer alike
(`tests/programs/wasm-linking.sld` runs on both). `compile-bytes` compiles
a module; `module-imports` lists what it imports, each a module and field
name with its kind, function, table, memory or global, which the host
holds and Snail-Core reads back a character at a time, as names go the
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
module imports its handle under that name. A replayed library first checks
that each file it linked still has the digest it was expanded with; a
missing or edited one expands the library again, which fails for a missing
file with the library and the path, and otherwise binds the new digest. The
digests enter the library's checked-body and interface keys, as an artifact
stamp does, so an edit compiles the library and its importers, which may
specialize a generic function that calls one of its handles. Every build
places every file from the modules it returns, compiled or replayed, as an
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
session replayed keeps the bytes it was assembled into, and their digest,
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
| `host/chibi/compile.scm` | Chibi's unwind boundary, which turns a failure into the same status. |
| `crates/snail/` | `build/snail`, a native executable embedding wasmtime, which runs programs that need only WASI, linked files and module loading by `run-snail.mjs`'s protocol, the compiled compiler among them, when `SNAIL_ENGINE=wasmtime`; it precompiles the compiler to a `.cwasm`. See [the bootstrap](bootstrap.md#the-native-executable). |
| `host/chibi/snail/stage0/build.sld` | Bootstrap, standalone generated libraries, tool builds and the native assembler/linker entry point. Each compile has private scratch; rebuilding shared tools holds `build/lock`. |
| `host/chibi/snail/stage0/process.sld` | Synchronous tool capture through private output files and a constant shell script with positional arguments. The parent reaps before reading or deleting files; stdin is EOF. This avoids Chibi 0.12 pipe-finalizer and sequential pipe-draining failures. |
| `crates/snail-core-support/` | Rust scalar services: math, Unicode, float text, console and file IO, directory and path operations, the monotonic clock, panics. External resources use explicit handles; managed references remain engine-traced. Its `assembler` feature builds the toolchain's runtime, which tools written in Snail-Core link (`build-toolchain-tool`), with in-process assembly and static linking for `(snail shell assembler)`, shared by the native executable. |
| `host/native/run-snail.mjs` | Node/WASI program execution, the compiled compiler's included, on Node's main thread, plus module loading; it drives the program's task scheduler through `host/browser/tasks.mjs`, as the page does. A trap is status 2 and a WASI exit its own, as on wasmtime. |
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
