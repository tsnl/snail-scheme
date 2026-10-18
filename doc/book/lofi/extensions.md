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
is supported by its foreign ABI; declaring an arbitrary Lofi type does not make
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
has its own initializer and an explicit signature. The signature must describe
a fixed-arity function, optionally quantified with `All` and qualified by class
requirements. Every alternative needs its own signature, even when its
initializer names an already annotated function. A family cannot share a name with an
ordinary definition, datatype or class method. An imported family can be extended
through its original identity, including after renaming.

```text
overload_declaration ::= "(" "define-overload" name signature expression ")"
```

The [typeclass and overload rules](types.md#typeclasses-and-overloads) govern
selection: argument and result constraints must leave exactly one compatible
complete signature. Declaration order and prerequisites do not rank candidates.
Omitting a signature is an error, including for unused alternatives and imported
family extensions. The compiler checks each implementation against its declared
signature; it does not infer the family members from their bodies or uses.
Ordinary `def` and `let` bindings still infer their types when unannotated.
Implementations retain their ordinary initialization sites and effects.

A qualified signature can require a family at a complete function type, for
example `(All (T) (requires (add (-> T T T))) (-> T T T))`. This reuses class evidence
and specialization; it does not introduce runtime dispatch.

## Standard operations

`(lofi base)` supplies the ordinary numeric and collection operations used in
the examples. `(lofi primitive)` exposes the compiler's concrete primitives.
`empty-list` has signature `(All (T) (-> (List T)))`; for example,
`(ann (empty-list) (List I32))` constructs an empty immutable list. There is no
`quote` form in Lofi. List construction otherwise uses ordinary `cons` calls.

`f32->i32 : (-> F32 I32)` truncates toward zero and traps on NaN, infinity or a
result outside the signed I32 range. It uses Wasm's checked conversion on both
execution targets; it does not silently clamp or wrap the result.

`i64->i32 : (-> I64 I32)` requires the value to fit the signed I32 range and
traps otherwise. `f64->f32 : (-> F64 F32)` rounds once to binary32, with ties to
even. It traps when a finite input rounds to infinity. Explicit infinities and
NaNs remain IEEE special values; underflow may produce a subnormal or signed
zero. These checks apply equally to direct calls and first-class function values.

Ordinary I32/I64 addition, subtraction and multiplication wrap at their declared
width. F32/F64 addition, subtraction, multiplication and division retain IEEE
results, including infinity on overflow. Direct primitives, overloads and
function values have the same contract. A discarded arithmetic result may be
eliminated, but its argument effects and any required division or conversion
traps remain observable.

The primitive library retains compatible names used by existing libraries:
`i64-wrapping-add` and `i64-wrapping-mul` have the same modulo-2^64 semantics as
ordinary I64 addition and multiplication. `f64-ieee-add`, `f64-ieee-sub`,
`f64-ieee-mul` and `f64-ieee-div` have the same semantics as their ordinary F64
counterparts. Import these aliases explicitly from `(lofi primitive)` when
needed. Datum hashing uses the word aliases. The nominal `Number` library
preserves IEEE behavior for inexact arithmetic, and the named `integer->f64`, `integer-ratio->f64` and
`rational->f64` conversions round an out-of-range exact value to infinity.
The scalar externs in `(lofi math)` likewise expose their documented IEEE
overflow/domain results. No implicit numeric promotion is inserted. Explicit
overflow-checking arithmetic variants remain future work, including their use by
a future Scheme-to-Lofi frontend; that frontend remains deferred.

The [implementation
roadmap](https://github.com/tsnl/snail-scheme/blob/main/doc/roadmap.md#align-with-the-lofi-book)
tracks remaining differences and the implemented first-class library compiler APIs. These gaps do
not weaken the language contract.
