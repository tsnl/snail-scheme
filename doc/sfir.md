# SFIR

SFIR (Snail functional IR, pronounced “sphere”) is a typed functional language
and a reusable compiler target. It occupies the role of an IR such as LLVM while
retaining functions, algebraic data, polymorphism and type inference. Its textual
surface must also be practical to write by hand.

This document defines the migration target. The existing strict compiler is its
starting point; a renamed executable alone does not implement this design.

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

Modules import and export types and values by resolved identity. Renaming an
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

## Compiler and execution

Read located SFIR syntax, resolve names into the shared IR, infer and check types,
specialize concrete uses, and emit WasmGC. Preserve source locations and type
evidence through these passes. Parsing assigns identities and holes; it does not
perform type inference or optimization. Make these boundaries educational to
read and use established type facts to eliminate redundant work.

Always run Binaryen as a Wasm-to-Wasm optimization pass. Execute the optimized
module in a Wasm engine, or mechanically lower it to LLVM for a 64-bit native
target with the in-house collector. Native lowering must not introduce a second
SFIR compiler. Typed foreign declarations map to Wasm interfaces or corresponding
C interfaces; the same Rust extern implementations serve both targets.

Port the complete benchmark suite to bare SFIR. Compare SFIR, Chez and Rust on
matched workloads, recording target and host differences explicitly. Preserve
canonical inputs, algorithms, correctness checks, failures and source provenance.
Keep clean timings separate from instrumented runs and compile time separate from
execution time. Historical Scheme measurements remain historical evidence.

## Later frontends

A future Scheme frontend may use `generate-library` to construct SFIR ASTs,
forwarding source locations. It performs elaboration, including Scheme macro
expansion, without its own optimization pipeline. Generated code can depend on
SFIR-defined functions and types and is checked and optimized by the same SFIR
compiler. Other languages can use this boundary too.

How macros survive compilation, cross-module compile-time access and staged
execution are deliberately undecided. None is required by the current goal.
