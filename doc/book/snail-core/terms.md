# Terms

## Programs and libraries

A program is a file of `import` forms followed by definitions and expressions,
which run in order. A library is an R7RS `define-library` with `import`,
`export` and `begin` sections, stored at a path that matches its name:
`(sample geometry)` lives in `sample/geometry.sld` under a search directory.
Import sets may use `only`, `except`, `prefix` and `rename`.

```scheme
(import
 (snail core base)
 (snail core io))

(: fibonacci (-> I64 I64))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 30))
(newline)
```

`src/` is always on the search path. `./scripts/snail-tool run -I DIR program.sld` adds more.

A library file may instead hold a `generate-library` recipe: a program whose
value is the library's `define-library` form, as a `Syntax` from
`(snail shell syntax)`. The compiler builds and runs it first:

```scheme
(generate-library (sample table)
  (import
   (snail core base)
   (snail shell syntax))
  (library-syntax (list "sample" "table")
                  (list "squares")
                  (list (list "snail" "core" "base"))
                  (list (form "define" (list (SymbolSyntax "squares")
                                             (form "list" (map (lambda (i) (IntegerSyntax (* i i))) (iota 6))))))))
```

The program writes the syntax as bytes that the compiler decodes, so no text
is printed or parsed in between, and a `BytesSyntax` reaches the compiler
as the bytes it holds. `datum->syntax` from `(snail shell datum)` turns a Scheme
datum into syntax. Every generated form is located at the recipe.

A recipe names the files it reads relative to itself, with the forms any
library uses: `(include-bytes "data/table.txt")` puts a file's bytes in the
recipe as a byte vector literal, and `(link-file "data/table.txt")` links the
file for the producer to read with `read-resource`, since the producer
computes the recipe's expression in a task. Both resolve against the
recipe's file wherever the build prints and runs its producer, so a recipe in
a library directory finds its data from any working directory.
`tests/programs/lib/sample/blob.sld` uses both.

## Forms

| Form | Meaning |
| --- | --- |
| `(define name value)`, `(define (name param ...) body ...)` | Definition. |
| `(lambda (param ...) body ...)` | Function with a fixed number of parameters. |
| `(fn (param ...) body ...)` | Function without an environment: it reads no local of the code around it ([ownership](ownership.md#closures-without-an-environment)). |
| `(if test then [else])` | `test` is `Bool`; without `else` the result is `Unit`. |
| `(begin form ...)` | A body: definitions and expressions in order. |
| `(let ((name value) ...) body ...)`, `(let loop ((name value) ...) body ...)` | Local bindings and loops. |
| `(match value (pattern body ...) ...)` | Pattern matching, checked for exhaustiveness and unreachable clauses. |
| `(: name type)` | Signature for the following definition. |
| `(ann expression type)` | Static type annotation. |
| `(type-convert expression type)` | Converts to or from `Any`; a downcast is checked at run time. |
| `(type-test expression type)` | Whether an `Any` holds a value of `type`, without trapping. |
| `(struct (Name param ...) ((field type) ...))` | Record type. |
| `(enum (Name param ...) (Case [((field type) ...)]) ...)` | Tagged sum. |
| `(type (Name param ...) type)` | Transparent alias. |
| `(typeclass (Class param ...) (: method type) ...)` | Class of types with methods. |
| `(instance (Class type ...) [(requires constraint ...)] (define ...) ...)` | Instance. |
| `(effect Name ((operation type) ...) [(default ((operation implementation) ...))])` | Effect with operations and optional Snail-Core defaults, each a lambda or a function's or extern's name. `(ctl operation type)` declares a control operation, which has no default ([effects and handlers](effects.md)). |
| `(handle Name ((operation implementation) ...) body ...)` | Handles an effect for the extent of `body`; a control operation's implementation also takes `resume`. |
| `(extern name "module" "symbol" type)` | Wasm import, asserted total. |
| `(primitive name type)` | An operation the backend implements, bound to the global `prim:name`. Accepted only in `(snail core primitive)`. |
| `(expose name "symbol")` | Exports a monomorphic top-level function to the host; its arguments and result must be unrestricted. |
| `(expose name "symbol" dynamic)` | Exports it instead for programs that load it as a plugin's (`plugin-function` in `(snail shell wasm)`): behind a wrapper of `Any` values, beside `"symbol:signature"`. Its arguments and result must be data, with no function or `Any` inside, and it must be pure ([plugins](compilers.md#plugins)). |
| `(define-syntax name (syntax-rules (literal ...) (pattern template) ...))` | Hygienic macro. |

`(snail core base)` adds `let*`, `letrec`, `cond`, `case`, `when`, `unless`, `and`,
`or`, `do`, `list`, `string` and a variadic `string-append` as macros.

### Bodies and scope

Library and program top levels see all of their definitions, so top-level
functions may be mutually recursive. A local body is sequential: a definition
is visible to the forms after it, and a local function is also visible to
itself. Write mutually recursive helpers at the top level.

Functions have fixed arity. Where Scheme uses variadic procedures, Snail-Core
uses macros (`list`, `string-append`) or lists.

## Proposed surface design

**Design for review, not implemented.** Everyday programs should be
comfortable to read and write without expertise in Lisp conventions.
Uniform S-expressions are useful for structured syntax and macros, but
they do not require every source operation to use the same punctuation.
Familiar projection syntax such as `a.b.c` should be considered on its
own merits, alongside bindings, calls, signatures and callback bodies.

The proposed [callable signatures](types.md#proposed-callable-typeclass)
use `impl Fun` contracts in place of `->`, with `fun` for definitions.
Direct-style suspension remains available: the compiler turns the remaining
computation into a one-shot callable. Callable contracts expose continuation
boundaries, including through wrapper calls. A separate checked call-site
marker remains open; examples use ordinary operation names and `!` retains
its mutation convention. [Effect transitions](effects.md#resumption-effects-and-effect-transitions)
describe entry and resumption requirements. The proposed
[places and locators](types.md#proposed-places-and-locators) let field
selection describe a typed path without exposing the compiler's field
classes. Exact projection, read, write and continuation-binder syntax
remains open. Choosing `::count!` is not a prerequisite for implementing
typed places, and dot notation need not expose a runtime offset.

Evaluate candidates by rewriting complete examples: the tour's counter,
a nested update in an application, a higher-order collection operation,
and an effect handler. Show the existing and proposed code side by side.
A useful syntax makes the receiver, arguments, binding scope and mutation
visible, works with multiline formatting, and gives useful diagnostics
for incomplete edits. Reducing the number of parentheses alone is not
enough to establish those properties.

Additional surface syntax must produce located, hygienic structure that
the existing expansion and checking pipeline understands. A projection
can remain unresolved until its receiver's type and writable-field
evidence are known. Parsing it must preserve evaluation order and evaluate
the receiver once. Before adopting dots, specify their interaction with
existing identifiers, numeric literals, quoted data and Scheme dotted
lists. Before adopting infix or brace syntax, specify precedence, scope
and macro matching. These are options for review, not selected changes.
The design should preserve one typed language and one compiler pipeline,
with editor, formatter, bootstrap and macro support developed together.

### Sweet-expression reader

**Candidate for review, not implemented.** Evaluate
[SRFI 110 sweet-expressions](https://srfi.schemers.org/srfi-110/srfi-110.html)
as the preferred source notation, selected by a language-reader directive
at the start of every file. A traditional S-expression reader is also
selectable. It combines indentation, call notation and
[SRFI 105 curly infix](https://srfi.schemers.org/srfi-105/srfi-105.html).
It accepts conventionally formatted S-expressions, but is not a
meaning-preserving superset of every traditional source file:

| Input at the start of a line | Traditional reader | Sweet reader |
| --- | --- | --- |
| `f(x)` | Two datums: `f` and `(x)` | One datum: `(f x)` |
| `(f) (g)` | Two datums | One datum: `((f) (g))` |

These distinctions are documented in the SRFI's compatibility section.
The directive selects parsing; parentheses can still be used within sweet
code. Backslash grouping/splitting is available, but explicit lists can
keep it out of routine examples. Curly infix does not supply conventional
operator precedence: write `{a + {b * c}}` to state the grouping.

With the proposed `fun` forms, the same definition could be written as:

```text
#lang snail/sweet
: square impl(Fun(I64 I64))
fun square(n)
  {n * n}
```

Its expansion is the parenthesized definition in
[callable signatures](types.md#proposed-callable-typeclass). Sweet syntax
only changes how forms are written; `fun` remains a separate language
change. Dot projection and typed locators also require their own rules;
adopting this reader does not itself specify field access.

New-file templates should choose sweet syntax, while every source file
declares its language reader. The header spellings `#lang snail/sweet` and
`#lang snail/sexp` are candidates, not implemented syntax. Parse that header
before invoking either reader. The traditional choice preserves exact
S-expression interpretation for generated code and imported libraries.
Both readers produce the same located syntax and share expansion,
checking and lowering. Selection is local to the file and does not
propagate into imports. A stream without a source-file header must have
its reader supplied explicitly by its caller. Supporting arbitrary
user-provided readers is separate from providing these two built-in choices.

During migration, compare both readers' output across the source tree and
add explicit headers or reformat files whose meaning changes. Do not guess
the reader from whether the first expression uses parentheses. Accepting
parenthesized expressions inside sweet source does not replace a true
traditional mode: generated `(f) (g)` must still be two forms when that
reader is selected. The source-file header selects one reader for that
file; support for SRFI parsing directives in data readers is a separate
conformance obligation, not an implicit replacement for the header.

Implement the source reader against the same located syntax consumed by
expansion. Preserve source locations and macro hygiene, and keep generated
binary syntax independent of textual notation. Reader equivalence tests
should compare structures while accounting for their different locations,
then execute equivalent programs. Include blank lines, indentation,
comments, quote forms and advanced markers. The formatter and editor must
agree with the compiler on mode and indentation; changing source syntax
must not silently change a program's data-reading protocol.

Chibi reads the compiler's source directly during stage 0. Adding sweet
syntax to Snail's reader alone does not let Chibi load a converted compiler.
Bootstrap-loaded sources need an explicit, tested header/reader adapter
or preprocessing solution with source mapping before source migration.
Claim SRFI 110 conformance only when its required reader behavior and APIs
are covered; an initial source-reader implementation must state its scope.

### Dot projection as a reader extension

**Candidate syntax, not implemented.** Reuse the neoteric reader's
postfix-to-form approach for field selection. SRFI 105 specifies postfix
calls and a bracket hook, `a[b]` becoming `($bracket-apply$ a b)`. It does
not give `a.b` field-access semantics; its `{a . b}` example produces an
improper form headed by `$nfx$`. Dot projection therefore needs a distinct
Snail extension, rather than treating a standalone dot as an ordinary
infix operator. [SRFI 105](https://srfi.schemers.org/srfi-105/srfi-105.html)

The proposed structural translation is schematically:

```text
a.b.c  =>  (project a b c)
```

`project` stands for a located projection form whose actual name is still
open. `a` is an evaluated expression; `b` and `c` are field labels, not
variable reads. The traditional reader must admit an explicit form with
the same semantics so generated code can express it without dot syntax.
The reader-created form must have a defined hygienic binding; a local
variable must not accidentally change what punctuation means.

For a concrete place receiver, the checked projection composes its static
path and produces another concrete place implementing the `Ref` capability
described in [places](types.md#proposed-places-and-locators).
The reader preserves the path without resolving field types or offsets.
Later checking establishes writable-field evidence and lowering resolves
the layout. Whether projection on an ordinary immutable value reads the
selected value, and how a place is read in a value context, remain explicit
design questions. A computed getter must not become writable by accident.

Projection should compose left to right with calls, so `make().b.c` has
one receiver evaluation. Its lexical rules must distinguish decimal
literals, the standalone dotted-list marker, ellipses and escaped names
that contain dots. Under the traditional reader a dotted identifier keeps
its existing meaning. Compatibility tests must cover these boundaries;
the extension must not split arbitrary identifier strings after parsing.

## Toolchain terms

These names distinguish source organization, compilation and execution.
Project descriptions, builds and the native `snail dev` editor are implemented.
The [application process and persistence workflow](applications.md#proposed-application-processes)
remains proposed.

| Term | Meaning |
| --- | --- |
| Project | One directory of source files and its project description. A plain directory can be edited before a description is added. |
| Workspace | A collection of projects. The tools support one project; they do not introduce a workspace object. |
| Build target | A named description of what to build. It produces one output directory, which may contain multiple files. |
| Artifact bundle | The complete output of a browser build target, resolved by name during compilation. |
| Run target | A named command for running a program build with its arguments. |
| Build attempt | One invocation of project building, with an ID, diagnostics and a success/failure result. |
| Compiler session | Cached expansion, checking and emitted code retained between builds. |
| Development session | A running `snail dev`: file watching, persistent compilation and the editor's services. Application control remains planned. |
| Application process | An OS process running a program. A browser frontend is a client of a server process, not a run target. |
| Runtime | The scheduler and effect bindings executing a program's tasks. It is distinct from both the compiler session and the OS process. |
| Host | The platform environment, such as Node or a browser, providing APIs to the runtime. |
| Worker | A separate execution agent used for CPU work, such as a Node worker thread; it is not a browser Service Worker or a Snail-Core task. |
| Working state | In-memory values used by the running application, including changes not yet saved. |
| Persisted data | The application's chosen representation committed to storage independently of the running code. It need not encode every transient resource or cache. |

**Incremental compilation** reuses compiler work. **Restart** starts a fresh
application process; the application can reconstruct working state from
persisted data. **Hot reload** (also called live reload) replaces
running code while preserving application data under a stated contract.
Today's browser uses state handover; the proposal uses durable typed tables
and disposable cached views, recomputed on demand after ordinary startup.
Recompiling incrementally does not by itself preserve application state, and
moving execution into a worker does not supply a preservation contract.
