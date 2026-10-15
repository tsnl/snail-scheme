# Strict native Scheme core

The new core keeps Scheme syntax and hygienic macros while inferring ML-style
types and emitting concrete Wasm values. It is currently an independent compiler
entry, hosted by Chibi. The existing gradual command-line compiler remains the
comparison implementation.

```sh
scripts/build-strict program.scm build/program.wasm
scripts/test-strict
```

Source imports `(snail strict)`. Compilation retains `.wasm.wat` and
`.wasm.raw.wasm`, then applies the shared Binaryen `-O3` optimization pipeline.
The module exports zero-argument `main`, whose native result is the final source
expression. It executes once per module instance; a second call traps, including
after a failed first call. The guard is set before any source initializer.
Pure programs have no runtime imports. The API is
`strict-source-file->core`, `strict-source-file->wasm`, and
`strict-source-file->wat-file` in `(snail-scheme strict-compiler)`; callers supply
the repository root and source path inside a trace scope.

## Types, inference and immutable bindings

Concrete scalars are `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
Integer literals default to I64, floating literals to F64. An immediate I32 or
F32 annotation chooses that literal's representation. Widths remain distinct;
there is no automatic numeric coercion. Integer literals must fit their width.
Native fixed-width arithmetic uses Wasm wraparound and division traps.
`(unit)` constructs Unit. `when` and `unless` evaluate their selected bodies and
produce Unit, including when their bodies are empty.

```scheme
(import (snail strict))
(define (identity x) x)
(if (identity #t) (+ (identity 40) (identity 2)) 0)
```

Each lambda parameter gets its own inference variable. Unification checks
occurrence and links flexible variables by their canonical lower ID. Recursive
definition groups are solved together. Nonexpansive values generalize variables
absent from their environment; allocations and other applications obey the
value restriction. All source bodies are checked, including unused definitions.
An explicit `(: identity (All (T) (-> T T)))` checks the body with rigid T.
`(inst identity I32)` selects an explicit view. Unused quantified variables need
not acquire a machine representation. Declaration-bound type names are currently
scoped to the signature, not to annotations or `inst` syntax in the body.

The existing `let` macro expands to a directly applied lambda. The strict checker
elaborates that exact fixed-arity syntactic form as a typed let: actuals are
checked in the caller environment, then eligible bindings generalize. This also
applies to directly written lambda applications. Named and opaque function
parameters remain monomorphic within their bodies.

Bindings cannot be assigned with `set!`. `(ref value)`, `ref-get`, `ref-set!`,
and `ref-eq?` provide explicit invariant cells. Each concrete `Ref T` has a
mutable native T field. Aliases retain one cell, including aliases captured by
different concrete copies of a generic function. Immutable `List T` supports
`cons`, `car`, `cdr`, `null?`, and typed empty lists. Mutable arrays are not part
of this first surface.

## Concrete calls and static classes

Function types are `(-> Fixed ... Result)` or
`(-> Fixed ... (Rest Element) Result)`. Fixed parameters become separate native
Wasm parameters. A rest parameter is one immutable typed list, with a fresh
spine and shared element identities. Ordinary calls evaluate operands left to
right before the operator. A closure contains a typed code reference and a
GC-visible environment. Known code can be called directly; unknown code uses a
typed indirect call. Tail calls use Wasm tail-call instructions.

Specialization keys retain concrete body, capture and class-obligation types,
including phantom class parameters. Instances are reserved before their bodies
are expanded, so ordinary recursion reuses one instance. Changing polymorphic
recursion is bounded and rejected with a located diagnostic, never widened to
a universal representation. Reachable expression types must be concrete.

`define-class`, `define-instance`, and qualified `All` retain the static class
contract. Instance heads match exactly. Inferred functions can generalize their
class obligations; explicit declarations must supply every abstract obligation.
Concrete method views and method values resolve to their implementation before
Wasm emission. Named implementations retain their original binding and
initializer site. Instance declarations do not evaluate an early runtime alias.
Lambda implementations initialize at their declaration position.

Code copies and runtime initialization are distinct. An effectful initializer
executes once at its lexical source site. Captured local immutable bindings use
private, once-initialized concrete cells when necessary to tie recursive closure
references. Those cells carry readiness state; capturing the cell does not read
an uninitialized value. They are separate from user-visible Ref cells. Global
bindings likewise check readiness, preserving failure before an early read.
An unused polymorphic name initializer still performs its source read. A lazily
created Unit readiness token preserves that check when no payload copy is needed;
erasing a concrete payload never erases a required early-binding failure.

## Explicit universal values

The bounded lattice is `Never <: T <: Top`. Top means a checked universal value;
an unsolved inference hole is not Top. Different branch types fail unless an
explicit Top expectation requests the conversion. `ann` injects concrete values
into Top and projects them back with a checked tag:

```scheme
(define value (ann (ref 42) Top))
(ref-get (ann value (Ref I64)))
```

Top is an engine-managed `eqref`. Small I64 values use signed i31 immediates;
other scalars use tagged boxes. Managed values use a wrapper containing the
original reference and a complete semantic type witness. Thus Bool and I32,
Ref Bool and Ref I32, and function signatures differing only in those types
remain distinct even when their physical Wasm layouts coincide. Projection
returns the original referenced value and preserves identity. Mismatches trap.
Projection to Never evaluates its operand and traps. Never-returning calls emit
validator-visible unreachable control flow when used in a concrete context.

## Current boundary

This slice supports scalar arithmetic, concrete higher-order closures, recursive
functions, explicit cells, immutable lists, static classes and explicit Top.
It does not yet provide strings, arbitrary integers, rationals, records, arrays,
dynamic `apply`, universal-value operation dispatch, or native foreign
declarations. The existing parser may recognize forms outside this surface;
the strict checker rejects unsupported expressions. Native scalar externs are
the next integration slice. No benchmark speedup is claimed from correctness
tests alone.
