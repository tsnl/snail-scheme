;; Located syntax to the core program. The expander is the only pass that knows
;; Snail-Core's binding forms. It loads libraries, resolves every identifier to a
;; binding, runs `syntax-rules` macros, records declared entities in the
;; program tables, and emits core expressions with unique names.
(define-library (snail shell compiler expand)
  (export
   ExpandedProgram
   empty-expansion
   library-key
   expand-program
   ArtifactUse
   discover-artifacts
   LinkedFile
   library-links
   program-links
   LibraryFile
   DefinedLibrary
   GeneratedLibrary
   library-file
   program-imports
   implicit-libraries
   Reached
   library-closure)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail shell compiler read)
   (snail shell compiler annotations)
   (only (snail shell compiler inputs)
         ArtifactFiles
         Inputs
         producer-text
         generated-output
         request-input
         generating-stack
         read-source-file)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (snail shell compiler dynamic)
   (snail shell compiler sha256))
  (begin

    ;; ---- Bindings and environments ----

    ;; What an identifier denotes. A struct's name is both a type and its
    ;; constructor. A macro remembers the scope it was defined in by number,
    ;; because the marks on the identifiers it introduces refer to it.
    (enum Binding
      (Local
       ((name String)))
      (Global
       ((name String)))
      (TypeName
       ((name String)
        (arity I64)
        (constructor (Option String))))
      (Alias
       ((name String)
        (params (List Syntax))
        (body Syntax)
        (env Env)))
      (TypeVar
       ((type Type)))
      (ClassName
       ((name String)))
      (InstanceSet
       ((name String)))
      (Associated
       ((class String)
        (member String)))
      (EffectName
       ((name String)))
      (Core
       ((name String)))
      (Macro
       ((id String)
        (literals (List Syntax))
        (rules (List Syntax))
        (scope I64))))

    ;; Two bindings are the same when they denote the same entity, which
    ;; unique names identify.
    (: binding-identity (impl (Fn Binding -> String)))
    (define (binding-identity binding)
      (match binding
        ((Local name) name)
        ((Global name) name)
        ((TypeName name _ _) name)
        ((Alias name _ _ _) name)
        ((TypeVar _) "%type-variable")
        ((ClassName name) name)
        ((InstanceSet name) name)
        ((Associated class member) (string-append class "." member))
        ((EffectName name) name)
        ((Core name) (string-append "%core " name))
        ((Macro id _ _ _) id)))

    ;; An environment is a chain of local frames, each binding one
    ;; identifier, that ends in a top level: the definitions the scan makes
    ;; before any body is expanded, over the table of its imports. Frames
    ;; never change; a body that defines a name passes a longer chain to the
    ;; forms after it. A top level's definitions are the context's, under the
    ;; top level's key, so an environment made before the scan bound a name
    ;; resolves it as well as one made after.
    (enum Env
      (Frame
       ((key String)
        (binding Binding)
        (rest Env)))
      (InstanceScope
       ((sets (List Syntax))
        (rest Env)))
      (InstanceOwner
       ((name String)
        (rest Env)))
      (EvidenceScope
       ((constraints (List Constraint))
        (rest Env)))
      (Top
       ((key String)
        (imports (Table Binding)))))

    (: extend (impl (Fn Env Syntax Binding -> Env)))
    (define (extend env ident binding)
      (Frame (ident-key ident) binding env))

    ;; A marked identifier is keyed by its mark, so the same name introduced by
    ;; two expansions binds two variables.
    (: ident-key (impl (Fn Syntax -> String)))
    (define (ident-key ident)
      (match ident
        ((Ident _ (Some mark) _) (::key mark))
        ((Ident name (None) _) name)
        (_ (panic "internal error: not an identifier"))))

    ;; An unbound marked identifier resolves as its original in the scope of
    ;; the macro that introduced it.
    (: resolve (impl (Fn Context Env Syntax -> (Option Binding))))
    (define (resolve cx env ident)
      (let ((key (ident-key ident)))
        (let lookup ((env env))
          (match env
            ((InstanceScope _ rest) (lookup rest))
            ((InstanceOwner _ rest) (lookup rest))
            ((EvidenceScope _ rest) (lookup rest))
            ((Frame other binding rest) (if (string=? other key) (Some binding) (lookup rest)))
            ((Top top imports)
             (match (top-binding cx top imports key)
               ((Some binding) (Some binding))
               ((None)
                (match ident
                  ((Ident _ (Some mark) _)
                   (resolve cx (scope-env cx (::scope mark)) (::original mark)))
                  (_ (None))))))))))

    ;; What a top level binds `key` to: its own definition, or else an
    ;; import.
    (: top-binding (impl (Fn Context String (Table Binding) String -> (Option Binding))))
    (define (top-binding cx top imports key)
      (match (table-ref (top-definitions cx top) key)
        ((Some binding) (Some binding))
        ((None) (table-ref imports key))))

    (: expect-ident (impl (Fn Syntax String -> Syntax ! compile)))
    (define (expect-ident syntax what)
      (match syntax
        ((Ident _ _ _) syntax)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items of a form, or an error naming what was expected.
    (: form-items (impl (Fn Syntax String -> (List Syntax) ! compile)))
    (define (form-items syntax what)
      (match syntax
        ((Form items _) items)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items after a form's head.
    (: form-tail (impl (Fn Syntax -> (List Syntax))))
    (define (form-tail syntax)
      (match syntax
        ((Form (Cons _ rest) _) rest)
        (_ (Nil))))

    (: head-binding (impl (Fn Context Env Syntax -> (Option Binding))))
    (define (head-binding cx env syntax)
      (match syntax
        ((Form (Cons head _) _)
         (match head
           ((Ident _ _ _) (resolve cx env head))
           (_ (None))))
        (_ (None))))

    (: core-form? (impl (Fn Context Env Syntax String -> Bool)))
    (define (core-form? cx env syntax name)
      (match (head-binding cx env syntax)
        ((Some (Core keyword)) (string=? keyword name))
        (_ #f)))

    ;; ---- Expansion context ----

    ;; One build's expansion, made fresh for each build and threaded through
    ;; it as plain data: a step takes the context and hands back the one it
    ;; learned in. Its fields fall into three kinds.
    ;;
    ;; What the build is given, which never changes: `predecessor` holds the
    ;; libraries of the build before, which this one replays where their
    ;; declarations and their imports' interfaces are unchanged, and a
    ;; one-off compile has none; `directories` are searched for libraries;
    ;; `generate` runs a producer program the build did not supply for
    ;; `generate-library`, given the libraries loading when it was reached,
    ;; and returns the bytes of the syntax it writes; the driver supplies it,
    ;; because running a program means compiling one; `inputs` holds what
    ;; the build supplies in memory: completed targets' files and producers'
    ;; outputs; and `recipe`, in a producer program, is the recipe its
    ;; printed copy stands for.
    ;;
    ;; Scope, which loading a library replaces and which the importer gets
    ;; back unchanged: `prefix` names the library being expanded, so its
    ;; globals are `prefix:name`; `loading` the libraries whose imports are
    ;; being loaded, innermost first, so a library requested while it loads
    ;; is part of an import cycle; `aliases` the type aliases whose bodies
    ;; are being resolved, innermost first, so an alias that refers to itself
    ;; is caught; and what the library itself uses and makes, newest first:
    ;; `artifact-uses`, the targets whose files it embeds, `links`, the
    ;; files its `link-handle` uses name, `items`, the items its body has
    ;; added so far, which join the program as one run when the body is
    ;; done, and `derives`, a declaration it derived instances for, if any,
    ;; which needs the implicit libraries.
    ;;
    ;; What the build has learned, which flows forward out of every library:
    ;; `program` is the program built so far, and `expanded` holds each
    ;; library this build has expanded, with what a later build needs to
    ;; replay it. `artifacts` says where an `artifact-files` use finds its
    ;; files; a discovery records there each use it reaches. `counter`
    ;; numbers fresh names. `scopes` holds the environments that marks refer
    ;; to, by number, and `scope-count` is the next number; `tops` holds
    ;; each top level's definitions, by key, and `top-count` makes the next
    ;; key. `deriving` is the scope derived instances resolve in, once one
    ;; is made.
    (struct Context
      ((predecessor (Table Expanded))
       (directories (List String))
       (generate (dyn (Fn (List String) (List Syntax) -> Bytes ! fs compile)))
       (inputs Inputs)
       (recipe (Option Recipe))
       (prefix String)
       (loading (List String))
       (aliases (List String))
       (artifact-uses (List ArtifactUse))
       (links (List LinkUse))
       (items (List Item))
       (derives (Option Loc))
       (program Program)
       (expanded (Table Expanded))
       (artifacts ArtifactSource)
       (counter I64)
       (scopes (Table Env))
       (scope-count I64)
       (tops (Table (Table Binding)))
       (top-count I64)
       (deriving (Option I64))))

    ;; A library loaded under its own scope, resumed in the importer's:
    ;; everything the load learned stays, and every scoped field is the
    ;; importer's again. One place names which fields are which, so a
    ;; library cannot leak its prefix or its uses into the one that imports
    ;; it.
    (: resumed (impl (Fn Context Context -> Context)))
    (define (resumed outer inner)
      (Context (::predecessor outer)
               (::directories outer)
               (::generate outer)
               (::inputs outer)
               (::recipe outer)
               (::prefix outer)
               (::loading outer)
               (::aliases outer)
               (::artifact-uses outer)
               (::links outer)
               (::items outer)
               (::derives outer)
               (::program inner)
               (::expanded inner)
               (::artifacts inner)
               (::counter inner)
               (::scopes inner)
               (::scope-count inner)
               (::tops inner)
               (::top-count inner)
               (::deriving inner)))

    ;; A sequence of steps that each take the context and hand it back,
    ;; written as `let*` is, as `learning` threads the checker in check.sld.
    ;; `(name (step argument ...))` binds the step's value;
    ;; `(then (step argument ...))` is for a step that hands back the
    ;; context alone. Every step is a call, with the context passed as its
    ;; first argument, and the context is named by an identifier: each step
    ;; rebinds that name, so the body and every later step see the newest
    ;; one and nothing can read a context a step has moved past.
    (define-syntax expanding
      (syntax-rules (then)
        ((_ cx () body ...) (begin body ...))
        ((_ cx ((then (f argument ...)) step ...) body ...)
         (let ((cx (f cx argument ...))) (expanding cx (step ...) body ...)))
        ((_ cx ((name (f argument ...)) step ...) body ...)
         (match (f cx argument ...)
           ((Pair name cx) (expanding cx (step ...) body ...))))))

    ;; `step` over each item in order, threading the context and collecting
    ;; the values, so a sequence of steps is itself one step.
    (: each
       (All (A B e) (requires (Copy B))
            (impl (Fn Context
                      (dyn (Fn Context A -> (Pair B Context) ! e))
                      (List A)
                      ->
                      (Pair (List B) Context)
                      ! e))))
    (define (each cx step items)
      (let ((done (fold-left (lambda (done item)
                               (match (step (::second done) item)
                                 ((Pair value cx) (Pair (Cons value (::first done)) cx))))
                             (Pair (Nil) cx) items)))
        (Pair (reverse (::first done)) (::second done))))

    (type Exports (List (Pair String Binding)))

    ;; A library's use of a completed target's files, with the snapshot it
    ;; embedded.
    (struct ArtifactUse
      ((name String)
       (loc Loc)
       (files ArtifactFiles)))

    ;; A file a library links rather than embeds, which the build places
    ;; beside the payload: `digest`, the SHA-256 of its bytes in hex, is the
    ;; name the payload asks its host for and the build ships it under, and
    ;; `path` is where the build finds the file.
    (struct LinkedFile
      ((digest String)
       (path String)))

    ;; A `link-handle` as the library's body expands: the global its
    ;; expression calls, its path made canonical, where that finds the
    ;; file, and where the library names it.
    (struct LinkUse
      ((handle String)
       (relative String)
       (path String)
       (loc Loc)))

    ;; Where an expanded `artifact-files` use finds its target's files. A
    ;; compile is supplied them in its inputs. A discovery expansion, which
    ;; learns what targets a program embeds before any is built, is supplied
    ;; none: it records each use as expansion reaches it, newest first, and
    ;; expands it with no files. That expands the same uses, since the files
    ;; become a literal no macro inspects.
    (enum ArtifactSource
      (Supplied)
      (Discovering
       ((uses (List ArtifactUse)))))

    (: artifact-files (impl (Fn Context String Loc -> (Pair ArtifactFiles Context) ! compile)))
    (define (artifact-files cx name loc)
      (match (::artifacts cx)
        ((Supplied)
         (match (table-ref (::artifacts (::inputs cx)) name)
           ((Some files) (Pair files cx))
           ((None) (request-input (ArtifactInput name loc)))))
        ((Discovering uses)
         (Pair (Nil)
               (Context-artifacts-set cx (Discovering (Cons (ArtifactUse name loc (Nil)) uses)))))))

    ;; A library as a build expanded it: its build key, the canonical text
    ;; of its declarations with the interfaces of its imports, which decides
    ;; whether a later build may replay it; its own interface; its exports;
    ;; everything it added to the program; the targets whose files it
    ;; embeds; the files it links; and what it derived instances against,
    ;; if it did.
    (struct Expanded
      ((key String)
       (body-key String)
       (interface String)
       (exports Exports)
       (delta Program)
       (artifacts (List ArtifactUse))
       (links (List LinkedFile))
       (derives (Option Derivation))))

    ;; A library's derived instances are made of the implicit libraries'
    ;; names, so they hold while those libraries' interfaces do (#546).
    ;; `loc` is the declaration whose deriving clause loaded them, which
    ;; loads them again when the library is replayed.
    (struct Derivation
      ((loc Loc)
       (interfaces String)))

    ;; What a build expanded: the program, its libraries, and the counters,
    ;; scopes and top levels a later build continues from, so that the names
    ;; and marks of the libraries it replays stay unique and resolve as they
    ;; did.
    (struct ExpandedProgram
      ((program Program)
       (libraries (Table Expanded))
       (counter I64)
       (scope-count I64)
       (scopes (Table Env))
       (tops (Table (Table Binding)))
       (top-count I64)))

    ;; The build before the first, or before a one-off compile: it expanded
    ;; nothing, so nothing is replayed.
    (: empty-expansion ExpandedProgram)
    (define empty-expansion
      (ExpandedProgram empty-program empty-table 0 0 empty-table empty-table 0))

    (: new-context
       (impl (Fn (List String)
                 (dyn (Fn (List String) (List Syntax) -> Bytes ! fs compile))
                 Inputs
                 ArtifactSource
                 ExpandedProgram
                 -> Context)))
    (define (new-context directories generate inputs artifacts predecessor)
      (Context (::libraries predecessor)
               directories
               generate
               inputs
               (None)
               ""
               (Nil)
               (Nil)
               (Nil)
               (Nil)
               (Nil)
               (None)
               empty-program
               empty-table
               artifacts
               (::counter predecessor)
               (::scopes predecessor)
               (::scope-count predecessor)
               (::tops predecessor)
               (::top-count predecessor)
               (None)))

    ;; What a finished build hands the next: everything it learned.
    (: expanded-program (impl (Fn Context -> ExpandedProgram)))
    (define (expanded-program cx)
      (ExpandedProgram (::program cx)
                       (::expanded cx)
                       (::counter cx)
                       (::scope-count cx)
                       (::scopes cx)
                       (::tops cx) (::top-count cx)))

    ;; Each addition hands back the context with a larger program, except
    ;; that an item joins the library's own items until its run is done.
    (: add-value (impl (Fn Context String Value -> Context)))
    (define (add-value cx name value)
      (Context-program-set cx (program-with-value (::program cx) name value)))

    (: add-item (impl (Fn Context Item -> Context)))
    (define (add-item cx item)
      (Context-items-set cx (Cons item (::items cx))))

    (: fresh (impl (Fn Context String -> (Pair String Context))))
    (define (fresh cx base)
      (let ((count (+ (::counter cx) 1)))
        (Pair (string-append base "." (i64->string count)) (Context-counter-set cx count))))

    (: global-name (impl (Fn Context String -> String)))
    (define (global-name cx key)
      (string-append (::prefix cx) ":" key))

    ;; Numbers `env` as the next scope.
    (: register-scope (impl (Fn Context Env -> (Pair I64 Context))))
    (define (register-scope cx env)
      (let ((number (::scope-count cx)))
        (Pair number (scope-set (Context-scope-count-set cx (+ number 1)) number env))))

    (: scope-set (impl (Fn Context I64 Env -> Context)))
    (define (scope-set cx number env)
      (Context-scopes-set cx (table-set (::scopes cx) (i64->string number) env)))

    (: scope-env (impl (Fn Context I64 -> Env)))
    (define (scope-env cx number)
      (match (table-ref (::scopes cx) (i64->string number))
        ((Some env) env)
        ((None) (panic "internal error: unknown scope"))))

    ;; A top level over `imports` that defines nothing yet.
    (: new-top (impl (Fn Context (Table Binding) -> (Pair Env Context))))
    (define (new-top cx imports)
      (let ((number (::top-count cx)))
        (Pair (Top (i64->string number) imports) (Context-top-count-set cx (+ number 1)))))

    (: top-definitions (impl (Fn Context String -> (Table Binding))))
    (define (top-definitions cx top)
      (match (table-ref (::tops cx) top)
        ((Some definitions) definitions)
        ((None) empty-table)))

    ;; Binds a name at a top level, once.
    (: bind-top (impl (Fn Context Env Syntax Binding -> Context ! compile)))
    (define (bind-top cx env ident binding)
      (match env
        ((InstanceScope _ rest) (bind-top cx rest ident binding))
        ((InstanceOwner _ rest) (bind-top cx rest ident binding))
        ((Top top _)
         (let ((definitions (top-definitions cx top)))
           (when (table-contains? definitions (ident-key ident))
             (compile-error (syntax-loc ident)
                            (string-append "duplicate top-level definition " (Ident-name ident))))
           (Context-tops-set cx
                             (table-set (::tops cx)
                                        top
                                        (table-set definitions (ident-key ident) binding)))))
        (_ (panic "internal error: not a top level"))))

    ;; ---- The core library ----

    ;; (snail core forms) is the one library without a file: the core forms
    ;; and the builtin types, both listed in core.sld, and the builtin
    ;; effects, which no handler implements: `mut`, which the compiler
    ;; itself performs, and `host`, the effect of code that may run
    ;; anything the host implements, such as work closed over its handlers
    ;; by `inherit-handlers`. Every other library, (snail core primitive)
    ;; among them, is a file.
    (: core-library (impl (Fn -> Exports)))
    (define (core-library)
      (append (map (lambda (name) (Pair name (Core name))) core-keywords)
              (append (map (lambda (entry)
                             (Pair (::first entry)
                                   (TypeName (::first entry) (::second entry) (None))))
                           (filter (lambda (entry) (not (string=? (::first entry) "fn")))
                                   builtin-types))
                      (list (Pair "mut" (EffectName "mut")) (Pair "host" (EffectName "host"))))))

    (: builtin-library? (impl (Fn String -> Bool)))
    (define (builtin-library? key)
      (string=? key "snail.core.forms"))

    ;; ---- Libraries ----

    ;; `(snail core base)` is the list ("snail" "core" "base"); its globals are prefixed
    ;; `snail.core.base` and its source is `snail/core/base.sld` in a search directory.
    (: library-name (impl (Fn Syntax -> (List String) ! compile)))
    (define (library-name syntax)
      (map (lambda (part)
             (match part
               ((Ident name _ _) name)
               ((Atom (DInt number) _) (i64->string number))
               (_ (compile-error (syntax-loc part) "expected a library name part"))))
           (form-items syntax "a library name")))

    (: check-library-name (impl (Fn Syntax (List String) Loc -> Unit ! compile)))
    (define (check-library-name declared name loc)
      (when (string=? (string-join name ".") "prim")
        (compile-error loc "the prim library name is reserved for compiler primitives"))
      (unless (string=? (string-join (library-name declared) ".") (string-join name "."))
        (compile-error loc "library name does not match its path")))

    ;; A library's exports, resolved when an import asks: the compiler's own
    ;; for (snail core forms), else the library as this build expanded it,
    ;; which happens once, under the library's own scope, resumed in the
    ;; importer's.
    (: load-library (impl (Fn Context (List String) Loc -> (Pair Exports Context) ! fs compile)))
    (define (load-library cx name loc)
      (let ((key (string-join name ".")))
        (cond ((builtin-library? key) (Pair (core-library) cx))
              ((member? key (::loading cx))
               (compile-error loc (string-append "library import cycle through " key)))
              (else (match (table-ref (::expanded cx) key)
                      ((Some entry) (Pair (::exports entry) cx))
                      ((None)
                       (match (read-library (Context-loading-set cx (Cons key (::loading cx)))
                                            name
                                            loc)
                         ((Pair exports loaded) (Pair exports (resumed cx loaded))))))))))

    (: read-library (impl (Fn Context (List String) Loc -> (Pair Exports Context) ! fs compile)))
    (define (read-library cx name loc)
      (let ((path (library-path (::directories cx) name loc)))
        (expand-library-file cx name (file-library name (read-source path) path))))

    ;; Where a library's source is: the first search directory holding it.
    (: find-library (impl (Fn (List String) (List String) -> (Option String) ! fs)))
    (define (find-library directories name)
      (let ((relative (string-append (string-join name "/") ".sld")))
        (find file-exists?
              (map (lambda (directory) (string-append directory "/" relative)) directories))))

    (: library-path (impl (Fn (List String) (List String) Loc -> String ! fs compile)))
    (define (library-path directories name loc)
      (match (find-library directories name)
        ((Some path) path)
        ((None)
         (compile-error loc (string-append "library not found: (" (string-join name " ") ")")))))

    ;; What a library's file declares, read but not expanded: a defined
    ;; library's sections, through its `cond-expand`s, or a generated
    ;; library's producer program, with the location of the recipe's
    ;; expression, where the producer's output is placed. The expander and
    ;; the closure walk both read files through this.
    (enum LibraryFile
      (DefinedLibrary
        ((sections (List (Pair String (List Syntax))))))
      (GeneratedLibrary
       ((forms (List Syntax))
        (loc Loc))))

    ;; A library file holds one `define-library`, or one `generate-library`
    ;; whose program writes the library's `define-library` form as syntax.
    (: file-library (impl (Fn (List String) (List Syntax) String -> LibraryFile ! fs compile)))
    (define (file-library name forms path)
      (match forms
        ((Cons (Form (Cons (Ident "define-library" _ _) (Cons declared declarations)) loc) (Nil))
         (check-library-name declared name loc)
         (DefinedLibrary (concatenate (map library-sections declarations))))
        ((Cons (Form (Cons (Ident "generate-library" _ _)
                           (Cons declared
                                 (Cons (Form (Cons (Ident "import" _ _) imports) _)
                                       (Cons expression (Nil)))))
                     loc)
               (Nil))
         (check-library-name declared name loc)
         (GeneratedLibrary
          (producer path (map with-included-bytes imports) (with-included-bytes expression) loc)
          (syntax-loc expression)))
        (_ (compile-error (Loc path 1 1)
                          "expected exactly one define-library or generate-library form"))))

    ;; The library a producer's output declares, as if it were written at
    ;; `loc` in the recipe's file.
    (: output-library-file (impl (Fn (List String) Bytes Loc -> LibraryFile ! fs compile)))
    (define (output-library-file name bytes loc)
      (file-library name (list (with-included-bytes (decode-syntax bytes loc))) (::file loc)))

    ;; A defined library expands its sections; a generated one expands the
    ;; library its producer's output declares.
    (: expand-library-file
       (impl (Fn Context (List String) LibraryFile -> (Pair Exports Context) ! fs compile)))
    (define (expand-library-file cx name file)
      (match file
        ((DefinedLibrary sections)
         (expand-sections (Context-prefix-set cx (string-join name ".")) sections))
        ((GeneratedLibrary forms loc)
         (expand-library-file cx name (output-library-file name (generated-bytes cx forms) loc)))))

    ;; What a producer wrote: the output the build supplied for it, or else
    ;; what the driver's provider makes of it. The producer is compiled while
    ;; this library loads, so the provider is given the loading stack, which
    ;; `load-library` began with this library's key.
    (: generated-bytes (impl (Fn Context (List Syntax) -> Bytes ! fs compile)))
    (define (generated-bytes cx forms)
      (match (generated-output (::inputs cx) (producer-text (::directories cx) forms))
        ((Some bytes) bytes)
        ((None) ((::generate cx) (::loading cx) forms))))

    ;; The producer imports what the recipe imports, names the recipe's
    ;; file, and writes the syntax its expression returns, a
    ;; `(snail shell syntax)` Syntax, which it computes in a task.
    (: producer (impl (Fn String (List Syntax) Syntax Loc -> (List Syntax))))
    (define (producer recipe imports expression loc)
      (let ((write-library (Ident "write-generated-library" (None) loc)))
        (list (Form (Cons (Ident "import" (None) loc)
                          (append imports
                                  (list (Form (list (Ident "only" (None) loc)
                                                    (Form (list (Ident "snail" (None) loc)
                                                                (Ident "shell" (None) loc)
                                                                (Ident "syntax" (None) loc))
                                                          loc)
                                                    write-library)
                                              loc))))
                    loc)
              (Form (list (Ident "recipe" (None) loc) (Atom (DString recipe) loc)) loc)
              (Form (list write-library
                          (Form (list (Ident "lambda" (None) loc) (Form (Nil) loc) expression) loc))
                    loc))))

    ;; ---- Sources ----

    ;; A source file's forms. `(include-bytes "path")` is another spelling
    ;; of a byte vector literal, which reads as `#u8(...)` holding the bytes
    ;; of the file at `path`, relative to the file the form is written in.
    (: read-source (impl (Fn String -> (List Syntax) ! fs compile)))
    (define (read-source path)
      (map with-included-bytes (read-source-file path)))

    (: with-included-bytes (impl (Fn Syntax -> Syntax ! fs compile)))
    (define (with-included-bytes syntax)
      (match syntax
        ((Form (Cons (Ident "include-bytes" _ _) args) loc)
         (Atom (DBytes (included-bytes args loc)) loc))
        ((Form items loc) (Form (map with-included-bytes items) loc))
        (_ syntax)))

    (: included-bytes (impl (Fn (List Syntax) Loc -> Bytes ! fs compile)))
    (define (included-bytes args loc)
      (match args
        ((Cons (Atom (DString path) _) (Nil))
         (let ((resolved (beside (::file loc) path)))
           (if (file-exists? resolved)
               (read-bytes resolved)
               (compile-error loc (string-append "no file to include at " resolved)))))
        (_ (compile-error loc "expected (include-bytes \"path\")"))))

    ;; `path` in the directory holding `file`, unless it is absolute.
    (: beside (impl (Fn String String -> String)))
    (define (beside file path)
      (if (and (> (string-length path) 0) (char=? (string-ref path 0) #\/))
          path
          (let loop ((end (string-length file)))
            (cond ((= end 0) path)
                  ((char=? (string-ref file (- end 1)) #\/)
                   (string-append (substring file 0 end) path))
                  (else (loop (- end 1)))))))

    ;; ---- Linked files ----

    ;; `(link-handle "path")` names a file the library links, which
    ;; `link-file` in (snail shell resource) wraps: it ships beside the
    ;; payload instead of in it, and the program gets a handle rather than
    ;; the bytes. The path is relative to the file it is written in, as
    ;; `include-bytes`'s is, and may not leave that file's directory. The
    ;; form is a call to a global of the library's, which `bind-links`
    ;; binds, once the body has expanded, to an import from
    ;; "snail.runtime.link" named for the file's digest: the module records
    ;; the content it needs where its host must see it, and the host reads
    ;; it only when the program asks for its bytes. Expanding an expression
    ;; reads no file, so the digest waits for the body.
    (: expand-link-file (impl (Fn Context (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-link-file cx items loc)
      (match items
        ((Cons _ (Cons (Atom (DString path) path-loc) (Nil)))
         (let* ((relative (linked-path path path-loc))
                (handle (global-name cx (string-append "%link " relative))))
           (Pair (expr (App (expr (Var handle (Nil) (Nil)) loc) (Nil)) loc)
                 (record-link cx handle relative path-loc))))
        (_ (compile-error loc "link-file expects a literal relative path"))))

    ;; Records a use on the library, once for each global. A macro whose
    ;; template holds the path names a file beside the macro's library, so
    ;; two files could claim one global; that is an error.
    (: record-link (impl (Fn Context String String Loc -> Context ! compile)))
    (define (record-link cx handle relative loc)
      (let ((path (beside (written-in cx loc) relative)))
        (match (find (lambda (use) (string=? (::handle use) handle)) (::links cx))
          ((Some use)
           (unless (string=? (::path use) path)
             (compile-error loc
                            (string-append "two files link as "
                                           relative
                                           ": "
                                           (::path use)
                                           " and "
                                           path)))
           cx)
          ((None)
           (Context-links-set cx (Cons (LinkUse handle relative path loc) (::links cx)))))))

    ;; A linked path in its canonical form: names separated by `/`, where
    ;; `.` is the directory it is in and `..` its parent, so
    ;; `data/../pixel.png` is `pixel.png`. A path that is absolute, has an
    ;; empty name, names nothing, or climbs out of the directory is refused,
    ;; since the payload could not ship its file under a name of its own.
    (: linked-path (impl (Fn String Loc -> String ! compile)))
    (define (linked-path path loc)
      (let loop ((names (path-names path)) (kept (Nil)))
        (match names
          ((Nil)
           (if (null? kept)
               (compile-error loc (string-append "link-file names no file: " path))
               (string-join (reverse kept) "/")))
          ((Cons "." rest) (loop rest kept))
          ((Cons ".." rest)
           (match kept
             ((Cons _ parent) (loop rest parent))
             ((Nil)
              (compile-error loc
                             (string-append "link-file may not leave the library's directory: "
                                            path)))))
          ((Cons "" _)
           (compile-error loc
                          (string-append
                           "link-file takes a path relative to the library, with no empty names: "
                           path)))
          ((Cons name rest) (loop rest (Cons name kept))))))

    (: path-names (impl (Fn String -> (List String))))
    (define (path-names path)
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (path-names (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    ;; Binds each use's global to the import from "snail.runtime.link" named
    ;; for its file's digest, which answers the file's handle, and gives the
    ;; files the library links, once each, in the order its uses were
    ;; reached. Files with the same bytes are one file.
    (: bind-links
       (impl (Fn Context (List LinkUse) -> (Pair (List LinkedFile) Context) ! fs compile)))
    (define (bind-links cx uses)
      (let ((linked (map (lambda (use) (Pair use (linked-file (::prefix cx) use))) uses)))
        (Pair
         (delete-duplicates (lambda (a b) (string=? (::digest a) (::digest b)))
                            (map ::second linked))
         (fold-left (lambda (cx entry)
                      (add-value cx
                                 (::handle (::first entry))
                                 (link-import (::second entry))))
                    cx linked))))

    ;; The file a use names, read for its digest. A missing file fails the
    ;; library's expansion, naming the library and the path.
    (: linked-file (impl (Fn String LinkUse -> LinkedFile ! fs compile)))
    (define (linked-file library use)
      (let ((path (::path use)))
        (if (file-exists? path)
            (LinkedFile (file-digest path) path)
            (compile-error (::loc use)
                           (string-append "the library " library " links " (::relative use)
                                          ", but there is no file at " path)))))

    (: link-import (impl (Fn LinkedFile -> Value)))
    (define (link-import file)
      (Foreign (Import "snail.runtime.link" (::digest file))
               (mono-scheme (TFun (Nil) (TCon "I32" (Nil)) empty-row))))

    (: file-digest (impl (Fn String -> String ! fs)))
    (define (file-digest path)
      (bytes->hex (sha256 (read-bytes path))))

    ;; A replayed library's files must hold the bytes it was expanded with,
    ;; since its module names their digests.
    (: linked-file-current? (impl (Fn LinkedFile -> Bool ! fs)))
    (define (linked-file-current? file)
      (and (file-exists? (::path file))
           (string=? (file-digest (::path file)) (::digest file))))

    ;; The digests enter the library's keys: its module names them, and so
    ;; does an importer's that specializes a generic function calling one
    ;; of its handles.
    (: links-stamp (impl (Fn (List LinkedFile) -> String)))
    (define (links-stamp files)
      (if (null? files)
          ""
          (string-append " links-"
                         (i64->string (fnv-1a (string-join (map ::digest files) " "))))))

    ;; The files a library links, as the build expanded it, in the order
    ;; its uses were reached.
    (: library-links (impl (Fn ExpandedProgram String -> (List LinkedFile))))
    (define (library-links expansion name)
      (match (table-ref (::libraries expansion) name)
        ((Some entry) (::links entry))
        ((None) (Nil))))

    ;; The files the whole program links: each library's, in program order.
    (: program-links (impl (Fn ExpandedProgram -> (List LinkedFile))))
    (define (program-links expansion)
      (let ((program (::program expansion)))
        (concatenate (map (lambda (library) (library-links expansion (::first library)))
                          (library-items program (program-items program))))))

    ;; Loads the imports, then replays the library from the build before
    ;; where it may, or expands it; either way the library is recorded for
    ;; the next build. What it uses and makes starts empty, after its
    ;; imports have loaded with their own.
    (: expand-sections
       (impl
        (Fn Context (List (Pair String (List Syntax))) -> (Pair Exports Context) ! fs compile)))
    (define (expand-sections cx sections)
      (expanding cx ((env (import-env (section-items sections "import"))))
                 (let* ((key (sections-key cx sections))
                        (cx (Context-derives-set
                             (Context-items-set (Context-links-set (Context-artifact-uses-set cx
                                                                                              (Nil))
                                                                   (Nil))
                                                (Nil))
                             (None))))
                   (expanding cx ((previous (replayable key)))
                              (match previous
                                ((Some entry) (replay cx entry))
                                ((None) (expand-recorded cx sections env key)))))))

    ;; The primitive library's body is its declarations, which add no items,
    ;; so it records no run and has no module.
    (: expand-library-body
       (impl
        (Fn Context (List (Pair String (List Syntax))) Env -> (Pair Exports Context) ! fs compile)))
    (define (expand-library-body cx sections env)
      (let* ((forms (section-items sections "begin"))
             (cx (if (primitive-library? cx)
                     (fold-left (lambda (cx form) (declare-primitive cx env form)) cx forms)
                     (expand-library-run cx env forms))))
        (Pair (map (lambda (spec) (export-entry cx env spec)) (section-items sections "export"))
              cx)))

    ;; The body's items are the library's run, which joins the program
    ;; whole once the body is expanded, so the program's items divide back
    ;; into libraries. A library loaded meanwhile, as the implicit libraries
    ;; are at the build's first deriving clause, has joined already, so its
    ;; items come before the run, as an import's do, and never inside it.
    (: expand-library-run (impl (Fn Context Env (List Syntax) -> Context ! fs compile)))
    (define (expand-library-run cx env forms)
      (let* ((cx (expand-top-level cx env forms))
             (cx (if (string=? (::prefix cx) "main") (with-one-body cx) cx)))
        (Context-program-set cx
                             (program-with-library (::program cx)
                                                   (::prefix cx)
                                                   (::items cx)))))

    ;; A program's statements are one body, a function of no arguments the
    ;; one statement left calls, which runs after the definitions are
    ;; initialized, in their order. A function, so a yield in a statement
    ;; saves the rest of the program as a frame when the body runs as the
    ;; program's first task ((snail shell task)'s `start-main`). `items`
    ;; are newest first.
    (: with-one-body (impl (Fn Context -> Context)))
    (define (with-one-body cx)
      (let ((items (::items cx))
            (statements (reverse (concatenate (map (lambda (item)
                                                     (match item
                                                       ((Do value) (list value))
                                                       (_ (Nil))))
                                                   (::items cx))))))
        (match statements
          ((Nil) cx)
          ((Cons first rest)
           (let ((name (string-append (::prefix cx) ":%body")) (loc (::loc first)))
             (add-value (Context-items-set cx
                                           (Cons
                                            (Do (expr (App (expr (Var name (Nil) (Nil)) loc) (Nil))
                                                      loc))
                                            (Cons (Define name
                                                    (expr (Lambda (Nil) (sequence first rest) #f)
                                                          loc))
                                                  (filter (lambda (item)
                                                            (match item
                                                              ((Do _) #f)
                                                              (_ #t)))
                                                          items))))
                        name
                        (Defined (None) (None) #t)))))))

    (: sequence (impl (Fn Expr (List Expr) -> Expr)))
    (define (sequence first rest)
      (match rest
        ((Nil) first)
        ((Cons next more) (expr (Seq first (sequence next more)) (::loc first)))))

    ;; Each declaration is a section of imports, exports or definitions, or a
    ;; `cond-expand` choosing more declarations.
    (: library-sections (impl (Fn Syntax -> (List (Pair String (List Syntax))) ! compile)))
    (define (library-sections declaration)
      (match declaration
        ((Form (Cons (Ident "cond-expand" _ _) clauses) _) (cond-expand-sections clauses))
        ((Form (Cons (Ident kind _ _) items) loc)
         (if (member? kind (list "import" "export" "begin"))
             (list (Pair kind items))
             (compile-error loc "expected import, export, begin or cond-expand")))
        (_
         (compile-error (syntax-loc declaration) "expected import, export, begin or cond-expand"))))

    ;; The declarations of the first clause whose requirement holds. Snail-Core's
    ;; only feature is `snail-core`.
    (: cond-expand-sections
       (impl (Fn (List Syntax) -> (List (Pair String (List Syntax))) ! compile)))
    (define (cond-expand-sections clauses)
      (match clauses
        ((Nil) (Nil))
        ((Cons (Form (Cons requirement declarations) _) rest)
         (if (feature? requirement)
             (concatenate (map library-sections declarations))
             (cond-expand-sections rest)))
        ((Cons clause _)
         (compile-error (syntax-loc clause) "expected (requirement declaration ...)"))))

    (: feature? (impl (Fn Syntax -> Bool)))
    (define (feature? requirement)
      (match requirement
        ((Ident name _ _) (or (string=? name "snail-core") (string=? name "else")))
        ((Form (Cons (Ident "and" _ _) items) _) (every? feature? items))
        ((Form (Cons (Ident "or" _ _) items) _) (any? feature? items))
        ((Form (Cons (Ident "not" _ _) (Cons item (Nil))) _) (not (feature? item)))
        (_ #f)))

    (: section-items (impl (Fn (List (Pair String (List Syntax))) String -> (List Syntax))))
    (define (section-items sections kind)
      (concatenate
       (map ::second (filter (lambda (section) (string=? (::first section) kind)) sections))))

    ;; A program is a sequence of imports followed by a body, which counts as
    ;; a library named `main` that exports nothing. A build replays what it
    ;; can of `predecessor`, the build before. A producer program begins
    ;; with `(generating ...)`, and its imports load inside the libraries
    ;; that form names, so one that leads back to them is a cycle.
    (: expand-program
       (impl (Fn (List String)
                 (dyn (Fn (List String) (List Syntax) -> Bytes ! fs compile))
                 Inputs
                 String
                 ExpandedProgram
                 -> ExpandedProgram
                 ! fs compile)))
    (define (expand-program directories generate inputs path predecessor)
      (expanded-program
       (expand-source (new-context directories generate inputs (Supplied) predecessor) path)))

    (: expand-source (impl (Fn Context String -> Context ! fs compile)))
    (define (expand-source cx path)
      (let* ((source (generating-stack (read-source path)))
             (parts (program-parts (::second source)))
             (body (producer-body path (::first source) (::second parts)))
             (cx (Context-recipe-set
                  (Context-loading-set (Context-prefix-set cx "main") (::first source))
                  (::first body))))
        (::second (expand-sections cx
                                   (list (Pair "import" (::first parts))
                                         (Pair "begin" (::second body)))))))

    ;; A producer program's printed copy, at `copy`, and the recipe it was
    ;; printed from, at `file`.
    (struct Recipe
      ((copy String)
       (file String)))

    ;; The body of the program at `path`, and the recipe it stands for when
    ;; it is a producer, printed with the libraries `loading` when it was
    ;; reached: such a body begins with `(recipe "lib/sample/blob.sld")`.
    (: producer-body
       (impl (Fn String (List String) (List Syntax) -> (Pair (Option Recipe) (List Syntax)))))
    (define (producer-body path loading body)
      (match body
        ((Cons (Form (Cons (Ident "recipe" _ _) (Cons (Atom (DString file) _) (Nil))) _) rest)
         (if (null? loading) (Pair (None) body) (Pair (Some (Recipe path file)) rest)))
        (_ (Pair (None) body))))

    ;; The file a path written at `loc` is relative to: the file it is
    ;; written in, where a producer's printed copy stands for its recipe, so
    ;; a recipe names files beside itself wherever its producer is printed.
    (: written-in (impl (Fn Context Loc -> String)))
    (define (written-in cx loc)
      (match (::recipe cx)
        ((Some (Recipe copy file)) (if (string=? (::file loc) copy) file (::file loc)))
        ((None) (::file loc))))

    ;; A program's leading `import` forms' specs, and the body after them.
    (: program-parts (impl (Fn (List Syntax) -> (Pair (List Syntax) (List Syntax)))))
    (define (program-parts forms)
      (match forms
        ((Cons (Form (Cons (Ident "import" _ _) specs) _) rest)
         (let ((parts (program-parts rest)))
           (Pair (append specs (::first parts)) (::second parts))))
        (_ (Pair (Nil) forms))))

    ;; The import specs of a program's leading `import` forms.
    (: program-imports (impl (Fn (List Syntax) -> (List Syntax))))
    (define (program-imports forms)
      (::first (program-parts forms)))

    ;; ---- Library closures ----

    ;; A generated library a walk reached: its producer program, where the
    ;; producer's output is placed, and the libraries loading when the walk
    ;; reached it, innermost first, itself among them, as `load-library`
    ;; would have them loading while the producer runs.
    (struct Reached
      ((library (List String))
       (forms (List Syntax))
       (loc Loc)
       (loading (List String))))

    ;; What a walk carries: where libraries are found, the producers'
    ;; outputs it may read on through, the libraries it has visited, and the
    ;; generated libraries it reached, latest first.
    (struct Walk
      ((directories (List String))
       (inputs Inputs)
       (visited (Table Bool))
       (reached (List Reached))))

    ;; The generated libraries a program's import specs reach, with
    ;; `loading` loading as it starts, in the order a depth-first walk first
    ;; reaches them. The walk reads files and follows imports as the
    ;; expander loads them, then the implicit libraries, where they exist,
    ;; and reads on through each output `inputs` supplies; beyond a generated
    ;; library without one, nothing is known yet. Like `load-library`, it
    ;; fails at an import that leads back to a library still loading.
    (: library-closure
       (impl (Fn (List String) Inputs (List String) (List Syntax) -> (List Reached) ! fs compile)))
    (define (library-closure directories inputs loading imports)
      (let* ((walk (walk-imports (Walk directories inputs empty-table (Nil)) loading imports))
             (walk (fold-left (lambda (walk name) (walk-implicit walk loading name))
                              walk
                              implicit-libraries)))
        (reverse (::reached walk))))

    (: walk-imports (impl (Fn Walk (List String) (List Syntax) -> Walk ! fs compile)))
    (define (walk-imports walk loading specs)
      (fold-left (lambda (walk spec)
                   (walk-library walk loading (library-name (spec-library spec)) (syntax-loc spec)))
                 walk
                 specs))

    ;; Only a library that derives loads these, so one need not exist.
    (: walk-implicit (impl (Fn Walk (List String) (List String) -> Walk ! fs compile)))
    (define (walk-implicit walk loading name)
      (match (find-library (::directories walk) name)
        ((Some path) (walk-library walk loading name (Loc path 1 1)))
        ((None) walk)))

    ;; The checks are `load-library`'s, in its order: (snail core forms) has
    ;; no file, and a library already loading is a cycle.
    (: walk-library (impl (Fn Walk (List String) (List String) Loc -> Walk ! fs compile)))
    (define (walk-library walk loading name loc)
      (let ((key (string-join name ".")))
        (cond ((builtin-library? key) walk)
              ((member? key loading)
               (compile-error loc (string-append "library import cycle through " key)))
              ((table-contains? (::visited walk) key) walk)
              (else (walk-file (Walk-visited-set walk (table-set (::visited walk) key #t))
                               (Cons key loading)
                               name
                               (library-file (::directories walk) name loc))))))

    (: walk-file (impl (Fn Walk (List String) (List String) LibraryFile -> Walk ! fs compile)))
    (define (walk-file walk loading name file)
      (match file
        ((DefinedLibrary sections) (walk-imports walk loading (section-items sections "import")))
        ((GeneratedLibrary forms loc)
         (let ((walk (Walk-reached-set walk
                                       (Cons (Reached name forms loc loading)
                                             (::reached walk)))))
           (match (generated-output (::inputs walk)
                                    (producer-text (::directories walk) forms))
             ((Some bytes) (walk-file walk loading name (output-library-file name bytes loc)))
             ((None) walk))))))

    ;; A library's file as a walk reads it: as `read-library` does, except
    ;; that the files a defined library includes are not read, since they
    ;; cannot name a library. (snail core forms) needs nothing.
    (: library-file (impl (Fn (List String) (List String) Loc -> LibraryFile ! fs compile)))
    (define (library-file directories name loc)
      (if (builtin-library? (string-join name "."))
          (DefinedLibrary (Nil))
          (let ((path (library-path directories name loc)))
            (file-library name (read-source-file path) path))))

    ;; ---- Discovering artifact uses ----

    ;; The targets whose files the program at `path` embeds: each
    ;; `artifact-files` use, once for each library that makes it, in the
    ;; order expansion reaches it. This is the expander itself, supplied no
    ;; target's files, so a use that only an unexpanded macro template
    ;; names is no use. Each producer the program reaches must have its
    ;; output in `inputs`: discovery is for a program whose closure waits
    ;; for nothing, so it asks its caller for nothing either.
    (: discover-artifacts
       (impl (Fn (List String) Inputs String -> (List ArtifactUse) ! fs compile)))
    (define (discover-artifacts directories inputs path)
      (match (::artifacts
              (expand-source (new-context directories
                                          unsupplied-producer
                                          inputs
                                          (Discovering (Nil))
                                          empty-expansion)
                             path))
        ((Discovering uses) (reverse uses))
        ((Supplied) (Nil))))

    (: unsupplied-producer (impl (Fn (List String) (List Syntax) -> Bytes)))
    (define (unsupplied-producer loading forms)
      (panic "internal error: discovery reached a producer whose output was not supplied"))

    ;; ---- Replaying libraries ----

    ;; Ordinary source/import eligibility is checked before these requests:
    ;; a changed body may have removed an old dependency. Every candidate
    ;; replay still requires the recorded inputs and compares exact file
    ;; contents. Removing an invocation must not require its obsolete input.
    (: artifacts-current? (impl (Fn Context (List ArtifactUse) -> (Pair Bool Context) ! compile)))
    (define (artifacts-current? cx uses)
      (match uses
        ((Nil) (Pair #t cx))
        ((Cons use rest)
         (expanding cx ((files (artifact-files (::name use) (::loc use))))
                    (if (artifact-files=? (::files use) files)
                        (artifacts-current? cx rest)
                        (Pair #f cx))))))

    (: artifact-files=? (impl (Fn ArtifactFiles ArtifactFiles -> Bool)))
    (define (artifact-files=? left right)
      (match (Pair left right)
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons a rest-a) (Cons b rest-b))
         (and (string=? (::first a) (::first b))
              (bytes=? (::second a) (::second b))
              (artifact-files=? rest-a rest-b)))
        (_ #f)))

    ;; The library as the build before expanded it, if this build may replay
    ;; it: its declarations and its imports' interfaces are unchanged, the
    ;; instances it derived still hold, its embedded files are current and
    ;; its linked files hold the bytes they did.
    (: replayable (impl (Fn Context String -> (Pair (Option Expanded) Context) ! fs compile)))
    (define (replayable cx key)
      (match (table-ref (::predecessor cx) (::prefix cx))
        ((Some entry)
         (if (string=? (::key entry) key)
             (expanding cx ((derived (derived-as-before? entry))
                            (current (artifacts-current? (::artifacts entry))))
                        (Pair (if (and derived
                                       current
                                       (every? linked-file-current? (::links entry)))
                                  (Some entry)
                                  (None))
                              cx))
             (Pair (None) cx)))
        ((None) (Pair (None) cx))))

    ;; Whether the implicit libraries' interfaces are those the library
    ;; derived its instances against. Its declarations are unchanged, so it
    ;; derives them again either way, and loading the implicit libraries is
    ;; what its replay or its expansion would do first.
    (: derived-as-before? (impl (Fn Context Expanded -> (Pair Bool Context) ! fs compile)))
    (define (derived-as-before? cx entry)
      (match (::derives entry)
        ((Some derivation)
         (let ((cx (::second (deriving-scope cx (::loc derivation)))))
           (Pair (string=? (implicit-interfaces cx) (::interfaces derivation)) cx)))
        ((None) (Pair #t cx))))

    ;; A library replayed adds what it added in the build before, after the
    ;; implicit libraries if it derived instances, since its run follows
    ;; them, as it did when it was expanded. The generation handoff is
    ;; functional: `expand-program` takes the previous generation as an
    ;; argument, `::predecessor` holds it read-only, and
    ;; `program-with` unions persistent tables, so a replayed library's
    ;; values alias the ones it produced before rather than being rebuilt.
    (: replay (impl (Fn Context Expanded -> (Pair Exports Context) ! fs compile)))
    (define (replay cx entry)
      (let ((cx (match (::derives entry)
                  ((Some derivation) (::second (deriving-scope cx (::loc derivation))))
                  ((None) cx))))
        (Pair (::exports entry)
              (record
               (Context-program-set cx (program-with (::program cx) (::delta entry)))
               entry))))

    ;; The fresh artifact stamp identifies each new artifact-bearing
    ;; expansion. The counter continues from the last
    ;; successful build; replay keeps its old stamp. It enters both the
    ;; checked-body key and importers' interface keys, including generic
    ;; importers that specialize this library's body into their own module.
    ;; Stamps identify entries in one session lineage, not global content.
    (: artifact-stamp (impl (Fn Context (List ArtifactUse) -> (Pair String Context))))
    (define (artifact-stamp cx uses)
      (if (null? uses) (Pair "" cx) (fresh cx " artifact-")))

    (: expand-recorded
       (impl (Fn Context
                 (List (Pair String (List Syntax)))
                 Env
                 String
                 -> (Pair Exports Context)
                 ! fs compile)))
    (define (expand-recorded cx sections env key)
      (expanding cx ((exports (expand-library-body sections env)))
                 (let* ((uses (::artifact-uses cx))
                        (derivation (derivation-of cx))
                        (derived (derivation-key derivation)))
                   (expanding cx ((stamp (artifact-stamp uses))
                                  (links (bind-links (reverse (::links cx)))))
                              (Pair exports
                                    (record cx
                                            (Expanded key
                                                      (string-append key
                                                                     derived
                                                                     stamp
                                                                     (links-stamp links))
                                                      (string-append (interface-hash cx sections)
                                                                     derived
                                                                     stamp
                                                                     (links-stamp links))
                                                      exports
                                                      (library-delta cx)
                                                      uses
                                                      links
                                                      derivation)))))))

    ;; What the library's instances were derived against, if it derived any.
    (: derivation-of (impl (Fn Context -> (Option Derivation))))
    (define (derivation-of cx)
      (match (::derives cx)
        ((Some loc) (Some (Derivation loc (implicit-interfaces cx))))
        ((None) (None))))

    ;; A derivation enters the checked-body key and importers' interface
    ;; keys as the artifact stamp does: a change to the implicit libraries'
    ;; interfaces derives the instances again, and the instances' code is
    ;; then new to whatever checked or specialized it.
    (: derivation-key (impl (Fn (Option Derivation) -> String)))
    (define (derivation-key derivation)
      (match derivation
        ((Some derivation) (string-append " derived " (::interfaces derivation)))
        ((None) "")))

    ;; What the library added, which a later build replays.
    (: library-delta (impl (Fn Context -> Program)))
    (define (library-delta cx)
      (if (primitive-library? cx)
          (primitive-delta (::program cx))
          (program-delta (::program cx) (::prefix cx))))

    (: record (impl (Fn Context Expanded -> Context)))
    (define (record cx entry)
      (Context-expanded-set cx (table-set (::expanded cx) (::prefix cx) entry)))

    ;; ---- Build keys ----

    ;; A library's build key: the canonical text of its declarations, with
    ;; the interfaces of its imports.
    (: sections-key (impl (Fn Context (List (Pair String (List Syntax))) -> String ! compile)))
    (define (sections-key cx sections)
      (string-append (string-join (map (lambda (section)
                                         (string-append (::first section)
                                                        " "
                                                        (forms-text (::second section))))
                                       sections)
                                  "\n")
                     "\n" (imports-interfaces cx sections)))

    (: forms-text (impl (Fn (List Syntax) -> String)))
    (define (forms-text forms)
      (string-join (map syntax->key forms) "\n"))

    ;; Syntax as text that keys a build. A byte vector shows only its length
    ;; and a hash of its bytes, so a library that embeds megabytes keys on a
    ;; few characters.
    (: syntax->key (impl (Fn Syntax -> String)))
    (define (syntax->key syntax)
      (match syntax
        ((Atom (DBytes value) _)
         (string-append "#u8<"
                        (i64->string (vector-length value))
                        ":"
                        (i64->string (bytes-hash value))
                        ">"))
        ((Atom value _) (datum->string value))
        ((Ident name _ _) name)
        ((Form items _) (string-append "(" (string-join (map syntax->key items) " ") ")"))))

    ;; FNV-1a over bytes, as `fnv-1a` hashes text.
    (: bytes-hash (impl (Fn Bytes -> I64)))
    (define (bytes-hash bytes)
      (vector-fold (lambda (hash byte) (fnv-step hash (i32->i64 (u8->i32 byte)))) fnv-offset bytes))

    ;; Each imported library's interface, as this build expanded it; the
    ;; compiler's own libraries never change.
    (: imports-interfaces
       (impl (Fn Context (List (Pair String (List Syntax))) -> String ! compile)))
    (define (imports-interfaces cx sections)
      (string-join (map (lambda (spec)
                          (library-interface cx
                                             (string-join (library-name (spec-library spec)) ".")))
                        (section-items sections "import"))
                   " "))

    ;; The implicit libraries' interfaces, as this build expanded them.
    (: implicit-interfaces (impl (Fn Context -> String)))
    (define (implicit-interfaces cx)
      (string-join (map (lambda (name) (library-interface cx (string-join name ".")))
                        implicit-libraries)
                   " "))

    (: library-interface (impl (Fn Context String -> String)))
    (define (library-interface cx name)
      (match (table-ref (::expanded cx) name)
        ((Some entry) (::interface entry))
        ((None) "builtin")))

    ;; The key a build expanded a library under. Anything made from the
    ;; library's expansion, such as its checked items, stays valid while its
    ;; key is unchanged.
    (: library-key (impl (Fn ExpandedProgram String -> String)))
    (define (library-key expansion name)
      (match (table-ref (::libraries expansion) name)
        ((Some entry) (::body-key entry))
        ((None) "")))

    (: spec-library (impl (Fn Syntax -> Syntax)))
    (define (spec-library spec)
      (match spec
        ((Form (Cons (Ident keyword _ _) (Cons inner _)) _)
         (if (member? keyword (list "only" "except" "prefix" "rename")) (spec-library inner) spec))
        (_ spec)))

    ;; What importers depend on: every declaration except the bodies of
    ;; definitions whose signatures are not generic, which only the
    ;; library's own module uses; and its imports' interfaces, since its
    ;; generic code carries theirs into importers.
    (: interface-hash (impl (Fn Context (List (Pair String (List Syntax))) -> String ! compile)))
    (define (interface-hash cx sections)
      (let* ((forms (section-items sections "begin")) (signed (monomorphic-signatures forms)))
        (i64->string (fnv-1a (string-append (forms-text (section-items sections "import"))
                                            "\n"
                                            (forms-text (section-items sections "export"))
                                            "\n"
                                            (string-join
                                             (map (lambda (form) (interface-form form signed))
                                                  forms)
                                             "\n")
                                            "\n" (imports-interfaces cx sections)
                                            "\n" (library-identities cx))))))

    ;; Instance methods and macro-introduced globals have fresh names after
    ;; expansion. Importers must not retain checked evidence or Wasm imports
    ;; naming the previous expansion, even if only a signed body changed.
    (: library-identities (impl (Fn Context -> String)))
    (define (library-identities cx)
      (let ((delta (library-delta cx)))
        (string-join
         (list-sort string<?
                    (append (table-keys (item-definitions (program-items delta)))
                            (map ::name
                                 (concatenate (table-values (::instances delta))))))
         "\n")))

    (: interface-form (impl (Fn Syntax (List String) -> String ! compile)))
    (define (interface-form form signed)
      (match form
        ((Form (Cons (Ident "define" _ _) _) _)
         (let ((name (Ident-name (definition-name form))))
           (if (member? name signed) (string-append "(define " name ")") (syntax->key form))))
        (_ (syntax->key form))))

    (: monomorphic-signatures (impl (Fn (List Syntax) -> (List String))))
    (define (monomorphic-signatures forms)
      (concatenate (map (lambda (form)
                          (match form
                            ((Form (Cons (Ident ":" _ _)
                                         (Cons (Ident name _ _)
                                               (Cons (Form (Cons (Ident "All" _ _) _) _) _)))
                                   _)
                             (Nil))
                            ((Form (Cons (Ident ":" _ _) (Cons (Ident name _ _) (Cons _ _))) _)
                             (list name))
                            (_ (Nil))))
                        forms)))

    ;; ---- Imports and exports ----

    ;; A top level over the bindings the specs provide, each loaded and
    ;; merged in turn.
    (: import-env (impl (Fn Context (List Syntax) -> (Pair Env Context) ! fs compile)))
    (define (import-env cx specs)
      (let loop ((cx cx) (specs specs) (imports empty-table))
        (match specs
          ((Nil) (new-top cx imports))
          ((Cons spec rest)
           (expanding cx ((entries (import-set spec)))
                      (loop cx
                            rest
                            (fold-left (lambda (imports entry)
                                         (import-binding imports entry (syntax-loc spec)))
                                       imports
                                       entries)))))))

    (: import-binding
       (impl (Fn (Table Binding) (Pair String Binding) Loc -> (Table Binding) ! compile)))
    (define (import-binding imports entry loc)
      (match (table-ref imports (::first entry))
        ((Some existing)
         (if (string=? (binding-identity existing) (binding-identity (::second entry)))
             imports
             (compile-error loc (string-append "conflicting imports of " (::first entry)))))
        ((None) (table-set imports (::first entry) (::second entry)))))

    ;; The (name . binding) entries an import set provides.
    (: import-set (impl (Fn Context Syntax -> (Pair Exports Context) ! fs compile)))
    (define (import-set cx spec)
      (match spec
        ((Form (Cons (Ident "only" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (expanding cx ((entries (checked-import-set inner idents)))
                      (Pair (filter (lambda (entry) (member? (::first entry) names)) entries)
                            cx))))
        ((Form (Cons (Ident "except" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (expanding cx ((entries (checked-import-set inner idents)))
                      (Pair
                       (filter (lambda (entry) (not (member? (::first entry) names))) entries)
                       cx))))
        ((Form (Cons (Ident "prefix" _ _) (Cons inner (Cons (Ident prefix _ _) (Nil)))) _)
         (expanding cx ((entries (import-set inner)))
                    (Pair (map (lambda (entry)
                                 (Pair (string-append prefix (::first entry))
                                       (::second entry)))
                               entries)
                          cx)))
        ((Form (Cons (Ident "rename" _ _) (Cons inner pairs)) _)
         (let ((renames (map rename-pair pairs)))
           (expanding cx ((entries (checked-import-set inner
                                                       (map (lambda (pair)
                                                              (match pair
                                                                ((Form (Cons from _) _) from)
                                                                (_ pair)))
                                                            pairs))))
                      (Pair (map (lambda (entry)
                                   (match (assoc-ref renames (::first entry))
                                     ((Some renamed) (Pair renamed (::second entry)))
                                     ((None) entry)))
                                 entries)
                            cx))))
        (_ (load-library cx (library-name spec) (syntax-loc spec)))))

    (: checked-import-set
       (impl (Fn Context Syntax (List Syntax) -> (Pair Exports Context) ! fs compile)))
    (define (checked-import-set cx spec idents)
      (expanding cx ((entries (import-set spec)))
                 (for-each (lambda (ident)
                             (match (assoc-ref entries (Ident-name ident))
                               ((Some _) (unit))
                               ((None) (compile-error (syntax-loc ident)
                                                      (string-append
                                                       "import names an identifier the library does not export: "
                                                       (Ident-name ident))))))
                           idents)
                 (Pair entries cx)))

    (: ident-names (impl (Fn (List Syntax) -> (List String) ! compile)))
    (define (ident-names idents)
      (map (lambda (ident) (Ident-name (expect-ident ident "an identifier"))) idents))

    (: rename-pair (impl (Fn Syntax -> (Pair String String) ! compile)))
    (define (rename-pair syntax)
      (match syntax
        ((Form (Cons (Ident from _ _) (Cons (Ident to _ _) (Nil))) _) (Pair from to))
        (_ (compile-error (syntax-loc syntax) "expected (name new-name)"))))

    (: export-entry (impl (Fn Context Env Syntax -> (Pair String Binding) ! compile)))
    (define (export-entry cx env spec)
      (match spec
        ((Ident name _ _) (Pair name (defined-binding cx env spec "exported name is not defined")))
        ((Form (Cons (Ident "rename" _ _) (Cons inner (Cons (Ident outer _ _) (Nil)))) _)
         (Pair outer (defined-binding cx env inner "exported name is not defined")))
        (_ (compile-error (syntax-loc spec) "expected an export specification"))))

    ;; The binding of an identifier that must be bound.
    (: defined-binding (impl (Fn Context Env Syntax String -> Binding ! compile)))
    (define (defined-binding cx env ident message)
      (match (resolve cx env (expect-ident ident "an identifier"))
        ((Some binding) binding)
        ((None)
         (compile-error (syntax-loc ident) (string-append message ": " (Ident-name ident))))))

    ;; The unique name of a top-level definition the scan bound.
    (: global-binding (impl (Fn Context Env Syntax -> String ! compile)))
    (define (global-binding cx env ident)
      (match (defined-binding cx env ident "undefined name")
        ((Global name) name)
        (_ (compile-error (syntax-loc ident)
                          (string-append "not a top-level definition: " (Ident-name ident))))))

    ;; ---- Top-level bodies ----

    ;; Pass 1 discovers every top-level name, so definitions may refer to later
    ;; ones. Signatures then resolve, needing only those names. Pass 2
    ;; resolves declarations, which enter the program as it goes, and
    ;; returns one step per definition or expression, from context to
    ;; context, that expands it. The steps then run as a fold, in the order
    ;; the scan found them, each handed the context the one before left, so
    ;; every body sees every declaration and the bodies before it. The
    ;; first two passes stop at an error, since what follows needs every
    ;; name and type; the bodies go on past one (`expand-bodies`).
    (struct Pending
      ((keyword String)
       (form Syntax)
       (env Env)))

    (: declaration-keywords (List String))
    (define declaration-keywords
      (list ":" "struct" "enum" "type" "typeclass" "instance" "extern" "effect" "expose"))

    (: expand-top-level (impl (Fn Context Env (List Syntax) -> Context ! fs compile)))
    (define (expand-top-level cx env forms)
      (expanding cx ((scanned (each (lambda (cx form) (scan-top-level cx env form)) forms)))
                 (let* ((pending (concatenate scanned))
                        (signatures
                         (fold-left (lambda (table entry) (with-signature cx table entry))
                                    empty-table
                                    pending)))
                   (expanding cx ((bodies (each (lambda (cx entry) (declare cx signatures entry))
                                                pending)))
                              (check-buildable-structs cx pending)
                              (expand-bodies cx (concatenate bodies))))))

    ;; A body that fails leaves the context as it was before it, and the
    ;; bodies after it are expanded all the same, so one compile reports
    ;; each body's error. Nothing a later body resolves can be missing for
    ;; it, since pass 1 bound every name. The library then fails with what
    ;; every failed body found, in order, and is never checked.
    (: expand-bodies
       (impl (Fn Context (List (dyn (Fn Context -> Context ! compile))) -> Context ! compile)))
    (define (expand-bodies cx bodies)
      (let ((run (fold-left (lambda (run body)
                              (match (recovering (lambda () (body (::first run))))
                                ((Ok cx) (Pair cx (::second run)))
                                ((Err found)
                                 (Pair (::first run)
                                       (append (::second run) (diagnostics->list found))))))
                            (Pair cx (Nil))
                            bodies)))
        (fail-if-found (::second run))
        (::first run)))

    ;; A struct whose every value would contain another value of itself,
    ;; through struct fields and cell contents only, can never be built: no
    ;; finite program constructs one. The backend relies on the rule, since
    ;; a call that may yield returns a placeholder of its type, a constant
    ;; it could not write for such a struct. Once every declaration of the
    ;; library is in, each struct is checked where it is declared. An empty
    ;; type is an enum with no cases.
    (: check-buildable-structs (impl (Fn Context (List Pending) -> Unit ! compile)))
    (define (check-buildable-structs cx pending)
      (for-each (lambda (entry)
                  (when (string=? (::keyword entry) "struct") (check-buildable cx entry)))
                pending))

    (: check-buildable (impl (Fn Context Pending -> Unit ! compile)))
    (define (check-buildable cx entry)
      (let ((name (declared-name (declaration-head (::form entry)))))
        (match (resolve cx (::env entry) name)
          ((Some (TypeName id _ _))
           (when (contains-itself? (::program cx) (program-type (::program cx) id))
             (compile-error (syntax-loc name)
                            (string-append "the struct "
                                           (Ident-name name)
                                           " can never be built: each of its values would contain another"))))
          (_ (panic "internal error: struct")))))

    (: scan-top-level (impl (Fn Context Env Syntax -> (Pair (List Pending) Context) ! fs compile)))
    (define (scan-top-level cx env form)
      (expanding cx ((form (expand-head env form)))
                 (let* ((parsed (declaration-annotations cx env form)) (bare (::first parsed))
                        (owner (if (null? (::second parsed)) (None)
                                   (Some (declared-name (declaration-head bare)))))
                        (scanned (scan-top-level-form cx env bare)))
                   (Pair (::first scanned)
                         (match owner
                           ((None) (::second scanned))
                           ((Some name) (with-name-annotations (::second scanned) name
                                                               (::second parsed))))))))

    ;; Annotation slots belong to declaration grammars, never executable
    ;; bodies or raw macro arguments. Expand a macro first; it can emit an
    ;; annotated signature just as a handwritten declaration can.
    (: declaration-annotations
       (impl (Fn Context Env Syntax -> (Pair Syntax (List Annotation)) ! compile)))
    (define (declaration-annotations cx env form)
      (match (head-binding cx env form)
        ((Some (Core keyword))
         (case keyword
           ((":" "type" "effect") (split-annotations form 3))
           (("struct" "enum" "typeclass") (split-annotations form 2))
           (("extern") (split-annotations form 5))
           (else (Pair form (Nil)))))
        (_ (Pair form (Nil)))))

    (: with-name-annotations (impl (Fn Context Syntax (List Annotation) -> Context)))
    (define (with-name-annotations cx ident annotations)
      (Context-program-set cx (program-with-annotations (::program cx)
                                                        (unique-name cx ident) annotations)))

    (: scan-top-level-form
       (impl (Fn Context Env Syntax -> (Pair (List Pending) Context) ! fs compile)))
    (define (scan-top-level-form cx env form)
      (match (head-binding cx env form)
        ((Some (Core "begin"))
         (expanding cx ((scanned (each (lambda (cx item) (scan-top-level cx env item))
                                       (form-tail form))))
                    (Pair (concatenate scanned) cx)))
        ((Some (Core "with-instances"))
         (match (form-tail form)
           ((Cons sets body)
            (let ((scope
                   (InstanceScope (form-items sets "a list of instance sets") env)))
              (expanding cx ((scanned
                              (each (lambda (cx item) (scan-top-level cx scope item))
                                    body)))
                         (Pair (Cons (Pending "instance-scope" form scope)
                                     (concatenate scanned))
                               cx))))
           (_ (compile-error (syntax-loc form)
                             "expected (with-instances (set ...) body ...)"))))
        ((Some (Core "define-instance-set")) (scan-instance-set cx env form))
        ((Some (Core "define-syntax")) (Pair (Nil) (define-top-macro cx env form)))
        ((Some (Core "primitive"))
         (compile-error (syntax-loc form)
                        "primitives are declared only in (snail core primitive)"))
        ((Some (Core "define"))
         (let ((ident (definition-name form)))
           (Pair (list (Pending "define" form env))
                 (bind-top cx env ident (Global (unique-name cx ident))))))
        ((Some (Core keyword))
         (if (member? keyword declaration-keywords)
             (scan-declared cx env keyword form)
             (Pair (list (Pending "expression" form env)) cx)))
        (_ (Pair (list (Pending "expression" form env)) cx))))

    (: scan-instance-set
       (impl (Fn Context Env Syntax -> (Pair (List Pending) Context) ! fs compile)))
    (define (scan-instance-set cx env form)
      (match (form-tail form)
        ((Cons name declarations)
         (let* ((name (expect-ident name "an instance set name")) (id (unique-name cx name))
                (cx (bind-top cx env name (InstanceSet id))) (scope (InstanceOwner id env)))
           (expanding cx ((scanned (each (lambda (cx declaration)
                                           (if (core-form? cx env declaration "instance")
                                               (scan-top-level cx scope declaration)
                                               (match declaration
                                                 ((Form (Cons (Ident "dynamic-instances" _ _) _) _)
                                                  (Pair (list (Pending "dynamic-instances"
                                                                       declaration
                                                                       scope))
                                                        cx))
                                                 (_ (compile-error (syntax-loc declaration)
                                                                   "an instance set contains instance or dynamic-instances declarations")))))
                                         declarations)))
                      (Pair (concatenate scanned) cx))))
        (_ (compile-error (syntax-loc form) "expected (define-instance-set name instance ...)"))))

    (: instance-owner (impl (Fn Env -> (Option String))))
    (define (instance-owner env)
      (match env
        ((InstanceOwner name _) (Some name))
        ((InstanceScope _ rest) (instance-owner rest))
        ((EvidenceScope _ rest) (instance-owner rest))
        ((Frame _ _ rest) (instance-owner rest))
        ((Top _ _) (None))))

    (: active-instance-sets (impl (Fn Context Env -> (List String) ! compile)))
    (define (active-instance-sets cx env)
      (match env
        ((InstanceScope sets rest)
         (delete-duplicates string=?
                            (append (map (lambda (name)
                                           (match (resolve cx
                                                           env
                                                           (expect-ident name "an instance set"))
                                             ((Some (InstanceSet id)) id)
                                             (_ (compile-error (syntax-loc name)
                                                               "not an instance set"))))
                                         sets)
                                    (active-instance-sets cx rest))))
        ((InstanceOwner name rest) (Cons name (active-instance-sets cx rest)))
        ((EvidenceScope _ rest) (active-instance-sets cx rest))
        ((Frame _ _ rest) (active-instance-sets cx rest))
        ((Top _ _) (Nil))))

    (: scope-instance-value (impl (Fn Context Env Expr -> Expr ! compile)))
    (define (scope-instance-value cx env value)
      (let ((sets (active-instance-sets cx env)))
        (if (null? sets) value
            (match (::term value)
              ((Lambda params body captures?)
               (Expr (Lambda params (expr (ScopedInstances sets body) (::loc body)) captures?)
                     (::type value) (::loc value)))
              (_ (expr (ScopedInstances sets value) (::loc value)))))))

    ;; A declaration binds its names, then the instances a struct or enum
    ;; derives are scanned after it.
    (: scan-declared
       (impl (Fn Context Env String Syntax -> (Pair (List Pending) Context) ! fs compile)))
    (define (scan-declared cx env keyword form)
      (expanding cx ((then (scan-declaration env keyword form)))
                 (if (or (string=? keyword "struct") (string=? keyword "enum"))
                     (expanding cx ((derived (derived-instances form (string=? keyword "enum")))
                                    (scanned
                                     (each (lambda (cx instance) (scan-top-level cx env instance))
                                           derived)))
                                (Pair (Cons (Pending keyword form env) (concatenate scanned)) cx))
                     (Pair (list (Pending keyword form env)) cx))))

    (: definition-name (impl (Fn Syntax -> Syntax ! compile)))
    (define (definition-name form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons name _) _) _)) _) (expect-ident name "a definition name"))
        ((Form (Cons _ (Cons name (Cons _ (Nil)))) _) (expect-ident name "a definition name"))
        (_ (compile-error (syntax-loc form)
                          "expected (define name value) or (define (name parameter ...) body ...)"))))

    (: declare
       (impl (Fn Context
                 (Table (Pair Scheme (Option Loc)))
                 Pending
                 -> (Pair (List (dyn (Fn Context -> Context ! compile))) Context) ! compile)))
    (define (declare cx signatures pending)
      (let ((form (::form pending)) (env (::env pending)))
        (case (::keyword pending)
          ((":") (Pair (Nil) cx))
          (("struct") (Pair (Nil) (declare-data cx env form #f)))
          (("enum") (Pair (Nil) (declare-data cx env form #t)))
          (("typeclass") (Pair (Nil) (declare-class cx env form)))
          (("instance") (declare-instance cx env form))
          (("dynamic-instances") (declare-dynamic-instances cx env form))
          (("instance-scope")
           (Pair (list (lambda (cx)
                         (check-active-instances (::program cx) (active-instance-sets cx env)
                                                 (syntax-loc form))
                         cx)) cx))
          (("extern") (Pair (Nil) (declare-extern cx env form)))
          (("effect") (declare-effect cx env form))
          (("define") (Pair (list (lambda (cx) (define-top-level cx signatures env form))) cx))
          (("expose") (Pair (list (lambda (cx) (add-item cx (expose-item cx env form)))) cx))
          (("expression")
           (Pair (list (lambda (cx)
                         (expanding cx ((value (expand-expr env form)))
                                    (add-item cx (Do (scope-instance-value cx env value))))))
                 cx))
          (else (Pair (Nil) cx)))))

    ;; `(expose name "symbol")` exports a top-level function to the host;
    ;; `(expose name "symbol" dynamic)` exports it for programs that load it
    ;; while they run, through (snail shell wasm).
    (: expose-item (impl (Fn Context Env Syntax -> Item ! compile)))
    (define (expose-item cx env form)
      (match form
        ((Form (Cons _ (Cons name (Cons (Atom (DString symbol) _) flags))) loc)
         (match (resolve cx env (expect-ident name "a function name"))
           ((Some (Global global)) (Expose global symbol (dynamic-flag? form flags) loc))
           (_ (compile-error (syntax-loc name)
                             (string-append "only a top-level function can be exposed: "
                                            (Ident-name name))))))
        (_ (compile-error (syntax-loc form) expose-usage))))

    (: dynamic-flag? (impl (Fn Syntax (List Syntax) -> Bool ! compile)))
    (define (dynamic-flag? form flags)
      (match flags
        ((Nil) #f)
        ((Cons (Ident "dynamic" _ _) (Nil)) #t)
        (_ (compile-error (syntax-loc form) expose-usage))))

    (: expose-usage String)
    (define expose-usage "expected (expose name \"symbol\") or (expose name \"symbol\" dynamic)")

    (: define-top-level
       (impl (Fn Context (Table (Pair Scheme (Option Loc))) Env Syntax -> Context ! compile)))
    (define (define-top-level cx signatures env form)
      (let ((name (global-binding cx env (definition-name form))))
        (check-signature cx (table-ref signatures name))
        (expanding cx ((value (definition-value env form))
                       (then (add-value name (match (table-ref signatures name)
                                               ((Some (Pair scheme loc))
                                                (Defined (Some scheme) loc (lambda-expr? value)))
                                               ((None)
                                                (Defined (None) (None) (lambda-expr? value)))))))
                   (add-item cx
                             (Define name
                               (scope-instance-value cx
                                                     env
                                                     (scope-instance-value cx
                                                                           env
                                                                           (top-level-value
                                                                            value))))))))

    ;; A signature's constraints, checked once every class the library
    ;; declares is in the program.
    (: check-signature (impl (Fn Context (Option (Pair Scheme (Option Loc))) -> Unit ! compile)))
    (define (check-signature cx signature)
      (match signature
        ((Some (Pair scheme (Some loc)))
         (for-each (lambda (constraint) (check-constraint (::program cx) constraint loc))
                   (::constraints scheme)))
        (_ (unit))))

    (: definition-value (impl (Fn Context Env Syntax -> (Pair Expr Context) ! compile)))
    (define (definition-value cx env form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons _ params) _) body)) loc)
         (expand-lambda cx env params body #t loc))
        ((Form (Cons _ (Cons _ (Cons value (Nil)))) _) (expand-expr cx env value))
        (_ (compile-error (syntax-loc form) "expected a definition"))))

    ;; No local is in scope where a top-level function is written, so it is
    ;; marked as one that may not capture, and every global function is
    ;; known to have no environment.
    (: top-level-value (impl (Fn Expr -> Expr)))
    (define (top-level-value value)
      (match (::term value)
        ((Lambda params body _) (Expr (Lambda params body #f) (::type value) (::loc value)))
        (_ value)))

    ;; ---- Declarations ----

    ;; Pass 1 binds the names a declaration introduces; pass 2 resolves types.
    (: scan-declaration (impl (Fn Context Env String Syntax -> Context ! compile)))
    (define (scan-declaration cx env keyword form)
      (match (form-tail form)
        ((Cons head rest)
         (case keyword
           (("struct") (scan-struct cx env head form))
           (("enum") (scan-enum cx env head form))
           (("type") (scan-alias cx env head rest form))
           (("typeclass") (scan-class cx env head rest))
           (("extern") (bind-member cx env head))
           (("effect") (scan-effect cx env head rest form))
           (else cx)))
        (_ (compile-error (syntax-loc form) "expected a declaration"))))

    ;; A declared name is global in the library that declares it.
    (: unique-name (impl (Fn Context Syntax -> String)))
    (define (unique-name cx ident)
      (global-name cx (ident-key ident)))

    ;; A struct's name is both its type and its constructor.
    (: scan-struct (impl (Fn Context Env Syntax Syntax -> Context ! compile)))
    (define (scan-struct cx env head form)
      (let* ((name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (Some (unique-name cx name))))))
        (bind-fields cx env name (struct-fields form) #t)))

    (: scan-enum (impl (Fn Context Env Syntax Syntax -> Context ! compile)))
    (define (scan-enum cx env head form)
      (let* ((name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (None)))))
        (fold-left (lambda (cx case) (scan-case cx env case)) cx (enum-cases form))))

    (: scan-alias (impl (Fn Context Env Syntax (List Syntax) Syntax -> Context ! compile)))
    (define (scan-alias cx env head rest form)
      (let ((name (declared-name head)))
        (match rest
          ((Cons body (Nil))
           (bind-top cx env name (Alias (unique-name cx name) (declared-params head) body env)))
          (_ (compile-error (syntax-loc form) "expected (type Name type)")))))

    ;; Register the complete class shape during scanning: signatures may
    ;; precede its declaration. Methods later establish which inputs are rows.
    (: scan-class (impl (Fn Context Env Syntax (List Syntax) -> Context ! compile)))
    (define (scan-class cx env head declarations)
      (let* ((name (declared-name head)) (id (unique-name cx name))
             (outputs (map associated-name (filter associated-form? declarations)))
             (params (append (map Ident-name (declared-params head)) outputs))
             (cx (bind-top cx env name (ClassName id))))
        (unless (= (length params) (length (delete-duplicates string=? params)))
          (compile-error (syntax-loc head)
                         "class parameters and associated types must be distinct"))
        (fold-left (lambda (cx declaration) (scan-class-member cx env name declaration))
                   (Context-program-set cx
                                        (program-with-class (::program cx)
                                                            (Class id params (Nil) outputs (Nil))))
                   declarations)))

    (: associated-form? (impl (Fn Syntax -> Bool)))
    (define (associated-form? form)
      (match form
        ((Form (Cons (Ident "type" _ _) _) _) #t)
        (_ #f)))

    (: associated-identifier (impl (Fn Syntax -> Syntax ! compile)))
    (define (associated-identifier form)
      (match (::first (split-annotations form 2))
        ((Form (Cons _ (Cons (Ident name mark loc) (Nil))) _) (Ident name mark loc))
        (_ (compile-error (syntax-loc form)
                          "expected (type Output); associated types take no parameters"))))

    (: associated-name (impl (Fn Syntax -> String ! compile)))
    (define (associated-name form)
      (Ident-name (associated-identifier form)))

    (: scan-class-member (impl (Fn Context Env Syntax Syntax -> Context ! compile)))
    (define (scan-class-member cx env class form)
      (let* ((associated? (associated-form? form))
             (parsed (split-annotations form (if associated? 2 3)))
             (bare (::first parsed))
             (name (if associated?
                       (suffixed-ident class (string-append "." (associated-name bare))
                                       (syntax-loc bare))
                       (declared-name (declaration-head bare))))
             (cx (scan-class-member-form cx env class bare)))
        (with-name-annotations cx name (::second parsed))))

    (: scan-class-member-form (impl (Fn Context Env Syntax Syntax -> Context ! compile)))
    (define (scan-class-member-form cx env class form)
      (if (associated-form? form)
          (let* ((member (associated-name form))
                 (name (suffixed-ident class (string-append "." member) (syntax-loc form))))
            (bind-top cx env name (Associated (unique-name cx class) member)))
          (match form
            ((Form (Cons (Ident ":" _ _) (Cons method (Cons _ (Nil)))) _)
             (bind-member cx env method))
            (_ (compile-error (syntax-loc form) "expected (: method type) or (type Output)")))))

    (: scan-effect (impl (Fn Context Env Syntax (List Syntax) Syntax -> Context ! compile)))
    (define (scan-effect cx env head rest form)
      (let* ((name (expect-ident head "an effect name"))
             (cx (bind-top cx env name (EffectName (unique-name cx name)))))
        (match rest
          ((Cons operations _)
           (fold-left (lambda (cx operation) (scan-operation cx env operation))
                      cx (form-items operations "a list of operations")))
          (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))")))))

    (: operation-form-arity (impl (Fn Syntax -> I64)))
    (define (operation-form-arity operation)
      (match operation
        ((Form (Cons (Ident "ctl" _ _) _) _) 3)
        (_ 2)))

    (: scan-operation (impl (Fn Context Env Syntax -> Context ! compile)))
    (define (scan-operation cx env operation)
      (let* ((parsed (split-annotations operation (operation-form-arity operation)))
             (name (match (::first parsed)
                     ((Form (Cons (Ident "ctl" _ _) (Cons name (Cons _ (Nil)))) _) name)
                     ((Form (Cons name (Cons _ (Nil))) _) name)
                     (_ (compile-error (syntax-loc operation)
                                       "expected (operation type) or (ctl operation type)"))))
             (cx (bind-member cx env name)))
        (with-name-annotations cx name (::second parsed))))

    (: bind-member (impl (Fn Context Env Syntax -> Context ! compile)))
    (define (bind-member cx env ident)
      (let ((ident (expect-ident ident "a name")))
        (bind-top cx env ident (Global (unique-name cx ident)))))

    (struct CaseSyntax
      ((name Syntax)
       (fields (List Syntax))
       (annotations (List Annotation))))

    (: parse-case (impl (Fn Syntax -> CaseSyntax ! compile)))
    (define (parse-case case)
      (let ((parsed (split-annotations case 1)))
        (match (::first parsed)
          ((Form (Cons name (Nil)) _)
           (CaseSyntax (expect-ident name "a case name") (Nil) (::second parsed)))
          ((Form (Cons name (Cons fields (Nil))) _)
           (CaseSyntax (expect-ident name "a case name")
                       (form-items fields "a field list") (::second parsed)))
          (_ (compile-error (syntax-loc case)
                            "expected (Case), or (Case ((field type) ...)), optionally with (annotations ...)")))))

    (: scan-case (impl (Fn Context Env Syntax -> Context ! compile)))
    (define (scan-case cx env case)
      (let* ((parsed (parse-case case)) (name (::name parsed))
             (cx (bind-member cx env name))
             (cx (bind-fields cx env name (::fields parsed) #f)))
        (with-name-annotations cx name (::annotations parsed))))

    ;; A field as written: `(name type)`, or `(name mut type)` for a
    ;; mutable one, optionally followed by an annotation list.
    (struct FieldSyntax
      ((name Syntax)
       (mutable? Bool)
       (type Syntax)
       (annotations (List Annotation))))

    (: parse-field (impl (Fn Syntax -> FieldSyntax ! compile)))
    (define (parse-field field)
      (let* ((required (match field
                         ((Form (Cons _ (Cons (Ident "mut" _ _) _)) _) 3)
                         (_ 2)))
             (parsed (split-annotations field required))
             (annotations (::second parsed)))
        (match (::first parsed)
          ((Form (Cons name (Cons type (Nil))) _) (FieldSyntax name #f type annotations))
          ((Form (Cons name (Cons (Ident "mut" _ _) (Cons type (Nil)))) _)
           (FieldSyntax name #t type annotations))
          (_ (compile-error (syntax-loc field)
                            "expected (field type) or (field mut type), optionally with (annotations ...)")))))

    ;; A field's generated names, by `field-suffixes`; a pure struct's
    ;; accessor name is reserved instead of bound.
    (: bind-fields (impl (Fn Context Env Syntax (List Syntax) Bool -> Context ! compile)))
    (define (bind-fields cx env name fields struct?)
      (let* ((parsed (map parse-field fields)) (pure? (not (any? ::mutable? parsed))))
        (for-each (lambda (field) (check-mutable-field cx field)) parsed)
        (fold-left (lambda (cx field)
                     (let ((cx (Context-program-set cx
                                                    (program-with-field-annotations
                                                     (::program cx)
                                                     (unique-name cx name)
                                                     (Ident-name
                                                      (expect-ident (::name field)
                                                                    "a field name"))
                                                     (::annotations field)))))
                       (fold-left (lambda (cx suffix)
                                    (bind-member cx
                                                 env
                                                 (field-ident name
                                                              (::name field)
                                                              suffix)))
                                  (if (and struct? pure?) (reserve-field-read cx env name field) cx)
                                  (field-suffixes field struct? pure?))))
                   cx parsed)))

    ;; A pure struct's field is read by path, but its accessor still exists
    ;; in the program under `Name-field`, as the field class instance's
    ;; method, so that name is bound as syntax that refuses use: a read
    ;; through it says to use the path, and a definition of it is a
    ;; duplicate rather than a silent replacement of the accessor.
    (: reserve-field-read (impl (Fn Context Env Syntax FieldSyntax -> Context ! compile)))
    (define (reserve-field-read cx env name field)
      (bind-top cx env (field-ident name (::name field) "") (Core "field-read")))

    (: field-read-message String)
    (define field-read-message
      "a struct's field is read by path, (::field s), not through an accessor")

    ;; `Ref` is the struct with a mutable field, declared in (snail core
    ;; base), and the runtime's `UnsafeSlot` in (snail shell slot) the
    ;; other: every other struct is a value, and a program holds one in a
    ;; cell to write its fields, `(set! (::count (ref-get r)) 1)`.
    (: check-mutable-field (impl (Fn Context FieldSyntax -> Unit ! compile)))
    (define (check-mutable-field cx field)
      (when (and (::mutable? field)
                 (not (member? (::prefix cx) (list "snail.core.base" "snail.shell.slot"))))
        (compile-error (syntax-loc (::name field))
                       "only Ref and the runtime's UnsafeSlot have a mutable field; hold the struct in a cell and write its fields with set!")))

    ;; The suffixes of the names a field binds. A struct whose fields are
    ;; all immutable is a value read by path, `(::field s)`, so it binds
    ;; only the pure replacement `Name-field-set`; its accessor exists in the
    ;; program as the field class instance's method. A mutable field, which
    ;; only Ref and UnsafeSlot have, is read by `Name-field` and written by
    ;; `Name-field-set!` and `Name-field-replace!`, and its struct has
    ;; identity, so no pure replacements. An enum's fields stay immutable
    ;; and have no field instance: a case's partial accessor `Case-field`
    ;; reads them, or a pattern does.
    (: field-suffixes (impl (Fn FieldSyntax Bool Bool -> (List String) ! compile)))
    (define (field-suffixes field struct? pure?)
      (cond ((and (::mutable? field) (not struct?))
             (compile-error (syntax-loc (::name field))
                            "an enum's fields cannot be mutable; hold a struct with a mutable field in the case"))
            ((::mutable? field) (list "" "-set!" "-replace!"))
            ((and struct? pure?) (list "-set"))
            (else (list ""))))

    ;; A field identifier shares the mark of its type's name, so a struct a
    ;; macro introduces has accessors only that expansion sees.
    (: field-ident (impl (Fn Syntax Syntax String -> Syntax ! compile)))
    (define (field-ident name field suffix)
      (suffixed-ident name
                      (string-append "-" (Ident-name (expect-ident field "a field name")) suffix)
                      (syntax-loc field)))

    ;; Generated accessors and projections inherit their declaring name's mark.
    (: suffixed-ident (impl (Fn Syntax String Loc -> Syntax)))
    (define (suffixed-ident name text loc)
      (Ident (string-append (Ident-name name) text)
             (match (Ident-mark name)
               ((Some mark)
                (Some (Mark (string-append (::key mark) text)
                            (::original mark)
                            (::scope mark))))
               ((None) (None))) loc))

    (: declared-name (impl (Fn Syntax -> Syntax ! compile)))
    (define (declared-name head)
      (match head
        ((Form (Cons name _) _) (expect-ident name "a type name"))
        (_ (expect-ident head "a type name"))))

    (: declared-params (impl (Fn Syntax -> (List Syntax) ! compile)))
    (define (declared-params head)
      (match head
        ((Form (Cons _ params) _)
         (map (lambda (param) (expect-ident param "a type parameter")) params))
        (_ (Nil))))

    ;; A struct or enum may end with `(deriving Class ...)`.
    (: deriving-clause? (impl (Fn Syntax -> Bool)))
    (define (deriving-clause? syntax)
      (match syntax
        ((Form (Cons (Ident "deriving" _ _) _) _) #t)
        (_ #f)))

    ;; The declaration's items after its head, without deriving clauses.
    (: declaration-body (impl (Fn Syntax -> (List Syntax))))
    (define (declaration-body form)
      (match (form-tail form)
        ((Cons _ rest) (filter (lambda (item) (not (deriving-clause? item))) rest))
        ((Nil) (Nil))))

    (: declaration-head (impl (Fn Syntax -> Syntax ! compile)))
    (define (declaration-head form)
      (match (form-tail form)
        ((Cons head _) head)
        ((Nil) (compile-error (syntax-loc form) "expected a declared name"))))

    (: struct-fields (impl (Fn Syntax -> (List Syntax) ! compile)))
    (define (struct-fields form)
      (match (declaration-body form)
        ((Nil) (Nil))
        ((Cons fields (Nil)) (form-items fields "a field list"))
        (_ (compile-error (syntax-loc form) "expected (struct Name ((field type) ...))"))))

    (: enum-cases (impl (Fn Syntax -> (List Syntax))))
    (define (enum-cases form)
      (declaration-body form))

    (: derived-classes (impl (Fn Syntax -> (List Syntax))))
    (define (derived-classes form)
      (concatenate (map form-tail (filter deriving-clause? (form-tail form)))))

    ;; `(deriving Move)` derives no instance: it makes the type linear by
    ;; its declaration (`::owned?`).
    (: move-class? (impl (Fn Syntax -> Bool)))
    (define (move-class? class)
      (match class
        ((Ident "Move" _ _) #t)
        (_ #f)))

    (: derived-instance-classes (impl (Fn Syntax -> (List Syntax))))
    (define (derived-instance-classes form)
      (filter (lambda (class) (not (move-class? class))) (derived-classes form)))

    ;; A type parameter scope binds each parameter to a rigid variable.
    (: type-scope (impl (Fn Env (List Syntax) -> Env)))
    (define (type-scope env params)
      (fold-left (lambda (scope param) (extend scope param (TypeVar (TRigid (Ident-name param)))))
                 env
                 params))

    ;; A case is its name followed by an optional field list; a struct is one
    ;; case named after the struct.
    (: declare-data (impl (Fn Context Env Syntax Bool -> Context ! compile)))
    (define (declare-data cx env form enum?)
      (let* ((head (declaration-head form)) (params (declared-params head))
             (id (match (resolve cx env (declared-name head))
                   ((Some (TypeName id _ _)) id)
                   (_ (panic "internal error: type"))))
             (scope (type-scope env params))
             (cases (if enum?
                        (map parse-case (enum-cases form))
                        (list (CaseSyntax (declared-name head) (struct-fields form) (Nil)))))
             (data (DataType id
                             (map Ident-name params)
                             (map-indexed (lambda (tag case) (resolve-case cx scope case id tag))
                                          cases)
                             enum?
                             (any? move-class? (derived-classes form)))))
        (Context-program-set cx
                             (fold-left (lambda (program case)
                                          (with-case-values program data case (not enum?)))
                                        (program-with-type (::program cx) data)
                                        (::cases data)))))

    (: resolve-case (impl (Fn Context Env CaseSyntax String I64 -> Case ! compile)))
    (define (resolve-case cx scope case type tag)
      (Case (constructor-name cx scope (::name case)) type tag
            (map (lambda (field) (resolve-field cx scope field)) (::fields case))))

    (: resolve-field (impl (Fn Context Env Syntax -> Field ! compile)))
    (define (resolve-field cx scope field)
      (let ((parsed (parse-field field)))
        (Field (Ident-name (expect-ident (::name parsed) "a field name"))
               (stored-type cx scope (::type parsed))
               (::mutable? parsed))))

    (: stored-type (impl (Fn Context Env Syntax -> Type ! compile)))
    (define (stored-type cx env syntax)
      (let ((type (resolve-type cx env syntax)))
        (check-stored-type type (syntax-loc syntax))
        type))

    (: check-stored-type (impl (Fn Type Loc -> Unit ! compile)))
    (define (check-stored-type type loc)
      (when (impl-callable? type)
        (compile-error loc
                       "stored and returned callable types require explicit dyn; impl is a definition or argument contract"))
      (match type
        ((TCon _ args) (for-each (lambda (arg) (check-stored-type arg loc)) args))
        ((TFun params result _) (for-each (lambda (part) (check-stored-type part loc))
                                          (Cons result params)))
        (_ (unit))))

    (: constructor-name (impl (Fn Context Env Syntax -> String ! compile)))
    (define (constructor-name cx env ident)
      (match (resolve cx env ident)
        ((Some (Global name)) name)
        ((Some (TypeName _ _ (Some constructor))) constructor)
        (_ (compile-error (syntax-loc ident)
                          (string-append "not a constructor: " (Ident-name ident))))))

    ;; A case's constructor, then each field's operations, as `bind-fields`
    ;; names them. Constructing is pure, even for a struct with identity,
    ;; and so is reading an immutable field; reading or writing a mutable
    ;; one performs `mut`.
    (: with-case-values (impl (Fn Program DataType Case Bool -> Program)))
    (define (with-case-values program data case struct?)
      (let* ((params (::params data)) (self (TCon (::name data) (map TRigid params)))
             (constructor (Constructor case
                                       (Scheme params
                                               (Nil)
                                               (Nil)
                                               (TFun (map ::type (::fields case))
                                                     self
                                                     empty-row))))
             (pure? (and struct? (not (any? ::mutable? (::fields case))))))
        (fold-left (lambda (program indexed)
                     (with-field-values program
                                        data
                                        case
                                        (::first indexed)
                                        (::second indexed)
                                        pure?))
                   (program-with-value program (::name case) constructor)
                   (zip (iota (length (::fields case))) (::fields case)))))

    (: with-field-values (impl (Fn Program DataType Case I64 Field Bool -> Program)))
    (define (with-field-values program data case index field pure?)
      (let* ((params (::params data))
             (self (TCon (::name data) (map TRigid params)))
             (type (::type field))
             (accessor (string-append (::name case) "-" (::name field)))
             (program (program-with-value
                       program
                       accessor
                       (Accessor case
                                 index
                                 (field-scheme params
                                               (list self)
                                               type
                                               (if (::mutable? field) mut-row empty-row))))))
        (cond ((::mutable? field)
               (program-with-value
                (program-with-value
                 program
                 (string-append accessor "-set!")
                 (Setter case
                         index
                         (field-scheme params (list self type) (TCon "Unit" (Nil)) mut-row)))
                (string-append accessor "-replace!")
                (Swapper case index (field-scheme params (list self type) type mut-row))))
              (pure?
               (program-with-field-instance
                (program-with-value
                 program
                 (string-append accessor "-set")
                 (Replacer case index (field-scheme params (list self type) self empty-row)))
                data
                (::name field)
                type
                accessor))
              (else program))))

    (: field-scheme (impl (Fn (List String) (List Type) Type Type -> Scheme)))
    (define (field-scheme params arguments result row)
      (Scheme params (Nil) (Nil) (TFun arguments result row)))

    ;; The signatures with the one a `(: name type)` declares, and where it
    ;; was written. A signature a macro writes is held to each expansion's
    ;; body like any other, so a macro that cannot know the row takes it as
    ;; an argument.
    (: with-signature
       (impl (Fn Context
                 (Table (Pair Scheme (Option Loc)))
                 Pending
                 -> (Table (Pair Scheme (Option Loc)))
                 ! compile)))
    (define (with-signature cx signatures pending)
      (if (string=? (::keyword pending) ":")
          (match (::form pending)
            ((Form (Cons _ (Cons name (Cons type (Nil)))) loc)
             (match (resolve cx (::env pending) (expect-ident name "a name"))
               ((Some (Global global))
                (table-set signatures
                           global
                           (Pair (resolve-scheme cx (::env pending) type) (Some loc))))
               (_ (compile-error (syntax-loc name)
                                 (string-append
                                  "signature names an undefined top-level definition: "
                                  (Ident-name name))))))
            (form (compile-error (syntax-loc form) "expected (: name type)")))
          signatures))

    (: declare-class (impl (Fn Context Env Syntax -> Context ! compile)))
    (define (declare-class cx env form)
      (let* ((head (declaration-head form))
             (id (match (resolve cx env (declared-name head))
                   ((Some (ClassName id)) id)
                   (_ (panic "internal error: class"))))
             (class (program-class (::program cx) id))
             (params (append (declared-params head)
                             (map associated-identifier
                                  (filter associated-form? (list-drop (form-tail form) 1)))))
             (self (Constraint id (map (lambda (param) (TRigid (Ident-name param))) params)))
             (scope (EvidenceScope (list self) (type-scope env params))))
        (expanding cx ((methods (each (lambda (cx signature)
                                        (declare-method cx env scope id params self signature))
                                      (filter (lambda (form) (not (associated-form? form)))
                                              (list-drop (form-tail form) 1)))))
                   (let ((rows (class-rows (::program cx) (::params class) methods
                                           (syntax-loc form))))
                     (when (any? (lambda (output) (member? output rows)) (::outputs class))
                       (compile-error (syntax-loc form)
                                      "an associated type must have kind Type, not an effect row"))
                     (Context-program-set cx
                                          (program-with-class (::program cx)
                                                              (Class id (::params class) rows
                                                                     (::outputs class)
                                                                     methods)))))))

    ;; The parameters the class's methods perform as rows, `e` in
    ;; `(: fetch-object (impl (Fn S String -> String ! e)))`, in order; a row's kind
    ;; is found from its use, as `All`'s variables' are. A parameter a
    ;; method also writes as a type could not be both.
    (: class-rows (impl (Fn Program (List String) (List String) Loc -> (List String) ! compile)))
    (define (class-rows program params methods loc)
      (let* ((types (map (lambda (method) (method-type program method)) methods))
             (rows (filter (lambda (param)
                             (any? (lambda (type) (member? param (row-names type))) types))
                           params)))
        (for-each (lambda (row)
                    (when (any? (lambda (type) (member? row (type-names type))) types)
                      (compile-error loc
                                     (string-append "the class parameter "
                                                    row
                                                    " is written both as a row and as a type"))))
                  rows)
        rows))

    (: method-type (impl (Fn Program String -> Type)))
    (define (method-type program method)
      (match (program-value program method)
        ((Some (Method _ scheme)) (::type scheme))
        (_ (panic "internal error: not a method"))))

    ;; The variables a type ends a row with, and those it writes as types.
    (: row-names (impl (Fn Type -> (List String))))
    (define (row-names type)
      (match type
        ((TFun params result row)
         (append (concatenate (map row-names params)) (append (row-names result) (row-names row))))
        ((TCon _ args) (concatenate (map row-names args)))
        ((TRow _ (Some (TRigid name))) (list name))
        ((TRow _ (Some tail)) (row-names tail))
        (_ (Nil))))

    (: type-names (impl (Fn Type -> (List String))))
    (define (type-names type)
      (match type
        ((TRigid name) (list name))
        ((TFun params result _) (append (concatenate (map type-names params)) (type-names result)))
        ((TCon _ args) (concatenate (map type-names args)))
        (_ (Nil))))

    (: declare-method
       (impl (Fn Context
                 Env
                 Env
                 String
                 (List Syntax)
                 Constraint
                 Syntax
                 ->
                 (Pair String Context)
                 ! compile)))
    (define (declare-method cx env scope class params self signature)
      (match (::first (split-annotations signature 3))
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (let ((own (operational-scheme (resolve-scheme cx scope type)))
               (global (global-binding cx env name)))
           (Pair global
                 (add-value cx global
                            (Method class
                                    (Scheme (append (map Ident-name params) (::vars own))
                                            (Cons self (::constraints own))
                                            (::copy own)
                                            (::type own)))))))
        (_ (compile-error (syntax-loc signature) "expected (: method type)"))))

    ;; Returns one step per method, which expands its definition.
    (: declare-instance
       (impl (Fn Context
                 Env
                 Syntax
                 ->
                 (Pair (List (dyn (Fn Context -> Context ! compile))) Context)
                 ! compile)))
    (define (declare-instance cx env form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons class-ident type-args) _) body)) loc)
         (let ((parts (split-requires body)))
           (expanding cx ((class (instance-class env class-ident))
                          (instance (declared-instance env class type-args (::first parts)
                                                       (filter associated-form? (::second parts))
                                                       loc))
                          (methods
                           (declare-instance-methods env class instance
                                                     (filter
                                                      (lambda (form) (not (associated-form? form)))
                                                      (::second parts)) loc)))
                      (check-instance-methods class methods loc)
                      (check-overlap (::program cx) instance loc)
                      (Pair (map ::expand methods)
                            (Context-program-set cx
                                                 (program-with-instance (instance-program cx
                                                                                          class
                                                                                          instance
                                                                                          loc)
                                                                        (instance-with-methods
                                                                         instance
                                                                         methods)))))))
        (_
         (compile-error (syntax-loc form) "expected (instance (Class type ...) definition ...)"))))

    (: declare-dynamic-instances
       (impl (Fn Context
                 Env
                 Syntax
                 ->
                 (Pair (List (dyn (Fn Context -> Context ! compile))) Context)
                 ! compile)))
    (define (declare-dynamic-instances cx env form)
      (match (Pair (form-tail form) (instance-owner env))
        ((Pair (Cons name domain) (Some owner))
         (expanding cx ((class (instance-class env name))
                        (id (fresh-global "dynamic")))
                    (let ((generated (generate-binary-instances
                                      (::program cx) class
                                      (map (lambda (pair)
                                             (map (lambda (type) (resolve-type cx env type))
                                                  (form-items pair "a pair of concrete types")))
                                           domain)
                                      (active-instance-sets cx env) owner id (syntax-loc form))))
                      (expanding cx ((bodies (each (lambda (cx generated)
                                                     (install-generated-instance cx
                                                                                 class
                                                                                 generated
                                                                                 (syntax-loc form)))
                                                   generated)))
                                 (Pair (concatenate bodies) cx)))))
        (_ (compile-error (syntax-loc form)
                          "expected (dynamic-instances Class (Left Right) ...) in an instance set"))))

    (: install-generated-instance
       (impl (Fn Context
                 Class
                 GeneratedInstance
                 Loc
                 -> (Pair (List (dyn (Fn Context -> Context ! compile))) Context)
                 ! compile)))
    (define (install-generated-instance cx class generated loc)
      (let* ((instance (::instance generated))
             (cx (fold-left (lambda (cx method)
                              (add-value cx (::second method)
                                         (Defined (Some (instance-method-scheme (::program cx)
                                                                                class
                                                                                (::first method)
                                                                                instance))
                                           (None) #t)))
                            cx (::methods instance))))
        (check-overlap (::program cx) instance loc)
        (Pair (map (lambda (definition) (lambda (cx) (add-item cx definition)))
                   (::definitions generated))
              (Context-program-set cx
                                   (program-with-instance (instance-program cx class instance loc)
                                                          instance)))))

    (: instance-class (impl (Fn Context Env Syntax -> (Pair Class Context) ! compile)))
    (define (instance-class cx env class-ident)
      (match (field-class-syntax cx class-ident)
        ((Some (Pair id cx)) (Pair (program-class (::program cx) id) cx))
        ((None)
         (match (resolve cx env class-ident)
           ((Some (ClassName id))
            (when (callable-class? id)
              (compile-error (syntax-loc class-ident)
                             "callable instances are established by the compiler from receiver access and captures"))
            (when (string=? id "snail.core.base:Unboxed")
              (compile-error (syntax-loc class-ident)
                             "Unboxed is decided by a type's representation; no instance can be declared"))
            (Pair (program-class (::program cx) id) cx))
           (_ (compile-error (syntax-loc class-ident)
                             "instance of something that is not a typeclass"))))))

    ;; A dispatch clause supplies ordinary methods, just as explicit
    ;; definitions do. Its finite domain belongs to this instance's library;
    ;; importing another instance never changes which payloads it accepts.
    (: declare-instance-methods
       (impl (Fn Context
                 Env
                 Class
                 Instance
                 (List Syntax)
                 Loc
                 -> (Pair (List MethodDefinition) Context)
                 ! compile)))
    (define (declare-instance-methods cx env class instance body loc)
      (match body
        ((Cons (Form (Cons (Ident "dispatch" _ _) types) _) (Nil))
         (let ((dispatch (parse-dispatch class instance
                                         (map (lambda (type) (resolve-type cx env type)) types)
                                         loc)))
           (each cx
                 (lambda (cx method)
                   (dispatch-instance-method cx class instance method dispatch loc))
                 (::methods class))))
        (_ (each cx
                 (lambda (cx definition) (instance-method cx env class instance definition))
                 body))))

    (: dispatch-instance-method
       (impl (Fn Context Class Instance String Dispatch Loc -> (Pair MethodDefinition Context))))
    (define (dispatch-instance-method cx class instance method dispatch loc)
      (expanding cx ((global (fresh-global (short-name method)))
                     (then (add-value global
                                      (Defined (Some (instance-method-scheme (::program cx)
                                                                             class method instance))
                                        (None) #t))))
                 (Pair (MethodDefinition method global
                                         (lambda (cx)
                                           (add-item cx
                                                     (Define global
                                                       (dispatch-method (::program cx)
                                                                        class
                                                                        instance
                                                                        method dispatch loc)))))
                       cx)))

    ;; The program after an instance's checks of its head, with a Drop
    ;; instance's type made linear; any other instance changes nothing.
    (: instance-program (impl (Fn Context Class Instance Loc -> Program ! compile)))
    (define (instance-program cx class instance loc)
      (let ((name (::name class)))
        (unless (= (length (::types instance)) (length (::params class)))
          (compile-error loc
                         (string-append (instance-noun name)
                                        " gives each of the class's parameters, as in ("
                                        (string-join (Cons (short-name name) (::params class))
                                                     " ")
                                        ")")))
        (when (and (lifecycle-class? name)
                   (match (::set instance) ((Some _) #t) ((None) #f)))
          (compile-error loc "lifecycle instances cannot belong to a named instance set"))
        (check-instance-determination (::program cx) class instance loc)
        (check-head-rows (::program cx) class instance loc)
        (if (lifecycle-class? name) (lifecycle-program cx instance loc) (::program cx))))

    ;; Prerequisites are ordered. Inputs bind variables first; only an
    ;; earlier requirement's row or output may determine another variable.
    ;; An expected result can never make an otherwise unknown input known.
    (: check-instance-determination (impl (Fn Program Class Instance Loc -> Unit ! compile)))
    (define (check-instance-determination program class instance loc)
      (unless (null? (::outputs class))
        (let* ((inputs
                (concatenate (map type-names (type-arguments class (::types instance)))))
               (known (fold-left (lambda (known requirement)
                                   (determined-requirement program known requirement loc))
                                 inputs (::requires instance)))
               (needed
                (concatenate (map type-names (output-arguments class (::types instance)))))
               (rows
                (concatenate (map row-variable (row-arguments class (::types instance))))))
          (unless (every? (lambda (name) (member? name known)) (append needed rows))
            (compile-error loc
                           "instance outputs must be determined by its inputs and earlier requirements"))
          (when (any? (lambda (name) (member? name rows)) needed)
            (compile-error loc "an associated output cannot use an effect row as a type")))))

    (: determined-requirement
       (impl (Fn Program (List String) Constraint Loc -> (List String) ! compile)))
    (define (determined-requirement program known requirement loc)
      (let* ((class (program-class program (::class requirement)))
             (types (::types requirement))
             (inputs (concatenate (map type-names (type-arguments class types)))))
        (unless (every? (lambda (name) (member? name known)) inputs)
          (compile-error loc "a prerequisite input must be determined before that prerequisite"))
        (append known (concatenate (map type-names
                                        (append (output-arguments class types)
                                                (row-arguments class types)))))))

    ;; A lifecycle instance is for a declared type, beside it; a Drop
    ;; instance's type is linear.
    (: lifecycle-program (impl (Fn Context Instance Loc -> Program ! compile)))
    (define (lifecycle-program cx instance loc)
      (let ((program (::program cx)) (class (::class instance)))
        (match (::types instance)
          ((Cons _ (Cons (TCon name args) (Nil)))
           (check-lifecycle-head cx class name args loc)
           (if (string=? class drop-class)
               (program-with-type program (DataType-owned?-set (program-type program name) #t))
               program))
          (_ (compile-error loc (string-append (instance-noun class)
                                               " names a row and a declared type"))))))

    ;; An instance writes each row its class's methods perform in its head,
    ;; `(! label ...)`, since mono finds the instance from ground types,
    ;; where no row variable could be solved, and gives a type for each
    ;; other parameter. A row is closed, or ends with the row `e` of the
    ;; instance's requirements, as `(Drop e A)` or `(Store e S)`, which the
    ;; types the requirement is given decide. Ordinary methods may perform
    ;; control effects; mono retains these rows in specialization keys and
    ;; call types. Drops and clones must still run to completion.
    (: check-head-rows (impl (Fn Program Class Instance Loc -> Unit ! compile)))
    (define (check-head-rows program class instance loc)
      (for-each (lambda (argument)
                  (check-head-argument program
                                       class
                                       (::first argument)
                                       (::second argument)
                                       loc))
                (zip (::params class) (::types instance)))
      (cond ((lifecycle-class? (::name class))
             (check-lifecycle-requirements (::name class) instance (head-tail instance) loc))
            ((not (null? (::rows class))) (check-row-requirements program class instance loc))
            (else (unit))))

    (: check-head-argument (impl (Fn Program Class String Type Loc -> Unit ! compile)))
    (define (check-head-argument program class param argument loc)
      (match argument
        ((TRow labels _)
         (unless (member? param (::rows class))
           (compile-error loc
                          (string-append (instance-noun (::name class))
                                         " gives its type parameter "
                                         param
                                         " a row, not a type")))
         (for-each (lambda (label) (check-head-label program (::name class) label loc))
                   labels))
        (_ (when (member? param (::rows class))
             (compile-error loc (row-usage (::name class)))))))

    (: check-head-label (impl (Fn Program String String Loc -> Unit ! compile)))
    (define (check-head-label program class label loc)
      (match (table-ref (::effects program) label)
        ((Some effect)
         (when (and (lifecycle-class? class) (not (null? (::control effect))))
           (compile-error loc
                          (string-append (cond ((string=? class drop-class) "a drop")
                                               ((string=? class clone-class) "a clone")
                                               (else (instance-noun class)))
                                         " cannot perform the control effect "
                                         (short-name label)))))
        ((None) (unit))))

    ;; The tail of a lifecycle instance's row, its first argument.
    (: head-tail (impl (Fn Instance -> (Option Type))))
    (define (head-tail instance)
      (match (::types instance)
        ((Cons (TRow _ tail) _) tail)
        (_ (None))))

    ;; A row class's instance ends its rows with variables its requirements
    ;; of row classes give their rows, and those requirements give theirs
    ;; no other variable: the types they are given then decide what the
    ;; rows hold. A requirement may give a closed row instead, as
    ;; `(Store (!) S)`, which bounds what its types may perform.
    (: check-row-requirements (impl (Fn Program Class Instance Loc -> Unit ! compile)))
    (define (check-row-requirements program class instance loc)
      (let ((tails (concatenate (map row-variable (row-arguments class (::types instance)))))
            (required (concatenate (map (lambda (constraint)
                                          (requirement-row-variables program constraint))
                                        (::requires instance)))))
        (unless (and (every? (lambda (row) (any? (lambda (tail) (rigid-named? row tail)) tails))
                             required)
                     (every? (lambda (tail) (any? (lambda (row) (rigid-named? row tail)) required))
                             tails))
          (compile-error loc (row-usage (::name class))))))

    ;; The variables a requirement gives its class's row parameters, where
    ;; it gives a variable rather than a closed row.
    (: requirement-row-variables (impl (Fn Program Constraint -> (List Type))))
    (define (requirement-row-variables program constraint)
      (filter (lambda (row)
                (match row
                  ((TRigid _) #t)
                  (_ #f)))
              (row-arguments (program-class program (::class constraint))
                             (::types constraint))))

    (: rigid-named? (impl (Fn Type String -> Bool)))
    (define (rigid-named? type name)
      (match type
        ((TRigid other) (string=? other name))
        (_ #f)))

    (: row-usage (impl (Fn String -> String)))
    (define (row-usage class)
      (if (lifecycle-class? class)
          (lifecycle-row-usage class)
          (string-append (instance-noun class)
                         "'s rows are closed, (! label ...), or end with the row e its"
                         " requirements give a row class, as (! label ... e) with (requires ("
                         (short-name class)
                         " e A))")))

    ;; Each requirement runs the class's method at one of the instance's
    ;; variables in the row its head ends with, so one row holds what all
    ;; of them perform; without one, the row is closed.
    (: check-lifecycle-requirements (impl (Fn String Instance (Option Type) Loc -> Unit ! compile)))
    (define (check-lifecycle-requirements class instance tail loc)
      (let ((required (::requires instance)))
        (for-each (lambda (constraint)
                    (unless (string=? (::class constraint) class)
                      (compile-error loc
                                     (string-append (instance-noun class)
                                                    " can require only (Copy A) and ("
                                                    (short-name class)
                                                    " e A)")))
                    (match (Pair tail (::types constraint))
                      ((Pair (Some (TRigid name)) (Cons (TRigid row) (Cons (TRigid var) (Nil))))
                       (unless (and (string=? name row) (member? var (::vars instance)))
                         (compile-error loc (lifecycle-row-usage class))))
                      (_ (compile-error loc (lifecycle-row-usage class)))))
                  required)
        (match (Pair tail required)
          ((Pair (Some _) (Nil)) (compile-error loc (lifecycle-row-usage class)))
          (_ (unit)))))

    (: lifecycle-row-usage (impl (Fn String -> String)))
    (define (lifecycle-row-usage class)
      (string-append (instance-noun class)
                     "'s row is closed, (! label ...), or ends with the row e of its requirements ("
                     (short-name class)
                     " e A), as (! label ... e)"))

    (: instance-noun (impl (Fn String -> String)))
    (define (instance-noun class)
      (string-append "a " (short-name class) " instance"))

    ;; It is declared beside its type, for the type at distinct variables,
    ;; so a type has one of each class, which its name finds, and its
    ;; library alone may take the type's values apart when it has a Drop
    ;; instance.
    (: check-lifecycle-head (impl (Fn Context String String (List Type) Loc -> Unit ! compile)))
    (define (check-lifecycle-head cx class name args loc)
      (unless (string=? (name-owner name) (::prefix cx))
        (compile-error loc
                       (string-append (instance-noun class)
                                      " is declared in the library of its type")))
      (let ((names (map (lambda (arg)
                          (match arg
                            ((TRigid name) name)
                            (_ "")))
                        args)))
        (unless (and (not (member? "" names))
                     (= (length (delete-duplicates string=? names)) (length names)))
          (compile-error loc
                         (string-append (instance-noun class)
                                        " is for its type at distinct variables")))))

    (: instance-with-methods (impl (Fn Instance (List MethodDefinition) -> Instance)))
    (define (instance-with-methods instance methods)
      (Instance-methods-set instance
                            (map (lambda (method)
                                   (Pair (::method method)
                                         (::global method)))
                                 methods)))

    ;; Unbound identifiers in an instance head are its type variables.
    (: declared-instance
       (impl (Fn Context Env Class (List Syntax) (List Syntax) (List Syntax) Loc
                 -> (Pair Instance Context) ! compile)))
    (define (declared-instance cx env class type-args requires equations loc)
      (let* ((vars (delete-duplicates string=?
                                      (concatenate
                                       (map (lambda (type) (free-type-names cx env type))
                                            type-args))))
             (scope (type-scope env (map (lambda (name) (Ident name (None) loc)) vars)))
             (requirements (resolve-requirements cx scope vars requires))
             (types (map (lambda (type) (resolve-type cx (::env requirements) type))
                         type-args))
             (outputs (instance-outputs cx (::env requirements) class equations loc)))
        (when (and (not (null? (::outputs class)))
                   (not (= (length types)
                           (- (length (::params class)) (length (::outputs class))))))
          (compile-error loc
                         "instance head gives each declared class parameter; associated types belong in its body"))
        (expanding cx ((name (fresh-global (short-name (::name class)))))
                   (Pair (Instance name (::name class) (::vars requirements)
                                   (append types outputs) (::constraints requirements)
                                   (::copy requirements) (Nil) (instance-owner env))
                         cx))))

    (: instance-outputs (impl (Fn Context Env Class (List Syntax) Loc -> (List Type) ! compile)))
    (define (instance-outputs cx env class equations loc)
      (let ((definitions (map associated-equation equations)))
        (unless (and (= (length definitions) (length (::outputs class)))
                     (= (length definitions)
                        (length (delete-duplicates string=? (map ::first definitions))))
                     (every? (lambda (entry) (member? (::first entry) (::outputs class)))
                             definitions))
          (compile-error loc "an instance defines each associated type exactly once"))
        (map (lambda (name)
               (match (assoc-ref definitions name)
                 ((Some type) (resolve-type cx env type))
                 ((None) (compile-error loc (string-append "missing associated type " name)))))
             (::outputs class))))

    (: associated-equation (impl (Fn Syntax -> (Pair String Syntax) ! compile)))
    (define (associated-equation syntax)
      (match syntax
        ((Form (Cons _ (Cons (Ident name _ _) (Cons type (Nil)))) _) (Pair name type))
        (_ (compile-error (syntax-loc syntax) "expected (type Output Type)"))))

    (: fresh-global (impl (Fn Context String -> (Pair String Context))))
    (define (fresh-global cx base)
      (expanding cx ((name (fresh base)))
                 (Pair (global-name cx name) cx)))

    ;; A body may start with `(requires (Class type ...) ...)`.
    (: split-requires (impl (Fn (List Syntax) -> (Pair (List Syntax) (List Syntax)))))
    (define (split-requires items)
      (match items
        ((Cons (Form (Cons (Ident "requires" _ _) constraints) _) rest) (Pair constraints rest))
        (_ (Pair (Nil) items))))

    ;; One method of an instance: the class method it implements, the global
    ;; that holds its definition, and the step that expands it.
    (struct MethodDefinition
      ((method String)
       (global String)
       (expand (dyn (Fn Context -> Context ! compile)))))

    (: instance-method
       (impl (Fn Context Env Class Instance Syntax -> (Pair MethodDefinition Context) ! compile)))
    (define (instance-method cx env class instance definition)
      (unless (core-form? cx env definition "define")
        (compile-error (syntax-loc definition) "expected a method definition"))
      (let* ((ident (definition-name definition))
             (method
              (match (find (lambda (method)
                             (string=? (if (field-class? (::name class))
                                           method
                                           (short-name method))
                                       (Ident-name ident)))
                           (::methods class))
                ((Some method) method)
                ((None)
                 (compile-error (syntax-loc ident)
                                (string-append "not a method of this class: "
                                               (Ident-name ident)))))))
        (expanding cx ((global (fresh-global (short-name method)))
                       (then (add-value global
                                        (Defined (Some (instance-method-scheme (::program cx)
                                                                               class
                                                                               method
                                                                               instance))
                                          (None)
                                          #f))))
                   (Pair (MethodDefinition method global
                                           (lambda (cx)
                                             (expanding cx ((value
                                                             (definition-value env definition)))
                                                        (add-item cx
                                                                  (Define global
                                                                    (top-level-value value))))))
                         cx))))

    (: instance-method-scheme (impl (Fn Program Class String Instance -> Scheme)))
    (define (instance-method-scheme program class method instance)
      (match (program-value program method)
        ((Some (Method _ (Scheme method-vars (Cons _ own) copy type)))
         (let* ((class-vars (::params class))
                (locals (rename-method-variables (list-drop method-vars (length class-vars))
                                                 (::vars instance)))
                (substitution (append (zip class-vars (::types instance))
                                      (map (lambda (binding)
                                             (Pair (::first binding)
                                                   (TRigid (::second binding))))
                                           locals))))
           (Scheme (append (::vars instance) (map ::second locals))
                   (append (::requires instance)
                           (map (lambda (c) (substitute-constraint substitution c)) own))
                   (append (::copy instance)
                           (map (lambda (name) (renamed-variable locals name)) copy))
                   (substitute substitution type))))
        (_ (panic "internal error: not a method"))))

    ;; An instance and a polymorphic method have separate quantifiers.
    ;; Fresh names keep their associated output slots separate when those
    ;; schemes are combined for the implementation; argument order stays fixed.
    (: rename-method-variables
       (impl (Fn (List String) (List String) -> (List (Pair String String)))))
    (define (rename-method-variables vars taken)
      (match vars
        ((Nil) (Nil))
        ((Cons var rest)
         (let ((name (fresh-type-variable (string-append "$method." var) taken)))
           (Cons (Pair var name) (rename-method-variables rest (Cons name taken)))))))

    (: fresh-type-variable (impl (Fn String (List String) -> String)))
    (define (fresh-type-variable name taken)
      (if (member? name taken) (fresh-type-variable (string-append "$" name) taken) name))

    (: renamed-variable (impl (Fn (List (Pair String String)) String -> String)))
    (define (renamed-variable names name)
      (match (assoc-ref names name)
        ((Some renamed) renamed)
        ((None) name)))

    ;; Instance selection matches heads, so two heads may never both match
    ;; the same types. A type variable in either head matches anything.
    (: check-overlap (impl (Fn Program Instance Loc -> Unit ! compile)))
    (define (check-overlap program instance loc)
      (check-instance-overlap
       program instance
       (filter (lambda (other)
                 (match (Pair (::set instance) (::set other))
                   ((Pair (None) (None)) #t)
                   ((Pair (Some name) (Some other)) (string=? name other))
                   (_ #f)))
               (class-instances program (::class instance))) loc))

    (: check-instance-methods (impl (Fn Class (List MethodDefinition) Loc -> Unit ! compile)))
    (define (check-instance-methods class methods loc)
      (for-each (lambda (method)
                  (unless (any? (lambda (definition)
                                  (string=? (::method definition) method))
                                methods)
                    (compile-error loc
                                   (string-append "instance is missing a method: "
                                                  (short-name method)))))
                (::methods class)))

    (: free-type-names (impl (Fn Context Env Syntax -> (List String))))
    (define (free-type-names cx env syntax)
      (match syntax
        ((Ident name _ _)
         (match (resolve cx env syntax)
           ((Some _) (Nil))
           ((None) (list name))))
        ((Form (Cons (Ident "!" _ _) labels) _)
         (concatenate (map (lambda (label) (free-type-names cx env label)) labels)))
        ((Form items _) (concatenate (map (lambda (item) (free-type-names cx env item)) items)))
        (_ (Nil))))

    (: declare-extern (impl (Fn Context Env Syntax -> Context ! compile)))
    (define (declare-extern cx env form)
      (match form
        ((Form (Cons _
                     (Cons name
                           (Cons (Atom (DString module) _)
                                 (Cons (Atom (DString symbol) _) (Cons type (Nil))))))
               _)
         (let ((resolved (fn-arrow (resolve-type cx env type))))
           (check-host-parameters resolved (syntax-loc type))
           (add-value cx
                      (global-binding cx env name)
                      (Foreign (Import module symbol) (mono-scheme resolved)))))
        (_ (compile-error (syntax-loc form) "expected (extern name \"module\" \"symbol\" type)"))))

    ;; The host reads only scalars, and one String or Bytes argument, which
    ;; the caller stages in the runtime's buffer just before the call; so a
    ;; host function may take a buffer only as its last argument.
    (: check-host-parameters (impl (Fn Type Loc -> Unit ! compile)))
    (define (check-host-parameters type loc)
      (match type
        ((TFun params _ _)
         (unless (staged-last? params)
           (compile-error loc
                          "a host function can take a String or Bytes only as its last argument")))
        (_ (unit))))

    (: staged-last? (impl (Fn (List Type) -> Bool)))
    (define (staged-last? params)
      (match params
        ((Cons param (Cons next rest))
         (and (not (buffer-type? param)) (staged-last? (Cons next rest))))
        (_ #t)))

    ;; Operations perform their effect. A `default` clause after them names
    ;; Snail-Core implementations, whose definitions expand with the
    ;; library's bodies, in the steps this returns.
    (: declare-effect
       (impl (Fn Context
                 Env
                 Syntax
                 ->
                 (Pair (List (dyn (Fn Context -> Context ! compile))) Context)
                 ! compile)))
    (define (declare-effect cx env form)
      (match form
        ((Form (Cons _ (Cons name (Cons operations clauses))) loc)
         (let ((id (match (resolve cx env name)
                     ((Some (EffectName id)) id)
                     (_ (panic "internal error: effect")))))
           (expanding cx ((declared
                           (each (lambda (cx operation) (declare-operation cx env id operation))
                                 (form-items operations "a list of operations"))))
                      (let ((operations (map ::first declared))
                            (control (map ::first (filter ::second declared))))
                        (expanding cx ((snail (snail-defaults env
                                                              operations
                                                              control
                                                              (default-clauses clauses))))
                                   (let ((effect (Effect id
                                                         operations
                                                         control
                                                         (effect-defaults snail loc)
                                                         (around-main? clauses))))
                                     (Pair (map ::expand snail)
                                           (Context-program-set cx
                                                                (program-with-effect
                                                                 (::program cx)
                                                                 effect)))))))))
        (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))"))))

    ;; `(name type)` declares an operation whose implementation returns to
    ;; its caller, `(ctl name type)` one whose implementation is handed the
    ;; rest of the handled computation as `resume`. The global name, and
    ;; whether it is a control operation.
    (: declare-operation
       (impl (Fn Context Env String Syntax -> (Pair (Pair String Bool) Context) ! compile)))
    (define (declare-operation cx env effect operation)
      (match (::first (split-annotations operation (operation-form-arity operation)))
        ((Form (Cons (Ident "ctl" _ _) (Cons name (Cons type (Nil)))) _)
         (declare-operation-type cx env effect name type #t))
        ((Form (Cons name (Cons type (Nil))) _) (declare-operation-type cx env effect name type #f))
        (_ (compile-error (syntax-loc operation)
                          "expected (operation type) or (ctl operation type)"))))

    ;; An operation's type performs its effect. The row an ordinary
    ;; operation's type writes is its latent row: the effects its
    ;; implementations may perform where it is performed, which its callers
    ;; are charged too. A control operation's implementation runs where its
    ;; handler is instead, so its type is total. A handler implements an
    ;; operation once, at one type, so the type quantifies nothing: an
    ;; implementation checked at one instance would serve callers at
    ;; others, and a row variable would let it perform what no caller is
    ;; charged.
    (: declare-operation-type
       (impl
        (Fn Context Env String Syntax Syntax Bool -> (Pair (Pair String Bool) Context) ! compile)))
    (define (declare-operation-type cx env effect name type control?)
      (match (operational-scheme (resolve-scheme cx env type))
        ((Scheme vars constraints _ (TFun params result (TRow latent (None))))
         (unless (and (null? vars) (null? constraints))
           (compile-error (syntax-loc type)
                          "an operation's type cannot be polymorphic: a handler implements it once, at one type"))
         (when (and control? (not (null? latent)))
           (compile-error (syntax-loc type)
                          "a control operation has a total function type; its effect is implied"))
         (when (member? effect latent)
           (compile-error (syntax-loc type) "an operation's latent row cannot name its own effect"))
         (let ((global (global-binding cx env name)))
           (Pair (Pair global control?)
                 (add-value cx
                            global
                            (Operation effect
                                       (mono-scheme
                                        (TFun params
                                              result
                                              (TRow (Cons effect latent) (None)))))))))
        (_ (compile-error (syntax-loc type)
                          "an operation has a function type with a closed row; its effect is implied"))))

    ;; The clauses after an effect's operations: `default` clauses, and
    ;; `(around-main)`, which says the host handles the effect around a
    ;; program's body.
    (: default-clauses (impl (Fn (List Syntax) -> (List Syntax) ! compile)))
    (define (default-clauses clauses)
      (filter (lambda (clause)
                (match clause
                  ((Form (Cons (Ident "default" _ _) _) _) #t)
                  ((Form (Cons (Ident "around-main" _ _) (Nil)) _) #f)
                  (_ (compile-error (syntax-loc clause)
                                    "expected a default clause or (around-main)"))))
              clauses))

    (: around-main? (impl (Fn (List Syntax) -> Bool)))
    (define (around-main? clauses)
      (any? (lambda (clause)
              (match clause
                ((Form (Cons (Ident "around-main" _ _) (Nil)) _) #t)
                (_ #f)))
            clauses))

    ;; Every default the clauses give, at most one per operation.
    (: effect-defaults
       (impl (Fn (List DefaultDefinition) Loc -> (List (Pair String String)) ! compile)))
    (define (effect-defaults snail loc)
      (let ((defaults (map (lambda (d)
                             (Pair (::operation d) (::global d)))
                           snail)))
        (unless (= (length (delete-duplicates string=? (map ::first defaults)))
                   (length defaults))
          (compile-error loc "an operation has at most one default"))
        defaults))

    ;; One Snail-Core default: its operation, the global that holds its
    ;; definition, and the step that expands it.
    (struct DefaultDefinition
      ((operation String)
       (global String)
       (expand (dyn (Fn Context -> Context ! compile)))))

    ;; `(default ((operation implementation) ...))` defines each
    ;; implementation as a function of this library whose type is its
    ;; operation's, latent row included, as an instance method has its
    ;; class method's. Its entry is its signature, so the unused-effect
    ;; rule holds it to that row, which every performer is charged. A
    ;; control operation has none: no handler is in scope where a default
    ;; runs, to be handed the rest of the computation.
    (: snail-defaults
       (impl (Fn Context
                 Env
                 (List String)
                 (List String)
                 (List Syntax)
                 -> (Pair (List DefaultDefinition) Context) ! compile)))
    (define (snail-defaults cx env operations control clauses)
      (each cx
            (lambda (cx entry) (snail-default cx env operations control entry))
            (concatenate (map default-entries clauses))))

    (: default-entries (impl (Fn Syntax -> (List Syntax) ! compile)))
    (define (default-entries clause)
      (match clause
        ((Form (Cons _ (Cons (Form entries _) (Nil))) _) entries)
        (_ (compile-error (syntax-loc clause)
                          "expected (default ((operation implementation) ...))"))))

    (: snail-default
       (impl (Fn Context
                 Env
                 (List String)
                 (List String)
                 Syntax
                 -> (Pair DefaultDefinition Context)
                 ! compile)))
    (define (snail-default cx env operations control entry)
      (match entry
        ((Form (Cons name (Cons value (Nil))) loc)
         (let ((operation (named-operation operations name)))
           (when (member? operation control)
             (compile-error loc "a control operation has no default"))
           (expanding cx ((global (fresh-global (string-append (short-name operation) "-default")))
                          (then (add-value global
                                           (Defined (Some (default-scheme cx operation loc))
                                             (Some loc)
                                             #f))))
                      (Pair (DefaultDefinition operation
                              global
                              (lambda (cx) (expand-default cx env global operation value loc)))
                            cx))))
        (_ (compile-error (syntax-loc entry) "expected (operation implementation)"))))

    ;; The operation's type without its own effect, which a default cannot
    ;; perform: no handler of it is in scope where a default runs.
    (: default-scheme (impl (Fn Context String Loc -> Scheme ! compile)))
    (define (default-scheme cx operation loc)
      (match (program-value (::program cx) operation)
        ((Some (Operation effect scheme))
         (match scheme
           ((Scheme (Nil) (Nil) _ (TFun params result _))
            (Scheme (Nil)
                    (Nil)
                    (Nil)
                    (TFun params result (TRow (operation-latent effect scheme) (None)))))
           (_ (compile-error loc "an operation with a default must have a monomorphic type"))))
        (_ (panic "internal error: not an operation"))))

    ;; A default that is not a lambda names a function, which it calls with
    ;; the operation's arguments.
    (: expand-default (impl (Fn Context Env String String Syntax Loc -> Context ! compile)))
    (define (expand-default cx env global operation syntax loc)
      (expanding cx ((value (expand-expr env syntax)))
                 (match (::term value)
                   ((Lambda _ _ _) (add-item cx (Define global (top-level-value value))))
                   ((Var _ _ _)
                    (expanding cx ((value (eta-expand value (operation-arity cx operation) loc)))
                               (add-item cx (Define global value))))
                   (_ (compile-error loc "a default is a lambda or the name of a function")))))

    (: eta-expand (impl (Fn Context Expr I64 Loc -> (Pair Expr Context))))
    (define (eta-expand cx function arity loc)
      (expanding cx ((names (each (lambda (cx index) (fresh cx "argument")) (iota arity))))
                 (Pair (expr (Lambda names
                                     (expr (App function
                                                (map
                                                 (lambda (name) (expr (Var name (Nil) (Nil)) loc))
                                                 names))
                                           loc)
                                     #f)
                             loc)
                       cx)))

    (: operation-arity (impl (Fn Context String -> I64)))
    (define (operation-arity cx operation)
      (match (program-value (::program cx) operation)
        ((Some (Operation _ (Scheme _ _ _ (TFun params _ _)))) (length params))
        (_ (panic "internal error: not an operation"))))

    ;; ---- Primitives ----

    ;; (snail core primitive) is a library file like any other, whose body
    ;; holds only primitive declarations. `(primitive name type)` declares an
    ;; operation the backend implements, as `extern` declares a foreign
    ;; function: it binds `name` to the global `prim:name`, the name the
    ;; checker, mono and `emit-primitive` know it by, and the value there is
    ;; a Primitive of the type's scheme. Elsewhere the form is an error.
    (: primitive-library? (impl (Fn Context -> Bool)))
    (define (primitive-library? cx)
      (string=? (::prefix cx) "snail.core.primitive"))

    (: declare-primitive (impl (Fn Context Env Syntax -> Context ! compile)))
    (define (declare-primitive cx env form)
      (unless (core-form? cx env form "primitive")
        (compile-error (syntax-loc form)
                       "(snail core primitive) holds only primitive declarations"))
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (let* ((global (primitive-global (Ident-name (expect-ident name "a primitive name"))))
                (cx (bind-top cx env name (Global global))))
           (add-value cx global (Primitive (resolve-primitive-scheme cx env global type)))))
        (_ (compile-error (syntax-loc form) "expected (primitive name type)"))))

    ;; This intrinsic preserves a complete, arity-independent signature.
    ;; The receiver and signature are ordinary class parameters; deriving
    ;; FnOnce evidence determines the result's erased calling convention.
    (: resolve-primitive-scheme (impl (Fn Context Env String Syntax -> Scheme ! compile)))
    (define (resolve-primitive-scheme cx env global syntax)
      (if (and (string=? global "prim:once")
               (match syntax ((Ident "callable-once" _ _) #t) (_ #f)))
          (let ((receiver (TRigid "F")) (signature (TRigid "Signature")))
            (Scheme (list "F" "Signature")
                    (list (Constraint (callable-class "FnOnce") (list receiver signature)))
                    (Nil) (TFun (list receiver) (TCon "FnOnce" (list signature)) empty-row)))
          (operational-scheme (resolve-scheme cx env syntax))))

    ;; ---- Types ----

    ;; Requirements bind hidden output variables and a projection scope.
    ;; No projection survives expansion: method and projection share the
    ;; same ordinary type argument of the same evidence requirement.
    (struct Requirements
      ((constraints (List Constraint))
       (copy (List String))
       (vars (List String))
       (env Env)))

    (: resolve-scheme (impl (Fn Context Env Syntax -> Scheme ! compile)))
    (define (resolve-scheme cx env syntax)
      (callable-scheme (resolve-raw-scheme cx env syntax) (syntax-loc syntax)))

    ;; A primitive, method or operation describes executable code, rather
    ;; than introducing a source closure identity of its own.
    (: operational-scheme (impl (Fn Scheme -> Scheme)))
    (define (operational-scheme scheme)
      (Scheme (::vars scheme) (::constraints scheme) (::copy scheme)
              (fn-arrow (::type scheme))))

    (: resolve-raw-scheme (impl (Fn Context Env Syntax -> Scheme ! compile)))
    (define (resolve-raw-scheme cx env syntax)
      (match syntax
        ((Form (Cons (Ident "All" _ _) (Cons (Form params _) rest)) loc)
         (let* ((params (map (lambda (param) (expect-ident param "a type variable")) params))
                (vars (map Ident-name params)) (scope (type-scope env params))
                (parts (split-requires rest))
                (requirements (resolve-requirements cx scope vars (::first parts))))
           (match (::second parts)
             ((Cons type (Nil))
              (Scheme (::vars requirements) (::constraints requirements)
                      (::copy requirements)
                      (resolve-type cx (::env requirements) type)))
             (_ (compile-error loc
                               "expected (All (variable ...) [(requires constraint ...)] type)")))))
        (_ (mono-scheme (resolve-type cx env syntax)))))

    ;; Argument-position impl introduces a caller-chosen type and evidence.
    ;; The outer impl belongs to this definition; checking gives it the
    ;; definition's concrete identity. Results and storage use explicit dyn.
    (: callable-scheme (impl (Fn Scheme Loc -> Scheme ! compile)))
    (define (callable-scheme scheme loc)
      (let ((type (::type scheme)))
        (match (callable-arrow type)
          ((Some arrow)
           (match (callable-signature-parameters arrow scheme loc)
             ((Pair arrow found)
              (Scheme (::vars found) (::constraints found) (::copy found)
                      (match type
                        ((TFun _ _ _) arrow)
                        ((TCon name _) (TCon name (list arrow)))
                        (_ type))))))
          ((None) scheme))))

    (: callable-signature-parameters (impl (Fn Type Scheme Loc -> (Pair Type Scheme) ! compile)))
    (define (callable-signature-parameters arrow found loc)
      (match arrow
        ((TFun params result row)
         (when (impl-callable? result)
           (compile-error loc
                          "a returned callable needs explicit dyn storage; impl is an argument or definition contract"))
         (let ((parts (fold-left (lambda (parts param)
                                   (match (callable-parameter param (::second parts))
                                     ((Pair param found)
                                      (Pair (Cons param (::first parts)) found))))
                                 (Pair (Nil) found) params)))
           (for-each (lambda (part) (check-stored-type part loc))
                     (Cons result (::first parts)))
           (Pair (TFun (reverse (::first parts)) result row) (::second parts))))
        (_ (panic "internal error: a callable contract has a function signature"))))

    (: callable-parameter (impl (Fn Type Scheme -> (Pair Type Scheme))))
    (define (callable-parameter type found)
      (if (impl-callable? type)
          (let* ((name (string-append "$callable-argument." (i64->string (length (::vars found)))))
                 (receiver (TRigid name)))
            (match (Pair (callable-kind type) (callable-arrow type))
              ((Pair (Some kind) (Some arrow))
               (Pair receiver (Scheme (append (::vars found) (list name))
                                      (append (::constraints found)
                                              (list (Constraint (callable-class kind)
                                                                (list receiver arrow))))
                                      (::copy found) (::type found))))
              (_ (panic "internal error: an impl parameter has a callable signature"))))
          (Pair type found)))

    (: resolve-requirements
       (impl (Fn Context Env (List String) (List Syntax) -> Requirements ! compile)))
    (define (resolve-requirements cx env vars requirements)
      (fold-left (lambda (found requirement) (resolve-requirement cx found requirement))
                 (Requirements (Nil) (Nil) vars env) requirements))

    (: resolve-requirement (impl (Fn Context Requirements Syntax -> Requirements ! compile)))
    (define (resolve-requirement cx found syntax)
      (match syntax
        ((Form (Cons (Ident "Copy" _ _) args) loc)
         (Requirements-copy-set found
                                (append (::copy found)
                                        (list (copy-variable (::vars found) args loc)))))
        (_ (let* ((constraint (resolve-constraint cx (::env found) syntax
                                                  (length (::constraints found))))
                  (hidden (filter (lambda (name) (and (>= (string-length name) 12)
                                                      (string=? (substring name 0 12)
                                                                "$associated.")))
                                  (concatenate (map type-names (::types constraint))))))
             (Requirements (append (::constraints found) (list constraint))
                           (::copy found)
                           (delete-duplicates string=? (append (::vars found) hidden))
                           (EvidenceScope (list constraint) (::env found)))))))

    (: copy-variable (impl (Fn (List String) (List Syntax) Loc -> String ! compile)))
    (define (copy-variable vars args loc)
      (match args
        ((Cons (Ident name _ _) (Nil))
         (if (member? name vars)
             name
             (compile-error loc
                            (string-append "Copy names a quantified type variable, not " name))))
        (_ (compile-error loc "expected (Copy variable)"))))

    (: resolve-constraint (impl (Fn Context Env Syntax I64 -> Constraint ! compile)))
    (define (resolve-constraint cx env syntax index)
      (match syntax
        ((Form (Cons class types) loc)
         (match (resolve cx env (expect-ident class "a typeclass"))
           ((Some (ClassName id))
            (if (callable-class? id)
                (resolve-callable-constraint cx env id types loc)
                (checked-constraint cx env id types index loc)))
           (_
            (match (field-class-syntax cx class)
              ((Some (Pair id cx)) (checked-constraint cx env id types index loc))
              ((None) (compile-error loc "expected a typeclass constraint"))))))
        (_ (compile-error (syntax-loc syntax) "expected (Class type ...)"))))

    (: resolve-callable-constraint
       (impl (Fn Context Env String (List Syntax) Loc -> Constraint ! compile)))
    (define (resolve-callable-constraint cx env class items loc)
      (match items
        ((Cons receiver signature)
         (Constraint class
                     (list (resolve-type cx env receiver)
                           (resolve-callable-arrow cx env signature (Nil) loc))))
        (_ (compile-error loc
                          "a callable requirement names its receiver type before its arguments"))))

    ;; The constraint of a class at resolved types, checked against the
    ;; class's parameters; a field class declared on first use checks too.
    (: checked-constraint
       (impl (Fn Context Env String (List Syntax) I64 Loc -> Constraint ! compile)))
    (define (checked-constraint cx env id arguments index loc)
      (let* ((class (program-class (::program cx) id))
             (types (map (lambda (type) (resolve-type cx env type))
                         (filter (lambda (form) (not (associated-form? form))) arguments)))
             (equalities (map associated-equation (filter associated-form? arguments)))
             (outputs (map (lambda (name)
                             (match (assoc-ref equalities name)
                               ((Some type) (resolve-type cx env type))
                               ((None)
                                (TRigid
                                 (string-append "$associated." (i64->string index) "." name)))))
                           (::outputs class)))
             (constraint (Constraint id (append types outputs))))
        (unless (and (= (length equalities)
                        (length (delete-duplicates string=? (map ::first equalities))))
                     (every? (lambda (entry) (member? (::first entry) (::outputs class)))
                             equalities))
          (compile-error loc "constraint has an unknown or repeated associated type equality"))
        (check-constraint (::program cx) constraint loc)
        constraint))

    ;; A constraint gives each of its class's parameters, and a row or a
    ;; row variable to each its methods perform. While signatures are
    ;; resolved, a class the same library declares is not in the program
    ;; yet, so a definition checks its signature's again
    ;; (`check-signature`).
    (: check-constraint (impl (Fn Program Constraint Loc -> Unit ! compile)))
    (define (check-constraint program constraint loc)
      (match (table-ref (::classes program) (::class constraint))
        ((Some class)
         (unless (= (length (::types constraint)) (length (::params class)))
           (compile-error loc
                          (string-append
                           "a constraint gives each of the class's parameters, as in ("
                           (string-join (Cons (short-name (::name class))
                                              (::params class))
                                        " ")
                           ")")))
         (for-each (lambda (row)
                     (match (::second row)
                       ((TRow _ _) (unit))
                       ((TRigid _) (unit))
                       (_ (compile-error loc
                                         (string-append
                                          "a constraint gives the class's row parameter "
                                          (::first row)
                                          " a row")))))
                   (zip (::rows class) (row-arguments class (::types constraint)))))
        ((None) (unit))))

    (: resolve-type (impl (Fn Context Env Syntax -> Type ! compile)))
    (define (resolve-type cx env syntax)
      (match syntax
        ((Ident _ _ loc) (resolve-type-name cx env syntax (Nil) loc))
        ((Form (Cons (Ident "impl" _ _) (Cons contract (Nil))) loc)
         (resolve-callable-contract cx env contract #f loc))
        ((Form (Cons (Ident "dyn" _ _) (Cons contract (Nil))) loc)
         (resolve-callable-contract cx env contract #t loc))
        ((Form (Cons (Ident "fn" _ _) items) loc)
         (TCon "fn" (list (resolve-callable-arrow cx env items (Nil) loc))))
        ((Form (Cons (Ident "->" _ _) _) loc)
         (compile-error loc
                        "use (impl (Fn arguments -> result ! effects)) for a callable contract, or dyn for storage"))
        ((Form (Cons (Ident "!" _ _) labels) loc) (resolve-row cx env labels loc))
        ((Form (Cons (Ident kind _ _) _) loc)
         (if (member? kind (list "Fn" "FnMut" "FnOnce"))
             (compile-error loc
                            "a callable type requires impl or dyn around its Fn, FnMut or FnOnce contract")
             (resolve-type-application cx env syntax loc)))
        ((Form (Cons head args) loc)
         (resolve-type-name cx env (expect-ident head "a type constructor") args loc))
        (_ (compile-error (syntax-loc syntax) "expected a type"))))

    (: resolve-type-application (impl (Fn Context Env Syntax Loc -> Type ! compile)))
    (define (resolve-type-application cx env syntax loc)
      (match syntax
        ((Form (Cons head args) _)
         (resolve-type-name cx env (expect-ident head "a type constructor") args loc))
        (_ (compile-error loc "expected a type application"))))

    (: resolve-callable-contract (impl (Fn Context Env Syntax Bool Loc -> Type ! compile)))
    (define (resolve-callable-contract cx env contract erased? loc)
      (match contract
        ((Form (Cons (Ident kind _ _) items) _)
         (unless (member? kind (list "Fn" "FnMut" "FnOnce"))
           (compile-error loc "impl and dyn require an Fn, FnMut or FnOnce contract"))
         (let ((arrow (resolve-callable-arrow cx env items (Nil) loc)))
           (if erased?
               (if (string=? kind "Fn") arrow (TCon kind (list arrow)))
               (TCon (string-append "$impl." kind) (list arrow)))))
        (_ (compile-error loc "expected (impl (Fn argument ... -> result ! effects)) or dyn"))))

    (: resolve-type-name (impl (Fn Context Env Syntax (List Syntax) Loc -> Type ! compile)))
    (define (resolve-type-name cx env ident args loc)
      (match (resolve cx env ident)
        ((Some (TypeName name arity _))
         (unless (= arity (length args))
           (compile-error loc
                          (string-append "wrong number of type arguments: " (Ident-name ident))))
         (TCon name (map (lambda (arg) (resolve-type cx env arg)) args)))
        ((Some (Associated class member))
         (resolve-projection env class member
                             (map (lambda (arg) (resolve-type cx env arg)) args)
                             (program-class (::program cx) class) loc))
        ((Some (TypeVar type))
         (if (null? args) type (compile-error loc "a type variable takes no arguments")))
        ((Some (Alias name params body alias-env))
         (unless (= (length params) (length args))
           (compile-error loc
                          (string-append "wrong number of alias arguments: " (Ident-name ident))))
         (when (member? name (::aliases cx))
           (compile-error loc (string-append "type alias refers to itself: " (Ident-name ident))))
         (let ((scope (fold-left (lambda (scope pair)
                                   (extend scope
                                           (::first pair)
                                           (TypeVar (resolve-type cx env (::second pair)))))
                                 alias-env (zip params args))))
           (resolve-type (Context-aliases-set cx (Cons name (::aliases cx))) scope body)))
        (_ (compile-error loc (string-append "not a type: " (Ident-name ident))))))

    (: resolve-projection (impl (Fn Env String String (List Type) Class Loc -> Type ! compile)))
    (define (resolve-projection env id member args class loc)
      (unless (= (length args) (- (length (::params class)) (length (::outputs class))))
        (compile-error loc "associated projection gives each declared class parameter"))
      (match (filter (lambda (constraint)
                       (and (string=? id (::class constraint))
                            (types=? (type-arguments class args)
                                     (type-arguments class (::types constraint)))))
                     (enclosing-requirements env))
        ((Cons constraint (Nil))
         (match (assoc-ref (zip (::params class) (::types constraint)) member)
           ((Some type) type)
           ((None) (panic "internal error: associated member"))))
        ((Nil) (compile-error loc "associated projection needs a matching requires constraint"))
        (_ (compile-error loc "associated projection matches multiple requirements"))))

    (: enclosing-requirements (impl (Fn Env -> (List Constraint))))
    (define (enclosing-requirements env)
      (match env
        ((EvidenceScope constraints rest) (append constraints (enclosing-requirements rest)))
        ((InstanceScope _ rest) (enclosing-requirements rest))
        ((InstanceOwner _ rest) (enclosing-requirements rest))
        ((Frame _ _ rest) (enclosing-requirements rest))
        ((Top _ _) (Nil))))

    ;; Callable contracts separate their parameters from one result with
    ;; `->`; only `!` may follow that result. Representation and receiver
    ;; mode are decisions of the enclosing former, not of this parser.
    (: resolve-callable-arrow
       (impl (Fn Context Env (List Syntax) (List Type) Loc -> Type ! compile)))
    (define (resolve-callable-arrow cx env items params loc)
      (match items
        ((Cons (Ident "->" _ _) rest)
         (resolve-callable-result cx env (reverse params) rest loc))
        ((Cons (Ident "!" _ _) _)
         (compile-error loc
                        "a callable signature puts -> before its result and ! before its effects"))
        ((Cons param rest)
         (resolve-callable-arrow cx env rest (Cons (resolve-type cx env param) params) loc))
        ((Nil) (compile-error loc "a callable signature needs -> followed by one result type"))))

    (: resolve-callable-result
       (impl (Fn Context Env (List Type) (List Syntax) Loc -> Type ! compile)))
    (define (resolve-callable-result cx env params items loc)
      (match items
        ((Cons (Ident "->" _ _) _) (compile-error loc "a callable signature has only one ->"))
        ((Cons (Ident "!" _ _) _)
         (compile-error loc "a callable signature needs a result before !"))
        ((Cons result (Nil)) (TFun params (resolve-type cx env result) empty-row))
        ((Cons result (Cons (Ident "!" _ _) labels))
         (TFun params (resolve-type cx env result) (resolve-row cx env labels loc)))
        (_ (compile-error loc
                          "expected one result type after ->, optionally followed by ! effects"))))

    (: resolve-row (impl (Fn Context Env (List Syntax) Loc -> Type ! compile)))
    (define (resolve-row cx env items loc)
      (let loop ((items items) (labels (Nil)))
        (match items
          ((Nil) (TRow labels (None)))
          ((Cons item rest)
           (match (resolve cx env (expect-ident item "an effect label"))
             ((Some (EffectName name)) (loop rest (label-union labels (list name))))
             ((Some (TypeVar type))
              (if (null? rest)
                  (TRow labels (Some type))
                  (compile-error loc "a row variable must come last")))
             (_ (compile-error (syntax-loc item)
                               (string-append "not an effect: " (Ident-name item)))))))))

    ;; ---- Expressions ----

    ;; Only an expanded use requests files. Unused macro templates cannot
    ;; trigger a build. The public macro supplies marked constructor names,
    ;; so ordinary expansion/typing constructs the value hygienically.
    (: expand-artifact-files
       (impl (Fn Context Env (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-artifact-files cx env items loc)
      (match items
        ((Cons _ (Cons (Atom (DString name) _) (Cons file (Cons cons (Cons nil (Nil))))))
         (expanding cx ((files (resolve-artifact-files name loc)))
                    (expand-expr cx env (fold-right (lambda (entry rest)
                                                      (Form (list cons
                                                                  (Form (list file
                                                                              (Atom
                                                                               (DString
                                                                                (::first entry))
                                                                               loc)
                                                                              (Atom
                                                                               (DBytes (::second
                                                                                        entry))
                                                                               loc))
                                                                        loc)
                                                                  rest)
                                                            loc))
                                                    (Form (list nil) loc) files))))
        (_ (compile-error loc "artifact-bundle expects a literal target name"))))

    ;; Each library owns its uses, including when expansion loads another
    ;; library during deriving. Record an actual invocation once; unused
    ;; macro templates never enter this accumulator.
    (: resolve-artifact-files
       (impl (Fn Context String Loc -> (Pair ArtifactFiles Context) ! compile)))
    (define (resolve-artifact-files cx name loc)
      (match (find (lambda (use) (string=? name (::name use))) (::artifact-uses cx))
        ((Some use) (Pair (::files use) cx))
        ((None)
         (expanding cx ((files (artifact-files name loc)))
                    (Pair files
                          (Context-artifact-uses-set cx
                                                     (Cons (ArtifactUse name loc files)
                                                           (::artifact-uses cx))))))))

    ;; Expands macro uses at the head of a form until the head is not a macro.
    (: expand-head (impl (Fn Context Env Syntax -> (Pair Syntax Context) ! compile)))
    (define (expand-head cx env syntax)
      (match (head-binding cx env syntax)
        ((Some (Macro _ literals rules scope))
         (expanding cx ((expanded (apply-macro env syntax literals rules scope)))
                    (expand-head cx env expanded)))
        (_ (Pair syntax cx))))

    (: expr (impl (Fn Term Loc -> Expr)))
    (define (expr term loc)
      (Expr term unchecked loc))

    (: expand-expr (impl (Fn Context Env Syntax -> (Pair Expr Context) ! compile)))
    (define (expand-expr cx env syntax)
      (expanding cx ((syntax (expand-head env syntax)))
                 (match syntax
                   ((Atom value loc) (Pair (expr (Lit value) loc) cx))
                   ((Ident name _ loc)
                    (if (path-name? name)
                        (expand-path cx name loc)
                        (Pair (expand-reference cx env syntax loc) cx)))
                   ((Form (Nil) loc) (compile-error loc "empty application"))
                   ((Form (Cons (Ident name _ _) (Cons arg (Nil))) loc)
                    (if (path-name? name)
                        (expand-path-call cx env name arg loc)
                        (expand-application cx env syntax loc)))
                   ((Form (Cons _ _) loc) (expand-application cx env syntax loc)))))

    (: expand-application (impl (Fn Context Env Syntax Loc -> (Pair Expr Context) ! compile)))
    (define (expand-application cx env syntax loc)
      (match syntax
        ((Form (Cons head args) _)
         (match (head-binding cx env syntax)
           ((Some (Core keyword)) (expand-core cx env keyword (Form-items syntax) loc))
           (_ (expanding cx ((callee (expand-expr env head))
                             (arguments (expand-each env args)))
                         (Pair (expr (App callee arguments) loc) cx)))))
        (_ (panic "internal error: not an application"))))

    ;; A path applied to one argument is the chain of reads itself, so
    ;; `(::last::x (ref-get c))` is a place, not a call of a function.
    (: expand-path-call (impl (Fn Context Env String Syntax Loc -> (Pair Expr Context) ! compile)))
    (define (expand-path-call cx env name arg loc)
      (let ((labels (path-labels name loc)))
        (expanding cx ((then (declare-field-classes labels))
                       (value (expand-expr env arg)))
                   (Pair (apply-path labels value loc) cx))))

    (: expand-each (impl (Fn Context Env (List Syntax) -> (Pair (List Expr) Context) ! compile)))
    (define (expand-each cx env forms)
      (each cx (lambda (cx form) (expand-expr cx env form)) forms))

    ;; `::a::b` reads field `a`, then field `b` of what it holds: each label
    ;; names the method of its field class (core.sld, "Field classes"),
    ;; declared on first use, and a chain is a function applying them in
    ;; order. Names beginning with `::` are reserved for paths.
    (: path-name? (impl (Fn String -> Bool)))
    (define (path-name? name)
      (and (> (string-length name) 2) (string=? (substring name 0 2) "::")))

    (: expand-path (impl (Fn Context String Loc -> (Pair Expr Context) ! compile)))
    (define (expand-path cx name loc)
      (let ((labels (path-labels name loc)))
        (expanding cx ((then (declare-field-classes labels)))
                   (match labels
                     ((Cons label (Nil))
                      (Pair (expr (Var (field-class-name label) (Nil) (Nil)) loc) cx))
                     (_
                      (expanding cx ((local (fresh "path")))
                                 (Pair (expr (Lambda (list local)
                                                     (apply-path labels
                                                                 (expr (Var local (Nil) (Nil)) loc)
                                                                 loc)
                                                     #t)
                                             loc)
                                       cx)))))))

    (: declare-field-classes (impl (Fn Context (List String) -> Context)))
    (define (declare-field-classes cx labels)
      (Context-program-set cx (fold-left program-with-field-class (::program cx) labels)))

    (: apply-path (impl (Fn (List String) Expr Loc -> Expr)))
    (define (apply-path labels value loc)
      (fold-left (lambda (value label)
                   (expr (App (expr (Var (field-class-name label) (Nil) (Nil)) loc) (list value))
                         loc))
                 value
                 labels))

    ;; The labels of `::a::b`, each non-empty.
    (: path-labels (impl (Fn String Loc -> (List String) ! compile)))
    (define (path-labels name loc)
      (let ((chars (string->vector name)) (end (string-length name)))
        (let loop ((start 2) (index 2) (labels (Nil)))
          (cond ((= index end)
                 (if (= start end)
                     (compile-error loc (string-append "empty field label in " name))
                     (reverse (Cons (substring name start end) labels))))
                ((and (char=? (vector-ref chars index) #\:)
                      (< (+ index 1) end)
                      (char=? (vector-ref chars (+ index 1)) #\:))
                 (if (= start index)
                     (compile-error loc (string-append "empty field label in " name))
                     (loop (+ index 2) (+ index 2) (Cons (substring name start index) labels))))
                (else (loop start (+ index 1) labels))))))

    ;; A `::label` in class position names the label's field class.
    (: field-class-syntax (impl (Fn Context Syntax -> (Option (Pair String Context)) ! compile)))
    (define (field-class-syntax cx syntax)
      (match syntax
        ((Ident name _ loc)
         (if (path-name? name)
             (match (path-labels name loc)
               ((Cons label (Nil))
                (Some (Pair (field-class-name label) (declare-field-classes cx (list label)))))
               (_ (compile-error loc (string-append "a field class names one label, not " name))))
             (None)))
        (_ (None))))

    (: expand-reference (impl (Fn Context Env Syntax Loc -> Expr ! compile)))
    (define (expand-reference cx env ident loc)
      (match (resolve cx env ident)
        ((Some (Local name)) (expr (Var name (Nil) (Nil)) loc))
        ((Some (Global name))
         (match (program-value (::program cx) name)
           ((Some (Replacer case _ _))
            (check-own-library cx (::type case) loc "replace its fields"))
           (_ (unit)))
         (expr (Var name (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (Some constructor))) (expr (Var constructor (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (None)))
         (compile-error loc (string-append "a type is not a value: " (Ident-name ident))))
        ((Some (Core "field-read")) (compile-error loc field-read-message))
        ((None) (compile-error loc (string-append "unbound identifier " (Ident-name ident))))
        (_ (compile-error loc (string-append "syntax used as a value: " (Ident-name ident))))))

    (: expand-core
       (impl (Fn Context Env String (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-core cx env keyword items loc)
      (case keyword
        (("field-read") (compile-error loc field-read-message))
        (("lambda")
         (match items
           ((Cons _ (Cons params body))
            (expand-lambda cx env (form-items params "a parameter list") body #t loc))
           (_ (compile-error loc "expected (lambda (parameter ...) body ...)"))))
        ;; A function that may not capture: it reads only its parameters,
        ;; its own locals and globals, so it has no environment.
        (("fn")
         (match items
           ((Cons _ (Cons params body))
            (expand-lambda cx env (form-items params "a parameter list") body #f loc))
           (_ (compile-error loc "expected (fn (parameter ...) body ...)"))))
        (("if")
         ;; `then` is `expanding`'s own keyword, so the branches are named
         ;; otherwise.
         (match items
           ((Cons _ (Cons test (Cons consequent (Cons alternative (Nil)))))
            (expanding cx ((test (expand-expr env test))
                           (consequent (expand-expr env consequent))
                           (alternative (expand-expr env alternative)))
                       (Pair (expr (If test consequent alternative) loc) cx)))
           ((Cons _ (Cons test (Cons consequent (Nil))))
            (expanding cx ((test (expand-expr env test)) (consequent (expand-expr env consequent)))
                       (Pair (expr (If test consequent (expr (Lit (DUnit)) loc)) loc) cx)))
           (_ (compile-error loc "expected (if test then [else])"))))
        (("with-instances")
         (match (list-tail items 1)
           ((Cons sets body)
            (let ((scope (InstanceScope (form-items sets "a list of instance sets") env)))
              (expanding cx ((value (expand-body scope body loc)))
                         (Pair (expr (ScopedInstances (active-instance-sets cx scope) value) loc)
                               cx))))
           (_ (compile-error loc "expected (with-instances (set ...) body ...)"))))
        (("begin") (expand-body cx env (list-tail items 1) loc))
        (("let") (expand-let cx env items loc))
        (("match") (expand-match cx env items loc))
        (("artifact-files") (expand-artifact-files cx env items loc))
        (("link-handle") (expand-link-file cx items loc))
        (("ann")
         (match items
           ((Cons _ (Cons value (Cons type (Nil))))
            (expanding cx ((value (expand-expr env value)))
                       (Pair (expr (Ann value (resolve-type cx env type)) loc) cx)))
           (_ (compile-error loc "expected (ann expression type)"))))
        (("handle") (expand-handle cx env items loc))
        (("type-convert")
         (match items
           ((Cons _ (Cons value (Cons type (Nil))))
            (expanding cx ((value (expand-expr env value)))
                       (Pair (expr (Convert value (resolve-type cx env type)) loc) cx)))
           (_ (compile-error loc "expected (type-convert expression type)"))))
        (("try-convert")
         (match items
           ((Cons _ (Cons value (Cons type (Nil))))
            (expanding cx ((value (expand-expr env value)))
                       (Pair (expr (TryConvert value (resolve-type cx env type)) loc) cx)))
           (_ (compile-error loc "expected (try-convert expression type)"))))
        (("type-test")
         (match items
           ((Cons _ (Cons value (Cons type (Nil))))
            (expanding cx ((value (expand-expr env value)))
                       (Pair (expr (TypeTest value (resolve-type cx env type)) loc) cx)))
           (_ (compile-error loc "expected (type-test expression type)"))))
        (("case-id")
         (match items
           ((Cons _ (Cons constructor (Nil)))
            (Pair (expr (Ann (expr (Lit (DInt (constructor-case-id cx env constructor))) loc)
                             (TCon "I32" (Nil)))
                        loc)
                  cx))
           (_ (compile-error loc "expected (case-id Constructor)"))))
        (("quote")
         (match items
           ((Cons _ (Cons (Atom value _) (Nil))) (Pair (expr (Lit value) loc) cx))
           (_ (compile-error loc "only literals can be quoted"))))
        (else
         (compile-error loc (string-append "this form is only valid as a definition: " keyword)))))

    (: expand-lambda
       (impl
        (Fn Context Env (List Syntax) (List Syntax) Bool Loc -> (Pair Expr Context) ! compile)))
    (define (expand-lambda cx env params body captures? loc)
      (expanding cx ((locals (bind-locals env params))
                     (body (expand-body (::first locals) body loc)))
                 (Pair (expr (Lambda (::second locals) body captures?) loc) cx)))

    ;; Binds each identifier to a fresh local, in order; returns the longer
    ;; environment and the unique names.
    (: bind-locals
       (impl (Fn Context Env (List Syntax) -> (Pair (Pair Env (List String)) Context) ! compile)))
    (define (bind-locals cx env idents)
      (expanding cx ((names (each (lambda (cx ident)
                                    (fresh cx (Ident-name (expect-ident ident "a variable name"))))
                                  idents)))
                 (Pair (Pair (fold-left (lambda (env bound)
                                          (extend env
                                                  (::first bound)
                                                  (Local (::second bound))))
                                        env
                                        (zip idents names))
                             names)
                       cx)))

    (: expand-body (impl (Fn Context Env (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-body cx env forms loc)
      (when (null? forms) (compile-error loc "empty body"))
      (expand-body-forms cx env forms (None) loc))

    ;; A local body is sequential: each definition is visible to the forms
    ;; after it, and a function definition is also visible to itself. A
    ;; signature annotates the definition that follows it.
    (: expand-body-forms
       (impl (Fn Context
                 Env
                 (List Syntax)
                 (Option (Pair String Type))
                 Loc
                 ->
                 (Pair Expr Context)
                 ! compile)))
    (define (expand-body-forms cx scope forms signature loc)
      (match forms
        ((Nil) (compile-error loc "a body must end with an expression"))
        ((Cons form rest)
         (expanding cx ((form (expand-head scope form)))
                    (match (head-binding cx scope form)
                      ((Some (Core "begin"))
                       (expand-body-forms cx scope (append (form-tail form) rest) signature loc))
                      ((Some (Core "define-syntax"))
                       (expanding cx ((inner (define-local-macro scope form)))
                                  (expand-body-forms cx inner rest signature loc)))
                      ((Some (Core ":"))
                       (expand-body-forms cx scope rest (Some (local-signature cx scope form)) loc))
                      ((Some (Core "define"))
                       (expand-local-definition cx scope form rest signature loc))
                      (_ (expanding cx ((value (expand-expr scope form)))
                                    (if (null? rest)
                                        (Pair value cx)
                                        (expanding cx ((more
                                                        (expand-body-forms scope rest (None) loc)))
                                                   (Pair (expr (Seq value more) (::loc value))
                                                         cx))))))))))

    (: local-signature (impl (Fn Context Env Syntax -> (Pair String Type) ! compile)))
    (define (local-signature cx scope form)
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (Pair (Ident-name (expect-ident name "a name"))
               (::type (resolve-scheme cx scope type))))
        (_ (compile-error (syntax-loc form) "expected (: name type)"))))

    (: expand-local-definition
       (impl (Fn Context
                 Env
                 Syntax
                 (List Syntax)
                 (Option (Pair String Type))
                 Loc
                 -> (Pair Expr Context)
                 ! compile)))
    (define (expand-local-definition cx scope form rest signature loc)
      (let ((ident (definition-name form)))
        (expanding cx ((name (fresh (Ident-name ident))))
                   (let ((inner (extend scope ident (Local name)))
                         (function? (match form
                                      ((Form (Cons _ (Cons (Form _ _) _)) _) #t)
                                      ((Form (Cons _ (Cons _ (Cons value (Nil)))) _)
                                       (or (core-form? cx scope value "lambda")
                                           (core-form? cx scope value "fn")))
                                      (_ #f))))
                     (expanding cx ((value (definition-value (if function? inner scope) form))
                                    (body (expand-body-forms inner rest (None) loc)))
                                (Pair (expr (Let name
                                                 (signed-value value signature (Ident-name ident))
                                                 body)
                                            (syntax-loc form))
                                      cx))))))

    ;; A local definition's value, annotated with the signature before it
    ;; when the signature names it.
    (: signed-value (impl (Fn Expr (Option (Pair String Type)) String -> Expr)))
    (define (signed-value value signature name)
      (match signature
        ((Some (Pair signed type))
         (if (string=? signed name) (expr (Ann value type) (::loc value)) value))
        ((None) value)))

    ;; `(let ((name value) ...) body ...)` or the named-let loop form.
    (: expand-let (impl (Fn Context Env (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-let cx env items loc)
      (match items
        ((Cons _ (Cons head (Cons more body)))
         (match head
           ((Ident _ _ _)
            (expand-named-let cx env head (form-items more "a list of bindings") body loc))
           ((Form bindings _) (expand-plain-let cx env bindings (Cons more body) loc))
           (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))
        (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))

    (: expand-named-let
       (impl
        (Fn Context Env Syntax (List Syntax) (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-named-let cx env ident bindings body loc)
      (expanding cx ((name (fresh (Ident-name ident)))
                     (loop (expand-lambda (extend env ident (Local name))
                                          (map binding-name bindings)
                                          body
                                          #t
                                          loc))
                     (initial
                      (each (lambda (cx binding) (expand-expr cx env (binding-value binding)))
                            bindings)))
                 (Pair
                  (expr (Let name loop (expr (App (expr (Var name (Nil) (Nil)) loc) initial) loc))
                        loc)
                  cx)))

    (: expand-plain-let
       (impl (Fn Context Env (List Syntax) (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-plain-let cx env bindings body loc)
      (expanding cx ((values
                      (each (lambda (cx binding) (expand-expr cx env (binding-value binding)))
                            bindings))
                     (locals (bind-locals env (map binding-name bindings)))
                     (body (expand-body (::first locals) body loc)))
                 (Pair (fold-right (lambda (pair body)
                                     (expr (Let (::first pair) (::second pair) body) loc))
                                   body
                                   (zip (::second locals) values))
                       cx)))

    (: binding-name (impl (Fn Syntax -> Syntax ! compile)))
    (define (binding-name binding)
      (match (form-items binding "a (name value) binding")
        ((Cons name _) (expect-ident name "a binding name"))
        ((Nil) (compile-error (syntax-loc binding) "expected (name value)"))))

    (: binding-value (impl (Fn Syntax -> Syntax ! compile)))
    (define (binding-value binding)
      (match binding
        ((Form (Cons _ (Cons value (Nil))) _) value)
        (_ (compile-error (syntax-loc binding) "expected (name value)"))))

    (: expand-handle (impl (Fn Context Env (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-handle cx env items loc)
      (match items
        ((Cons _ (Cons effect (Cons (Form implementations _) body)))
         (let ((id (match (resolve cx env (expect-ident effect "an effect name"))
                     ((Some (EffectName id)) id)
                     (_ (compile-error (syntax-loc effect)
                                       (string-append "not an effect: " (Ident-name effect)))))))
           (when (member? id (list "mut" "host"))
             (compile-error (syntax-loc effect)
                            (string-append "the builtin effect "
                                           id
                                           " has no operations to handle")))
           (expanding cx ((implementations (each (lambda (cx implementation)
                                                   (expand-implementation cx env id implementation))
                                                 implementations))
                          (body (expand-body env body loc)))
                      (Pair (expr (Handle id implementations body) loc) cx))))
        (_
         (compile-error loc "expected (handle Effect ((operation implementation) ...) body ...)"))))

    (: expand-implementation
       (impl (Fn Context Env String Syntax -> (Pair (Pair String Expr) Context) ! compile)))
    (define (expand-implementation cx env effect implementation)
      (match implementation
        ((Form (Cons name (Cons value (Nil))) _)
         (let ((operation (operation-name cx effect name)))
           (expanding cx ((value (expand-expr env value)))
                      (Pair (Pair operation value) cx))))
        (_ (compile-error (syntax-loc implementation) "expected (operation implementation)"))))

    ;; A handler names operations by their names within the effect, so they
    ;; need not be imported.
    (: operation-name (impl (Fn Context String Syntax -> String ! compile)))
    (define (operation-name cx effect ident)
      (named-operation (::operations (program-effect (::program cx) effect)) ident))

    (: named-operation (impl (Fn (List String) Syntax -> String ! compile)))
    (define (named-operation operations ident)
      (let ((name (Ident-name (expect-ident ident "an operation name"))))
        (match (find (lambda (operation) (string=? (short-name operation) name)) operations)
          ((Some operation) operation)
          ((None)
           (compile-error (syntax-loc ident)
                          (string-append "not an operation of this effect: " name))))))

    (: constructor-case-id (impl (Fn Context Env Syntax -> I64 ! compile)))
    (define (constructor-case-id cx env constructor)
      (match (program-value (::program cx) (pattern-constructor cx env constructor))
        ((Some (Constructor case _)) (case-type-id (::program cx) case))
        (_ (compile-error (syntax-loc constructor) "not a constructor"))))

    ;; ---- Deriving ----

    ;; Derived instances are ordinary instance declarations, built as syntax.
    ;; Identifiers they introduce are marked to resolve in an environment of
    ;; the implicit libraries, whatever the declaring library imports.
    (: implicit-libraries (List (List String)))
    (define implicit-libraries
      (list (list "snail" "core" "forms")
            (list "snail" "core" "primitive")
            (list "snail" "shell" "wire")))

    (: derived-instances
       (impl (Fn Context Syntax Bool -> (Pair (List Syntax) Context) ! fs compile)))
    (define (derived-instances cx form enum?)
      (let* ((head (declaration-head form)) (loc (syntax-loc form))
             (cases (if enum?
                        (map (lambda (form)
                               (let ((case (parse-case form)))
                                 (Pair (::name case) (length (::fields case)))))
                             (enum-cases form))
                        (list (Pair (declared-name head) (length (struct-fields form)))))))
        (when (and (not enum?)
                   (not (null? (derived-instance-classes form)))
                   (any? (lambda (field) (::mutable? (parse-field field)))
                         (struct-fields form)))
          (compile-error loc
                         "a struct with a mutable field has identity, so it cannot derive an instance"))
        (each cx
              (lambda (cx class)
                (match class
                  ((Ident "Serialize" _ _) (serialize-instance cx head cases loc))
                  ((Ident "Deserialize" _ _) (deserialize-instance cx head cases loc))
                  (_ (compile-error (syntax-loc class)
                                    "only Move, Serialize and Deserialize can be derived"))))
              (derived-instance-classes form))))

    ;; The scope derived instances resolve in, made at the build's first
    ;; deriving clause, which loads the implicit libraries, and shared by
    ;; every later one. The library notes the declaration at `loc`, so that
    ;; replaying it loads them too.
    (: deriving-scope (impl (Fn Context Loc -> (Pair I64 Context) ! fs compile)))
    (define (deriving-scope cx loc)
      (let ((cx (Context-derives-set cx (Some loc))))
        (match (::deriving cx)
          ((Some scope) (Pair scope cx))
          ((None)
           (expanding cx ((exports
                           (each (lambda (cx name) (load-library cx name loc)) implicit-libraries))
                          (env (new-top (fold-left (lambda (table entry)
                                                     (table-set table
                                                                (::first entry)
                                                                (::second entry)))
                                                   empty-table (concatenate exports))))
                          (scope (register-scope env)))
                      (Pair scope (Context-deriving-set cx (Some scope))))))))

    ;; Builds the syntax of a derived instance; `w` makes wire identifiers.
    (struct Deriver
      ((scope I64)
       (loc Loc)))

    (: w (impl (Fn Deriver String -> Syntax)))
    (define (w deriver name)
      (let ((loc (::loc deriver)))
        (Ident name
               (Some (Mark (string-append name "%deriving")
                           (Ident name (None) loc)
                           (::scope deriver)))
               loc)))

    (: f (impl (Fn Deriver (List Syntax) -> Syntax)))
    (define (f deriver items)
      (Form items (::loc deriver)))

    (: field-idents (impl (Fn Deriver I64 -> (List Syntax))))
    (define (field-idents deriver count)
      (map (lambda (index) (w deriver (string-append "field" (i64->string index)))) (iota count)))

    (: instance-head (impl (Fn Deriver String Syntax -> (List Syntax) ! compile)))
    (define (instance-head d class head)
      (let ((params (declared-params head)))
        (append (list (w d "instance") (f d (list (w d class) head)))
                (if (null? params)
                    (Nil)
                    (list (f d
                             (Cons (w d "requires")
                                   (map (lambda (param) (f d (list (w d class) param)))
                                        params))))))))

    ;; Each case writes its TypeId, then its fields in order.
    (: serialize-instance
       (impl
        (Fn Context Syntax (List (Pair Syntax I64)) Loc -> (Pair Syntax Context) ! fs compile)))
    (define (serialize-instance cx head cases loc)
      (expanding cx ((scope (deriving-scope loc)))
                 (let* ((d (Deriver scope loc)) (value (w d "value")) (encoder (w d "encoder")))
                   (Pair (f d (append (instance-head d "Serialize" head)
                                      (list (f d
                                               (list (w d "define")
                                                     (f d (list (w d "encode") value encoder))
                                                     (f d (Cons (w d "match")
                                                                (Cons value
                                                                      (map (lambda (case)
                                                                             (serialize-case d
                                                                                             case
                                                                                             encoder))
                                                                           cases)))))))))
                         cx))))

    (: serialize-case (impl (Fn Deriver (Pair Syntax I64) Syntax -> Syntax)))
    (define (serialize-case d case encoder)
      (let ((fields (field-idents d (::second case))))
        (f d (Cons (f d (Cons (::first case) fields))
                   (Cons (f d
                            (list (w d "encode-case-id")
                                  encoder
                                  (f d (list (w d "case-id") (::first case)))))
                         (append
                          (map (lambda (field) (f d (list (w d "encode") field encoder))) fields)
                          (list (f d (list (w d "unit"))))))))))

    ;; The TypeId read selects the case; an unknown one is a schema mismatch.
    (: deserialize-instance
       (impl
        (Fn Context Syntax (List (Pair Syntax I64)) Loc -> (Pair Syntax Context) ! fs compile)))
    (define (deserialize-instance cx head cases loc)
      (expanding cx ((scope (deriving-scope loc)))
                 (let* ((d (Deriver scope loc)) (decoder (w d "decoder")) (id (w d "id")))
                   (Pair (f d (append (instance-head d "Deserialize" head)
                                      (list
                                       (f d (list (w d "define") (f d (list (w d "decode") decoder))
                                                  (f d
                                                     (list (w d "let")
                                                           (f d
                                                              (list (f d
                                                                       (list id
                                                                             (f d
                                                                                (list (w d
                                                                                         "decode-case-id")
                                                                                      decoder))))))
                                                           (fold-right (lambda (case otherwise)
                                                                         (f d (list (w d "if")
                                                                                    (f d
                                                                                       (list (w d
                                                                                                "case-id=?")
                                                                                             id
                                                                                             (f d
                                                                                                (list
                                                                                                 (w
                                                                                                  d
                                                                                                  "case-id")
                                                                                                 (::first
                                                                                                  case)))))
                                                                                    (deserialize-case
                                                                                     d
                                                                                     case
                                                                                     decoder)
                                                                                    otherwise)))
                                                                       (f d
                                                                          (list (w d "panic")
                                                                                (Atom
                                                                                 (DString
                                                                                  "wire data has a different schema")
                                                                                 loc)))
                                                                       cases))))))))
                         cx))))

    (: deserialize-case (impl (Fn Deriver (Pair Syntax I64) Syntax -> Syntax)))
    (define (deserialize-case d case decoder)
      (let ((fields (field-idents d (::second case))))
        (fold-right (lambda (field body)
                      (f d
                         (list (w d "let")
                               (f d (list (f d (list field (f d (list (w d "decode") decoder))))))
                               body)))
                    (f d (Cons (::first case) fields)) fields)))

    ;; ---- Patterns ----

    (: expand-match (impl (Fn Context Env (List Syntax) Loc -> (Pair Expr Context) ! compile)))
    (define (expand-match cx env items loc)
      (match items
        ((Cons _ (Cons scrutinee clauses))
         (expanding cx ((scrutinee (expand-expr env scrutinee))
                        (clauses (each (lambda (cx clause) (expand-clause cx env clause)) clauses)))
                    (Pair (expr (Match scrutinee clauses) loc) cx)))
        (_ (compile-error loc "expected (match expression clause ...)"))))

    ;; A clause binds its pattern's variables first, so the pattern itself
    ;; only looks names up.
    (: expand-clause (impl (Fn Context Env Syntax -> (Pair Clause Context) ! compile)))
    (define (expand-clause cx env clause)
      (match (form-items clause "a match clause")
        ((Cons pattern body)
         (expanding cx ((locals (bind-locals env (pattern-variables pattern))))
                    (let* ((scope (::first locals))
                           (pattern (expand-pattern cx env scope pattern)))
                      (expanding cx ((body (expand-body scope body (syntax-loc clause))))
                                 (Pair (Clause pattern body) cx)))))
        ((Nil) (compile-error (syntax-loc clause) "expected (pattern body ...)"))))

    ;; The variables of a pattern, in order, each named once.
    (: pattern-variables (impl (Fn Syntax -> (List Syntax) ! compile)))
    (define (pattern-variables syntax)
      (let ((variables (pattern-idents syntax)))
        (for-each (lambda (variable)
                    (when (< 1
                             (length (filter (lambda (other)
                                               (string=? (ident-key other) (ident-key variable)))
                                             variables)))
                      (compile-error (syntax-loc variable)
                                     (string-append "pattern variable bound twice: "
                                                    (Ident-name variable)))))
                  variables)
        variables))

    (: pattern-idents (impl (Fn Syntax -> (List Syntax))))
    (define (pattern-idents syntax)
      (match syntax
        ((Ident "_" _ _) (Nil))
        ((Ident _ _ _) (list syntax))
        ((Form (Cons _ args) _) (concatenate (map pattern-idents args)))
        (_ (Nil))))

    ;; Bare identifiers are `_` or variables bound in `scope`; constructors
    ;; resolve in `env` and are always applied, as in `(None)`.
    (: expand-pattern (impl (Fn Context Env Env Syntax -> Pattern ! compile)))
    (define (expand-pattern cx env scope syntax)
      (match syntax
        ((Ident "_" _ _) (PWild unchecked))
        ((Ident _ _ _)
         (match (resolve cx scope syntax)
           ((Some (Local name)) (PVar name unchecked))
           (_ (panic "internal error: unbound pattern variable"))))
        ((Atom (DBytes _) loc) (compile-error loc "a byte vector cannot be a pattern"))
        ((Atom value _) (PLit value unchecked))
        ((Form (Cons head args) _)
         (PCon (pattern-constructor cx env head)
               (map (lambda (arg) (expand-pattern cx env scope arg)) args)
               unchecked))
        (_ (compile-error (syntax-loc syntax) "expected a pattern"))))

    (: pattern-constructor (impl (Fn Context Env Syntax -> String ! compile)))
    (define (pattern-constructor cx env head)
      (let ((name (constructor-name cx env (expect-ident head "a constructor"))))
        (match (program-value (::program cx) name)
          ((Some (Constructor case _))
           (check-own-library cx
                              (::type case)
                              (syntax-loc head)
                              "take it apart; drop it instead"))
          (_ (unit)))
        name))

    ;; A type with a Drop instance is taken apart, or has a field replaced,
    ;; only in its own library, which the instance trusts to release what a
    ;; value holds; elsewhere a value of it is dropped, or given to a
    ;; function of its library.
    (: check-own-library (impl (Fn Context String Loc String -> Unit ! compile)))
    (define (check-own-library cx type loc what)
      (match (lifecycle-instance (::program cx) drop-class type)
        ((Some _)
         (unless (string=? (name-owner type) (::prefix cx))
           (compile-error loc
                          (string-append (short-name type)
                                         " has a Drop instance, so only its own library can "
                                         what))))
        ((None) (unit))))

    ;; ---- Syntax rules ----

    (struct MacroForm
      ((name Syntax)
       (literals (List Syntax))
       (rules (List Syntax))))

    (: macro-form (impl (Fn Syntax -> MacroForm ! compile)))
    (define (macro-form form)
      (match form
        ((Form (Cons _
                     (Cons name
                           (Cons
                            (Form (Cons (Ident "syntax-rules" _ _) (Cons (Form literals _) rules))
                                  _)
                            (Nil))))
               _)
         (MacroForm (expect-ident name "a macro name") literals rules))
        (_ (compile-error (syntax-loc form)
                          "expected (define-syntax name (syntax-rules (literal ...) rule ...))"))))

    ;; A macro's template resolves in the environment of its definition,
    ;; which includes the macro, so it may expand to a use of itself.
    (: define-top-macro (impl (Fn Context Env Syntax -> Context ! compile)))
    (define (define-top-macro cx env form)
      (let ((parts (macro-form form)))
        (expanding cx ((id (fresh "%macro")) (scope (register-scope env)))
                   (bind-top cx
                             env
                             (::name parts)
                             (Macro id (::literals parts) (::rules parts) scope)))))

    (: define-local-macro (impl (Fn Context Env Syntax -> (Pair Env Context) ! compile)))
    (define (define-local-macro cx env form)
      (let ((parts (macro-form form)))
        (expanding cx ((scope (register-scope env)) (id (fresh "%macro")))
                   (let ((inner (extend env
                                        (::name parts)
                                        (Macro id
                                               (::literals parts)
                                               (::rules parts)
                                               scope))))
                     (Pair inner (scope-set cx scope inner))))))

    (: apply-macro
       (impl
        (Fn Context Env Syntax (List Syntax) (List Syntax) I64 -> (Pair Syntax Context) ! compile)))
    (define (apply-macro cx env form literals rules scope)
      (let ((loc (syntax-loc form)))
        (match rules
          ((Nil) (compile-error loc "no syntax-rules pattern matches this use"))
          ((Cons rule more)
           (match rule
             ((Form (Cons (Form (Cons _ pattern) _) (Cons template (Nil))) _)
              (match (match-pattern cx
                                    (Form pattern loc)
                                    (Form (form-tail form) loc)
                                    literals
                                    env
                                    (scope-env cx scope))
                ((Some bindings)
                 (expanding cx ((stamp (fresh "m")))
                            (Pair (transcribe template bindings (Expansion stamp scope loc)) cx)))
                ((None) (apply-macro cx env form literals more scope))))
             (_ (compile-error (syntax-loc rule) "expected ((_ pattern ...) template)")))))))

    ;; What a pattern variable matched: one form, or under n ellipses a
    ;; depth-n nesting of matches.
    (enum Bound
      (One
       ((syntax Syntax)))
      (Many
       ((matches (List Bound)))))

    (type Bindings (List (Pair String Bound)))

    (: literal? (impl (Fn Syntax (List Syntax) -> Bool)))
    (define (literal? ident literals)
      (any? (lambda (literal) (string=? (ident-key literal) (ident-key ident))) literals))

    (: match-pattern (impl (Fn Context Syntax Syntax (List Syntax) Env Env -> (Option Bindings))))
    (define (match-pattern cx pattern input literals env macro-env)
      (match pattern
        ((Ident "_" _ _) (Some (Nil)))
        ((Ident _ _ _)
         (cond
          ((not (literal? pattern literals)) (Some (list (Pair (ident-key pattern) (One input)))))
          ((same-binding? cx env input macro-env pattern) (Some (Nil)))
          (else (None))))
        ((Atom value _)
         (match input
           ((Atom other _) (if (datum=? value other) (Some (Nil)) (None)))
           (_ (None))))
        ((Form items _)
         (match input
           ((Form inputs _) (match-items cx items inputs literals env macro-env))
           (_ (None))))))

    ;; A literal matches an identifier with the same binding, or the same
    ;; name when both are unbound.
    (: same-binding? (impl (Fn Context Env Syntax Env Syntax -> Bool)))
    (define (same-binding? cx env input macro-env literal)
      (match input
        ((Ident name _ _)
         (match (resolve cx env input)
           ((Some a)
            (match (resolve cx macro-env literal)
              ((Some b) (string=? (binding-identity a) (binding-identity b)))
              ((None) #f)))
           ((None)
            (match (resolve cx macro-env literal)
              ((Some _) #f)
              ((None) (string=? name (Ident-name literal)))))))
        (_ #f)))

    (: match-items
       (impl (Fn Context (List Syntax) (List Syntax) (List Syntax) Env Env -> (Option Bindings))))
    (define (match-items cx patterns inputs literals env macro-env)
      (match patterns
        ((Cons repeated (Cons (Ident "..." _ _) after))
         (match-ellipsis cx repeated after inputs literals env macro-env))
        ((Nil) (if (null? inputs) (Some (Nil)) (None)))
        ((Cons pattern more)
         (match inputs
           ((Nil) (None))
           ((Cons input rest)
            (match (match-pattern cx pattern input literals env macro-env)
              ((Some head)
               (match (match-items cx more rest literals env macro-env)
                 ((Some tail) (Some (append head tail)))
                 ((None) (None))))
              ((None) (None))))))))

    (: match-ellipsis
       (impl
        (Fn Context Syntax (List Syntax) (List Syntax) (List Syntax) Env Env -> (Option Bindings))))
    (define (match-ellipsis cx repeated after inputs literals env macro-env)
      (let ((count (- (length inputs) (length after))))
        (if (< count 0)
            (None)
            (match (match-items cx after (list-drop inputs count) literals env macro-env)
              ((None) (None))
              ((Some tail)
               (match (all-matched (map (lambda (input)
                                          (match-pattern cx repeated input literals env macro-env))
                                        (take inputs count)))
                 ((None) (None))
                 ((Some matches)
                  (Some (append (map (lambda (key)
                                       (Pair key
                                             (Many (map (lambda (bindings) (bound-ref bindings key))
                                                        matches))))
                                     (pattern-keys repeated literals))
                                tail)))))))))

    ;; Every match, or None if any failed.
    (: all-matched (impl (Fn (List (Option Bindings)) -> (Option (List Bindings)))))
    (define (all-matched matches)
      (fold-right (lambda (match-result rest)
                    (match match-result
                      ((Some bindings)
                       (match rest ((Some more) (Some (Cons bindings more))) ((None) (None))))
                      ((None) (None))))
                  (Some (Nil)) matches))

    (: bound-ref (impl (Fn Bindings String -> Bound)))
    (define (bound-ref bindings key)
      (match (assoc-ref bindings key)
        ((Some bound) bound)
        ((None) (panic "internal error: unbound pattern variable"))))

    (: pattern-keys (impl (Fn Syntax (List Syntax) -> (List String))))
    (define (pattern-keys pattern literals)
      (match pattern
        ((Ident name _ _)
         (if (or (string=? name "_") (string=? name "...") (literal? pattern literals))
             (Nil)
             (list (ident-key pattern))))
        ((Form items _) (concatenate (map (lambda (item) (pattern-keys item literals)) items)))
        (_ (Nil))))

    ;; One expansion: identifiers the template introduces share one mark per
    ;; name, and every introduced form is located at the macro use.
    (struct Expansion
      ((stamp String)
       (scope I64)
       (loc Loc)))

    (: transcribe (impl (Fn Syntax Bindings Expansion -> Syntax ! compile)))
    (define (transcribe template bindings expansion)
      (match template
        ((Ident name _ _)
         (match (assoc-ref bindings (ident-key template))
           ((None) (rename-ident template expansion))
           ((Some (Many _))
            (compile-error (::loc expansion)
                           (string-append "pattern variable used without an ellipsis: " name)))
           ((Some (One syntax)) syntax)))
        ((Atom _ _) template)
        ((Form items _)
         (Form (transcribe-items items bindings expansion) (::loc expansion)))))

    (: transcribe-items (impl (Fn (List Syntax) Bindings Expansion -> (List Syntax) ! compile)))
    (define (transcribe-items items bindings expansion)
      (match items
        ((Nil) (Nil))
        ((Cons item (Cons (Ident "..." _ _) rest))
         (append (transcribe-repeated item bindings expansion)
                 (transcribe-items rest bindings expansion)))
        ((Cons item rest)
         (Cons (transcribe item bindings expansion) (transcribe-items rest bindings expansion)))))

    ;; The repeated template iterates over every variable it uses that matched
    ;; under an ellipsis; such variables must have equal lengths.
    (: transcribe-repeated (impl (Fn Syntax Bindings Expansion -> (List Syntax) ! compile)))
    (define (transcribe-repeated template bindings expansion)
      (let ((repeated (concatenate (map (lambda (key)
                                          (match (assoc-ref bindings key)
                                            ((Some (Many matches)) (list (Pair key matches)))
                                            (_ (Nil))))
                                        (delete-duplicates string=? (template-keys template))))))
        (match repeated
          ((Nil)
           (compile-error (::loc expansion)
                          "ellipsis follows a template without pattern variables"))
          ((Cons first _)
           (let ((count (length (::second first))))
             (unless (every? (lambda (entry) (= count (length (::second entry)))) repeated)
               (compile-error (::loc expansion)
                              "pattern variables under one ellipsis matched different lengths"))
             (map (lambda (index)
                    (transcribe template
                                (append (map (lambda (entry)
                                               (Pair (::first entry)
                                                     (list-ref (::second entry) index)))
                                             repeated)
                                        bindings)
                                expansion))
                  (iota count)))))))

    (: template-keys (impl (Fn Syntax -> (List String))))
    (define (template-keys template)
      (match template
        ((Ident _ _ _) (list (ident-key template)))
        ((Form items _) (concatenate (map template-keys items)))
        (_ (Nil))))

    ;; A template's identifier becomes the same marked identifier wherever it
    ;; appears in one expansion: its mark is its key with the expansion's
    ;; stamp, resolved in the macro's scope.
    (: rename-ident (impl (Fn Syntax Expansion -> Syntax)))
    (define (rename-ident ident expansion)
      (Ident (Ident-name ident)
             (Some (Mark (string-append (ident-key ident) "%" (::stamp expansion))
                         ident
                         (::scope expansion)))
             (::loc expansion)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-expand)
    (import
     (only (chibi filesystem) create-directory*)
     (only (chibi string) string-contains string-cursor->index)
     (snail stage0 testing)
     (only (snail shell compiler inputs) no-inputs supply-generated))
    (begin

      ;; A walk reads imports through `cond-expand`, stops at a producer
      ;; whose output is missing, reads on through one supplied, and fails
      ;; where a producer's imports lead back to the library it makes.
      ;; Discovery finds the uses expansion reaches, in program order, one
      ;; of them in a supplied output, and not one only an unused macro
      ;; names. The primitive library is read from its file. The sources are
      ;; written into `directory`; `library` holds the standard libraries.
      (define (test-expand directory library)
        (test-callable-signatures)
        (write-sources directory)
        (let ((walk (list (string-append directory "/walk") library))
              (discover (string-append directory "/discover")))
          (test-library-file walk)
          (test-library-closure walk)
          (test-discovery (list discover library) discover)
          (test-links (string-append directory "/links"))
          (test-primitives (string-append directory "/primitive") library)
          (test-annotation-metadata (string-append directory "/annotations") library)
          (test-deriving-runs (string-append directory "/deriving") library)
          (test-deriving-key (string-append directory "/deriving-key") library)))

      (define (test-callable-signatures)
        (expect (callable-signature "(-> Unit)")
                (TFun (Nil) (TCon "Unit" (Nil)) empty-row))
        (expect (callable-signature "(I64 (Vector String) -> Bool ! mut)")
                (TFun (list (TCon "I64" (Nil)) (TCon "Vector" (list (TCon "String" (Nil)))))
                      (TCon "Bool" (Nil)) mut-row))
        (for-each (lambda (source)
                    (expect (and (compile-failure (lambda () (callable-signature source))) #t) #t))
                  (list "()" "(I64 Unit)" "(I64 ! mut -> Unit)"
                        "(I64 ->)" "(I64 -> ! mut)" "(I64 -> -> Unit)"
                        "(I64 -> Unit Bool)")))

      (define (callable-signature text)
        (let* ((cx (new-context (Nil) (lambda (loading forms) (panic "unexpected producer"))
                                no-inputs (Supplied) empty-expansion))
               (imports (fold-left (lambda (table entry)
                                     (table-set table (::first entry) (::second entry)))
                                   empty-table (core-library)))
               (env (::first (new-top cx imports))))
          (match (read-text text "callable.sld")
            ((Cons (Form items loc) (Nil)) (resolve-callable-arrow cx env items (Nil) loc)))))

      ;; Metadata follows canonical declarations through imports and replay.
      ;; Updating only a field's documentation does not change its wire or
      ;; dynamic type identity, and equal field names have distinct owners.
      (define (test-annotation-metadata directory library)
        (create-directory* (string-append directory "/sample"))
        (let ((source (string-append directory "/main.sld"))
              (module (string-append directory "/sample/docs.sld"))
              (directories (list directory library)))
          (write-file source "(import (prefix (sample docs) renamed-)) (renamed-Entry \"ok\")")
          (write-file module (annotation-library "original"))
          (let* ((first (expand-program directories
                                        annotation-generator
                                        no-inputs
                                        source
                                        empty-expansion))
                 (replayed (expand-program directories annotation-generator no-inputs source first))
                 (program (::program replayed))
                 (entry (program-type program "sample.docs:Entry")))
            (expect (annotation-documentation (program-annotations program "sample.docs:Entry"))
                    (Some "A record.\nIts fields are immutable."))
            (expect (annotation-documentation
                     (program-field-annotations program "sample.docs:Entry" "value"))
                    (Some "original"))
            (expect (annotation-documentation
                     (program-field-annotations program "sample.docs:Other" "value"))
                    (Some "A different field."))
            (expect (program-annotations program "sample.docs:Entry-value") (Nil))
            (expect (annotation-documentation (program-annotations program "sample.docs:label"))
                    (Some "Name this value."))
            (expect (annotation-documentation (program-annotations program "sample.docs:Waiting"))
                    (Some "No value yet."))
            (expect (annotation-documentation (program-annotations program "sample.docs:read-name"))
                    (Some "Read a name."))
            (write-file module (annotation-library "updated"))
            (let* ((changed
                    (expand-program directories annotation-generator no-inputs source replayed))
                   (next (::program changed)))
              (expect (annotation-documentation
                       (program-field-annotations next "sample.docs:Entry" "value"))
                      (Some "updated"))
              (expect (any-type-id next (TCon "sample.docs:Entry" (Nil)))
                      (any-type-id program (TCon "sample.docs:Entry" (Nil))))
              (expect (case-type-id next
                                    (list-ref
                                     (::cases (program-type next "sample.docs:Entry"))
                                     0))
                      (case-type-id program (list-ref (::cases entry) 0)))))))

      (define (annotation-generator loading forms)
        (panic "annotation fixture must not request a generator"))

      (define (annotation-library documentation)
        (string-append
         "(define-library (sample docs) (export Entry) (import (snail core base)) (begin\n"
         "(struct Entry ((value String (annotations (doc " (datum->string (DString documentation))
         ")))) (annotations (doc \"A record.\") (doc \"Its fields are immutable.\")))\n"
         "(struct Other ((value I64 (annotations (doc \"A different field.\")))))\n"
         "(enum Readiness (Waiting (annotations (doc \"No value yet.\"))))\n"
         "(typeclass (Named T) (: label (dyn (Fn T -> String)) (annotations (doc \"Name this value.\"))))\n"
         "(effect names ((read-name (dyn (Fn Unit -> String)) (annotations (doc \"Read a name.\")))))\n"
         "))"))

      ;; A producer names its recipe after its imports, as the path the
      ;; recipe was found at.
      (define (test-library-file directories)
        (let ((loc (Loc "test.sld" 1 1)))
          (expect (library-file directories (list "snail" "core" "forms") loc)
                  (DefinedLibrary (Nil)))
          (expect (map syntax->string
                       (section-items (DefinedLibrary-sections (library-file directories
                                                                             (list "sample" "top")
                                                                             loc))
                                      "import"))
                  (list "(sample made)"))
          (expect (map syntax->string
                       (GeneratedLibrary-forms
                        (library-file directories (list "sample" "made") loc)))
                  (list
                   "(import (snail core base) (sample helper) (only (snail shell syntax) write-generated-library))"
                   (string-append "(recipe "
                                  (datum->string (DString (string-append (list-ref directories 0)
                                                                         "/sample/made.sld")))
                                  ")")
                   "(write-generated-library (lambda () (unit)))"))))

      (define (test-library-closure directories)
        (let* ((imports (program-imports (read-text "(import (sample top)) (unit)" "main.sld")))
               (cold (library-closure directories no-inputs (Nil) imports))
               (made (list-ref cold 0))
               (inputs (supply-generated no-inputs (producer-text directories (::forms made))
                                         (generated-library-bytes
                                          "(define-library (sample made) (export) (import (sample inner)) (begin))")))
               (warm (library-closure directories inputs (Nil) imports)))
          (expect (map ::library cold) (list (list "sample" "made")))
          (expect (::loading made) (list "sample.made" "sample.top"))
          (expect (map ::library warm) (list (list "sample" "made") (list "sample" "inner")))
          (expect (::loading (list-ref warm 1))
                  (list "sample.inner" "sample.made" "sample.top"))
          (expect (closure-error directories made) #t)))

      ;; The producer of (sample made) imports (sample helper), which
      ;; imports (sample made) while it is still loading.
      (define (closure-error directories made)
        (let ((message (compile-failure (lambda ()
                                          (library-closure directories
                                                           no-inputs
                                                           (::loading made)
                                                           (program-imports
                                                            (::forms made)))))))
          (and message
               (string-contains message "helper.sld:1:")
               (string-contains message "library import cycle through sample.made")
               #t)))

      (define (test-discovery directories root)
        (let* ((assets (library-file directories (list "sample" "assets") (Loc "test.sld" 1 1)))
               (inputs (supply-generated no-inputs
                                         (producer-text directories (GeneratedLibrary-forms assets))
                                         (generated-library-bytes assets-output)))
               (uses (discover-artifacts directories inputs (string-append root "/main.sld"))))
          (expect (map ::name uses) (list "admin" "client"))
          (expect (map (lambda (use) (::file (::loc use))) uses)
                  (list (string-append root "/sample/assets.sld")
                        (string-append root "/main.sld")))))

      ;; A linked path is made canonical against its library's directory,
      ;; and the file is named for the digest of its bytes, once however
      ;; many uses or paths reach the same bytes. A path that leaves the
      ;; directory, or a file that is not there, is an error naming the
      ;; library and the path.
      (define (test-links root)
        (create-directory* (string-append root "/sample/data"))
        (write-file (string-append root "/sample/data/pixel.bin") "pixel")
        (write-file (string-append root "/notes.txt") "notes")
        (write-file (string-append root "/copy.txt") "notes")
        (write-file (string-append root "/sample/linked.sld")
                    "(define-library (sample linked) (export pixel) (import (snail core forms)) (begin (define pixel (link-handle \"data/./x/../pixel.bin\"))))")
        (let ((expansion (link-expansion root
                                         "(import (snail core forms) (sample linked)) (define notes (link-handle \"notes.txt\")) (link-handle \"notes.txt\") (link-handle \"copy.txt\")")))
          (expect (map ::digest (program-links expansion))
                  (list "3f8d7379e2f0f7d0c845a06f7b67ef80cacce0c686254aced769c1698f3fe59a"
                        "ab5aa97074c454a0632057e704220d9a6678fbf773a0a5806fc09b8173b07309"))
          (expect (map ::path (library-links expansion "sample.linked"))
                  (list (string-append root "/sample/data/pixel.bin"))))
        (expect (link-error root "../notes.txt")
                "link-file may not leave the library's directory: ../notes.txt")
        (expect (link-error root "/notes.txt")
                "link-file takes a path relative to the library, with no empty names: /notes.txt")
        (expect (link-error root "./")
                "link-file takes a path relative to the library, with no empty names: ./")
        (expect (link-error root "absent.bin")
                (string-append "the library main links absent.bin, but there is no file at "
                               root
                               "/absent.bin")))

      (define (link-expansion root body)
        (write-file (string-append root "/main.sld") body)
        (expand-program (list root)
                        (lambda (loading forms) (panic "unexpected producer"))
                        no-inputs
                        (string-append root "/main.sld")
                        empty-expansion))

      (define (link-error root path)
        (let ((message (compile-failure
                        (lambda ()
                          (link-expansion root
                                          (string-append
                                           "(import (snail core forms)) (link-handle \""
                                           path
                                           "\")"))))))
          (if message
              (substring message
                         (+ (string-cursor->index message (string-contains message ": ")) 2)
                         (string-length message))
              "accepted")))

      ;; Loading (snail core primitive) binds each primitive's value under
      ;; `prim:NAME`, quantified over the variables its declaration names, in
      ;; their order, and records no run of items, since the library has no
      ;; module.
      (define (test-primitives root library)
        (create-directory* root)
        (write-file (string-append root "/main.sld") "(import (snail core primitive)) (unit)")
        (let ((program (::program (expand-program (list root library)
                                                  (lambda (loading forms)
                                                    (panic "unexpected producer"))
                                                  no-inputs
                                                  (string-append root "/main.sld")
                                                  empty-expansion))))
          (expect (primitive-scheme program "vector-ref")
                  (list (list "A") "(dyn (Fn (Vector A) I64 -> A))"))
          (expect (primitive-scheme program "vector-generate")
                  (list (list "A" "e") "(dyn (Fn I64 (dyn (Fn I64 -> A ! e)) -> (Vector A) ! e))"))
          (expect (primitive-scheme program "array-ref")
                  (list (list "A") "(dyn (Fn (Array A) I64 -> A ! mut))"))
          (expect (primitive-scheme program "inherit-handlers")
                  (list (list "A" "e")
                        "(dyn (Fn (dyn (FnOnce -> A ! e)) -> (dyn (FnOnce -> A ! host)) ! e))"))
          (expect (map ::first (library-items program (program-items program))) (list "main"))))

      ;; A library that derives without importing (snail shell wire) loads
      ;; it at its first deriving clause, and the wire's run of items comes
      ;; before the library's, not inside it: each run holds only the
      ;; definitions of the library it names, and the library's are the two
      ;; methods it derived. Replaying the library, when nothing else
      ;; imports the wire, loads it first again.
      (define (test-deriving-runs root library)
        (create-directory* (string-append root "/sample"))
        (write-file (string-append root "/sample/shape.sld")
                    (string-append
                     "(define-library (sample shape) (export Shape) (import (snail core base))"
                     " (begin (struct Shape ((side I64)) (deriving Serialize Deserialize))))"))
        (write-file (string-append root "/main.sld")
                    "(import (snail core base) (sample shape)) (Shape 2)")
        (let* ((expand (lambda (predecessor)
                         (expand-program (list root library)
                                         (lambda (loading forms) (panic "unexpected producer"))
                                         no-inputs
                                         (string-append root "/main.sld") predecessor)))
               (first (expand empty-expansion)))
          (expect (every? own-run? (expansion-runs first)) #t)
          (expect (run-length first "sample.shape") 2)
          (expect (deriving-order first) (list "snail.shell.wire" "sample.shape" "main"))
          (expect (deriving-order (expand first)) (list "snail.shell.wire" "sample.shape" "main"))))

      ;; A library's derived instances hold while the implicit libraries'
      ;; interfaces do (#546): a definition added to the wire changes its
      ;; interface, so the library that derives is expanded under a new
      ;; key, though its text is the same. A body edit also re-expands the
      ;; wire's instance methods with fresh identities; derived evidence
      ;; must follow them. An unchanged build still replays. The wire is a
      ;; copy of the standard one, found first.
      (define (test-deriving-key root library)
        (let* ((wire (read-file (string-append library "/snail/shell/wire.sld")))
               (end (- (string-length wire) 2))
               (marked (lambda (value)
                         (string-append (substring wire 0 end)
                                        " (begin (: wire-marker I64) (define wire-marker "
                                        value
                                        ")))\n")))
               (expand (lambda (text predecessor)
                         (write-file (string-append root "/snail/shell/wire.sld") text)
                         (expand-program (list root library)
                                         (lambda (loading forms) (panic "unexpected producer"))
                                         no-inputs
                                         (string-append root "/main.sld")
                                         predecessor)))
               (key (lambda (expansion) (library-key expansion "sample.shape"))))
          (expect (substring wire end (string-length wire)) ")\n")
          (create-directory* (string-append root "/sample"))
          (create-directory* (string-append root "/snail/shell"))
          (write-file (string-append root "/sample/shape.sld")
                      (string-append
                       "(define-library (sample shape) (export Shape) (import (snail core base))"
                       " (begin (struct Shape ((side I64)) (deriving Serialize))))"))
          (write-file (string-append root "/main.sld")
                      "(import (snail core base) (sample shape)) (Shape 2)")
          (let* ((first (expand wire empty-expansion))
                 (second (expand (marked "1") first))
                 (third (expand (marked "2") second))
                 (fourth (expand (marked "2") third)))
            (expect (string=? (key first) (key second)) #f)
            (expect (string=? (key second) (key third)) #f)
            (expect (key fourth) (key third)))))

      (define (expansion-runs expansion)
        (let ((program (::program expansion)))
          (library-items program (program-items program))))

      (define (own-run? run)
        (every? (lambda (item)
                  (match item
                    ((Define name _) (string=? (name-owner name) (::first run)))
                    (_ #t)))
                (::second run)))

      (define (run-length expansion name)
        (match (find (lambda (run) (string=? (::first run) name)) (expansion-runs expansion))
          ((Some run) (length (::second run)))
          ((None) -1)))

      (define (deriving-order expansion)
        (filter (lambda (name) (member? name (list "snail.shell.wire" "sample.shape" "main")))
                (map ::first (expansion-runs expansion))))

      (define (primitive-scheme program name)
        (match (program-value program (string-append "prim:" name))
          ((Some (Primitive scheme))
           (list (::vars scheme) (type->string (::type scheme))))
          (_ (list))))

      (define assets-output
        (string-append
         "(define-library (sample assets) (export admin-bundle) (import (snail core base) (snail shell artifact)) "
         "(begin (: admin-bundle ArtifactBundle) (define admin-bundle (artifact-bundle \"admin\"))))"))

      (define (write-sources directory)
        (create-directory* (string-append directory "/walk/sample"))
        (create-directory* (string-append directory "/discover/sample"))
        (for-each (lambda (source)
                    (write-file (string-append directory "/" (::first source))
                                (::second source)))
                  (list (Pair "walk/sample/top.sld"
                              "(define-library (sample top) (export) (cond-expand ((not snail-core) (import (sample never))) (else (import (sample made)))) (begin))")
                        (Pair "walk/sample/made.sld"
                              "(generate-library (sample made) (import (snail core base) (sample helper)) (unit))")
                        (Pair "walk/sample/helper.sld"
                              "(define-library (sample helper) (export) (import (sample made)) (begin))")
                        (Pair "walk/sample/inner.sld"
                              "(generate-library (sample inner) (import (snail core base)) (unit))")
                        (Pair "discover/sample/assets.sld"
                              "(generate-library (sample assets) (import (snail core base)) (unit))")
                        (Pair "discover/main.sld" discovery-main))))

      (define discovery-main
        (string-append
         "(import (snail core base) (rename (snail shell artifact) (artifact-bundle bundle)) (sample assets))\n"
         "(define-syntax client-snapshot (syntax-rules () ((_) (bundle \"client\"))))\n"
         "(define-syntax unused (syntax-rules () ((_) (bundle \"does-not-exist\"))))\n"
         "(define snapshot (client-snapshot))\n"
         "(define again (client-snapshot))\n"))))
   (else)))
