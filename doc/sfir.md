# SFIR

SFIR (Snail functional IR, pronounced “sphere”) is a typed functional language
and a reusable compiler target. It occupies the role of an IR such as LLVM while
retaining functions, algebraic data, polymorphism and type inference. Its textual
surface must also be practical to write by hand.

This document defines the migration target. The existing strict compiler is its
starting point; a renamed executable alone does not implement this design.
The library and build APIs below are design contracts. Their concrete signatures
and transport formats remain to be specified.

## Scope

SFIR is the sole supported input language. Remove the non-strict Scheme compiler
and the `snail-scheme` executable. `snail-sfir` runs or compiles `.sfir` programs.
There is no Scheme compilation, Scheme interpretation or macro expansion in the
product. The compiler remains written in Scheme and hosted by Chibi.

Keep `build.scm` outside this migration for now. Scheme elaboration, macro staging
and self-hosting are later projects, after SFIR is robust.

## Explicit functional surface

Use s-expressions with a small set of primitive forms: definitions, lambdas,
applications, conditionals, local bindings, sequencing, annotations and matching.
Definitions have an optional attached signature; an omitted signature introduces
an inference hole.

```lisp
(import (sfir core))

(define increment (-> I64 I64)
  (lambda (x) (+ x 1)))

(define answer
  (let ((value 41))
    (increment value)))

answer
```

`define` always names a value: `(define name initializer)` or
`(define name Type initializer)`. Function-definition shorthand is rejected.
`lambda` and `let` each take one body expression; `if` requires both branches.
`let` is an explicit lexical-binding primitive; its initializers run left to
right in the enclosing scope. `begin` provides a lexical block with ordered
sequencing and a final result expression. Definitions in a block share scope
and may be recursive; runtime initializers retain source order and premature
reads remain checked.

Bindings are immutable. Mutable state uses explicit `Ref T` cells or mutable
container operations. A container's element type cannot change through a write.
Functions have positional arguments and may declare a typed rest parameter;
ordinary calls do not package every argument into a list.

Libraries import and export types and values by resolved identity. Renaming an
import preserves that identity. Nominal data declarations, constructor matching,
type classes, overloads and typed extern declarations are language facilities.
There are no user macros, `syntax-rules`, named-`let` shorthand or derived control
forms such as `cond`, `and`, `or`, `when` and `unless`.

## Types and specialization

The type lattice has `Never` below every type and `Top` above every type.
Concrete types include fixed-width scalars, functions, containers, records and
variants. Numeric tower types can be implemented in SFIR libraries. Distinct
numeric types do not implicitly convert into one another.

Inference holes represent compile-time questions, never an implicit choice of
`Top`. Type checking must establish the representations and operations required
by compilation. Conversions into `Top` and checked projections out are explicit.
`Top` uses a managed reference, boxing concrete values when necessary; it has
grade many. Affine values require an explicit shared-ownership wrapper before
entering `Top` or other unrestricted dynamic containers.

Polymorphism belongs to binding-level schemes. An explicit outer `All` is checked
with rigid variables. Uses specialize it into concrete implementations; runtime
function values, fields and container elements have concrete types. Nested
runtime `All`, unresolved specialization and silent generic or JIT fallbacks are
unsupported. Generalization respects mutable state and the value restriction.

Argument and result constraints jointly select overloads. Selection must be
unambiguous; declaration order does not break ties. Promotions are ordinary SFIR
implementations of overloads. Type-class requirements use the same checking and
specialization machinery.

## Library values and dependencies

`SfirLibrary` is the structured, located AST of one source-level compilation unit.
It contains a library identity, import requirements, exported bindings, and
declarations and bodies with optional signatures and inference holes. The textual
parser and generator functions construct the same representation. Construction
establishes structural validity; resolution establishes binding validity; checking
establishes type validity. Generators cannot manufacture trusted type evidence.

The AST API must support fresh binding identities and references to imported
declarations. Source locations and printed names do not establish identity.
Combining libraries or transporting their ASTs must preserve lexical bindings and
nominal type identities without relying on compiler-process pointers. Composition
preserves private scopes rather than concatenating declarations into one scope.

An import describes required bindings; it does not prescribe how to find, load or
instantiate another library. The caller supplies libraries that satisfy those
requirements. Producing one library need not obtain its complete implementation
dependency closure. Independent resolution and checking need the relevant binding
and type interfaces; compilation also needs the implementations demanded by the
assembled program. Exported inference that depends on another library waits for
its interface; recursive checking groups or explicit signatures must account for
cyclic type dependencies.

A build driver assembles the dependency graph. Source-level linking resolves
imports against supplied SFIR libraries before final checking and specialization.
This differs from linking emitted artifacts with foreign providers. Libraries
retain the polymorphic bodies and evidence needed for specialization; they are
not machine object files. Separately compiled formats and checking caches remain
future design work.

## Compiler and execution

The compiler is a reusable library accepting supplied `SfirLibrary` values and a
selected executable entry point. It resolves imports and names, infers and checks
types, specializes concrete uses, and emits WasmGC. Textual parsing is one producer
of its input. Preserve source locations and type evidence through these passes.
Parsing assigns identities and holes; it does not perform type inference or
optimization. Make these boundaries educational to read and use established type
facts to eliminate redundant work.

The operations have separate contracts:

```text
SFIR source -> parse -> SfirLibrary
supplied libraries + executable entry -> compile -> artifact
artifact -> load executable code
executable code + supplied dependencies -> instantiate -> instance
instance + selected function + arguments -> invoke -> value
```

Loading executable code and instantiating its state are explicit, separate
operations. Reusing code must preserve the behavior of independent instantiations;
sharing initialized state requires explicitly sharing an instance. Callers choose
loading functions directly. File extensions do not select loaders implicitly.

A build driver starts from an entry description identifying root library
producers, their dependencies and the executable entry. It obtains library values,
executes generators when needed, and invokes compilation. Discovery, file I/O,
generator execution and publication belong to that driver. `snail-sfir` is one
client of these APIs, implementing run and compile commands. Other build programs
and hosts can orchestrate the same operations without another SFIR compiler.

Always run Binaryen as a Wasm-to-Wasm optimization pass. Execute the optimized
module in a Wasm engine, or mechanically lower it to LLVM for a 64-bit native
target with the in-house collector. Native lowering must not introduce a second
SFIR compiler. Typed foreign declarations map to Wasm interfaces or corresponding
C interfaces; the same Rust extern implementations serve both targets.

## Generation and staged execution

`generate-library` is an ordinary producer function returning a `SfirLibrary`,
not a privileged SFIR syntax form. A generator may construct declarations, parse
source, invoke other producers, or compose supplied libraries. Its library output
passes through the same resolution, checking and optimization as parsed SFIR.
Artifact dependencies accompany the result through an explicit build protocol.

A generator can itself be implemented by SFIR libraries. The build driver supplies
their dependencies, compiles them, loads the executable artifact, instantiates it,
and invokes the selected generator function:

```text
generator libraries + dependencies
  -> compile -> load -> instantiate -> invoke
  -> generated SfirLibrary
  -> assemble application dependencies -> compile application
```

Nested generation follows the same process. Generator prerequisites must be
available before invocation, and dependency cycles receive diagnostics. Each
generation chain must reach source or available executable code that can be
prepared without further generation. This bootstrap path does not require the
compiler to be self-hosted; Chibi remains its implementation host.

Staging follows these execution dependencies rather than a mandatory pair of
compile-time and runtime interfaces on every library. Generator execution and
generated-program execution have distinct instances and state. Live references
and closures belong to their execution contexts; transferring information between
contexts requires explicit data transport or interfaces. Returning an AST that
describes a lambda does not transfer the generator's executable closure.

## Measurements

Port the complete benchmark suite to bare SFIR. Compare SFIR, Chez and Rust on
matched workloads, recording target and host differences explicitly. Preserve
canonical inputs, algorithms, correctness checks, failures and source provenance.
Keep clean timings separate from instrumented runs and compile time separate from
execution time. Historical Scheme measurements remain historical evidence.

## Later frontends

A future Scheme frontend may implement a `generate-library` function producing a
`SfirLibrary` while forwarding source locations. It performs elaboration, including
Scheme macro expansion, without its own optimization pipeline. Generated code can
depend on SFIR-defined functions and types and is checked and optimized by the
same SFIR compiler. Other languages can use this boundary too.

A frontend may need transformers and their dependencies before it can produce its
library. The build driver can supply those frontend values separately from the
SFIR implementation libraries required by the generated application. SFIR itself
does not interpret macros or require every library to expose a macro interface.

Scheme elaboration, macro persistence, hygiene transport and frontend-specific
interfaces remain deferred. The general library-generation and execution model
above does not require those facilities or the migration of `build.scm` today.
