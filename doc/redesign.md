# Redesign: Lofi from a clean slate, and how to get there

> **Historical design, partly implemented.** [GitHub issues](https://github.com/tsnl/snail-scheme/issues)
> track open work; section 7 records this design's implementation history.
> The [language chapters](book/lofi/index.md) and [compiler architecture](book/lofi/compilers.md)
> describe implemented behavior.

This document designs Lofi as if starting over, then plans the path from the
previous compiler to that design.

## 1. Requirements

Lofi must:

1. Compile to WebAssembly, with proper tail calls.
2. Be a low-level language that is still pleasant: explicit representations,
   fixed-width scalars, predictable code generation, no hidden boxing.
3. Have one type system that can grow into dependent types and protocol types
   without being rebuilt.
4. Work in a distributed setting: types that cross a process, network or device
   boundary have stable identities and a schema both sides check.
5. Be an idiomatic pure functional language whose effects are tracked by the
   type system.
6. Support generic code that is checked once, at its definition ("templates
   with concepts"), alongside `syntax-rules`.
7. Support typeclasses and instances, including generic instances.
8. Be a Lisp: S-expressions, `define-library`, `define-syntax`/`syntax-rules`.
9. Replace `data` with explicit `struct` definitions, `enum` sums and `type`
   aliases.
10. Implement the compiler in the Scheme subset that Lofi itself accepts. Only the
    program entry point may differ between hosts, and preferably not even that.
11. Implement full, dynamically typed Scheme as a library that generates Lofi,
    using `generate-library`.

Garbage collection is acceptable. The [runtime contract](book/runtimes/contract.md)
extends this design with type-directed affine ownership, checked transfer
and reusable handlers. Its implementation is staged separately from the
original redesign; the book records what has landed.

## 2. Assessment of the starting point

### 2.1 What is reusable from today's compiler

- The backend idea: monomorphize, then emit WasmGC with `return_call`, then run
  Binaryen. Lofi on Wasm measured about 2× slower than Rust on Wasm, which is a
  reasonable baseline.
- The Rust scalar services for Unicode, float printing and parsing, and WASI I/O.
- The dynamic Scheme libraries: `datum`, `read`, `write`, `number`, `rational`
  and `integer`. They become the runtime for the generated Scheme of §6.
- Hygienic `syntax-rules` and `define-library` resolution, as behavior. The
  implementation is restructured (§4).
- The test discipline of executing raw and optimized Wasm.

### 2.2 What the review found structurally wrong

1. **Types stop at every boundary.** The application protocol is numbered `I32`
   words, the GPU layout is synchronized by hand, and the checker produces no
   artifact that a host can consume.
2. **The whole program is the only compilation unit.** All libraries are
   concatenated and checked together. Type tags are local to one module.
3. **The kernel grammar and its scoping rules are implemented three times**: in
   the expander, the frontend parser and the (now deleted) transfer receiver.
   Libraries are parsed speculatively, then parsed again after expansion.
4. **Two ad hoc polymorphism mechanisms**: typeclasses with concrete heads, and
   overload families. Overload selection is speculative unification that raises
   an exception on each mismatch, and it is repeated during specialization.
5. **No real program uses the type system.** Siegework encodes its domain as
   integers, and the compiler is untyped Chibi Scheme.

## 3. Language design

### 3.1 Syntax and libraries

Lofi programs are R7RS `define-library` forms. Lofi keeps Scheme's binding forms
(`define`, `lambda`, `let`, `let*`, `letrec`, named `let`, `if`, `cond`,
`case`, `when`, `unless`, `begin`) with their Scheme meanings, restricted by
types. `if` requires `Bool`. Lofi adds a small number of typed forms:

| Form | Meaning |
| --- | --- |
| `(: name type)` | Signature for a following `define`. |
| `(struct (Name param ...) [((field type) ...)])` | Nominal record type and its constructor, accessors and pattern. |
| `(enum (Name param ...) (Case [((field type) ...)]) ...)` | Nominal, disjoint tagged sum; each case gets a constructor, accessors and pattern. |
| `(type (Name param ...) type)` | Transparent alias. |
| `(typeclass (Class param ...) (: method type) ...)` | Open, type-indexed record of methods. |
| `(instance (Class type ...) [(requires ...)] (define ...) ...)` | Instance; may be generic. |
| `(match e (pattern body ...) ...)` | Nested patterns, wildcards and literals; exhaustiveness and redundancy checked. |
| `(ann e type)` | Static annotation; never checks at run time. |
| `(type-convert e type)` | Upcast checked statically, or downcast checked at run time (§6). |
| `(extern name module symbol type)` | Total foreign function, such as a math routine (§3.5). |
| `(effect Name ((operation type) ...) [(host module ((operation symbol) ...))])` | Effect and its operations, with optional host defaults (§3.5). |
| `(handle Name ((operation implementation) ...) body ...)` | Installs an effect's implementations for the extent of `body` (§3.5). |

A color example:

```scheme
(define-library (example colors)
  (import
   (lofi base))
  (export Vec3 PrimaryColor Red Green Blue Color Primary Rgb ToHex to-hex)
  (begin
    (struct (Vec3 T) ((x T) (y T) (z T)))
    (enum PrimaryColor
      (Red)
      (Green)
      (Blue))
    (enum Color
      (Primary ((value PrimaryColor)))
      (Rgb ((value (Vec3 F32)))))

    (typeclass (ToHex T)
      (: to-hex (-> T String)))

    (instance (ToHex PrimaryColor)
      (define (to-hex color)
        (match color
          ((Red) "#ff0000")
          ((Green) "#00ff00")
          ((Blue) "#0000ff"))))

    (instance (ToHex (Vec3 F32))
      (define (to-hex v)
        (string-append "#" (channel-hex (Vec3-x v))
                       (channel-hex (Vec3-y v)) (channel-hex (Vec3-z v)))))

    (instance (ToHex Color)
      (define (to-hex color)
        (match color
          ((Primary value) (to-hex value))
          ((Rgb value) (to-hex value)))))))
```

Enum cases are constructors of their enum, not types of their own. Nesting gives
`Color` its primary colors: `(Primary (Red))`.

A function defined by cases uses `match`. Closed clause syntax can be sugar over
it later:

```scheme
(: fibonacci (-> I64 I64))
(define (fibonacci n)
  (match n
    (0 0)
    (1 1)
    (n (+ (fibonacci (- n 1)) (fibonacci (- n 2))))))
```

Top-level definitions that are polymorphic or exported carry signatures. Local
definitions are inferred.

### 3.2 Scalars, functions and literals

Scalars are `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`, plus `String`
(immutable UTF-8) and `Bytes`. A literal checks against an expected numeric type
and is range-checked at compile time. With no expected type it defaults to `I64`
or `F64`. Computed values never convert implicitly. Arithmetic is a typeclass
(`Num`), so `(+ x 1)` works for any `x` with a `Num` instance. Collection
lengths and indices are `I64`, consistent with that default. Overflow behavior
is part of the instance: wrapping for the fixed-width types, with explicit
checked operations.

Functions have fixed arity. Proper tail calls are guaranteed. A function type
may name its parameters, so the result can depend on them:
`(-> (n I64) (Vector I32 n))`.

Arguments of kind `Type` (and later, proofs) are static: they are erased or
monomorphized, and a representation depends only on static type arguments.
Value indices of types, such as `n` above, are erased. Definitional equality
uses normalization by evaluation, and evaluation inside types is fuel-bounded
with a clear error; a totality checker can come later.

### 3.3 Structs and enums

A `struct` is a nominal type with immutable fields, listed together. Its
constructor, accessors and pattern are generated. An empty field list can be
omitted, as in `(struct Marker)`, unless a later clause follows it. A struct family `(Vec3 T)` is
a function from types to a struct type.

An `enum` is a nominal sum with named cases:

```scheme
(enum (Option T)
  (Some ((value T)))
  (None))
(enum (Result T E)
  (Ok ((value T)))
  (Err ((error E))))
```

- **Cases are constructors, not types.** `(Some 1)` has type `(Option I64)`.
  A case without fields omits its field list, so declaration, construction and
  pattern all read `(None)`.
- **Disjoint by construction.** Cases are tags of their enum, so type variables
  are fine and `(Option (Option I32))` keeps both levels.
- **Matching.** `match` tests case tags and must cover every case.
- **Representation.** Each case is a WasmGC struct type under the enum's
  supertype, and `match` compiles to `br_on_cast`.

The elaborated core treats enums as ordinary inductive sums and needs no
subtyping, which keeps it a standard dependent type theory.

### 3.4 Typeclasses

A typeclass elaborates to a struct of methods indexed by its type parameters.
An instance is a value of that struct. Resolution happens at each use: match
instance heads against the normalized type, then resolve requirements. The
elaborated core passes instances as explicit arguments. Monomorphization then
specializes them away, so there is no runtime dictionary unless code is
polymorphic at run time.

Rules:

- No overlapping heads. An instance lives with its class or its head type.
- A class's parameters must be determined by each method's type.
- Generic instances may have requirements.

This replaces both today's concrete-head classes and `define-overload`.

### 3.5 Effects

Every function type carries an **effect row**, in the style of Koka: the set of
effects calling the function may perform. A function whose row is empty is
**total**: its result depends only on its arguments and immutable data, and
calling it changes nothing observable. An effect declares operations, and
`handle` binds implementations for them. Operations are tail-resumptive: an
implementation returns to the operation's caller exactly once, so no
continuation is ever captured.

#### Syntax

A row follows `!` at the end of an arrow. Without `!`, the row is empty.

```scheme
(: parse (-> String Config))                     ; total
(: load-config (-> String Config ! fs))          ; reads files
(: count-line (-> String I64 ! console mut))     ; prints, updates a counter
(: map (All (A B e) (-> (-> A B ! e) (List A) (List B) ! e)))
```

- **Labels** are nominal, like types, and imports and exports treat them like
  type names.
  - `mut` is built in. It covers allocating, reading and writing `Ref` and
    mutable vector storage, has no operations and cannot be handled.
  - Every other label is an effect declared with operations. The standard
    library declares `console`, `clock`, `random`, `fs` and `net`.
- **Rows are sets.** `! fs fs` is `! fs`, and order is irrelevant.
- **Row variables.** A type variable after `!`, bound by `All`, makes the row
  *open*: `(-> A B ! fs e)` performs `fs` plus whatever `e` stands for. A row
  has at most one variable, written last. Whether an `All` variable ranges over
  types or rows is inferred from where it occurs.
- **Data.** Function-typed fields carry rows too, and a struct or enum may take
  a row parameter: `(struct (Task e) ((run (-> Unit ! e))))`.

#### Declaring and handling effects

```scheme
(effect Log
  ((log (-> String Unit))))

(: quietly (All (A e) (-> (-> A ! Log e) A ! e)))
(define (quietly action)
  (handle Log
    ((log (lambda (message) (unit))))
    (action)))
```

- **Operations.** An effect lists its operations and their types, one list
  like a struct's fields. Calling `(log "starting")` performs `Log`.
- **Handlers.** `(handle Log ((log implementation)) body ...)` installs
  implementations for the dynamic extent of `body` and discharges `Log` from
  its row (HANDLE below). Implementations may perform the surrounding
  context's effects.
- **Dispatch.** An operation goes to the innermost handler active when it is
  called. An implementation runs in its handler's outer context, so if it
  performs the same effect, the next handler out receives it. A closure that
  escapes a handler still says `! Log` in its type, so it can only be called
  under some `Log` handler.
- **Host defaults.** An effect can name host imports as its default
  implementation:

  ```scheme
  (effect fs
    ((read-file (-> String Bytes)))
    (host "fs" ((read-file "read_file"))))
  ```

  The effects in the entry point's row must all have host defaults, which the
  host installs at program start. Any code can shadow them with `handle`, so a
  test can run an application under deterministic `fs`, `net`, `clock` and
  `random` handlers.

#### Typing

`Γ ⊢ e : T ! ε` means `e` has type `T` and evaluating it may perform the
effects `ε`. A lambda turns its body's effects into its latent row, and creating
the closure is total. A call performs the effects of evaluating its operator
and arguments, plus the operator's latent row:

```text
Γ, x₁:T₁, …, xₙ:Tₙ ⊢ body : R ! ε
──────────────────────────────────────────────── LAMBDA
Γ ⊢ (lambda (x₁ … xₙ) body) : (-> T₁ … Tₙ R ! ε) ! ∅

Γ ⊢ f : (-> T₁ … Tₙ R ! ε) ! ε₀      Γ ⊢ aᵢ : Tᵢ ! εᵢ
──────────────────────────────────────────────── CALL
Γ ⊢ (f a₁ … aₙ) : R ! ε₀ ∪ ε₁ ∪ … ∪ εₙ ∪ ε

Γ ⊢ e : T ! ε      ε ⊆ ε′
──────────────────────────────────────────────── WEAKEN
Γ ⊢ e : T ! ε′

Γ ⊢ body : T ! {L | ε}      Γ ⊢ implᵢ : opᵢ ! ε   (each operation of L)
──────────────────────────────────────────────── HANDLE
Γ ⊢ (handle L ((op₁ impl₁) …) body) : T ! ε
```

A signature's row is an upper bound. Checking a body against
`(-> String Config ! fs)` fails if the body can perform `net`.

#### Inference

The checker infers rows the way Koka does, by unification rather than
subtyping:

- **One row per body.** Each function body has a current row, initially a fresh
  row variable. Every call's latent row is unified into it, which implements the
  unions in CALL. Local functions and lambdas need no annotations.
- **Row unification.** Unifying `{l̄ | ρ₁}` with `{m̄ | ρ₂}` matches shared
  labels, binds `ρ₂` to the labels only on the left plus a fresh tail `ρ`, and
  binds `ρ₁` to the labels only on the right plus the same `ρ`. A closed row
  missing a required label is an error. Rows have an occurs check like types.
- **Opening instead of subeffecting.** When a name is instantiated, every closed
  row in the positive positions of its type gets a fresh tail. A total
  `(-> A B)` can therefore be passed where `(-> A B ! fs)` is expected, without
  a subtyping relation. WEAKEN is admissible from this rule.
- **Generalization by totality.** A binding generalizes its type and row
  variables only if evaluating its initializer is total. Allocating mutable
  storage performs `mut`, so `(let cell (ref (empty-list)))` stays
  monomorphic, while an application such as `(compose f g)` can generalize.
  This replaces today's syntactic value restriction with a more precise rule.
- **Diagnostics** name the label and the call that introduced it: "`save`
  performs `fs` here, but its signature allows only `console`."

#### Typeclasses and instances

Method signatures carry rows like any other function type. An instance method
must fit the class signature, so an instance of a total method must itself be
total. A class whose methods need effects says so in the method type, often
with a row variable: `(: emit (All (e) (-> T Unit ! e)))`. Effects never take
part in instance selection.

#### Foreign calls and initialization

An `extern` declares a total foreign function, such as a math routine; the
declaration asserts that totality, which is the boundary's explicit unsafe
assumption. Effectful host services are effects with host defaults, so they
can be handled like any other effect.

Library initializers may perform any effects. Instantiating a library is the
host's effectful act, while functions that later read a library's mutable
state still declare `mut`.

#### What is not tracked

Traps and divergence are not tracked, so a total function may still trap or
fail to terminate. Tracking them as labels would make most arithmetic and
indexing effectful. The optimizer knows which primitives can trap.

Mutation of storage that a call allocates and never lets escape cannot be
observed by its caller, so such a function may be total. A function whose
type has no `mut` may therefore perform `mut` in its body, and the checker
confirms afterwards that it is confined: nothing the function can reach from
outside, its parameters, its result or a name it reads, can hold mutable
storage. Then the only storage it can mutate is storage it allocates, and
none of it outlives the call. Primitives, constructors and field operations
act only on their arguments, so they are always allowed. Builders such as
`string-concatenate` rely on this.

The check needs no region types, so it cannot see that a helper defined
outside a function only mutates the storage passed to it. Where that matters,
`unsafe-total` runs a thunk and drops all its effects unchecked; each use is
an unsafe assumption with a comment saying why none of the storage escapes.
`serialize` uses it, because its encoder's methods declare `mut`. A function
that touches storage it did not allocate, such as a library's top-level `Ref`,
still declares `mut`.

#### Uses

Purity is enforced, rather than left to convention, because later stages rely
on it:

- **Model checking.** Application handlers must be total (§5), so a test can
  replay and explore transitions without a browser or a network. Code that
  does use host effects runs under deterministic test handlers.
- **Optimization.** The compiler may merge and reorder total calls, and drop
  those that cannot trap.
- **Boundaries.** A handler's type shows whether it can touch files, the
  network or a GPU, which checking across processes and devices needs. GPU
  code must be total.
- **Self-hosting.** The compiler's passes are total, so host divergence stays
  at the entry point (§6).

An effect system gives these guarantees in Scheme's direct style. Rows are part
of signatures, so the erasure property of §6 is unaffected. The Scheme
translator gives generated code rows naming the host effects R7RS exposes, such
as `console`, `fs` and `mut`.

#### Implementation in the current checker

Effect rows fit the HM checker of phase 2 before dependent types arrive:

1. Arrow types gain a row: labels plus an optional row variable. Unification
   gains row unification with an occurs check.
2. Inference threads one current row per function body, opens rows on
   instantiation, and generalizes only total initializers.
3. The frontend parses `!`, `effect` and `handle`. Primitives and standard
   libraries get their rows.
4. Rows are erased before specialization. Each effect becomes a handler stack
   in a WasmGC global: `handle` pushes its implementations, runs the body and
   pops; an operation loads the top implementation and calls it, possibly as a
   tail call. An implementation runs with its own entry temporarily removed,
   which gives the outer-context rule. Calls resolve statically when inlining
   exposes the enclosing handler.

### 3.6 Macros and generic code

`define-syntax` with hygienic `syntax-rules`, using scope sets, provides new
surface syntax such as binding forms and DSL notation. Macros expand before
elaboration. This also provides Scheme compatibility.

Generic code needs no macros. A dependent function such as `Vec3` over
`(T Type)` is a template, a typeclass requirement is a concept, and
monomorphization is instantiation; unlike C++, the body is checked once, at its
definition. `generate-library` remains for producing whole libraries from
external input (§6).

### 3.7 Wire types and stable identities

A type is a **wire type** if it implements `Serialize` and `Deserialize`.
Deriving supplies both for structs and enums whose fields are wire types;
scalars, `String`, `Bytes`, `List` and `Vector` have them. Functions and `Ref`
have no instances.

Each struct and each enum case has a `TypeId`:

```text
TypeId(struct) = H(library name, struct name, parameters,
                   [(field name, TypeId(field type)) ...])
TypeId(case)   = H(library name, enum name, parameters, case name,
                   [(field name, TypeId(field type)) ...])
TypeId(F args) = H(TypeId(F), TypeId(args) ...)
```

Aliases are transparent and have no identity of their own. An ID changes exactly
when its schema or declaring library changes. Two programs exchange a value only
if they agree on its `TypeId`, which a link or handshake step can check. An enum
value is encoded with its case's `TypeId`, so adding a case does not change the
encodings of existing cases: a protocol enum can grow without breaking old
messages.

This combines Unison's content-addressed definitions with nominal identity
through the library name. It is close to Cap'n Proto's scoped IDs and Avro's
schema fingerprints.

The encoding is `(TypeId, fields)` in the existing compact binary format, with
an equivalent readable S-expression form. The compiler exports wire schemas as
data, and WIT, Protobuf or JSON Schema can be printed from that.

The same schemas define the **canonical ABI** for every Wasm boundary.
Wire values cross to JavaScript or to another module as bytes in linear memory,
encoded and decoded by code generated from the schema. That one mechanism
replaces today's `I32` word protocols and the deleted compiler bridge, and it
serves application commands and state, persistence, IPC, and calling a
Wasm-hosted compiler from JavaScript.

### 3.8 Room for later type features

Binders in the core carry a multiplicity slot. It is always `0` (static) or `ω`
(unrestricted) for now. That is quantitative type theory restricted to two
points, so adding `1` (affine or linear) later does not change the core's shape.
Session types become expressible once that slot gains `1`, making channel
endpoints linear.

GPU code is a checked subset of Lofi (scalars, vector structs, no allocation,
recursion or closures) emitted as WGSL by a second backend. Host and shader
share the same `struct` definitions, so layouts are never synchronized by hand.

## 4. Compiler architecture

Every pass reads immutable data and produces it; the driver composes them.
Inside a pass, state that grows as the pass runs, such as fresh-name
counters, type-variable solutions and worklists, lives in `Ref` cells, and
tables are immutable `(lofi table)` values.

```text
text ──read──▶ located S-expressions
     ──load──▶ library headers: imports and exports resolved first
     ──expand─▶ core AST              (hygienic syntax-rules; knows binding forms)
     ──elaborate▶ explicit typed core + checked interface per library
     ──specialize▶ first-order mono IR (types erased, instances specialized,
                                       closures and tail calls decided)
     ──emit───▶ WasmGC binary          (Binaryen optional)
              ▶ WGSL                   (GPU subset)
              ▶ wire schemas           (canonical ABI, WIT/Protobuf)
```

1. **Reader.** About 300 lines of hand-written recursive descent producing
   syntax objects with spans. No parser-combinator framework.
2. **Loader.** Reads `define-library` headers, resolves imports against
   explicit library maps, and detects cycles. Nothing is parsed speculatively.
3. **Expander.** The only module that knows Lofi's binding forms. Bodies use
   two-pass expansion: expand heads to discover definitions, then expand
   bodies, as R6RS and Racket do. It emits core AST directly, with no fixpoint
   loop and no second parse.
4. **Elaborator.** Bidirectional checking with metavariables, NbE, implicit
   arguments, instance resolution, effect rows, and pattern compilation with
   Maranget's exhaustiveness and redundancy checks. Its output is an explicit
   core plus a **checked interface** for each library: exported names, types,
   structs with `TypeId`s, and instances. Interfaces are serialized and cached,
   so libraries are checked once rather than with every program.
5. **Specializer.** Erases static arguments and monomorphizes over types and
   instances. It records selected instances on the nodes, never re-resolving
   them, and decides closure conversion and tail positions.
6. **Backends.** WasmGC and WGSL. Wire schemas come from interfaces.

Each pass owns one data structure, with one record type per node kind, and
consumes the previous pass's output without consulting earlier
representations.

## 5. Runtime and application model

The actor hierarchy has been replaced by one-shot tasks. A runtime owns
queued, executing and suspended work. The language permits multiple
threads; the shipping WasmGC and JSPI implementation runs cooperatively on
one execution agent. Ordinary handlers are reusable `Send + Sync`
capabilities. See the [runtime contract](book/runtimes/contract.md).

An application owns its state as arguments to a loop. Its total update and
view functions remain easy to test and model-check without browser code.
The runtime buffers input and supplies suspending event and storage
operations. Reload waits for the loop's saved handover and remaining task
cleanup. An unchanged TypeId reuses the state; otherwise `save` and
`restore` perform the migration. No actor interface, transport, mailbox or
supervisor is required.

<!-- ANCHOR: bootstrap -->
## 6. Bootstrap, self-hosting and Scheme

**Scheme compatibility.** Lofi's Scheme-shaped core is designed with an
*erasure property*. Delete the typed forms of §3.1, replacing them with
untyped R7RS equivalents, and the result is an R7RS program with the same
behavior whenever the Lofi program does not trap or overflow:

| Lofi | R7RS after erasure |
| --- | --- |
| `(struct (Vec3 T) ((x T) (y T) (z T)))` | `(define-record-type Vec3 (Vec3 x y z) Vec3? (x Vec3-x) (y Vec3-y) (z Vec3-z))` |
| `(enum (Option T) (Some ((value T))) (None))` | One record type per case (`Some`, `None`) and a predicate `Option?` that tests the cases. |
| `(: ...)`, `(type ...)` | Removed, including effect rows. |
| `(effect Log ((log T)) ...)` | A parameter holding a record of implementations and the outer record, and a procedure per operation that calls the current implementation with the parameter rebound to the outer record. The shim supplies host defaults. |
| `(handle Log ((log impl)) body ...)` | `(parameterize ((Log (make-Log impl))) body ...)` |
| `(ann e T)`, `(type-convert e T)` | `e` |
| `(match e ((Some v) a) ((None) b))` | `(let ((x e)) (cond ((Some? x) (let ((v (Some-value x))) a)) ((None? x) b)))` |
| Typeclass method | A generic procedure that dispatches on its first argument's record predicate. |
| `I64`, `F64` literals | Exact integers and flonums. |

Each `define-record-type` creates a fresh runtime type, so struct identities and
enum cases stay distinct after erasure.

**The compiler is written in that core.** No host-specific code appears in the
passes. Hosts differ only in library implementations, which is ordinary
in Scheme, where every implementation provides its own `(scheme base)`:

- **On Lofi.** The typed forms are built in, and the compiler's libraries,
  `(lofi base)`, `(lofi table)` and `(lofi io)`, are Lofi libraries backed by
  WASI.
- **On Chibi.** `host/chibi/` implements the same three libraries with
  Chibi's own procedures, and `(lofi forms)` defines `:`, `struct`, `enum`,
  `type` and `match` as erasing macros. The compiler defines no typeclass
  instances of its own, so nothing dispatches at run time.

The shared compiler driver reads its arguments and files through `(lofi io)`.
The Chibi and Wasm entries publish missing-input requests after unwinding. Lofi's standard library lives on Lofi's search path only,
so Chibi never sees it, and Chibi runs the compiler with
`-I src -I host/chibi`, the last `-I` winning. The hosts disagree on integer overflow, argument
evaluation order and the order of table keys, so the compiler's output never
depends on them, except for the numbering of generated names, which follows
evaluation order.

**Bootstrap.**

1. Stage 0 is the previous compiled compiler, or, the first time, the
   compiler's source running on Chibi.
2. Stage 0 compiles the source to Wasm, giving stage 1.
3. Stage 1 compiles stage 2.
4. Stage 2 must reproduce its own text exactly.

The driver repeats this whenever the compiler's source changes, so a pinned
Wasm build bootstraps without Chibi. Chibi remains the host of the first
bootstrap and of `make test-chibi`.

**Full Scheme.** `(scheme compiler)` is a Lofi library: a reader plus a
translator from R7RS source to the syntax of a Lofi library. Every Scheme
value is a `Datum`, the type of Scheme data in the dynamic libraries
(`datum`, `number`, `read`, `write`), so matching on one enum replaces
run-time type tests. Scheme code calls no typed Lofi code yet. *Proposed:*
wherever generated code meets typed Lofi code, the translator inserts
`(type-convert e T)`, liberally and without proving it necessary:

- **Upcast.** Converting a typed value to `Any` is checked statically and
  injects the value with its `TypeId`.
- **Downcast.** Converting an `Any` to a specific type checks the `TypeId` at
  run time and traps on a mismatch; `(type-test e T)` asks first, without
  trapping.
- **Redundancy.** The compiler removes conversions it proves redundant, such
  as a downcast of a value just upcast from the same type.

On Chibi, `type-convert` erases to its expression. A `generate-library` recipe
runs the translator:

```scheme
(generate-library (legacy program)
                  (import
                   (lofi base)
                   (lofi io)
                   (scheme compiler))
                  (scheme->lofi-library (list "legacy" "program") (read-file "program.scm")))
```
<!-- ANCHOR_END: bootstrap -->

## 7. Migration

The phases below were first planned as changes to the previous compiler.
Instead, phases 1 to 3 began with a new compiler written from scratch in the
Scheme subset, beside the old one, which was then deleted.

### Done

- **Phase 0, cleanup.** Benchmarks, historical documentation and the compiler
  bridge are gone.
- **Phase 1, one front end and one polymorphism mechanism.** The expander
  emits the core program directly; nothing is parsed twice. Typeclasses with
  generic instances replace overload families, and instances are chosen once,
  during checking. Literals check against their expected type and default to
  `I64` and `F64`.
- **Phase 2, the target type surface.** `struct`, `enum` and `type`; `match`
  with nested patterns and Maranget's checks; derived `Serialize` and
  `Deserialize` with per-case TypeIds; effect rows, `effect`, `handle` and
  host defaults. Applications are total `init`, `update` and `view` functions
  over typed values, and Siegework is rewritten with enums and `match`.
- **Phase 3, self-hosting.** The compiler is written in typed Lofi and
  compiles itself; section 6 describes the bootstrap. Compiling the compiler
  takes under a second as Wasm and about forty seconds on Chibi.
- The dynamic Scheme libraries (`integer`, `rational`, `number`, `datum`,
  `read`, `write`) and `generate-library` are ported, without complex
  numbers or mutable pairs.
- `Any` and `type-convert` (section 6): an upcast boxes a value with its
  type's identity, a downcast checks it at run time, and a downcast of a
  value just upcast from the same type is removed.

- **Section 5, reload.** `./scripts/lofi-tool serve` relinks a rebuilt module into a
  running page and hands the state over as it is when `type-test` finds its
  type unchanged, or through its save otherwise ([application model](book/lofi/applications.md#hot-reload)). Migration functions between schemas are not implemented.

- **Phase 5, partly.** `./scripts/lofi-tool schema` prints the wire schema of every data
  type with a `Serialize` instance: each case's TypeId and field types.
  `(lofi explore)` checks an invariant of a total state machine by bounded
  breadth-first search, identifying states by their wire encoding.

- **Phase 5, `(scheme compiler)`.** A translator from R7RS text to the
  syntax of a Lofi library, run by a `generate-library` recipe, with
  `(scheme runtime)` for the standard procedures. It covers the core forms
  but not macros, quasiquote, continuations or mutable pairs. Every value
  is a `Datum`, the dynamic libraries' type for Scheme data, which gained a
  procedure case, rather than `Any`: pattern matching on one enum replaces
  run-time type tests, and Scheme code calls no typed Lofi code yet.

<!-- ANCHOR: omissions -->
### Cut from the plan

These parts of sections 3 to 5 were dropped because they would cost more
than they give the programs Lofi runs today. Each can return if a program
needs it.

- **The dependent elaborator.** Generic code is served by Hindley–Milner
  checking with typeclasses, effect rows and monomorphization. Normalization
  by evaluation and implicit arguments would add type-level computation
  no program uses. The implemented ownership subset assigns grade `1` to
  `Once` and concrete records containing it; it has no general dependent
  elaborator or grade-polymorphic containers.
- **Checked interfaces.** Separate compilation hashes each library's
  interface to decide what to rebuild, but stores none: the compiled
  compiler checks Siegework, the largest program, in a fraction of a second,
  so an interface file would add a format and its invalidation without a
  measurable gain. Wire schemas come from the checked program.
- **The WGSL backend.** The renderer's shaders are WGSL text that shares no
  structs with Lofi code beyond fixed instance and material layouts. The
  runtime and graphics plan proposes shaders written as S-expressions.
- **Actor destinations.** Tasks schedule one-shot closures. Mailboxes,
  request/reply protocols and network transports are application concerns.

### Simplifications made on the way

- Local bodies are sequential: a local function may call itself but not a
  later local definition.
- Only unannotated top-level functions are generalized; other definitions
  are monomorphic unless they have a signature.
- Effect labels take no type parameters, and operations are monomorphic.
- Classes have no superclasses and no higher-kinded parameters.
- Wire TypeIds are 32 bits, and every struct and enum value carries its
  case's TypeId.
<!-- ANCHOR_END: omissions -->

### Risks

- **Compile time.** The compiled compiler builds itself, about 6,800 lines,
  in under a second, and Siegework in about a second. Chibi needs about
  forty seconds and several gigabytes of heap for the compiler, so it only
  starts a bootstrap.
- **Scope.** A dependent elaborator with typeclasses, pattern matching and good
  diagnostics is large. Phases 1–3 deliver a useful typed Scheme without it,
  and the core's multiplicity slot and explicit instances keep phase 4
  additive.
