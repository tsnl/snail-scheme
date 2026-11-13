# Terms

## Programs and libraries

A program is a file of `import` forms followed by declarations and definitions.
Its root `main` starts runtime work. Top-level definitions bind functions;
values live in function bodies and explicit state objects. Importing a library
runs no source initializer. A library uses `define-library` with `import`,
`export` and `begin` sections, stored at a path that matches its name:
`(sample geometry)` lives in `sample/geometry.sld` under a search directory.
Import sets may use `only`, `except`, `prefix` and `rename`.

```scheme
(import
 (snail core base)
 (snail core io))


(define (fibonacci (n I64)) (→ I64)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(define (main) (→ Unit) (! output-port)
  (write-line (show (fibonacci 30))))
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
as the bytes it holds. Construct syntax explicitly with `(snail shell syntax)`.
Every generated form is located at the recipe.

A recipe names the files it reads relative to itself, with the forms any
library uses: `(link-file "data/table.txt")` declares a packaged resource,
and `read-resource` reads its bytes when the producer runs. A producer can emit
those bytes as a byte literal in its generated library.
`tests/programs/lib/sample/blob.sld` demonstrates this flow.

## Forms

| Form | Meaning |
| --- | --- |
| `(define (name (param type) ...) (→ Result) [header ...] body ...)` | Typed function definition. Optional effect, generic and constraint clauses precede the body. A direct lambda definition can infer its type; ordinary value definitions are local only. |
| `(lambda (param ...) body ...)` | Function with a fixed number of parameters. |
| `(if test then [else])` | `test` is `Bool`; without `else` the result is `Unit`. |
| `(begin form ...)` | A body: definitions and expressions in order. |
| `(let ((name value) ...) body ...)`, `(let loop ((name value) ...) body ...)` | Local bindings and loops. |
| `(match value (pattern body ...) ...)` | Pattern matching, checked for exhaustiveness and unreachable clauses. |
| `(declare (name (param type) ...) (→ Result) [header ...])` | Bodyless method declaration in a typeclass, with the same header as a function definition. |
| `(ann expression type)` | Static type annotation. |
| `(cache function)` | A closure with the same signature and a private, unbounded result cache. |
| `(lru-cache capacity function)` | The same wrapper with a least-recently-used entry limit. |
| `(Any expression)` | Boxes an unrestricted value with its concrete type. |
| `(downcast Type boxed)` | Returns `Some` of the payload if its type matches, or `None`. |
| `(struct (Name param ...) ((field type) ...))` | Record type. |
| `(enum (Name param ...) (Case [((field type) ...)]) ...)` | Tagged sum. |
| `(type (Name param ...) type)` | Transparent alias. |
| `(typeclass (Class param ...) (declare (method ...) ...) ...)` | Class of types with methods. |
| `(instance (Class type ...) [(⊨ constraint ...)] (define ...) ...)` | Instance. |
| `(effect Name ((operation type) ...) [(default ((operation implementation) ...))])` | Effect with operations and optional Snail Scheme defaults, each a lambda or a function's or extern's name. `(ctl operation type)` declares a control operation, which has no default ([effects and handlers](effects.md)). |
| `(handle Name ((operation implementation) ...) body ...)` | Handles an effect for the extent of `body`; a control operation's implementation also takes `resume`. |
| `(extern name "module" "symbol" type)` | Wasm import, asserted total. |
| `(primitive name type)` | An operation the backend implements, bound to the global `prim:name`. Accepted only in `(snail core primitive)`. |
| `(expose name "symbol")` | Exports a monomorphic top-level function to the host; its arguments and result must be unrestricted. |
| `(define-syntax name (syntax-rules (literal ...) (pattern template) ...))` | Hygienic macro. |

`(snail core base)` adds `let*`, `letrec`, `cond`, `case`, `when`, `unless`, `and`,
`or`, `do`, `list`, `string` and a variadic `string-append` as macros.

### Bodies and scope

Library and program top levels see all of their definitions, so top-level
functions may be mutually recursive. A local body is sequential: a definition
is visible to the forms after it, and a local function is also visible to
itself. Write mutually recursive helpers at the top level.

Functions have fixed arity. Where Scheme uses variadic procedures, Snail Scheme
uses macros (`list`, `string-append`) or lists.

## Cached functions

`cache` and `lru-cache` wrap ordinary functions, including lambdas. They preserve
all argument types, the result type, and the effect row; they work at any fixed
arity. The callback expression is evaluated once. Each wrapper owns a fresh
local cache that remains alive between calls. Aliases of that wrapper share its
cache, while two evaluations of `(cache f)` have separate caches.

```scheme
(define (make-lookup) (→ (Fn I64 → I64))
  (cache (lambda (key) (* key key))))

(define (use-lookup) (→ I64)
  (let ((lookup (lru-cache 128 (lambda (key) (* key key)))))
    (+ (lookup 12) (lookup 12))))
```

An unbounded cache retains successful results until its wrapper becomes
unreachable. An LRU cache holds at most `capacity` entries; a hit moves its entry
to the front, and insertion evicts the least recently used entry if needed.
Capacity zero returns the original function without caching; a negative capacity
panics when constructing the wrapper. Zero-argument functions use a single
cached result slot.

Every positional argument participates in the key. Integers, booleans, characters
and fieldless enum cases compare by value; strings compare by content. Floating
point keys compare their bits, so signed zeros differ and identical NaN bit
patterns match. Other heap objects compare by identity. Mutating an object key
does not invalidate its entry. Results are shared objects, so callers see mutations
to a cached result.

Scalar and string hashes distribute entries into growing hash buckets; collisions
always check complete key equality. WasmGC has no portable identity hash, so
object components contribute a constant hash. Object-only keys can therefore
require a linear bucket search. Mixed keys still benefit from scalar and string
components. There is no hidden identity field added to user objects.

Raw `Funcref` host handles cannot be keys. Keys and results must have no
deterministic cleanup, including through their
fields. Linear values, `Rc`, `Any`, functions, and aggregates containing them are
rejected. Plain mutable structs and vectors are allowed. The callback may itself
capture counted resources: its usual closure ownership keeps them alive and
releases them when the last wrapper owner leaves. `FnOnce` callbacks and callbacks
that can perform control operations are rejected.

A hit skips the callback body, including its effects. Ordinary closure cleanup
still runs when an owner leaves scope. Cache only functions for which
that behavior is intended; the type system does not prove that mutation or
external state cannot change their answers. The private cache adds no effect to
the function's signature. A result is stored only after a successful return.
Reentrant calls can populate the same cache: the last successful completion for
a key wins, and each call returns its own computed result. There is no in-progress
entry or recursive-cycle guard. Wrapping a function does not redirect its original
recursive references through the wrapper.

**Possible follow-up, not implemented:** dedicated `rc-cache` and `lru-rc-cache`
wrappers could support `Rc T` results without keeping their payloads alive. Their
maps would store only `WeakRc T`: upgrade a live hit to a strong result, or
recompute after a dead hit. A miss holds and returns the callback's strong result
while recording its weak reference. Periodic pruning removes dead entries, and
bounded eviction prefers dead entries before the least recently used live entry.
The pruning schedule and effect contract remain design work on [the roadmap](https://github.com/tsnl/snail-scheme/issues/729).
Ordinary `cache` and `lru-cache` reject `Rc` results today; `WeakRc` results are
allowed, and their cached weak references may become dead.

A local wrapper has one monomorphic callable type. Generic factory functions can
create fresh wrappers for different concrete types; one wrapper is never shared
across unrelated type instantiations.

### Cache performance

A focused V8 benchmark measures 50,000 calls over 128 scalar keys, including each
wrapper's creation and initial misses. On an Intel Core Ultra 7 270K Plus, two
processes with 21 alternating-order samples each measured:

| Workload | Plain function | `cache` | `lru-cache 128` |
| --- | ---: | ---: | ---: |
| 64-step integer calculation, repeated keys | 9.04–9.50 ms | 0.297–0.301 ms | 0.384–0.386 ms |
| One multiplication, repeated keys | 0.142–0.143 ms | 0.274–0.276 ms | — |
| One multiplication, 20,000 distinct keys | 0.0571–0.0573 ms | 0.427–0.428 ms | — |

Caching helps when avoided work exceeds lookup and storage costs. Here the
repeated expensive calculation is about 30–32 times faster; trivial repeated
work costs about 1.9 times as much, and all-miss trivial work costs about 7.5 times
as much. These are scalar-key microbenchmarks, not compiler-wide or object-key
performance claims. The LRU capacity fits every key, so eviction pressure is not
measured. Forced GC runs outside timing; wrapper release is included, but eventual
collection of discarded tables is not measured. [Raw samples and artifact hashes](measurements/function-cache-20261113.json)
include an independent-process confirmation. Reproduce after building the
compiler:

```sh
./scripts/snail-tool compile -o build/function-cache.wasm tests/benchmarks/function-cache.sld
taskset -c 2 node --no-warnings --expose-gc scripts/benchmark-cache.mjs build/function-cache.wasm
```

## Proposed surface design

**Design for review, not implemented.** Everyday programs should be
comfortable to read and write without expertise in Lisp conventions.
Uniform S-expressions are useful for structured syntax and macros, but
they do not require every source operation to use the same punctuation.
Familiar projection syntax such as `a.b.c` should be considered on its
own merits, alongside bindings, calls, signatures and callback bodies.

The implemented [function types](types.md#function-types) are `Fn` and
`FnOnce`, with `→` separating the result and `!` introducing effects. Named
functions use typed parameter pairs and inline result, effect, generic and
constraint clauses. Definitions continue to use `define`.

Direct field selection is `(● receiver label ...)`: each nominal struct type
supplies its stored fields, and paths follow heap references, including `Rc`
payloads. Use a projection in `set!` or `replace!` to write its final field.
Every field is mutable. Computed getters are ordinary functions.

Direct-style suspension remains available: the compiler turns the remaining
computation into a one-shot callable. Callable types expose continuation
boundaries, including through wrapper calls. A separate checked call-site
marker remains open; examples use ordinary operation names, and `!` retains
its mutation convention. [Effect transitions](effects.md#resumption-effects-and-effect-transitions)
describe entry and resumption requirements. Dot notation need not expose a
runtime offset or change ownership.

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

With the existing definition form, the same callable could be written as:

```text
#lang snail/sweet
define square(n(I64)) (→ I64)
  {n * n}
```

Its expansion is the parenthesized definition in
[function signatures](types.md#functions). Sweet syntax
only changes how forms are written. Dot projection and typed locators also require their own rules;
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

Chez reads the compiler's source directly during stage 0. Adding sweet
syntax to Snail's reader alone does not let Chez load a converted compiler.
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

The translation should preserve the existing nominal projection semantics:
read `(● object field ...)`, or use that projection in `set!` / `replace!`.
Each step follows one object reference. Field lookup is resolved during
checking, and every stored field is mutable. Computed getters are ordinary
functions and do not become writable by punctuation.

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
| Development session | A running `snail dev`: file watching, persistent compilation and the editor's services. Application control remains planned. |
| Application process | An OS process running a program. A browser frontend is a client of a server process, not a run target. |
| Runtime | The scheduler and effect bindings executing a program's tasks. It is distinct from compilation and the OS process. |
| Host | The platform environment, such as Node or a browser, providing APIs to the runtime. |
| Worker | A separate execution agent used for CPU work, such as a Node worker thread; it is not a browser Service Worker or a Snail Scheme task. |
| Working state | In-memory values used by the running application, including changes not yet saved. |
| Persisted data | The application's chosen representation committed to storage independently of the running code. It need not encode every transient resource or cache. |

**Incremental compilation** reuses compiler work. **Restart** starts a fresh
application process; the application can reconstruct working state from
persisted data. **Hot reload** (also called live reload) replaces
running code while preserving application data under a stated contract.
Today's browser uses state handover; the proposal uses durable typed tables
and disposable cached views, recomputed on demand after ordinary startup.
Recompiling does not by itself preserve application state, and
moving execution into a worker does not supply a preservation contract.
