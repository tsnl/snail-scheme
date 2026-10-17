# Libraries

So far, a program has been expressions and definitions with familiar names such
as `+` already available. Libraries explain where those names come from and how
separately written pieces fit together.

A `LofiLibrary` describes one source unit: imports, exports, declarations and
source locations. Plain kernel source is parsed immediately. Source that needs
imported macros retains its located syntax until resolution supplies the
transformers and their binding identities. Expansion then produces the same
Lofi declarations. Neither representation is fully typed until checking.

Library names correspond to paths under `src/`: `(scheme base)` lives at
`src/scheme/base.sld`, `(lofi compiler)` at `src/lofi/compiler.sld`. Imports select
language/forms; `.sld` is common to all of them.

## Writing a library

`define-library` is the file-level notation for describing a library value.
Its import clauses state which bindings the body can use; its export clauses
state which bindings other libraries can use.

```scheme
                                        ; demo/math.sld
(define-library (demo math)
  (import
   (lofi base))
  (export increment)
  (begin
    (def increment (-> I32 I32) (lambda (value) (+ value 1)))))

                                        ; demo/app.sld
(define-library (demo app)
  (import
   (lofi base)
   (only (demo math) increment))
  (export main)
  (begin
    (def main (-> I32) (lambda () (increment 41)))))
```

Here the `begin` clause contains the library's statements; it does not need a
final result expression. Its bindings follow the same scope and initialization
rules as a local block. Top-level snippets in the earlier chapters represent the
body of an implicit library supplied by an interactive host or script driver.

Reading this description produces data. It does not run `main` or initialize
the described bindings. The parser or generator that produces the library may
itself perform effects, such as reading source files.

```text
library_name ::= "(" name name … ")"

library_file ::= "(" "define-library" library_name library_clause … ")"

library_clause ::= import_clause
                 | export_clause
                 | body_clause

import_clause ::= "(" "import" import_set … ")"

export_clause ::= "(" "export" export_spec … ")"

body_clause ::= "(" "begin" library_statement … ")"

library_statement ::= statement
                    | static_definition
                    | library_splice

library_splice ::= "(" "library-begin" library_statement … ")"

import_set ::= library_name
             | "(" "only" import_set name … ")"
             | "(" "rename" import_set rename_pair … ")"

rename_pair ::= "(" name name ")"

export_spec ::= name
              | "(" "rename" name name ")"
```

`library_name` contains name components such as `(demo math)`. An import
`rename_pair` lists the original name followed by the local name; an export
rename lists the local name followed by the public name.

Multiple body clauses concatenate their statements in source order. Import
clauses supply bindings to the whole body; they are not executable statements.
Within a body, `library-begin` splices several forms into the same library scope;
it is useful when a [macro](macros.md#producing-several-library-declarations)
generates a type and several operations together. Ordinary expression `begin`
still creates a lexical block. Neither body macros nor splices may generate
import, export or `define-library` directives.

## Exports and imports

An export gives a binding a public name. Unexported names remain private, but
exported functions can still refer to private definitions. Exporting a type
preserves its nominal identity; constructors and accessors must be exported
separately to be available by name. Re-exporting an imported binding preserves
its original identity and does not copy its value or implementation. The same
rules apply to [macros](macros.md); their templates retain private definition-site
bindings without exposing those names in the public interface.

An import introduces local names for exported bindings. `only` restricts the
names introduced; `rename` changes their local spelling. Two import paths to
the same binding retain that identity. Distinct bindings cannot occupy the same
local name, and distinct exports cannot have the same public name. Instance
declarations accompany their provider's interface and participate in coherent
instance selection even when an `only` clause restricts value names.

Consider the application's `increment` import:

1. A driver supplies a library under the key `(demo math)`.
2. Resolution finds that library's public name `increment` and follows it to
   the original binding identity, including through any re-exports.
3. References to the application's local `increment` now denote that binding.
4. Checking uses its declared or inferred signature, `(-> I32 I32)`, to check
   the argument `41` and the result expected by `main`.

A missing library, missing export or conflicting local name is an error.
Resolution operates on supplied values. It does not search the filesystem or
run the provider's initializers.

## Finding source files

The default source driver supplies those values by searching explicit `-I`
directories. `(demo math)` maps to `demo/math.sld`. Search directories in the
given order and use the first matching file; report its path in diagnostics.
A found file must describe the requested name with `define-library` or the
`generate-library` form below. Parse errors in a found file are errors, not a
reason to silently try a different directory.

For each requested key, the driver records one chosen library in the graph
being assembled and recursively obtains its imports. Repeated imports use
that graph entry. This is an explicit choice of library identity within one
build, not a global cache of running instances. A caller can instead construct
the map itself or supply the same library under several keys.

Producing one library does not require its entire dependency closure. Checking
it requires the relevant interfaces; compiling the assembled program requires
the implementations it uses. The driver can therefore prepare libraries
separately and assemble them later. Inferred exports wait until their dependency
interfaces are available. Library dependency cycles are rejected in this model;
recursion inside a library remains supported.

## Generating a library

A file may describe how to produce a library instead of spelling out its
declarations. The driver recognizes this second file-level form:

```scheme
                                        ; demo/legacy.sld
(generate-library (demo legacy)
                  (import
                   (lofi base)
                   (lofi compiler)
                   (frontend scheme))
                  (scheme->lofi (read-source "legacy.scm")))
```

The imports belong to the generator. Its body is an ordinary Lofi expression
that must return a `LofiLibrary`. The driver runs it and registers that result
under `(demo legacy)`. The result has its own imports for the generated program.
Relative source paths in this example are resolved against the descriptor's
directory, which the driver supplies as an explicit source context.

```text
generation_file ::= "(" "generate-library" library_name import_clause expression ")"
```

This is a driver-level recipe for calling code that produces a library. It does
not add macros or implicit staging to expression evaluation. A manually written
build can call the same producer function directly. In its choice of a language
frontend the recipe resembles Racket's `#lang`; selection here is explicit in
the file, without dispatch based on the input's extension.

The [next chapter](compilers.md) explains how a generator written in Lofi can
itself be compiled and executed.

## The library value

The following record definitions fix the data boundary using the same
single-constructor `datatype` form as other structs. `LibraryId`, `BindingId`
and `ScopeId` are opaque identities; `Name` is an identifier spelling
and `LibraryKey` is a sequence of name components. `SourceSpan` describes an
input location. `Declaration` is a structured language declaration containing
its local binders, references and annotations. A `BindingReference` is either a
local binding identity or a name together with the scope in which to resolve it.

```scheme
(def ImportRename
     (datatype ()
       (import-rename
        (original Name)
        (local Name))))
(def ImportSelection
     (datatype ()
       (all-imports)
       (only-imports
        (from ImportSelection)
        (names (List Name)))
       (rename-imports
        (from ImportSelection)
        (names (List ImportRename)))))
(def Import
     (datatype ()
       (library-import
        (provider LibraryKey)
        (selection ImportSelection)
        (scope ScopeId))))
(def Export
     (datatype ()
       (library-export
        (public Name)
        (binding BindingReference))))
(def LocatedDeclaration
     (datatype ()
       (located-declaration
        (location SourceSpan)
        (declaration Declaration))))
(def LofiLibrary
     (datatype ()
       (lofi-library
        (id LibraryId)
        (imports (List Import))
        (exports (List Export))
        (declarations (List LocatedDeclaration)))))
```

Import selections remain descriptive until the provider's exports are available.
This lets parsing produce a library without first obtaining its dependencies.
Resolution expands the selections and associates the imported names in each
scope with the providers' canonical binding identities. Exports can refer to
those names to re-export imports. References carry binding identities or scoped
names, never just an unscoped string. Declarations retain their lexical structure
and source order, including private definitions and polymorphic function bodies
needed for specialization.

Fresh parsing creates fresh local identities. Aliasing a library value preserves
its identity. Combining independently produced libraries must preserve their
private scopes, never merge bindings merely because their names match. A
producer cannot forge evidence that a declaration has passed checking:
resolution and type checking construct that evidence before code generation.
