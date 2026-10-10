# Generated libraries

`generate-library` is a planned feature. It is not implemented, and the examples
in this document do not run in the current compiler. This note records the
intended shape and staging model; it does not commit to a generator result API.

## A Scheme wrapper for another source format

A Scheme file explicitly describes how to turn source files into a library.
The source files keep their own syntax. There is no `#lang` prefix, reader
registry, extension-based selection, or language-definition lookup. Ordinary
Scheme code chooses the reader and supplies its input paths.

Like `define-library`, `generate-library` declares a library name, imports, and
exports. It has exactly one `begin` clause. The forms in that clause are the
body of a function that runs during library generation. Internal definitions
and ordinary Scheme expressions are allowed; the final expression produces the
library's implementation.

```scheme
;; site/guide.sld -- proposed syntax
(generate-library (site guide)
  (export make-page)
  (import (scheme base)
          (site markup-reader))
  (begin
    (define source "./guide.markup")
    (read-markup-library-contents source)))
```

`read-markup-library-contents` is an illustrative reader procedure, not an
existing API. The reader is an ordinary Scheme dependency used by the function
body. There is no separate generator-script declaration or named entry procedure.

Conceptually, `begin` supplies the body of a thunk evaluated in the environment
established by the generator's imports. Its forms are executed to produce syntax;
they are not copied into the generated library's runtime body.

One wrapper describes an independently imported library. Its reader may consume
several supporting files without giving each fragment or asset its own wrapper.
An ordinary Scheme entry program can import the resulting library. Any future
direct invocation of a foreign entry file should select its wrapper explicitly.

## Imports and exports across stages

The outer `import` declarations apply to the generator code. Imports required
by the generated code are separate and must be supplied by the generator's
result. A generator-only dependency does not become a runtime dependency merely
because generation used it.

The outer `export` declarations describe the resulting library's public
interface. They refer to bindings in the generated implementation, not to local
variables or procedures used while generating it. Normal export resolution,
including renaming, happens after generation.

For example, the preceding declaration could produce the equivalent of:

```scheme
(define-library (site guide)
  (export make-page)
  (import (scheme base)
          (site document))
  (begin
    (define (make-page)
      (document
        (paragraph "Hello, " (emphasis "reader") ".")))))
```

Here `(site markup-reader)` runs during generation; `(site document)` supplies
bindings to the generated program. The document procedures are also illustrative.
The wrapper owns the library name and exports. The result supplies implementation
code and the imports that code requires.

The exact result representation remains open. A list of located implementation
declarations, containing generated `import` and `begin` forms, is one candidate.
The compiler would assemble those declarations with the wrapper's name and
exports into ordinary `define-library` syntax. The result protocol must specify
which declarations are accepted and reject conflicting names or exports.

## Staging

Reading embedded Scheme syntax does not execute that Scheme code.

| Stage | Work |
| --- | --- |
| Generate the library | Run the generator body, read source files, and produce located Scheme syntax. |
| Compile the library | Resolve generated imports and exports, expand macros, and compile its implementation. |
| Run the generated program | Execute generated procedures, for example to construct and render a document. |
| Interact with a workbook | Execute computations explicitly assigned to the workbook's interaction stage. |

A generator can deliberately compute a value and emit a literal containing it.
It can instead emit an expression whose computation belongs to a later stage.
Host closures and other live generator objects do not implicitly cross this
boundary: the output is Scheme syntax, subject to the compiler's supported forms
and literal representations.

Generator imports and generated imports are distinct dependency edges, even
when they name the same library. Loading a library to run generator code must not
accidentally execute its generated runtime counterpart. Generation cycles need
diagnostics that identify the stage and dependency path.

## Paths, dependencies, and source locations

Source paths written in the wrapper should resolve relative to that wrapper,
independent of the process's working directory. A reader that supports includes
should resolve them relative to the including source. This path policy needs an
explicit source-opening API; ordinary host file operations alone do not establish
it.

Generation must account for the wrapper, generator libraries, input files, and
discovered includes. A tracked read operation or dependency-reporting mechanism
is still to be designed. Untracked IO cannot be assumed cacheable. The first
implementation can regenerate on every build; persistent caching requires a
complete dependency contract, including options and relevant tool versions.

Readers should return located syntax using the existing syntax records. An
embedded expression should retain its original filename and position, so an
unbound identifier points into the document. Generated scaffolding should have
an identifiable origin in the wrapper or source construct that produced it.
Source locations do not solve identifier capture: generated helper bindings
also need a deliberate hygiene policy.

## Compiler integration and remaining work

The current [compiler loader](../src/snail-scheme/compiler.sld) reads one located
library declaration. The [expander](../src/snail-scheme/expand.sld) expects that
declaration to be `define-library`. A future preparation step can recognize
`generate-library`, execute its body, and normalize its result before handing
the library to ordinary expansion. A regular macro cannot supply this step on
its own: the generator must run before its library implementation can be expanded.

The compiler remains hosted by Chibi. An initial generator runner should use
that host, with a separate generator environment. This is not a self-hosting
milestone or a claim that the expander already supports arbitrary compile-time
Scheme evaluation. The runner must define how host-compatible generator
dependencies are loaded and how their locations and dependencies are retained.

Before implementation, settle the result protocol, generator environment,
tracked source-opening API, cycle handling, and generated-name hygiene. Then
exercise one reader through an import and an entry program, checking failures
against the original source locations and separating generator effects from
runtime effects.

The document-composition API can be prototyped as ordinary Scheme running under
Chibi independently of this feature. A future markup reader would generate calls
to that API; its functions would execute at the document-construction stage.

The [staged-program scope](staged-programs.md) explores a wrapper producing a
server library together with browser and shader artifacts. It keeps compiler
phases distinct from runtime targets and identifies the additional artifact and
procedural-transformer APIs that this would require. These are also planned.

The [application-engine plan](application-engines.md) describes the separate
runtime contract: an engine invokes exported behavior, while ordinary runtime
functions provide explicit state retention. Generating a library does not grant
its globals persistence or implement the engine's reload protocol.
