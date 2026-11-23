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

`link-file` resolves relative to the recipe's own file.
The first embeds a dependency as a literal; the second makes a linked resource
available to the producer's task. Every emitted form is located at the recipe
for diagnostics. Use `(snail shell syntax)` to construct syntax explicitly;
there is no dynamic Scheme datum conversion layer.

### What a build keeps

A build runs every producer it reaches, every time, and keeps none of
their output, so no build is handed a library made from inputs that have
since changed. Running one again is cheap: a build of Hearsay, its three
producers among its work, takes about four seconds. Nor could a build
tell when a kept output had gone stale: a recipe reads files through
`Fs`, runs processes and reaches the web, and nothing records what it
read. A cache keyed by the recipe's text would serve the LPC art as it
was when the cache was filled.

What is costly is what a recipe fetches, and the recipe keeps that
itself, under a digest that pins what it must be. A fetch pinned so gives
the same bytes or fails, whatever its server does later, so its result
depends on the pin alone, and keeping it changes nothing a build can
observe: the machine's cache holds it for every workspace, and a build
that finds it there needs no network. `(snail shell web zip)` reads a zip
archive's members that way, pinned by the digest of the archive's end, and
a dataset's recipe is one call of it
([datasets](../libraries/datasets.md)):

```scheme
(generate-library (datasets mipnerf360 bicycle)
                  (import
                   (snail core base)
                   (only (snail core io) Fs ProcessEnvironment)
                   (only (snail shell web) Web)
                   (datasets mipnerf360))
                  (lambda ((fs Fs) (web Web) (environment ProcessEnvironment))
                    (scene-library fs web environment
                                   (list "datasets" "mipnerf360" "bicycle")
                                   "bicycle"
                                   "images_4")))
```

The network is one more capability the recipe asks for, `Web`, and the
cache's place comes from the environment it is handed. The library it
returns links each file it fetched rather than embedding it, so the
program reads them as resources, and they ship in its `store/`.
