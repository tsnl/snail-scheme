# Implementation extensions

The compiler retains two explicit declaration forms used by its libraries.
They supplement the core grammar while foreign interfaces and ad-hoc overload
declarations acquire their complete specification. They are not macros or
alternative spellings of `def`.

## Foreign functions

```scheme
(define-extern clock-nanoseconds "host" "clock_nanoseconds" (-> I64))
```

The declaration binds a function with a concrete signature to a provider module
and symbol. Both names are literal strings. The target checks that the signature
is supported by its foreign ABI; declaring an arbitrary SFIR type does not make
that type transportable. Wasm imports and native C linkage use the same declared
interface. A declaration can occur at library scope or in a local block; it
does not call the function or allocate a provider when evaluated.

```text
extern_declaration ::= "(" "define-extern" name string_literal string_literal function_type ")"
```

## Ad-hoc overload families

```scheme
(define-overload add (-> I32 I32 I32) i32-add)
(define-overload add (-> F64 F64 F64) f64-add)
```

These library-level declarations add members to one named family. Each member
has its own initializer and optional signature. A family cannot share a name
with an ordinary definition, datatype or class method. An imported family can
be extended through its original identity, including after renaming.

```text
overload_declaration ::= "(" "define-overload" name [signature] expression ")"
```

The [typeclass and overload rules](types.md#typeclasses-and-overloads) govern
selection: argument and result constraints must leave exactly one compatible
complete signature. Declaration order and prerequisites do not rank candidates.
An overload signature can be inferred; unresolved captures that prevent a stable
signature are errors. Implementations retain their ordinary initialization
sites and effects.

A qualified signature can require a family at a complete function type, for
example `(All (T) (=> ((add (-> T T T))) (-> T T T)))`. This reuses class evidence
and specialization; it does not introduce runtime dispatch.

## Standard operations

`(sfir base)` supplies the ordinary numeric and collection operations used in
the examples. `(sfir primitive)` exposes the compiler's concrete primitives.
`empty-list` has signature `(All (T) (-> (List T)))`; for example,
`(ann (empty-list) (List I32))` constructs an empty immutable list. There is no
`quote` form in SFIR. List construction otherwise uses ordinary `cons` calls.

`f32->i32 : (-> F32 I32)` truncates toward zero and traps on NaN, infinity or a
result outside the signed I32 range. It uses Wasm's checked conversion on both
execution targets; it does not silently clamp or wrap the result.

`i64->i32 : (-> I64 I32)` requires the value to fit the signed I32 range and
traps otherwise. `f64->f32 : (-> F64 F32)` rounds once to binary32, with ties to
even. It traps when a finite input rounds to infinity. Explicit infinities and
NaNs remain IEEE special values; underflow may produce a subnormal or signed
zero. These checks apply equally to direct calls and first-class function values.

Ordinary I32/I64 addition, subtraction and multiplication trap on signed
overflow. F32/F64 addition, subtraction, multiplication and division trap when
finite operands produce an infinite rounded result, except that a zero divisor
retains IEEE zero-division behavior. Direct primitives, overloads and function
values have the same contract; discarding a result does not discard its trap.

The primitive library provides explicit exceptions for existing low-level
algorithms: `i64-wrapping-add` and `i64-wrapping-mul` compute modulo 2^64, while
`f64-ieee-add`, `f64-ieee-sub`, `f64-ieee-mul` and `f64-ieee-div` retain IEEE
overflow results. Import these names explicitly from `(sfir primitive)`;
ordinary operators in `(sfir base)` remain checked. Datum hashing uses the
wrapping operations. The nominal `Number` library preserves IEEE behavior for
inexact arithmetic, and the named `integer->f64`, `integer-ratio->f64` and
`rational->f64` conversions round an out-of-range exact value to infinity.
The scalar externs in `(sfir math)` likewise expose their documented IEEE
overflow/domain results. These library contracts do not weaken fixed-width
arithmetic or insert an implicit numeric promotion.

The [implementation roadmap](../../roadmap.md#align-with-the-sfir-book) tracks
remaining differences, including first-class library compilation APIs.
These gaps do not weaken the language
contract.
