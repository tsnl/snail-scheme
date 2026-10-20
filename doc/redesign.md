# Redesign: Lofi from a clean slate, and how to get there

> **Status: proposal.** Nothing in this document is implemented unless it says
> so. The [book](book/lofi/index.md) and [tour](../TOUR.md) describe the current
> compiler.

This document designs Lofi as if starting over, then plans an incremental path
from today's `main` to that design. The current compiler stays working at every
step.

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

Garbage collection is acceptable. Affine and graded types are out of scope for
now, but the core keeps room for them (§3.8).

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
| `(extern name module symbol type)` | Foreign function; its type declares its effects (§3.5). |

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

Every function type carries an effect row, in the style of Koka. A function
with an empty row is total: it reads only its arguments and immutable data.

```scheme
(: parse (-> String Config))                         ; total
(: load-config (-> String Config ! fs))              ; reads files
(: map (All (A B e) (-> (-> A B ! e) (List A) (List B) ! e)))
```

- **Labels.** `mut` covers writes to shared `Ref` and vector storage; `io`
  covers console, clock and randomness. A library can declare further labels
  with `(effect name)`, for example `fs`, `net` or `gpu`.
- **Rows.** A row lists labels after `!`. A type variable in a row makes it
  open, so `map` has exactly the effects of its function argument.
- **Inference.** Rows unify like types, so local functions and lambdas need no
  effect annotations, and code stays in direct style.
- **Foreign calls.** An `extern` states its effects in its type. A foreign
  function declared without effects is trusted to be total; that is the
  boundary's explicit unsafe assumption.
- **No handlers yet.** Effects are checked and then erased; they have no run
  time representation. Traps and divergence are not tracked initially.

Purity is enforced, rather than left to convention, because later stages rely
on it:

- **Model checking.** Application handlers must be total (§5), so a test can
  replay and explore transitions without a browser or a network.
- **Optimization.** The compiler may drop, merge, reorder or hoist calls whose
  rows are empty.
- **Boundaries.** A handler's type shows whether it can touch files, the
  network or a GPU, which is what checking across processes and devices needs.
- **Self-hosting.** The compiler's passes are total, so host divergence stays
  at the entry point (§6).

An effect system gives these guarantees while keeping Scheme's direct style.
That keeps the erasure property of §6 trivial: rows are part of signatures, and
signatures erase.

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

Every pass is a pure function on immutable data. The driver composes them.

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

An application is a set of actors. Each actor has a typed state `S`, a message
enum `M` of wire types, and a total handler `(-> S M (Transition S))`. A
transition contains the next state and a list of typed effects. A send effect
names a destination typed by that destination's message enum, so the set of
messages each handler may send is visible in its type.

The host delivers one message at a time per actor. State lives in Wasm as a
typed value. Bytes cross the boundary only for persistence and reload, using the
state's wire encoding. Reload is compatible when the state's `TypeId` is
unchanged; otherwise it requires an explicit migration function `(-> Old New)`.

Because handlers are total and states and messages are wire types, a test library
can explore bounded state spaces, check invariants and replay traces without
browser code. Host scheduling semantics are written once as a pure Lofi
reference model and checked against the JavaScript host.

Siegework is rewritten as an ordinary functional program in this model: enums
for building kinds and job states, `match`, `Option`, and a world value with no
integer codes.

## 6. Bootstrap, self-hosting and Scheme

**Scheme compatibility.** Lofi's Scheme-shaped core is designed with an
*erasure property*. Delete the typed forms of §3.1, replacing them with
untyped R7RS equivalents, and the result is an R7RS program with the same
behavior whenever the Lofi program does not trap or overflow:

| Lofi | R7RS after erasure |
| --- | --- |
| `(struct (Vec3 T) ((x T) (y T) (z T)))` | `(define-record-type Vec3 (Vec3 x y z) Vec3? (x Vec3-x) (y Vec3-y) (z Vec3-z))` |
| `(enum (Option T) (Some ((value T))) (None))` | One record type per case (`Some`, `None`) and a predicate `Option?` that tests the cases. |
| `(: ...)`, `(type ...)`, `(effect ...)` | Removed, including effect rows. |
| `(ann e T)`, `(type-convert e T)` | `e` |
| `(match e ((Some v) a) ((None) b))` | `(let ((x e)) (cond ((Some? x) (let ((v (Some-value x))) a)) ((None? x) b)))` |
| Typeclass method | A generic procedure that dispatches on its first argument's record predicate. |
| `I64`, `F64` literals | Exact integers and flonums. |

Each `define-record-type` creates a fresh runtime type, so struct identities and
enum cases stay distinct after erasure.

**The compiler is written in that core.** No host-specific code appears in the
passes. Hosts differ only in library implementations, which is ordinary
in Scheme, where every implementation provides its own `(scheme base)`:

- **On Lofi.** The typed forms are built in, and `(scheme base)` and
  `(scheme file)` are Lofi libraries backed by WASI.
- **On Chibi.** A small shim library defines `:`, `struct`, `enum`, `type`,
  `typeclass`, `instance` and `match` as erasing macros. Typeclass methods dispatch on the
  runtime struct type of their first argument, so the compiler's own code avoids
  methods that dispatch only on their result type.

The entry point reads arguments and files through `(scheme process-context)` and
`(scheme file)`, which both hosts provide. Nothing else diverges.

This also removes today's `bootstrap/` loader view. Lofi's implementations of
the R7RS libraries live on Lofi's search path only, so Chibi never sees them, and
Chibi runs the compiler with `-I src -I shims/chibi`.

**Bootstrap.**

1. Stage 0 is the compiler source running on Chibi through the shim.
2. Stage 0 compiles the same source to Wasm, giving stage 1.
3. Stage 1 compiles stage 2.
4. Stages 1 and 2 must produce identical output on the test corpus.

After that, a pinned Wasm build can bootstrap without Chibi. Chibi remains an
optional host for debugging.

**Full Scheme.** `(scheme compiler)` is a Lofi library: a reader plus a
translator from R7RS source text to Lofi source text. Its output represents
every value as `Any` and uses the existing dynamic libraries (`datum`,
`number`, `read`, `write`) for Scheme's own data. Wherever generated code meets
typed Lofi code, the translator inserts `(type-convert e T)`, liberally and
without proving it necessary:

- **Upcast.** Converting a typed value to `Any` is checked statically and
  injects the value with its `TypeId`.
- **Downcast.** Converting an `Any` to a specific type checks the `TypeId` at
  run time and traps on a mismatch.
- **Redundancy.** The compiler removes conversions it proves redundant, such
  as a downcast of a value just upcast from the same type.

On Chibi, `type-convert` erases to its expression. A `generate-library` recipe
runs the translator:

```scheme
(generate-library (legacy program)
                  (import
                   (scheme compiler))
                  (scheme->lofi-text (read-source "program.scm")))
```

## 7. Migration from today's `main`

Each phase leaves a working compiler with passing suites. Phases 1 and 2 change
the current Chibi-hosted compiler; phase 3 replaces it.

### Phase 0: cleanup (in progress)

Delete the benchmark archive, historical documentation and the compiler bridge,
and generate libraries as text. Also remove unused application features and dead
code, consolidate the test runners, and fix the bugs found in review.

### Phase 1: one front end and one polymorphism mechanism

1. Resolve library headers before parsing, always expand, and have the expander
   emit IR directly. Delete the frontend's second grammar and the speculative
   parse. This also fixes path-dependent keyword reservation.
2. One declaration form per concept. Remove `library-begin` and
   `(def X (datatype ...))`.
3. Replace `define-overload` with typeclasses that allow generic instance
   heads and requirements. Record selected instances during checking, so
   specialization never re-resolves them. This removes the dominant
   compile-time cost found in profiling.
4. Literals check against the expected numeric type, and the default integer
   type becomes `I64`, matching collection indices.

**Exit criterion:** the numeric operators are typeclass methods, and no source
form is parsed twice.

### Phase 2: the target type surface on the current checker

1. `struct`, `enum` and `type` replace `data`, with WasmGC subtype
   representation and `TypeId`s.
2. `match` with nested patterns, wildcards, and exhaustiveness and redundancy
   checks.
3. Derived `Serialize` and `Deserialize` keyed by `TypeId`. Add a canonical
   byte ABI for entry parameters and results, with schema-generated JavaScript
   decoders.
4. Effect rows on function types, `extern` effect declarations, and total
   application handlers.
5. The application framework moves to typed messages and in-Wasm state, and
   the word protocols are deleted. Rewrite Siegework's model with enums and
   `match`. This is the forcing function for the language.

**Exit criterion:** Siegework has no integer-coded state, and no hand-written
JavaScript decoder remains.

### Phase 3: self-hosting in the Scheme subset

1. Fix the erasure property and write the Chibi shim.
2. Port the compiler pass by pass into the subset, as pure passes with typed
   records. Run each port on Chibi through the shim and compare its output with
   the current compiler on the test corpus.
3. Bootstrap stages 1 and 2 as in §6. Delete the old implementation and
   `bootstrap/`.

**Exit criterion:** the compiler compiles itself, and stages 1 and 2 agree.

### Phase 4: the dependent elaborator

Replace HM inference in the self-hosted compiler with the elaborator of §4:
type-level functions, indexed types, implicit arguments and NbE. Add serialized
checked interfaces, which give separate checking and faster builds.

### Phase 5: distribution and devices

Add the WGSL backend sharing struct layouts, wire schema export, typed
destinations, the bounded model-checking library, and `(scheme compiler)`.

### Risks

- **Compile time.** The current compiler takes about a minute for Siegework and
  ran out of memory on a large Scheme program. Phase 1.3 addresses the measured
  hot spot. Phase 3 still needs the compiler to compile something its own size,
  so measure that before starting the port.
- **Scope.** A dependent elaborator with typeclasses, pattern matching and good
  diagnostics is large. Phases 1–3 deliver a useful typed Scheme without it,
  and the core's multiplicity slot and explicit instances keep phase 4
  additive.
