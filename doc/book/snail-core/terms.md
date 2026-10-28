# Terms

## Programs and libraries

A program is a file of `import` forms followed by definitions and expressions,
which run in order. A library is an R7RS `define-library` with `import`,
`export` and `begin` sections, stored at a path that matches its name:
`(sample geometry)` lives in `sample/geometry.sld` under a search directory.
Import sets may use `only`, `except`, `prefix` and `rename`.

```scheme
(import
 (snail-core base)
 (snail-core io))

(: fibonacci (-> I64 I64))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(display (fibonacci 30))
(newline)
```

`src/` is always on the search path. `./scripts/snail-tool run -I DIR program.sld` adds more.

A library file may instead hold a `generate-library` recipe: a program whose
value is the library's `define-library` form, as a `Syntax` from
`(snail-core syntax)`. The compiler builds and runs it first:

```scheme
(generate-library (sample table)
  (import
   (snail-core base)
   (snail-core syntax))
  (library-syntax (list "sample" "table")
                  (list "squares")
                  (list (list "snail-core" "base"))
                  (list (form "define" (list (SymbolSyntax "squares")
                                             (form "list" (map (lambda (i) (IntegerSyntax (* i i))) (iota 6))))))))
```

The program writes the syntax as bytes that the compiler decodes, so no text
is printed or parsed in between, and a `BytesSyntax` reaches the compiler
as the bytes it holds. `datum->syntax` from `(snail-core datum)` turns a Scheme
datum into syntax. Every generated form is located at the recipe.

## Forms

| Form | Meaning |
| --- | --- |
| `(define name value)`, `(define (name param ...) body ...)` | Definition. |
| `(lambda (param ...) body ...)` | Function with a fixed number of parameters. |
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
| `(effect Name ((operation type) ...) [(host "module" ((operation "symbol") ...))])` | Effect with operations and optional host defaults. |
| `(handle Name ((operation implementation) ...) body ...)` | Handles an effect for the extent of `body`. |
| `(extern name "module" "symbol" type)` | Wasm import, asserted total. |
| `(primitive name type)` | An operation the backend implements, bound to the global `prim:name`. Accepted only in `(snail-core primitive)`. |
| `(expose name "symbol")` | Exports a monomorphic top-level function to the host; its arguments and result must be unrestricted. |
| `(expose name "symbol" dynamic)` | Exports it instead for programs that load it as a plugin's (`plugin-function` in `(snail-core wasm)`): behind a wrapper of `Any` values, beside `"symbol:signature"`. Its arguments and result must be data, with no function or `Any` inside, and it must be pure ([plugins](compilers.md#plugins)). |
| `(define-syntax name (syntax-rules (literal ...) (pattern template) ...))` | Hygienic macro. |

`(snail-core base)` adds `let*`, `letrec`, `cond`, `case`, `when`, `unless`, `and`,
`or`, `do`, `list`, `string` and a variadic `string-append` as macros.

### Bodies and scope

Library and program top levels see all of their definitions, so top-level
functions may be mutually recursive. A local body is sequential: a definition
is visible to the forms after it, and a local function is also visible to
itself. Write mutually recursive helpers at the top level.

Functions have fixed arity. Where Scheme uses variadic procedures, Snail-Core
uses macros (`list`, `string-append`) or lists.

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
| Worker | A separate execution agent used for CPU work. Here a native compiler worker keeps its own compiler state; it is not a browser Service Worker or a Snail-Core task. |
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
