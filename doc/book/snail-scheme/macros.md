# Macros and generated libraries

Macros are hygienic `syntax-rules` transformers, defined with
`define-syntax` at the top level or in a local body. Surface forms such as
`let*`, `cond`, `case` and the variadic `list` are macros in `(snail core base)`.
So is what a `deriving` clause expands to, a use of a macro in its class's
library: a macro can expand into an `instance`, as into any declaration.
They expand before checking, so generated expressions obey the same type
rules as handwritten code.

A macro can generate a typed definition, including its `(→ Result)`, `∀`,
`⊨` and documentation clauses. It cannot hand code a capability it was
not given: a template's own names are resolved where the macro is defined.
Generated identifiers retain their lexical context; field labels select
stored slots of the receiver's nominal type.

`snail-scheme` is a statically-typed Scheme successor. There is no R7RS
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
library. A recipe that needs capabilities is a `lambda` over them, and the
producer's `main` asks its target for each
(`src/lpc/skins.sld` reads a linked file through a `Resources`):

```scheme
(generate-library (lpc skins)
  (import (snail core base) (lpc embed) (snail shell resource))
  (lambda ((resources Resources))
    (ramps-library (list "lpc" "skins")
                   (read-resource resources (link-file "palettes/skin.json")))))
```

 The resulting library still contains only definitions and
compile-time declarations. Recipe inputs, failures and cycles are tracked
by the [compiler input protocol](compilers.md#compiler-inputs).

A native producer can also run a build tool. Last Mile links its Ink sources in the recipe, asks for `Processes` to run inklecate, and returns ordinary dialogue definitions for the game. Both browser and Node builds use that producer. [Ink recipe](../games/last-mile.md#write-dialogue-in-ink)

`link-file` resolves relative to the recipe's own file.
The first embeds a dependency as a literal; the second makes a linked resource
available to the producer's task. Every emitted form is located at the recipe
for diagnostics. Use `(snail shell syntax)` to construct syntax explicitly;
there is no dynamic Scheme datum conversion layer.
