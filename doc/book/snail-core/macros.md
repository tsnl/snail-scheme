# Macros and Scheme libraries

Macros are hygienic `syntax-rules` transformers, defined with
`define-syntax` at the top level or in a local body. Surface forms such as
`let*`, `cond`, `case` and the variadic `list` are macros in `(snail core base)`,
and they expand away before checking, so the checker sees only the core.

A library file may hold a `generate-library` recipe instead of a
`define-library`: the compiler builds and runs that program first, and
compiles the library syntax it returns, which the program writes as bytes
the compiler decodes rather than as text.

Scheme is a library too. `(scheme base)` gives R7RS names (`cons`, `car`,
`vector`, `char=?`, ...) over the typed language, and `(scheme compiler)`
translates R7RS programs into Snail-Core libraries, run by a `generate-library`
recipe, with `(scheme runtime)` for the standard procedures. Its character
procedures are Unicode's, from `(snail shell text)`: `char-upcase` maps the full
repertoire, `char-numeric?` and `digit-value` hold for any script's decimal
digits, and `string-ci=?` compares case-folded text, so `"Straße"` and
`"STRASSE"` are equal. The [Scheme on Snail-Core](tutorials/scheme.md) tutorial runs
a Scheme program.

That compatibility rests on Snail-Core's core being built so that erasing its typed
forms leaves an R7RS program — which is also how Chibi Scheme runs the
compiler's own source. [Bootstrap and self-hosting](bootstrap.md) sets out the
erasure property and the stages.

**Dynamic Scheme.** `(scheme compiler)` translates the supported Scheme forms
into a typed library. Its runtime values and mutable cells use `Any` and
`Ref Any`. Booleans, characters, strings, bytes, arbitrary-size `Integer`s,
`Rational`s and `F64`s keep their Core types inside `Any`. A Scheme vector is
`Vector Any`; the empty list (`Null`), symbols (`Symbol`) and pairs
(`SchemePair`, with two `Any` fields) have distinct nominal types. Pairs remain
immutable and may have improper tails. `Datum` and the old scalar constructors
are no longer part of `(snail shell datum)`.

`(snail shell read)` returns these values directly. `(snail shell write)` keeps
the existing external notation and prints unsupported Core values as
`#<opaque>`; that placeholder is not readable data. Such values can still pass
through Scheme pairs, vectors, cells and procedures. Structural equality
continues to implement `eq?`, `eqv?` and `equal?` for supported immutable data;
procedures and arbitrary Core values compare false. Only native `#f` is false
in a Scheme condition. The compiler's separate located syntax enum is unchanged.

`(snail shell datum)` provides pure `match-any`: each clause names a concrete
type and an ordinary pattern for the recovered value. It evaluates the input
once and tries the next clause if either the type or pattern does not match:

```scheme
(match-any value
  ((Symbol (Symbol "ready")) #t)
  ((String text) (string=? text "ready"))
  (else #f))
```

Procedures use a nominal `Procedure` wrapper whose callable field has type
`(dyn (Fn (List Any) → Any ! console mut dyn-cast))`. Recovering the wrapper preserves
that effect signature; it does not erase an effectful function type. The
runtime's `call` takes `Any` and `List Any` and declares those same effects.
A typed client can construct a `Procedure` adapter for its library function
and handle `dyn-cast` around the call. Native values need no Scheme-specific
scalar wrapper. Failed required type and domain checks use `dyn-cast`;
arity, bounds and arithmetic errors retain their existing behavior.

Generated scripts explicitly call `scheme-evaluate` around each top-level
expression or definition initializer. It handles `dyn-cast` and fails the
script with a diagnostic. Runtime procedures themselves do not catch failures,
so callers can instead use `try-dynamic` or their own handler. No host silently
enables the effect. There is still no interactive evaluator, Scheme import
bridge or whole-program gradual inference: translated variables and dynamic
calls remain erased. The existing supported forms are unchanged.

Scheme `+`, `-`, `*` and `/` select the lexical `dynamic-arithmetic` policy
from [the arithmetic libraries](types.md#asymmetric-arithmetic). Exact literals
start as `Integer` or nonintegral `Rational`; decimal literals use `F64`.
Operations preserve their selected instance's result type: integer division
returns `Rational` even when integral, and `integer?` recognizes its value.
Printing an integral rational as `2` and reading it again gives an `Integer`:
text preserves the Scheme numerical value, not the original Core type identity.
The typed `Number` parser and a temporary numeric view still serve comparison,
equality and formatting; no `Number` value is stored as a Scheme number.
Comparison policy and existing floating-point limitations are unchanged.
Importing Scheme's runtime does not activate its promotion policy in a client.

A `generate-library` recipe runs the translator on a program it includes, `program.scm` beside the
recipe:

```scheme
(generate-library (legacy program)
                  (import
                   (snail core base)
                   (snail shell utf8)
                   (scheme compiler))
                  (match (utf8->string (include-bytes "program.scm"))
                    ((Ok text) (scheme->snail-core-library (list "legacy" "program") text))
                    ((Err _) (panic "program.scm is not UTF-8"))))
```
