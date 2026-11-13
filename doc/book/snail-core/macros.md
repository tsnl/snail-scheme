# Macros and generated libraries

Macros are hygienic `syntax-rules` transformers, defined with
`define-syntax` at the top level or in a local body. Surface forms such as
`let*`, `cond`, `case` and the variadic `list` are macros in `(snail core base)`.
They expand before checking, so generated expressions obey the same types,
effects and ownership rules as handwritten code.

A macro can generate a typed definition, including its `(→ Result)`, `!`,
`∀`, `⊨` and documentation clauses. It cannot grant permission to perform an
effect, hide a linear member, or introduce an effectful top-level initializer.
Generated identifiers retain their lexical context; field labels select
stored slots of the receiver's nominal type.

Snail Scheme is a statically typed Scheme descendant. There is no R7RS
translator, `(scheme base)` compatibility library, dynamic Scheme runtime,
`call/cc` or `dynamic-wind`. S-expressions, hygienic macros and the
`define-library` envelope remain useful syntax in their own right. The
compiler's [Chez bootstrap](bootstrap.md) is a host adapter for its source
closure, not a compatibility contract for arbitrary programs.

## Generated libraries

A library file may hold a `generate-library` recipe instead of a
`define-library`. The build driver compiles and runs the producer, then the
compiler decodes the `Syntax` it returns. The wire representation carries
bytes directly, so a producer need not print and reparse a source string.

```scheme
(generate-library (sample table)
  (import
   (snail core base)
   (snail shell syntax))
  (library-syntax (list "sample" "table")
                  (list "squares")
                  (list (list "snail" "core" "base"))
                  (list (form "define"
                              (list (SymbolSyntax "squares")
                                    (form "list"
                                          (map (lambda (i) (IntegerSyntax (* i i)))
                                               (iota 6))))))))
```

The recipe is an explicit build-time program. Its expression is placed in a
producer entry function; it is not a runtime initializer in the generated
library. The resulting library still contains only definitions and
compile-time declarations. Recipe inputs, failures and cycles are tracked
by the [compiler input protocol](compilers.md#compiler-inputs).

`include-bytes` and `link-file` resolve relative to the recipe's own file.
The first embeds a dependency as a literal; the second makes a linked resource
available to the producer's task. Every emitted form is located at the recipe
for diagnostics. Use `(snail shell syntax)` to construct syntax explicitly;
there is no dynamic Scheme datum conversion layer.
