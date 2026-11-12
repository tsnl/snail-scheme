;; Located syntax to the core program. The expander is the only pass that knows
;; Snail Scheme's binding forms. It loads libraries, resolves every identifier to a
;; binding, runs `syntax-rules` macros, records declared entities in the
;; program tables, and emits core expressions with unique names.
(define-library (snail shell compiler expand)
  (export
   ExpandedProgram
   library-key
   instance-interfaces
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

    (define (binding-identity (binding Binding)) (→ String)
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

    (define (extend (env Env) (ident Syntax) (binding Binding)) (→ Env)
      (Frame (ident-key ident) binding env))

    ;; A marked identifier is keyed by its mark, so the same name introduced by
    ;; two expansions binds two variables.

    (define (ident-key (ident Syntax)) (→ String)
      (match ident
        ((Ident _ (Some mark) _) (● mark key))
        ((Ident name (None) _) name)
        (_ (panic "internal error: not an identifier"))))

    ;; An unbound marked identifier resolves as its original in the scope of
    ;; the macro that introduced it.

    (define (resolve (cx Context) (env Env) (ident Syntax)) (→ (Option Binding))
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
                   (resolve cx (scope-env cx (● mark scope)) (● mark original)))
                  (_ (None))))))))))

    ;; What a top level binds `key` to: its own definition, or else an
    ;; import.

    (define (top-binding (cx Context) (top String) (imports (Table Binding)) (key String))
      (→ (Option Binding))
      (match (table-ref (top-definitions cx top) key)
        ((Some binding) (Some binding))
        ((None) (table-ref imports key))))

    (define (expect-ident (syntax Syntax) (what String)) (→ Syntax) (! compile)
      (match syntax
        ((Ident _ _ _) syntax)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items of a form, or an error naming what was expected.

    (define (form-items (syntax Syntax) (what String)) (→ (List Syntax)) (! compile)
      (match syntax
        ((Form items _) items)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items after a form's head.

    (define (form-tail (syntax Syntax)) (→ (List Syntax))
      (match syntax
        ((Form (Cons _ rest) _) rest)
        (_ (Nil))))

    (define (head-binding (cx Context) (env Env) (syntax Syntax)) (→ (Option Binding))
      (match syntax
        ((Form (Cons head _) _)
         (match head
           ((Ident _ _ _) (resolve cx env head))
           (_ (None))))
        (_ (None))))

    (define (core-form? (cx Context) (env Env) (syntax Syntax) (name String)) (→ Bool)
      (match (head-binding cx env syntax)
        ((Some (Core keyword)) (string=? keyword name))
        (_ #f)))

    ;; ---- Expansion context ----

    ;; One build's expansion, made fresh for each build and threaded through
    ;; it as plain data: a step takes the context and hands back the one it
    ;; learned in. Its fields fall into three kinds.
    ;;
    ;; What the build is given, which never changes: `directories` are
    ;; searched for libraries;
    ;; `inputs` holds what
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
    ;; library this build has expanded, with its exports and content key. `artifacts` says where an `artifact-files` use finds its
    ;; files; a discovery records there each use it reaches. `counter`
    ;; numbers fresh names. `scopes` holds the environments that marks refer
    ;; to, by number, and `scope-count` is the next number; `tops` holds
    ;; each top level's definitions, by key, and `top-count` makes the next
    ;; key. `deriving` is the scope derived instances resolve in, once one
    ;; is made.
    (struct Context
      ((directories (List String))
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

    (define (resumed (outer Context) (inner Context)) (→ Context)
      (Context (● outer directories)
               (● outer inputs)
               (● outer recipe)
               (● outer prefix)
               (● outer loading)
               (● outer aliases)
               (● outer artifact-uses)
               (● outer links)
               (● outer items)
               (● outer derives)
               (● inner program)
               (● inner expanded)
               (● inner artifacts)
               (● inner counter)
               (● inner scopes)
               (● inner scope-count)
               (● inner tops)
               (● inner top-count)
               (● inner deriving)))

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

    (define (each (cx Context) (step (Fn Context A → (Pair B Context) ! e)) (items (List A)))
      (→ (Pair (List B) Context))
      (! e)
      (∀ A B e)
      (⊨ (Copy B) (Drop e B))
      (let ((done (fold-left (lambda (done item)
                               (match (step (● done second) item)
                                 ((Pair value cx) (Pair (Cons value (● done first)) cx))))
                             (Pair (Nil) cx) items)))
        (Pair (reverse (● done first)) (● done second))))

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

    (define (artifact-files (cx Context) (name String) (loc Loc))
      (→ (Pair ArtifactFiles Context))
      (! compile)
      (match (● cx artifacts)
        ((Supplied)
         (match (table-ref (● (● cx inputs) artifacts) name)
           ((Some files) (Pair files cx))
           ((None) (request-input (ArtifactInput name loc)))))
        ((Discovering uses)
         (Pair (Nil)
               (Context-artifacts-set cx (Discovering (Cons (ArtifactUse name loc (Nil)) uses)))))))

    ;; Expansion is fresh for each build. Only semantic content keys,
    ;; exports used by this build's imports, and linked files survive it.
    (struct Expanded
      ((interface String)
       (exports Exports)
       (links (List LinkedFile))))

    (struct ExpandedProgram
      ((program Program)
       (libraries (Table Expanded))))



    (define (new-context (directories (List String))
                         (inputs Inputs)
                         (artifacts ArtifactSource))
      (→ Context)
      (Context directories inputs (None) "" (Nil) (Nil) (Nil) (Nil) (Nil) (None)
               empty-program empty-table artifacts 0 empty-table 0 empty-table 0 (None)))

    (define (expanded-program (cx Context)) (→ ExpandedProgram)
      (ExpandedProgram (● cx program) (● cx expanded)))

    ;; Each addition hands back the context with a larger program, except
    ;; that an item joins the library's own items until its run is done.

    (define (add-value (cx Context) (name String) (value Value)) (→ Context)
      (Context-program-set cx (program-with-value (● cx program) name value)))

    (define (add-item (cx Context) (item Item)) (→ Context)
      (Context-items-set cx (Cons item (● cx items))))

    (define (fresh (cx Context) (base String)) (→ (Pair String Context))
      (let ((count (+ (● cx counter) 1)))
        (Pair (string-append base "." (i64->string count)) (Context-counter-set cx count))))

    (define (global-name (cx Context) (key String)) (→ String)
      (string-append (● cx prefix) ":" key))

    ;; Numbers `env` as the next scope.

    (define (register-scope (cx Context) (env Env)) (→ (Pair I64 Context))
      (let ((number (● cx scope-count)))
        (Pair number (scope-set (Context-scope-count-set cx (+ number 1)) number env))))

    (define (scope-set (cx Context) (number I64) (env Env)) (→ Context)
      (Context-scopes-set cx (table-set (● cx scopes) (i64->string number) env)))

    (define (scope-env (cx Context) (number I64)) (→ Env)
      (match (table-ref (● cx scopes) (i64->string number))
        ((Some env) env)
        ((None) (panic "internal error: unknown scope"))))

    ;; A top level over `imports` that defines nothing yet.

    (define (new-top (cx Context) (imports (Table Binding))) (→ (Pair Env Context))
      (let ((number (● cx top-count)))
        (Pair (Top (i64->string number) imports) (Context-top-count-set cx (+ number 1)))))

    (define (top-definitions (cx Context) (top String)) (→ (Table Binding))
      (match (table-ref (● cx tops) top)
        ((Some definitions) definitions)
        ((None) empty-table)))

    ;; Binds a name at a top level, once.

    (define (bind-top (cx Context) (env Env) (ident Syntax) (binding Binding))
      (→ Context)
      (! compile)
      (match env
        ((InstanceScope _ rest) (bind-top cx rest ident binding))
        ((InstanceOwner _ rest) (bind-top cx rest ident binding))
        ((Top top _)
         (let ((definitions (top-definitions cx top)))
           (when (table-contains? definitions (ident-key ident))
             (compile-error (syntax-loc ident)
                            (string-append "duplicate top-level definition " (Ident-name ident))))
           (Context-tops-set cx
                             (table-set (● cx tops)
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

    (define (core-library) (→ Exports)
      (append (map (lambda (name) (Pair name (Core name))) core-keywords)
              (append (map (lambda (entry)
                             (Pair (● entry first)
                                   (TypeName (● entry first) (● entry second) (None))))
                           (filter (lambda (entry) (not (string=? (● entry first) "fn")))
                                   builtin-types))
                      (list (Pair "mut" (EffectName "mut")) (Pair "host" (EffectName "host"))))))

    (define (builtin-library? (key String)) (→ Bool)
      (string=? key "snail.core.forms"))

    ;; ---- Libraries ----

    ;; `(snail core base)` is the list ("snail" "core" "base"); its globals are prefixed
    ;; `snail.core.base` and its source is `snail/core/base.sld` in a search directory.

    (define (library-name (syntax Syntax)) (→ (List String)) (! compile)
      (map (lambda (part)
             (match part
               ((Ident name _ _) name)
               ((Atom (DInt number) _) (i64->string number))
               (_ (compile-error (syntax-loc part) "expected a library name part"))))
           (form-items syntax "a library name")))

    (define (check-library-name (declared Syntax) (name (List String)) (loc Loc))
      (→ Unit)
      (! compile)
      (when (string=? (string-join name ".") "prim")
        (compile-error loc "the prim library name is reserved for compiler primitives"))
      (unless (string=? (string-join (library-name declared) ".") (string-join name "."))
        (compile-error loc "library name does not match its path")))

    ;; A library's exports, resolved when an import asks: the compiler's own
    ;; for (snail core forms), else the library as this build expanded it,
    ;; which happens once, under the library's own scope, resumed in the
    ;; importer's.

    (define (load-library (cx Context) (name (List String)) (loc Loc))
      (→ (Pair Exports Context))
      (! fs compile generator)
      (let ((key (string-join name ".")))
        (cond ((builtin-library? key) (Pair (core-library) cx))
              ((member? key (● cx loading))
               (compile-error loc (string-append "library import cycle through " key)))
              (else (match (table-ref (● cx expanded) key)
                      ((Some entry) (Pair (● entry exports) cx))
                      ((None)
                       (match (read-library (Context-loading-set cx (Cons key (● cx loading)))
                                            name
                                            loc)
                         ((Pair exports loaded) (Pair exports (resumed cx loaded))))))))))

    (define (read-library (cx Context) (name (List String)) (loc Loc))
      (→ (Pair Exports Context))
      (! fs compile generator)
      (let ((path (library-path (● cx directories) name loc)))
        (expand-library-file cx name (file-library name (read-source path) path))))

    ;; Where a library's source is: the first search directory holding it.

    (define (find-library (directories (List String)) (name (List String)))
      (→ (Option String))
      (! fs)
      (let ((relative (string-append (string-join name "/") ".sld")))
        (find file-exists?
              (map (lambda (directory) (string-append directory "/" relative)) directories))))

    (define (library-path (directories (List String)) (name (List String)) (loc Loc))
      (→ String)
      (! fs compile)
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

    (define (file-library (name (List String)) (forms (List Syntax)) (path String))
      (→ LibraryFile)
      (! fs compile)
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

    (define (output-library-file (name (List String)) (bytes Bytes) (loc Loc))
      (→ LibraryFile)
      (! fs compile)
      (file-library name (list (with-included-bytes (decode-syntax bytes loc))) (● loc file)))

    ;; A defined library expands its sections; a generated one expands the
    ;; library its producer's output declares.

    (define (expand-library-file (cx Context) (name (List String)) (file LibraryFile))
      (→ (Pair Exports Context))
      (! fs compile generator)
      (match file
        ((DefinedLibrary sections)
         (expand-sections (Context-prefix-set cx (string-join name ".")) sections))
        ((GeneratedLibrary forms loc)
         (expand-library-file cx name (output-library-file name (generated-bytes cx forms) loc)))))

    ;; What a producer wrote: the output the build supplied for it, or else
    ;; what the driver's handler produces. The context owns only plain data;
    ;; generator policy belongs to this invocation's handler. A request keeps
    ;; the exact loading stack, so recursive compilation still detects cycles.

    (effect generator
      ((run-generator (Fn (List String) (List Syntax) → Bytes ! fs compile))))

    (define (generated-bytes (cx Context) (forms (List Syntax))) (→ Bytes) (! generator fs compile)
      (match (generated-output (● cx inputs) (producer-text (● cx directories) forms))
        ((Some bytes) bytes)
        ((None) (run-generator (● cx loading) forms))))

    ;; The producer imports what the recipe imports, names the recipe's
    ;; file, and writes the syntax its expression returns, a
    ;; `(snail shell syntax)` Syntax, which it computes in a task.

    (define (producer (recipe String) (imports (List Syntax)) (expression Syntax) (loc Loc))
      (→ (List Syntax))
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
              (Form (list (Ident "define" (None) loc) (Ident "main" (None) loc)
                          (Form (list (Ident "lambda" (None) loc) (Form (Nil) loc)
                                      (Form (list write-library
                                                  (Form (list (Ident "lambda" (None) loc)
                                                              (Form (Nil) loc) expression) loc))
                                            loc)) loc)) loc))))

    ;; ---- Sources ----

    ;; A source file's forms. `(include-bytes "path")` is another spelling
    ;; of a byte vector literal, which reads as `#u8(...)` holding the bytes
    ;; of the file at `path`, relative to the file the form is written in.

    (define (read-source (path String)) (→ (List Syntax)) (! fs compile)
      (map with-included-bytes (read-source-file path)))

    (define (with-included-bytes (syntax Syntax)) (→ Syntax) (! fs compile)
      (match syntax
        ((Form (Cons (Ident "include-bytes" _ _) args) loc)
         (Atom (DBytes (included-bytes args loc)) loc))
        ((Form items loc) (Form (map with-included-bytes items) loc))
        (_ syntax)))

    (define (included-bytes (args (List Syntax)) (loc Loc)) (→ Bytes) (! fs compile)
      (match args
        ((Cons (Atom (DString path) _) (Nil))
         (let ((resolved (beside (● loc file) path)))
           (if (file-exists? resolved)
               (read-bytes resolved)
               (compile-error loc (string-append "no file to include at " resolved)))))
        (_ (compile-error loc "expected (include-bytes \"path\")"))))

    ;; `path` in the directory holding `file`, unless it is absolute.

    (define (beside (file String) (path String)) (→ String)
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

    (define (expand-link-file (cx Context) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
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

    (define (record-link (cx Context) (handle String) (relative String) (loc Loc))
      (→ Context)
      (! compile)
      (let ((path (beside (written-in cx loc) relative)))
        (match (find (lambda (use) (string=? (● use handle) handle)) (● cx links))
          ((Some use)
           (unless (string=? (● use path) path)
             (compile-error loc
                            (string-append "two files link as "
                                           relative
                                           ": "
                                           (● use path)
                                           " and "
                                           path)))
           cx)
          ((None)
           (Context-links-set cx (Cons (LinkUse handle relative path loc) (● cx links)))))))

    ;; A linked path in its canonical form: names separated by `/`, where
    ;; `.` is the directory it is in and `..` its parent, so
    ;; `data/../pixel.png` is `pixel.png`. A path that is absolute, has an
    ;; empty name, names nothing, or climbs out of the directory is refused,
    ;; since the payload could not ship its file under a name of its own.

    (define (linked-path (path String) (loc Loc)) (→ String) (! compile)
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

    (define (path-names (path String)) (→ (List String))
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (path-names (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    ;; Binds each use's global to the import from "snail.runtime.link" named
    ;; for its file's digest, which answers the file's handle, and gives the
    ;; files the library links, once each, in the order its uses were
    ;; reached. Files with the same bytes are one file.

    (define (bind-links (cx Context) (uses (List LinkUse)))
      (→ (Pair (List LinkedFile) Context))
      (! fs compile)
      (let ((linked (map (lambda (use) (Pair use (linked-file (● cx prefix) use))) uses)))
        (Pair
         (delete-duplicates (lambda (a b) (string=? (● a digest) (● b digest)))
                            (map (lambda (record) (● record second)) linked))
         (fold-left (lambda (cx entry)
                      (add-value cx
                                 (● (● entry first) handle)
                                 (link-import (● entry second))))
                    cx linked))))

    ;; The file a use names, read for its digest. A missing file fails the
    ;; library's expansion, naming the library and the path.

    (define (linked-file (library String) (use LinkUse)) (→ LinkedFile) (! fs compile)
      (let ((path (● use path)))
        (if (file-exists? path)
            (LinkedFile (file-digest path) path)
            (compile-error (● use loc)
                           (string-append "the library " library " links " (● use relative)
                                          ", but there is no file at " path)))))

    (define (link-import (file LinkedFile)) (→ Value)
      (Foreign (Import "snail.runtime.link" (● file digest))
               (mono-scheme (TFun (Nil) (TCon "I32" (Nil)) empty-row))))

    (define (file-digest (path String)) (→ String) (! fs)
      (bytes->hex (sha256 (read-bytes path))))

    ;; The digests enter the library's keys: its module names them, and so
    ;; does an importer's that specializes a generic function calling one
    ;; of its handles.

    (define (links-stamp (files (List LinkedFile))) (→ String)
      (if (null? files)
          ""
          (string-append " links-"
                         (i64->string
                          (fnv-1a (string-join (map (lambda (record) (● record digest)) files)
                                               " "))))))

    ;; The files a library links, as the build expanded it, in the order
    ;; its uses were reached.

    (define (library-links (expansion ExpandedProgram) (name String)) (→ (List LinkedFile))
      (match (table-ref (● expansion libraries) name)
        ((Some entry) (● entry links))
        ((None) (Nil))))

    ;; The files the whole program links: each library's, in program order.

    (define (program-links (expansion ExpandedProgram)) (→ (List LinkedFile))
      (let ((program (● expansion program)))
        (concatenate (map (lambda (library) (library-links expansion (● library first)))
                          (library-items program (program-items program))))))

    ;; Load imports once per build, then expand current declarations. What
    ;; this library uses and makes starts empty after its imports have loaded.
    ;; Checked code and Wasm may be reused later, under completed content keys.

    (define (expand-sections (cx Context) (sections (List (Pair String (List Syntax)))))
      (→ (Pair Exports Context))
      (! fs compile generator)
      (expanding cx ((env (import-env (section-items sections "import"))))
                 (let* ((key (sections-key cx sections))
                        (cx (Context-derives-set
                             (Context-items-set (Context-links-set
                                                 (Context-artifact-uses-set cx (Nil)) (Nil)) (Nil))
                             (None))))
                   (expand-recorded cx sections env key))))

    ;; The primitive library's body is its declarations, which add no items,
    ;; so it records no run and has no module.

    (define (expand-library-body (cx Context)
                                 (sections (List (Pair String (List Syntax))))
                                 (env Env))
      (→ (Pair Exports Context))
      (! fs compile generator)
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

    (define (expand-library-run (cx Context) (env Env) (forms (List Syntax)))
      (→ Context)
      (! fs compile generator)
      (let* ((cx (expand-top-level cx env forms))
             (cx (if (string=? (● cx prefix) "main") (with-entry cx) cx)))
        (Context-program-set cx
                             (program-with-library (● cx program)
                                                   (● cx prefix)
                                                   (● cx items)))))

    ;; Only the root program's own main is an entry. An imported function
    ;; called main remains an ordinary function, with no startup behavior.
    (define (with-entry (cx Context)) (→ Context)
      (match (find (lambda (item)
                     (match item ((Define "main:main" _) #t) (_ #f))) (● cx items))
        ((Some (Define name value)) (add-item cx (Entry name (● value loc))))
        (_ cx)))

    ;; Each declaration is a section of imports, exports or definitions, or a
    ;; `cond-expand` choosing more declarations.

    (define (library-sections (declaration Syntax))
      (→ (List (Pair String (List Syntax))))
      (! compile)
      (match declaration
        ((Form (Cons (Ident "cond-expand" _ _) clauses) _) (cond-expand-sections clauses))
        ((Form (Cons (Ident kind _ _) items) loc)
         (if (member? kind (list "import" "export" "begin"))
             (list (Pair kind items))
             (compile-error loc "expected import, export, begin or cond-expand")))
        (_
         (compile-error (syntax-loc declaration) "expected import, export, begin or cond-expand"))))

    ;; The declarations of the first clause whose requirement holds. Snail Scheme's
    ;; only feature is `snail-core`.

    (define (cond-expand-sections (clauses (List Syntax)))
      (→ (List (Pair String (List Syntax))))
      (! compile)
      (match clauses
        ((Nil) (Nil))
        ((Cons (Form (Cons requirement declarations) _) rest)
         (if (feature? requirement)
             (concatenate (map library-sections declarations))
             (cond-expand-sections rest)))
        ((Cons clause _)
         (compile-error (syntax-loc clause) "expected (requirement declaration ...)"))))

    (define (feature? (requirement Syntax)) (→ Bool)
      (match requirement
        ((Ident name _ _) (or (string=? name "snail-core") (string=? name "else")))
        ((Form (Cons (Ident "and" _ _) items) _) (every? feature? items))
        ((Form (Cons (Ident "or" _ _) items) _) (any? feature? items))
        ((Form (Cons (Ident "not" _ _) (Cons item (Nil))) _) (not (feature? item)))
        (_ #f)))

    (define (section-items (sections (List (Pair String (List Syntax)))) (kind String))
      (→ (List Syntax))
      (concatenate
       (map (lambda (record) (● record second))
            (filter (lambda (section) (string=? (● section first) kind)) sections))))

    ;; A program is a sequence of imports followed by a body, which counts as
    ;; a library named `main` that exports nothing. Every build starts with
    ;; fresh names and scopes. A producer program begins
    ;; with `(generating ...)`, and its imports load inside the libraries
    ;; that form names, so one that leads back to them is a cycle.

    (define (expand-program (directories (List String))
                            (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                            (inputs Inputs)
                            (path String))
      (→ ExpandedProgram)
      (! fs compile)
      (handle generator ((run-generator generate))
        (expanded-program
         (expand-source (new-context directories inputs (Supplied)) path))))

    (define (expand-source (cx Context) (path String)) (→ Context) (! fs compile generator)
      (let* ((source (generating-stack (read-source path)))
             (parts (program-parts (● source second)))
             (body (producer-body path (● source first) (● parts second)))
             (cx (Context-recipe-set
                  (Context-loading-set (Context-prefix-set cx "main") (● source first))
                  (● body first))))
        (● (expand-sections cx
                            (list (Pair "import" (● parts first))
                                  (Pair "begin" (● body second)))) second)))

    ;; A producer program's printed copy, at `copy`, and the recipe it was
    ;; printed from, at `file`.
    (struct Recipe
      ((copy String)
       (file String)))

    ;; The body of the program at `path`, and the recipe it stands for when
    ;; it is a producer, printed with the libraries `loading` when it was
    ;; reached: such a body begins with `(recipe "lib/sample/blob.sld")`.

    (define (producer-body (path String) (loading (List String)) (body (List Syntax)))
      (→ (Pair (Option Recipe) (List Syntax)))
      (match body
        ((Cons (Form (Cons (Ident "recipe" _ _) (Cons (Atom (DString file) _) (Nil))) _) rest)
         (if (null? loading) (Pair (None) body) (Pair (Some (Recipe path file)) rest)))
        (_ (Pair (None) body))))

    ;; The file a path written at `loc` is relative to: the file it is
    ;; written in, where a producer's printed copy stands for its recipe, so
    ;; a recipe names files beside itself wherever its producer is printed.

    (define (written-in (cx Context) (loc Loc)) (→ String)
      (match (● cx recipe)
        ((Some (Recipe copy file)) (if (string=? (● loc file) copy) file (● loc file)))
        ((None) (● loc file))))

    ;; A program's leading `import` forms' specs, and the body after them.

    (define (program-parts (forms (List Syntax))) (→ (Pair (List Syntax) (List Syntax)))
      (match forms
        ((Cons (Form (Cons (Ident "import" _ _) specs) _) rest)
         (let ((parts (program-parts rest)))
           (Pair (append specs (● parts first)) (● parts second))))
        (_ (Pair (Nil) forms))))

    ;; The import specs of a program's leading `import` forms.

    (define (program-imports (forms (List Syntax))) (→ (List Syntax))
      (● (program-parts forms) first))

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

    (define (library-closure (directories (List String))
                             (inputs Inputs)
                             (loading (List String))
                             (imports (List Syntax)))
      (→ (List Reached))
      (! fs compile)
      (let* ((walk (walk-imports (Walk directories inputs empty-table (Nil)) loading imports))
             (walk (fold-left (lambda (walk name) (walk-implicit walk loading name))
                              walk
                              implicit-libraries)))
        (reverse (● walk reached))))

    (define (walk-imports (walk Walk) (loading (List String)) (specs (List Syntax)))
      (→ Walk)
      (! fs compile)
      (fold-left (lambda (walk spec)
                   (walk-library walk loading (library-name (spec-library spec)) (syntax-loc spec)))
                 walk
                 specs))

    ;; Only a library that derives loads these, so one need not exist.

    (define (walk-implicit (walk Walk) (loading (List String)) (name (List String)))
      (→ Walk)
      (! fs compile)
      (match (find-library (● walk directories) name)
        ((Some path) (walk-library walk loading name (Loc path 1 1)))
        ((None) walk)))

    ;; The checks are `load-library`'s, in its order: (snail core forms) has
    ;; no file, and a library already loading is a cycle.

    (define (walk-library (walk Walk) (loading (List String)) (name (List String)) (loc Loc))
      (→ Walk)
      (! fs compile)
      (let ((key (string-join name ".")))
        (cond ((builtin-library? key) walk)
              ((member? key loading)
               (compile-error loc (string-append "library import cycle through " key)))
              ((table-contains? (● walk visited) key) walk)
              (else (walk-file (Walk-visited-set walk (table-set (● walk visited) key #t))
                               (Cons key loading)
                               name
                               (library-file (● walk directories) name loc))))))

    (define (walk-file (walk Walk) (loading (List String)) (name (List String)) (file LibraryFile))
      (→ Walk)
      (! fs compile)
      (match file
        ((DefinedLibrary sections) (walk-imports walk loading (section-items sections "import")))
        ((GeneratedLibrary forms loc)
         (let ((walk (Walk-reached-set walk
                                       (Cons (Reached name forms loc loading)
                                             (● walk reached)))))
           (match (generated-output (● walk inputs)
                                    (producer-text (● walk directories) forms))
             ((Some bytes) (walk-file walk loading name (output-library-file name bytes loc)))
             ((None) walk))))))

    ;; A library's file as a walk reads it: as `read-library` does, except
    ;; that the files a defined library includes are not read, since they
    ;; cannot name a library. (snail core forms) needs nothing.

    (define (library-file (directories (List String)) (name (List String)) (loc Loc))
      (→ LibraryFile)
      (! fs compile)
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

    (define (discover-artifacts (directories (List String)) (inputs Inputs) (path String))
      (→ (List ArtifactUse))
      (! fs compile)
      (handle generator ((run-generator unsupplied-producer))
        (match (● (expand-source (new-context directories
                                              inputs
                                              (Discovering (Nil)))
                                 path) artifacts)
          ((Discovering uses) (reverse uses))
          ((Supplied) (Nil)))))

    (define (unsupplied-producer (loading (List String)) (forms (List Syntax))) (→ Bytes)
      (panic "internal error: discovery reached a producer whose output was not supplied"))

    ;; ---- Expansion fingerprints ----

    ;; Artifacts may change without any source edit. Their stamp is content,
    ;; never a fresh-name counter: expansion restarts those counters each build.
    (define (artifact-stamp (uses (List ArtifactUse))) (→ String)
      (i64->string (fnv-1a (string-join (map artifact-key uses) "\n"))))

    (define (artifact-key (use ArtifactUse)) (→ String)
      (string-append (datum->string (DString (● use name))) " "
                     (string-join
                      (map (lambda (file)
                             (string-append (datum->string (DString (● file first))) " "
                                            (syntax->key (Atom (DBytes (● file second))
                                                               (● use loc)))))
                           (● use files)) " ")))

    (define (expand-recorded (cx Context)
                             (sections (List (Pair String (List Syntax))))
                             (env Env) (key String))
      (→ (Pair Exports Context))
      (! fs compile generator)
      (expanding cx ((exports (expand-library-body sections env))
                     (links (bind-links (reverse (● cx links)))))
                 (Pair exports
                       (record cx (Expanded
                                   (string-append (interface-hash cx key)
                                                  (derivation-key cx)
                                                  " artifacts-"
                                                  (artifact-stamp (● cx artifact-uses))
                                                  (links-stamp links))
                                   exports links)))))

    ;; Derived code depends on the implicit libraries loaded at the deriving
    ;; clause, even when the source did not import those libraries explicitly.
    (define (derivation-key (cx Context)) (→ String)
      (match (● cx derives)
        ((Some _) (string-append " derived " (implicit-interfaces cx)))
        ((None) "")))

    ;; The declarations introduced by this library, for its identity key.

    (define (library-delta (cx Context)) (→ Program)
      (if (primitive-library? cx)
          (primitive-delta (● cx program))
          (program-delta (● cx program) (● cx prefix))))

    (define (record (cx Context) (entry Expanded)) (→ Context)
      (Context-expanded-set cx (table-set (● cx expanded) (● cx prefix) entry)))

    ;; ---- Build keys ----

    ;; A library's build key: the canonical text of its declarations, with
    ;; the interfaces of its imports.

    (define (sections-key (cx Context) (sections (List (Pair String (List Syntax)))))
      (→ String)
      (! compile)
      (string-append (string-join (map (lambda (section)
                                         (string-append (● section first)
                                                        " "
                                                        (forms-text (● section second))))
                                       sections)
                                  "\n")
                     "\n" (imports-interfaces cx sections)))

    (define (forms-text (forms (List Syntax))) (→ String)
      (string-join (map syntax->key forms) "\n"))

    ;; Syntax as text that keys a build. A byte vector shows only its length
    ;; and a hash of its bytes, so a library that embeds megabytes keys on a
    ;; few characters.

    (define (syntax->key (syntax Syntax)) (→ String)
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

    (define (bytes-hash (bytes Bytes)) (→ I64)
      (vector-fold (lambda (hash byte) (fnv-step hash (i32->i64 (u8->i32 byte)))) fnv-offset bytes))

    ;; Each imported library's interface, as this build expanded it; the
    ;; compiler's own libraries never change.

    (define (imports-interfaces (cx Context) (sections (List (Pair String (List Syntax)))))
      (→ String)
      (! compile)
      (string-join (map (lambda (spec)
                          (library-interface cx
                                             (string-join (library-name (spec-library spec)) ".")))
                        (section-items sections "import"))
                   " "))

    ;; The implicit libraries' interfaces, as this build expanded them.

    (define (implicit-interfaces (cx Context)) (→ String)
      (string-join (map (lambda (name) (library-interface cx (string-join name ".")))
                        implicit-libraries)
                   " "))

    (define (library-interface (cx Context) (name String)) (→ String)
      (match (table-ref (● cx expanded) name)
        ((Some entry) (● entry interface))
        ((None) "builtin")))

    ;; Checking sees the final program's instances, including sibling
    ;; providers outside a library's imports. Their implementations and
    ;; imports enter every checked-code key. Named policies participate too.
    ;; Expansion itself always uses the current program, so it caches no
    ;; choices made under a partially loaded instance environment.
    (define (instance-interfaces (program Program) (libraries (Table Expanded))) (→ String)
      (let ((owners (list-sort string<?
                               (delete-duplicates string=?
                                                  (map (lambda (instance)
                                                         (name-owner (● instance name)))
                                                       (concatenate
                                                        (table-values (● program instances))))))))
        (string-join (map (lambda (owner)
                            (string-append owner " "
                                           (match (table-ref libraries owner)
                                             ((Some entry) (● entry interface))
                                             ((None)
                                              (panic
                                               "internal error: an instance provider was not expanded")))))
                          owners)
                     "\n")))

    ;; The key a build expanded a library under. Anything made from the
    ;; library's expansion, such as its checked items, stays valid while its
    ;; completed interface key is unchanged, including its own fresh names.

    (define (library-key (expansion ExpandedProgram) (name String)) (→ String)
      (match (table-ref (● expansion libraries) name)
        ((Some entry) (● entry interface))
        ((None) "")))

    (define (spec-library (spec Syntax)) (→ Syntax)
      (match spec
        ((Form (Cons (Ident keyword _ _) (Cons inner _)) _)
         (if (member? keyword (list "only" "except" "prefix" "rename")) (spec-library inner) spec))
        (_ spec)))

    ;; Any function can run while forcing a constant, even a monomorphic
    ;; function under a local handler. Importers therefore depend on every
    ;; implementation body through its transitive source key. The final
    ;; counter certifies local-name stability when an earlier library changes;
    ;; global declaration identities certify generated types and imports.
    (define (interface-hash (cx Context) (key String)) (→ String)
      (i64->string (fnv-1a (string-append key "\n" (i64->string (● cx counter))
                                          "\n" (library-identities cx)))))

    ;; Instance methods and macro-introduced globals have fresh names after
    ;; expansion. Importers must not retain checked evidence or Wasm imports
    ;; naming the previous expansion, even if only a signed body changed.

    (define (library-identities (cx Context)) (→ String)
      (let ((delta (library-delta cx)))
        (string-join
         (list-sort string<?
                    (concatenate (list (table-keys (● delta values))
                                       (table-keys (● delta types))
                                       (table-keys (● delta classes))
                                       (table-keys (● delta effects))
                                       (map (lambda (record) (● record name))
                                            (concatenate (table-values (● delta instances)))))))
         "\n")))

    ;; ---- Imports and exports ----

    ;; A top level over the bindings the specs provide, each loaded and
    ;; merged in turn.

    (define (import-env (cx Context) (specs (List Syntax)))
      (→ (Pair Env Context))
      (! fs compile generator)
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

    (define (import-binding (imports (Table Binding)) (entry (Pair String Binding)) (loc Loc))
      (→ (Table Binding))
      (! compile)
      (match (table-ref imports (● entry first))
        ((Some existing)
         (if (string=? (binding-identity existing) (binding-identity (● entry second)))
             imports
             (compile-error loc (string-append "conflicting imports of " (● entry first)))))
        ((None) (table-set imports (● entry first) (● entry second)))))

    ;; The (name . binding) entries an import set provides.

    (define (import-set (cx Context) (spec Syntax))
      (→ (Pair Exports Context))
      (! fs compile generator)
      (match spec
        ((Form (Cons (Ident "only" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (expanding cx ((entries (checked-import-set inner idents)))
                      (Pair (filter (lambda (entry) (member? (● entry first) names)) entries)
                            cx))))
        ((Form (Cons (Ident "except" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (expanding cx ((entries (checked-import-set inner idents)))
                      (Pair
                       (filter (lambda (entry) (not (member? (● entry first) names))) entries)
                       cx))))
        ((Form (Cons (Ident "prefix" _ _) (Cons inner (Cons (Ident prefix _ _) (Nil)))) _)
         (expanding cx ((entries (import-set inner)))
                    (Pair (map (lambda (entry)
                                 (Pair (string-append prefix (● entry first))
                                       (● entry second)))
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
                                   (match (assoc-ref renames (● entry first))
                                     ((Some renamed) (Pair renamed (● entry second)))
                                     ((None) entry)))
                                 entries)
                            cx))))
        (_ (load-library cx (library-name spec) (syntax-loc spec)))))

    (define (checked-import-set (cx Context) (spec Syntax) (idents (List Syntax)))
      (→ (Pair Exports Context))
      (! fs compile generator)
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

    (define (ident-names (idents (List Syntax))) (→ (List String)) (! compile)
      (map (lambda (ident) (Ident-name (expect-ident ident "an identifier"))) idents))

    (define (rename-pair (syntax Syntax)) (→ (Pair String String)) (! compile)
      (match syntax
        ((Form (Cons (Ident from _ _) (Cons (Ident to _ _) (Nil))) _) (Pair from to))
        (_ (compile-error (syntax-loc syntax) "expected (name new-name)"))))

    (define (export-entry (cx Context) (env Env) (spec Syntax))
      (→ (Pair String Binding))
      (! compile)
      (match spec
        ((Ident name _ _) (Pair name (defined-binding cx env spec "exported name is not defined")))
        ((Form (Cons (Ident "rename" _ _) (Cons inner (Cons (Ident outer _ _) (Nil)))) _)
         (Pair outer (defined-binding cx env inner "exported name is not defined")))
        (_ (compile-error (syntax-loc spec) "expected an export specification"))))

    ;; The binding of an identifier that must be bound.

    (define (defined-binding (cx Context) (env Env) (ident Syntax) (message String))
      (→ Binding)
      (! compile)
      (match (resolve cx env (expect-ident ident "an identifier"))
        ((Some binding) binding)
        ((None)
         (compile-error (syntax-loc ident) (string-append message ": " (Ident-name ident))))))

    ;; The unique name of a top-level definition the scan bound.

    (define (global-binding (cx Context) (env Env) (ident Syntax)) (→ String) (! compile)
      (match (defined-binding cx env ident "undefined name")
        ((Global name) name)
        (_ (compile-error (syntax-loc ident)
                          (string-append "not a top-level definition: " (Ident-name ident))))))

    ;; ---- Top-level bodies ----

    ;; Definition headers describe the value before any body is expanded.
    ;; Parameters and fields have the same (name Type) shape. The header's
    ;; variables scope over every type in the definition, even its head.
    (struct DefinitionHeader
      ((result (Option Syntax))
       (effects (List Syntax))
       (variables (List Syntax))
       (constraints (List Syntax))
       (annotations (List Annotation))))

    (struct Definition
      ((name Syntax)
       (parameters (Option (List (Pair Syntax Syntax))))
       (header DefinitionHeader)
       (body (List Syntax))
       (loc Loc)))

    (define (definition-clause (form Syntax)) (→ String)
      (match form
        ((Form (Cons (Ident "annotations" _ _) entries) _)
         (match entries
           ((Nil) "annotations")
           ((Cons (Form _ _) _) "annotations")
           (_ "")))
        ((Form (Cons (Ident name _ _) _) _)
         (if (member? name (list "→" "!" "∀" "⊨")) name ""))
        (_ "")))

    (define (definition-parameter (form Syntax)) (→ (Pair Syntax Syntax)) (! compile)
      (match form
        ((Form (Cons name (Cons type (Nil))) _)
         (Pair (expect-ident name "a parameter name") type))
        (_ (compile-error (syntax-loc form) "a function parameter needs (name Type)"))))

    (define (definition-header-clause (header DefinitionHeader) (name String) (form Syntax))
      (→ DefinitionHeader)
      (! compile)
      (let ((items (form-tail form)))
        (case name
          (("→")
           (match items
             ((Cons result (Nil)) (DefinitionHeader-result-set header (Some result)))
             (_ (compile-error (syntax-loc form) "expected (→ Type)"))))
          (("!") (DefinitionHeader-effects-set header items))
          (("∀")
           (let ((variables
                  (map (lambda (item) (expect-ident item "a quantified variable")) items)))
             (unless (= (length variables)
                        (length (delete-duplicates string=? (map Ident-name variables))))
               (compile-error (syntax-loc form) "duplicate quantified variable"))
             (DefinitionHeader-variables-set header variables)))
          (("⊨") (DefinitionHeader-constraints-set header items))
          (("annotations") (DefinitionHeader-annotations-set header (parse-annotations form)))
          (else (panic "internal error: definition clause")))))

    (define (definition-header (forms (List Syntax)))
      (→ (Pair DefinitionHeader (List Syntax)))
      (! compile)
      (let loop ((forms forms)
                 (header (DefinitionHeader (None) (Nil) (Nil) (Nil) (Nil)))
                 (seen (Nil)))
        (match forms
          ((Nil) (Pair header forms))
          ((Cons form rest)
           (let ((name (definition-clause form)))
             (if (string=? name "") (Pair header forms)
                 (begin
                   (when (member? name seen)
                     (compile-error (syntax-loc form)
                                    (string-append "duplicate definition clause " name)))
                   (loop rest (definition-header-clause header name form) (Cons name seen)))))))))

    (define (parse-definition (form Syntax)) (→ Definition) (! compile)
      (match (form-tail form)
        ((Cons head forms)
         (let* ((parsed (definition-header forms))
                (header (● parsed first))
                (body (● parsed second))
                (parameters (match head
                              ((Form (Cons _ parameters) _)
                               (Some (map definition-parameter parameters)))
                              (_ (None)))))
           (when (null? body) (compile-error (syntax-loc form) "a definition needs a body"))
           (for-each (lambda (item)
                       (unless (member? (definition-clause item) (list "" "annotations"))
                         (compile-error (syntax-loc item)
                                        "definition clauses must precede the body")))
                     body)
           (check-definition-header parameters header body (syntax-loc form))
           (Definition (definition-name form) parameters header body (syntax-loc form))))
        (_ (compile-error (syntax-loc form) "expected a definition"))))

    (define (check-definition-header (parameters (Option (List (Pair Syntax Syntax))))
                                     (header DefinitionHeader)
                                     (body (List Syntax))
                                     (loc Loc))
      (→ Unit)
      (! compile)
      (match parameters
        ((Some _)
         (match (● header result)
           ((None) (compile-error loc "a function definition needs (→ Result)"))
           (_ (unit))))
        ((None)
         (unless (= (length body) 1) (compile-error loc "a value definition needs one initializer"))
         (unless (null? (● header effects))
           (compile-error loc "a value's callable effects belong in its type"))))
      (when (and (or (not (null? (● header variables))) (not (null? (● header constraints))))
                 (match (● header result) ((None) #t) (_ #f)))
        (compile-error loc "a polymorphic definition needs (→ Type)")))

    ;; Reuse the callable and quantified type parsers: this construction is
    ;; the only translation from a definition header to its complete type.

    (define (definition-type (definition Definition)) (→ Syntax)
      (let* ((header (● definition header)) (loc (● definition loc))
             (result (match (● header result)
                       ((Some type) type)
                       (_ (panic "internal error: unsigned definition"))))
             (type (match (● definition parameters)
                     ((None) result)
                     ((Some parameters)
                      (definition-callable-type parameters result (● header effects) loc)))))
        (if (and (null? (● header variables)) (null? (● header constraints))) type
            (Form (list (Ident "∀" (None) loc) (Form (● header variables) loc)
                        (Form (Cons (Ident "⊨" (None) loc) (● header constraints)) loc) type)
                  loc))))

    (define (definition-callable-type (parameters (List (Pair Syntax Syntax)))
              (result Syntax) (effects (List Syntax)) (loc Loc))
      (→ Syntax)
      (let ((arguments (map (lambda (record) (● record second)) parameters))
            (performs (if (null? effects) (Nil) (Cons (Ident "!" (None) loc) effects))))
        (Form (Cons (Ident "Fn" (None) loc)
                    (append arguments (Cons (Ident "→" (None) loc) (Cons result performs))))
              loc)))

    (define (definition-scope (cx Context) (env Env) (definition Definition)) (→ Env) (! compile)
      (let* ((header (● definition header)) (variables (● header variables))
             (scope (type-scope env variables)))
        (● (resolve-requirements cx scope (map Ident-name variables) (● header constraints)) env)))

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
       (env Env)
       (definition (Option Definition))))

    (define declaration-keywords (→ (List String))
      (list ":" "struct" "enum" "type" "typeclass" "instance" "extern" "effect" "expose"))

    (define (expand-top-level (cx Context) (env Env) (forms (List Syntax)))
      (→ Context)
      (! fs compile generator)
      (expanding cx ((scanned (each (lambda (cx form) (scan-top-level cx env form)) forms)))
                 (let* ((pending (concatenate scanned))
                        (signatures
                         (fold-left (lambda (table entry) (with-signature cx table entry))
                                    empty-table
                                    pending)))
                   (expanding cx ((bodies (each (lambda (cx entry) (declare cx signatures entry))
                                                pending)))
                              (check-buildable-structs cx pending)
                              (check-repr-types cx pending)
                              (expand-bodies cx (concatenate bodies))))))

    ;; A body that fails leaves the context as it was before it, and the
    ;; bodies after it are expanded all the same, so one compile reports
    ;; each body's error. Nothing a later body resolves can be missing for
    ;; it, since pass 1 bound every name. The library then fails with what
    ;; every failed body found, in order, and is never checked.

    (define (expand-bodies (cx Context) (bodies (List (Fn Context → Context ! compile))))
      (→ Context)
      (! compile)
      (let ((run (fold-left (lambda (run body)
                              (match (recovering (lambda () (body (● run first))))
                                ((Ok cx) (Pair cx (● run second)))
                                ((Err found)
                                 (Pair (● run first)
                                       (append (● run second) (diagnostics->list found))))))
                            (Pair cx (Nil))
                            bodies)))
        (fail-if-found (● run second))
        (● run first)))

    ;; A struct whose every value would contain another value of itself,
    ;; through struct fields and cell contents only, can never be built: no
    ;; finite program constructs one. The backend relies on the rule, since
    ;; a call that may yield returns a placeholder of its type, a constant
    ;; it could not write for such a struct. Once every declaration of the
    ;; library is in, each struct is checked where it is declared. An empty
    ;; type is an enum with no cases.

    (define (check-buildable-structs (cx Context) (pending (List Pending))) (→ Unit) (! compile)
      (for-each (lambda (entry)
                  (when (string=? (● entry keyword) "struct") (check-buildable cx entry)))
                pending))

    (define (check-buildable (cx Context) (entry Pending)) (→ Unit) (! compile)
      (let ((name (declared-name (declaration-head (● entry form)))))
        (match (resolve cx (● entry env) name)
          ((Some (TypeName id _ _))
           (when (contains-itself? (● cx program) (program-type (● cx program) id))
             (compile-error (syntax-loc name)
                            (string-append "the struct "
                                           (Ident-name name)
                                           " can never be built: each of its values would contain another"))))
          (_ (panic "internal error: struct")))))

    (define (scan-top-level (cx Context) (env Env) (form Syntax))
      (→ (Pair (List Pending) Context))
      (! fs compile generator)
      (expanding cx ((form (expand-head env form)))
                 (let* ((parsed (declaration-annotations cx env form)) (bare (● parsed first))
                        (owner (if (null? (● parsed second)) (None)
                                   (Some (declared-name (declaration-head bare)))))
                        (scanned (scan-top-level-form cx env bare)))
                   (Pair (● scanned first)
                         (match owner
                           ((None) (● scanned second))
                           ((Some name) (with-name-annotations (● scanned second) name
                                                               (● parsed second))))))))

    ;; Annotation slots belong to declaration grammars, never executable
    ;; bodies or raw macro arguments. Expand a macro first; it can emit an
    ;; annotated signature just as a handwritten declaration can.

    (define (declaration-annotations (cx Context) (env Env) (form Syntax))
      (→ (Pair Syntax (List Annotation)))
      (! compile)
      (match (head-binding cx env form)
        ((Some (Core keyword))
         (case keyword
           ((":" "type" "effect") (split-annotations form 3))
           (("struct" "enum" "typeclass") (split-annotations form 2))
           (("extern") (split-annotations form 5))
           (else (Pair form (Nil)))))
        (_ (Pair form (Nil)))))

    (define (with-name-annotations (cx Context) (ident Syntax) (annotations (List Annotation)))
      (→ Context)
      (Context-program-set cx (program-with-annotations (● cx program)
                                                        (unique-name cx ident) annotations)))

    (define (scan-top-level-form (cx Context) (env Env) (form Syntax))
      (→ (Pair (List Pending) Context))
      (! fs compile generator)
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
                         (Pair (Cons (Pending "instance-scope" form scope (None))
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
         (let* ((definition (parse-definition form)) (ident (● definition name))
                (cx (bind-top cx env ident (Global (unique-name cx ident)))))
           (Pair (list (Pending "define" form env (Some definition)))
                 (if (null? (● (● definition header) annotations)) cx
                     (with-name-annotations cx ident (● (● definition header) annotations))))))
        ((Some (Core keyword))
         (if (member? keyword declaration-keywords)
             (scan-declared cx env keyword form)
             (Pair (list (Pending "expression" form env (None))) cx)))
        (_ (Pair (list (Pending "expression" form env (None))) cx))))

    (define (scan-instance-set (cx Context) (env Env) (form Syntax))
      (→ (Pair (List Pending) Context))
      (! fs compile generator)
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
                                                                       scope (None)))
                                                        cx))
                                                 (_ (compile-error (syntax-loc declaration)
                                                                   "an instance set contains instance or dynamic-instances declarations")))))
                                         declarations)))
                      (Pair (concatenate scanned) cx))))
        (_ (compile-error (syntax-loc form) "expected (define-instance-set name instance ...)"))))

    (define (instance-owner (env Env)) (→ (Option String))
      (match env
        ((InstanceOwner name _) (Some name))
        ((InstanceScope _ rest) (instance-owner rest))
        ((EvidenceScope _ rest) (instance-owner rest))
        ((Frame _ _ rest) (instance-owner rest))
        ((Top _ _) (None))))

    (define (active-instance-sets (cx Context) (env Env)) (→ (List String)) (! compile)
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

    (define (scope-instance-value (cx Context) (env Env) (value Expr)) (→ Expr) (! compile)
      (let ((sets (active-instance-sets cx env)))
        (if (null? sets) value
            (match (● value term)
              ((Lambda params body captures?)
               (Expr (Lambda params (expr (ScopedInstances sets body) (● body loc)) captures?)
                     (● value type) (● value loc)))
              (_ (expr (ScopedInstances sets value) (● value loc)))))))

    ;; A declaration binds its names, then the instances a struct or enum
    ;; derives are scanned after it.

    (define (scan-declared (cx Context) (env Env) (keyword String) (form Syntax))
      (→ (Pair (List Pending) Context))
      (! fs compile generator)
      (expanding cx ((then (scan-declaration env keyword form)))
                 (if (or (string=? keyword "struct") (string=? keyword "enum"))
                     (expanding cx ((derived (derived-instances form (string=? keyword "enum")))
                                    (scanned
                                     (each (lambda (cx instance) (scan-top-level cx env instance))
                                           derived)))
                                (Pair (Cons (Pending keyword form env (None)) (concatenate scanned))
                                      cx))
                     (Pair (list (Pending keyword form env (None))) cx))))

    (define (definition-name (form Syntax)) (→ Syntax) (! compile)
      (match form
        ((Form (Cons _ (Cons (Form (Cons name _) _) _)) _) (expect-ident name "a definition name"))
        ((Form (Cons _ (Cons name _)) _) (expect-ident name "a definition name"))
        (_ (compile-error (syntax-loc form)
                          "expected (define name value) or (define (name (parameter Type) ...) (→ Result) body ...)"))))

    (define (declare (cx Context) (signatures (Table (Pair Scheme (Option Loc)))) (pending Pending))
      (→ (Pair (List (Fn Context → Context ! compile)) Context))
      (! compile)
      (let ((form (● pending form)) (env (● pending env)))
        (case (● pending keyword)
          ((":") (Pair (Nil) cx))
          (("struct") (Pair (Nil) (declare-data cx env form #f)))
          (("enum") (Pair (Nil) (declare-data cx env form #t)))
          (("typeclass") (Pair (Nil) (declare-class cx env form)))
          (("instance") (declare-instance cx env form))
          (("dynamic-instances") (declare-dynamic-instances cx env form))
          (("instance-scope")
           (Pair (list (lambda (cx)
                         (check-active-instances (● cx program) (active-instance-sets cx env)
                                                 (syntax-loc form))
                         cx)) cx))
          (("extern") (Pair (Nil) (declare-extern cx env form)))
          (("effect") (declare-effect cx env form))
          (("define")
           (match (● pending definition)
             ((Some definition)
              (Pair (list (lambda (cx) (define-top-level cx signatures env definition))) cx))
             (_ (panic "internal error: unparsed definition"))))
          (("expose") (Pair (list (lambda (cx) (add-item cx (expose-item cx env form)))) cx))
          (("expression")
           (compile-error (syntax-loc form)
                          "top-level expressions are not allowed; put runtime work in main"))
          (else (Pair (Nil) cx)))))

    ;; `(expose name "symbol")` exports a top-level function to the host;
    ;; `(expose name "symbol" dynamic)` exports it for programs that load it
    ;; while they run, through (snail shell wasm).

    (define (expose-item (cx Context) (env Env) (form Syntax)) (→ Item) (! compile)
      (match form
        ((Form (Cons _ (Cons name (Cons (Atom (DString symbol) _) flags))) loc)
         (match (resolve cx env (expect-ident name "a function name"))
           ((Some (Global global)) (Expose global symbol (dynamic-flag? form flags) loc))
           (_ (compile-error (syntax-loc name)
                             (string-append "only a top-level function can be exposed: "
                                            (Ident-name name))))))
        (_ (compile-error (syntax-loc form) expose-usage))))

    (define (dynamic-flag? (form Syntax) (flags (List Syntax))) (→ Bool) (! compile)
      (match flags
        ((Nil) #f)
        ((Cons (Ident "dynamic" _ _) (Nil)) #t)
        (_ (compile-error (syntax-loc form) expose-usage))))

    (define expose-usage
      (→ String)
      "expected (expose name \"symbol\") or (expose name \"symbol\" dynamic)")

    (define (define-top-level (cx Context)
              (signatures (Table (Pair Scheme (Option Loc))))
              (env Env)
              (definition Definition))
      (→ Context)
      (! compile)
      (let ((name (global-binding cx env (● definition name))))
        (check-signature cx (table-ref signatures name))
        (expanding cx ((value (definition-value env definition))
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

    (define (check-signature (cx Context) (signature (Option (Pair Scheme (Option Loc)))))
      (→ Unit)
      (! compile)
      (match signature
        ((Some (Pair scheme (Some loc)))
         (for-each (lambda (constraint) (check-constraint (● cx program) constraint loc))
                   (● scheme constraints)))
        (_ (unit))))

    (define (definition-value (cx Context) (env Env) (definition Definition))
      (→ (Pair Expr Context))
      (! compile)
      (let ((scope (definition-scope cx env definition)))
        (match (● definition parameters)
          ((Some parameters)
           (expand-lambda cx
                          scope
                          (map (lambda (record) (● record first)) parameters)
                          (● definition body)
                          #t
                          (● definition loc)))
          ((None) (expand-expr cx scope (list-ref (● definition body) 0))))))

    (define (annotated-definition-value (cx Context) (env Env) (definition Definition) (value Expr))
      (→ Expr)
      (! compile)
      (match (● (● definition header) result)
        ((None) value)
        ((Some _)
         (expr (Ann value (● (resolve-scheme cx env (definition-type definition)) type))
               (● definition loc)))))

    ;; No local is in scope where a top-level function is written, so it is
    ;; marked as one that may not capture, and every global function is
    ;; known to have no environment.

    (define (top-level-value (value Expr)) (→ Expr)
      (match (● value term)
        ((Lambda params body _) (Expr (Lambda params body #f) (● value type) (● value loc)))
        (_ value)))

    ;; ---- Declarations ----

    ;; Pass 1 binds the names a declaration introduces; pass 2 resolves types.

    (define (scan-declaration (cx Context) (env Env) (keyword String) (form Syntax))
      (→ Context)
      (! compile)
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

    (define (unique-name (cx Context) (ident Syntax)) (→ String)
      (global-name cx (ident-key ident)))

    ;; A struct's name is both its type and its constructor.

    (define (scan-struct (cx Context) (env Env) (head Syntax) (form Syntax)) (→ Context) (! compile)
      (let* ((name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (Some (unique-name cx name))))))
        (bind-fields cx env name (struct-fields form) #t)))

    (define (scan-enum (cx Context) (env Env) (head Syntax) (form Syntax)) (→ Context) (! compile)
      (let* ((name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (None)))))
        (fold-left (lambda (cx case) (scan-case cx env case)) cx (enum-cases form))))

    (define (scan-alias (cx Context) (env Env) (head Syntax) (rest (List Syntax)) (form Syntax))
      (→ Context)
      (! compile)
      (let ((name (declared-name head)))
        (match rest
          ((Cons body (Nil))
           (bind-top cx env name (Alias (unique-name cx name) (declared-params head) body env)))
          (_ (compile-error (syntax-loc form) "expected (type Name type)")))))

    ;; Register the complete class shape during scanning: signatures may
    ;; precede its declaration. Methods later establish which inputs are rows.

    (define (scan-class (cx Context) (env Env) (head Syntax) (declarations (List Syntax)))
      (→ Context)
      (! compile)
      (let* ((name (declared-name head)) (id (unique-name cx name))
             (outputs (map associated-name (filter associated-form? declarations)))
             (params (append (map Ident-name (declared-params head)) outputs))
             (cx (bind-top cx env name (ClassName id))))
        (unless (= (length params) (length (delete-duplicates string=? params)))
          (compile-error (syntax-loc head)
                         "class parameters and associated types must be distinct"))
        (fold-left (lambda (cx declaration) (scan-class-member cx env name declaration))
                   (Context-program-set cx
                                        (program-with-class (● cx program)
                                                            (Class id params (Nil) outputs (Nil))))
                   declarations)))

    (define (associated-form? (form Syntax)) (→ Bool)
      (match form
        ((Form (Cons (Ident "type" _ _) _) _) #t)
        (_ #f)))

    (define (associated-identifier (form Syntax)) (→ Syntax) (! compile)
      (match (● (split-annotations form 2) first)
        ((Form (Cons _ (Cons (Ident name mark loc) (Nil))) _) (Ident name mark loc))
        (_ (compile-error (syntax-loc form)
                          "expected (type Output); associated types take no parameters"))))

    (define (associated-name (form Syntax)) (→ String) (! compile)
      (Ident-name (associated-identifier form)))

    (define (scan-class-member (cx Context) (env Env) (class Syntax) (form Syntax))
      (→ Context)
      (! compile)
      (let* ((associated? (associated-form? form))
             (parsed (split-annotations form (if associated? 2 3)))
             (bare (● parsed first))
             (name (if associated?
                       (suffixed-ident class (string-append "." (associated-name bare))
                                       (syntax-loc bare))
                       (declared-name (declaration-head bare))))
             (cx (scan-class-member-form cx env class bare)))
        (with-name-annotations cx name (● parsed second))))

    (define (scan-class-member-form (cx Context) (env Env) (class Syntax) (form Syntax))
      (→ Context)
      (! compile)
      (if (associated-form? form)
          (let* ((member (associated-name form))
                 (name (suffixed-ident class (string-append "." member) (syntax-loc form))))
            (bind-top cx env name (Associated (unique-name cx class) member)))
          (match form
            ((Form (Cons (Ident ":" _ _) (Cons method (Cons _ (Nil)))) _)
             (bind-member cx env method))
            (_ (compile-error (syntax-loc form) "expected (: method type) or (type Output)")))))

    (define (scan-effect (cx Context) (env Env) (head Syntax) (rest (List Syntax)) (form Syntax))
      (→ Context)
      (! compile)
      (let* ((name (expect-ident head "an effect name"))
             (cx (bind-top cx env name (EffectName (unique-name cx name)))))
        (match rest
          ((Cons operations _)
           (fold-left (lambda (cx operation) (scan-operation cx env operation))
                      cx (form-items operations "a list of operations")))
          (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))")))))

    (define (operation-form-arity (operation Syntax)) (→ I64)
      (match operation
        ((Form (Cons (Ident "ctl" _ _) _) _) 3)
        (_ 2)))

    (define (scan-operation (cx Context) (env Env) (operation Syntax)) (→ Context) (! compile)
      (let* ((parsed (split-annotations operation (operation-form-arity operation)))
             (name (match (● parsed first)
                     ((Form (Cons (Ident "ctl" _ _) (Cons name (Cons _ (Nil)))) _) name)
                     ((Form (Cons name (Cons _ (Nil))) _) name)
                     (_ (compile-error (syntax-loc operation)
                                       "expected (operation type) or (ctl operation type)"))))
             (cx (bind-member cx env name)))
        (with-name-annotations cx name (● parsed second))))

    (define (bind-member (cx Context) (env Env) (ident Syntax)) (→ Context) (! compile)
      (let ((ident (expect-ident ident "a name")))
        (bind-top cx env ident (Global (unique-name cx ident)))))

    (struct CaseSyntax
      ((name Syntax)
       (fields (List Syntax))
       (annotations (List Annotation))))

    (define (parse-case (case Syntax)) (→ CaseSyntax) (! compile)
      (let ((parsed (split-annotations case 1)))
        (match (● parsed first)
          ((Form (Cons name (Nil)) _)
           (CaseSyntax (expect-ident name "a case name") (Nil) (● parsed second)))
          ((Form (Cons name (Cons fields (Nil))) _)
           (CaseSyntax (expect-ident name "a case name")
                       (form-items fields "a field list") (● parsed second)))
          (_ (compile-error (syntax-loc case)
                            "expected (Case), or (Case ((field type) ...)), optionally with (annotations ...)")))))

    (define (scan-case (cx Context) (env Env) (case Syntax)) (→ Context) (! compile)
      (let* ((parsed (parse-case case)) (name (● parsed name))
             (cx (bind-member cx env name))
             (cx (bind-fields cx env name (● parsed fields) #f)))
        (with-name-annotations cx name (● parsed annotations))))

    ;; A field is `(name type)`, optionally followed by annotations.
    ;; All fields are mutable; there is no second field grammar.
    (struct FieldSyntax
      ((name Syntax)
       (type Syntax)
       (annotations (List Annotation))))

    (define (parse-field (field Syntax)) (→ FieldSyntax) (! compile)
      (let ((parsed (split-annotations field 2)))
        (match (● parsed first)
          ((Form (Cons name (Cons type (Nil))) _)
           (FieldSyntax name type (● parsed second)))
          (_ (compile-error (syntax-loc field)
                            "expected (field type), optionally with (annotations ...)")))))

    ;; A field's generated names, by `field-suffixes`; a struct's
    ;; accessor name is reserved instead of bound.

    (define (bind-fields (cx Context) (env Env) (name Syntax) (fields (List Syntax)) (struct? Bool))
      (→ Context)
      (! compile)
      (let ((parsed (map parse-field fields)))
        (fold-left (lambda (cx field)
                     (let ((cx (Context-program-set cx
                                                    (program-with-field-annotations
                                                     (● cx program)
                                                     (unique-name cx name)
                                                     (Ident-name
                                                      (expect-ident (● field name)
                                                                    "a field name"))
                                                     (● field annotations)))))
                       (fold-left (lambda (cx suffix)
                                    (bind-member cx
                                                 env
                                                 (field-ident name
                                                              (● field name)
                                                              suffix)))
                                  (if struct? (reserve-field-read cx env name field) cx)
                                  (field-suffixes struct?))))
                   cx parsed)))

    ;; A struct's field is read by path, but its accessor still exists
    ;; in the program under `Name-field` for the checker's resolved call,
    ;; so that name is bound as syntax that refuses use: a read
    ;; through it says to use the path, and a definition of it is a
    ;; duplicate rather than a silent replacement of the accessor.

    (define (reserve-field-read (cx Context) (env Env) (name Syntax) (field FieldSyntax))
      (→ Context)
      (! compile)
      (bind-top cx env (field-ident name (● field name) "") (Core "field-read")))

    (define field-read-message (→ String)
      "a struct's field is read by path, (● s field), not through an accessor")



    ;; Every field has a setter and swapper. Struct reads use nominal paths
    ;; and offer pure replacement; enum reads name their partial case accessor.
    (define (field-suffixes (struct? Bool)) (→ (List String))
      (if struct? (list "-set" "-set!" "-replace!") (list "" "-set!" "-replace!")))

    ;; A field identifier shares the mark of its type's name, so a struct a
    ;; macro introduces has accessors only that expansion sees.

    (define (field-ident (name Syntax) (field Syntax) (suffix String)) (→ Syntax) (! compile)
      (suffixed-ident name
                      (string-append "-" (Ident-name (expect-ident field "a field name")) suffix)
                      (syntax-loc field)))

    ;; Generated accessors and projections inherit their declaring name's mark.

    (define (suffixed-ident (name Syntax) (text String) (loc Loc)) (→ Syntax)
      (Ident (string-append (Ident-name name) text)
             (match (Ident-mark name)
               ((Some mark)
                (Some (Mark (string-append (● mark key) text)
                            (● mark original)
                            (● mark scope))))
               ((None) (None))) loc))

    (define (declared-name (head Syntax)) (→ Syntax) (! compile)
      (match head
        ((Form (Cons name _) _) (expect-ident name "a type name"))
        (_ (expect-ident head "a type name"))))

    (define (declared-params (head Syntax)) (→ (List Syntax)) (! compile)
      (match head
        ((Form (Cons _ params) _)
         (map (lambda (param) (expect-ident param "a type parameter")) params))
        (_ (Nil))))

    ;; A struct or enum may end with `(deriving Class ...)`.

    (define (deriving-clause? (syntax Syntax)) (→ Bool)
      (match syntax
        ((Form (Cons (Ident "deriving" _ _) _) _) #t)
        (_ #f)))

    ;; The declaration's items after its head, without deriving clauses.

    (define (declaration-body (form Syntax)) (→ (List Syntax))
      (match (form-tail form)
        ((Cons _ rest) (filter (lambda (item) (not (deriving-clause? item))) rest))
        ((Nil) (Nil))))

    (define (declaration-head (form Syntax)) (→ Syntax) (! compile)
      (match (form-tail form)
        ((Cons head _) head)
        ((Nil) (compile-error (syntax-loc form) "expected a declared name"))))

    (define (struct-fields (form Syntax)) (→ (List Syntax)) (! compile)
      (match (declaration-body form)
        ((Nil) (Nil))
        ((Cons fields (Nil)) (form-items fields "a field list"))
        (_ (compile-error (syntax-loc form) "expected (struct Name ((field type) ...))"))))

    (define (enum-cases (form Syntax)) (→ (List Syntax))
      (declaration-body form))

    (define (derived-classes (form Syntax)) (→ (List Syntax))
      (concatenate (map form-tail (filter deriving-clause? (form-tail form)))))

    ;; `(deriving Move)` derives no instance: it makes the type linear by
    ;; its declaration (`owned?`).

    (define (move-class? (class Syntax)) (→ Bool)
      (match class
        ((Ident "Move" _ _) #t)
        (_ #f)))

    (define (derived-instance-classes (form Syntax)) (→ (List Syntax))
      (filter (lambda (class) (not (move-class? class))) (derived-classes form)))

    ;; A type parameter scope binds each parameter to a rigid variable.

    (define (type-scope (env Env) (params (List Syntax))) (→ Env)
      (fold-left (lambda (scope param) (extend scope param (TypeVar (TRigid (Ident-name param)))))
                 env
                 params))

    ;; A case is its name followed by an optional field list; a struct is one
    ;; case named after the struct.

    (define (declare-data (cx Context) (env Env) (form Syntax) (enum? Bool)) (→ Context) (! compile)
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
                                        (program-with-type (● cx program) data)
                                        (● data cases)))))

    (define (resolve-case (cx Context) (scope Env) (case CaseSyntax) (type String) (tag I64))
      (→ Case)
      (! compile)
      (Case (constructor-name cx scope (● case name)) type tag
            (map (lambda (field) (resolve-field cx scope field)) (● case fields))))

    (define (resolve-field (cx Context) (scope Env) (field Syntax)) (→ Field) (! compile)
      (let ((parsed (parse-field field)))
        (Field (Ident-name (expect-ident (● parsed name) "a field name"))
               (resolve-type cx scope (● parsed type)))))





    (define (constructor-name (cx Context) (env Env) (ident Syntax)) (→ String) (! compile)
      (match (resolve cx env ident)
        ((Some (Global name)) name)
        ((Some (TypeName _ _ (Some constructor))) constructor)
        (_ (compile-error (syntax-loc ident)
                          (string-append "not a constructor: " (Ident-name ident))))))

    ;; Construction and field reads are pure. Setters and swappers perform
    ;; mut; ownership decides whether overwritten content may be released.
    (define (with-case-values (program Program) (data DataType) (case Case) (struct? Bool))
      (→ Program)
      (let* ((params (● data params)) (self (TCon (● data name) (map TRigid params)))
             (constructor (Constructor case
                                       (Scheme params
                                               (Nil)
                                               (Nil)
                                               (TFun (map (lambda (record) (● record type))
                                                          (● case fields))
                                                     self
                                                     empty-row)))))
        (fold-left (lambda (program indexed)
                     (with-field-values program
                                        data
                                        case
                                        (● indexed first)
                                        (● indexed second)
                                        struct?))
                   (program-with-value program (● case name) constructor)
                   (zip (iota (length (● case fields))) (● case fields)))))

    (define (with-field-values (program Program) (data DataType) (case Case)
                               (index I64) (field Field) (struct? Bool))
      (→ Program)
      (let* ((params (● data params)) (self (TCon (● data name) (map TRigid params)))
             (type (● field type)) (name (string-append (● case name) "-" (● field name)))
             (program (program-with-value program name
                                          (Accessor case
                                                    index
                                                    (field-scheme params
                                                                  (list self)
                                                                  type
                                                                  empty-row))))
             (program (if struct?
                          (program-with-value program (string-append name "-set")
                                              (Replacer case
                                                        index
                                                        (field-scheme params
                                                                      (list self type)
                                                                      self
                                                                      empty-row)))
                          program)))
        (program-with-value
         (program-with-value program (string-append name "-set!")
                             (Setter case
                                     index
                                     (field-scheme params
                                                   (list self type)
                                                   (TCon "Unit" (Nil))
                                                   mut-row)))
         (string-append name "-replace!")
         (Swapper case index (field-scheme params (list self type) type mut-row)))))

    (define (field-scheme (params (List String)) (arguments (List Type)) (result Type) (row Type))
      (→ Scheme)
      (Scheme params (Nil) (Nil) (TFun arguments result row)))

    ;; The signatures with the one a `(: name type)` declares, and where it
    ;; was written. A signature a macro writes is held to each expansion's
    ;; body like any other, so a macro that cannot know the row takes it as
    ;; an argument.

    (define (with-signature (cx Context)
                            (signatures (Table (Pair Scheme (Option Loc))))
                            (pending Pending))
      (→ (Table (Pair Scheme (Option Loc))))
      (! compile)
      (match (● pending definition)
        ((Some definition)
         (match (● (● definition header) result)
           ((None) signatures)
           ((Some _)
            (add-signature cx signatures (● pending env) (● definition name)
                           (definition-type definition) (● definition loc)))))
        ((None)
         (if (string=? (● pending keyword) ":")
             (match (● pending form)
               ((Form (Cons _ (Cons name (Cons type (Nil)))) loc)
                (add-signature cx signatures (● pending env) name type loc))
               (form (compile-error (syntax-loc form) "expected (: name type)")))
             signatures))))

    (define (add-signature (cx Context)
                           (signatures (Table (Pair Scheme (Option Loc))))
                           (env Env)
                           (name Syntax)
                           (type Syntax)
                           (loc Loc))
      (→ (Table (Pair Scheme (Option Loc))))
      (! compile)
      (let ((global (global-binding cx env name)))
        (match (table-ref signatures global)
          ((Some _) (compile-error loc "a definition has only one type signature"))
          ((None)
           (table-set signatures global (Pair (resolve-scheme cx env type) (Some loc)))))))

    (define (declare-class (cx Context) (env Env) (form Syntax)) (→ Context) (! compile)
      (let* ((head (declaration-head form))
             (id (match (resolve cx env (declared-name head))
                   ((Some (ClassName id)) id)
                   (_ (panic "internal error: class"))))
             (class (program-class (● cx program) id))
             (params (append (declared-params head)
                             (map associated-identifier
                                  (filter associated-form? (list-drop (form-tail form) 1)))))
             (self (Constraint id (map (lambda (param) (TRigid (Ident-name param))) params)))
             (scope (EvidenceScope (list self) (type-scope env params))))
        (expanding cx ((methods (each (lambda (cx signature)
                                        (declare-method cx env scope id params self signature))
                                      (filter (lambda (form) (not (associated-form? form)))
                                              (list-drop (form-tail form) 1)))))
                   (let ((rows (class-rows (● cx program) (● class params) methods
                                           (syntax-loc form))))
                     (when (any? (lambda (output) (member? output rows)) (● class outputs))
                       (compile-error (syntax-loc form)
                                      "an associated type must have kind Type, not an effect row"))
                     (Context-program-set cx
                                          (program-with-class (● cx program)
                                                              (Class id (● class params) rows
                                                                     (● class outputs)
                                                                     methods)))))))

    ;; The parameters the class's methods perform as rows, `e` in
    ;; `(: fetch-object (Fn S String → String ! e))`, in order; a row's kind
    ;; is found from its use, as quantified variables are. A parameter a
    ;; method also writes as a type could not be both.

    (define (class-rows (program Program) (params (List String)) (methods (List String)) (loc Loc))
      (→ (List String))
      (! compile)
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

    (define (method-type (program Program) (method String)) (→ Type)
      (match (program-value program method)
        ((Some (Method _ scheme)) (● scheme type))
        (_ (panic "internal error: not a method"))))

    ;; The variables a type ends a row with, and those it writes as types.

    (define (row-names (type Type)) (→ (List String))
      (match type
        ((TFun params result row)
         (append (concatenate (map row-names params)) (append (row-names result) (row-names row))))
        ((TCon _ args) (concatenate (map row-names args)))
        ((TRow _ (Some (TRigid name))) (list name))
        ((TRow _ (Some tail)) (row-names tail))
        (_ (Nil))))

    (define (type-names (type Type)) (→ (List String))
      (match type
        ((TRigid name) (list name))
        ((TFun params result _) (append (concatenate (map type-names params)) (type-names result)))
        ((TCon _ args) (concatenate (map type-names args)))
        (_ (Nil))))

    (define (declare-method (cx Context)
                            (env Env)
                            (scope Env)
                            (class String)
                            (params (List Syntax))
                            (self Constraint)
                            (signature Syntax))
      (→ (Pair String Context))
      (! compile)
      (match (● (split-annotations signature 3) first)
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (let ((own (operational-scheme (resolve-scheme cx scope type)))
               (global (global-binding cx env name)))
           (Pair global
                 (add-value cx global
                            (Method class
                                    (Scheme (append (map Ident-name params) (● own vars))
                                            (Cons self (● own constraints))
                                            (● own copy)
                                            (● own type)))))))
        (_ (compile-error (syntax-loc signature) "expected (: method type)"))))

    ;; Returns one step per method, which expands its definition.

    (define (declare-instance (cx Context) (env Env) (form Syntax))
      (→ (Pair (List (Fn Context → Context ! compile)) Context))
      (! compile)
      (match form
        ((Form (Cons _ (Cons (Form (Cons class-ident type-args) _) body)) loc)
         (let ((parts (split-requires body)))
           (expanding cx ((class (instance-class env class-ident))
                          (instance (declared-instance env class type-args (● parts first)
                                                       (filter associated-form? (● parts second))
                                                       loc))
                          (methods
                           (declare-instance-methods env class instance
                                                     (filter
                                                      (lambda (form) (not (associated-form? form)))
                                                      (● parts second)) loc)))
                      (check-instance-methods class methods loc)
                      (check-overlap (● cx program) instance loc)
                      (Pair (map (lambda (record) (● record expand)) methods)
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

    (define (declare-dynamic-instances (cx Context) (env Env) (form Syntax))
      (→ (Pair (List (Fn Context → Context ! compile)) Context))
      (! compile)
      (match (Pair (form-tail form) (instance-owner env))
        ((Pair (Cons name domain) (Some owner))
         (expanding cx ((class (instance-class env name))
                        (id (fresh-global "dynamic")))
                    (let ((generated (generate-binary-instances
                                      (● cx program) class
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

    (define (install-generated-instance (cx Context)
                                        (class Class)
                                        (generated GeneratedInstance)
                                        (loc Loc))
      (→ (Pair (List (Fn Context → Context ! compile)) Context))
      (! compile)
      (let* ((instance (● generated instance))
             (cx (fold-left (lambda (cx method)
                              (add-value cx (● method second)
                                         (Defined (Some (instance-method-scheme (● cx program)
                                                                                class
                                                                                (● method first)
                                                                                instance))
                                           (None) #t)))
                            cx (● instance methods))))
        (check-overlap (● cx program) instance loc)
        (Pair (map (lambda (definition) (lambda (cx) (add-item cx definition)))
                   (● generated definitions))
              (Context-program-set cx
                                   (program-with-instance (instance-program cx class instance loc)
                                                          instance)))))

    (define (instance-class (cx Context) (env Env) (class-ident Syntax))
      (→ (Pair Class Context)) (! compile)
      (match (resolve cx env class-ident)
        ((Some (ClassName id))


         (Pair (program-class (● cx program) id) cx))
        (_ (compile-error (syntax-loc class-ident)
                          "instance of something that is not a typeclass"))))

    ;; A dispatch clause supplies ordinary methods, just as explicit
    ;; definitions do. Its finite domain belongs to this instance's library;
    ;; importing another instance never changes which payloads it accepts.

    (define (declare-instance-methods (cx Context)
                                      (env Env)
                                      (class Class)
                                      (instance Instance)
                                      (body (List Syntax))
                                      (loc Loc))
      (→ (Pair (List MethodDefinition) Context))
      (! compile)
      (match body
        ((Cons (Form (Cons (Ident "dispatch" _ _) types) _) (Nil))
         (let ((dispatch (parse-dispatch class instance
                                         (map (lambda (type) (resolve-type cx env type)) types)
                                         loc)))
           (each cx
                 (lambda (cx method)
                   (dispatch-instance-method cx class instance method dispatch loc))
                 (● class methods))))
        (_ (each cx
                 (lambda (cx definition) (instance-method cx env class instance definition))
                 body))))

    (define (dispatch-instance-method (cx Context)
                                      (class Class)
                                      (instance Instance)
                                      (method String)
                                      (dispatch Dispatch)
                                      (loc Loc))
      (→ (Pair MethodDefinition Context))
      (expanding cx ((global (fresh-global (short-name method)))
                     (then (add-value global
                                      (Defined (Some (instance-method-scheme (● cx program)
                                                                             class method instance))
                                        (None) #t))))
                 (Pair (MethodDefinition method global
                                         (lambda (cx)
                                           (add-item cx
                                                     (Define global
                                                       (dispatch-method (● cx program)
                                                                        class
                                                                        instance
                                                                        method dispatch loc)))))
                       cx)))

    ;; The program after an instance's checks of its head, with a Drop
    ;; instance's type made linear; any other instance changes nothing.

    (define (instance-program (cx Context) (class Class) (instance Instance) (loc Loc))
      (→ Program)
      (! compile)
      (let ((name (● class name)))
        (unless (= (length (● instance types)) (length (● class params)))
          (compile-error loc
                         (string-append (instance-noun name)
                                        " gives each of the class's parameters, as in ("
                                        (string-join (Cons (short-name name) (● class params))
                                                     " ")
                                        ")")))
        (when (and (lifecycle-class? name)
                   (match (● instance set) ((Some _) #t) ((None) #f)))
          (compile-error loc "lifecycle instances cannot belong to a named instance set"))
        (check-instance-determination (● cx program) class instance loc)
        (check-head-rows (● cx program) class instance loc)
        (if (lifecycle-class? name) (lifecycle-program cx instance loc) (● cx program))))

    ;; Prerequisites are ordered. Inputs bind variables first; only an
    ;; earlier requirement's row or output may determine another variable.
    ;; An expected result can never make an otherwise unknown input known.

    (define (check-instance-determination (program Program)
                                          (class Class)
                                          (instance Instance)
                                          (loc Loc))
      (→ Unit)
      (! compile)
      (unless (null? (● class outputs))
        (let* ((inputs
                (concatenate (map type-names (type-arguments class (● instance types)))))
               (known (fold-left (lambda (known requirement)
                                   (determined-requirement program known requirement loc))
                                 inputs (● instance requires)))
               (needed
                (concatenate (map type-names (output-arguments class (● instance types)))))
               (rows
                (concatenate (map row-variable (row-arguments class (● instance types))))))
          (unless (every? (lambda (name) (member? name known)) (append needed rows))
            (compile-error loc
                           "instance outputs must be determined by its inputs and earlier requirements"))
          (when (any? (lambda (name) (member? name rows)) needed)
            (compile-error loc "an associated output cannot use an effect row as a type")))))

    (define (determined-requirement (program Program)
                                    (known (List String))
                                    (requirement Constraint)
                                    (loc Loc))
      (→ (List String))
      (! compile)
      (let* ((class (program-class program (● requirement class)))
             (types (● requirement types))
             (inputs (concatenate (map type-names (type-arguments class types)))))
        (unless (every? (lambda (name) (member? name known)) inputs)
          (compile-error loc "a prerequisite input must be determined before that prerequisite"))
        (append known (concatenate (map type-names
                                        (append (output-arguments class types)
                                                (row-arguments class types)))))))

    ;; A lifecycle instance is for a declared type, beside it; a Drop
    ;; instance's type is linear.

    (define (lifecycle-program (cx Context) (instance Instance) (loc Loc)) (→ Program) (! compile)
      (let ((program (● cx program)) (class (● instance class)))
        (match (● instance types)
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

    (define (check-head-rows (program Program) (class Class) (instance Instance) (loc Loc))
      (→ Unit)
      (! compile)
      (for-each (lambda (argument)
                  (check-head-argument program
                                       class
                                       (● argument first)
                                       (● argument second)
                                       loc))
                (zip (● class params) (● instance types)))
      (cond ((lifecycle-class? (● class name))
             (check-lifecycle-requirements (● class name) instance (head-tail instance) loc))
            ((not (null? (● class rows))) (check-row-requirements program class instance loc))
            (else (unit))))

    (define (check-head-argument (program Program)
                                 (class Class)
                                 (param String)
                                 (argument Type)
                                 (loc Loc))
      (→ Unit)
      (! compile)
      (match argument
        ((TRow labels _)
         (unless (member? param (● class rows))
           (compile-error loc
                          (string-append (instance-noun (● class name))
                                         " gives its type parameter "
                                         param
                                         " a row, not a type")))
         (for-each (lambda (label) (check-head-label program (● class name) label loc))
                   labels))
        (_ (when (member? param (● class rows))
             (compile-error loc (row-usage (● class name)))))))

    (define (check-head-label (program Program) (class String) (label String) (loc Loc))
      (→ Unit)
      (! compile)
      (match (table-ref (● program effects) label)
        ((Some effect)
         (when (and (lifecycle-class? class) (not (null? (● effect control))))
           (compile-error loc
                          (string-append (cond ((string=? class drop-class) "a drop")
                                               ((string=? class clone-class) "a clone")
                                               (else (instance-noun class)))
                                         " cannot perform the control effect "
                                         (short-name label)))))
        ((None) (unit))))

    ;; The tail of a lifecycle instance's row, its first argument.

    (define (head-tail (instance Instance)) (→ (Option Type))
      (match (● instance types)
        ((Cons (TRow _ tail) _) tail)
        (_ (None))))

    ;; A row class's instance ends its rows with variables its requirements
    ;; of row classes give their rows, and those requirements give theirs
    ;; no other variable: the types they are given then decide what the
    ;; rows hold. A requirement may give a closed row instead, as
    ;; `(Store (!) S)`, which bounds what its types may perform.

    (define (check-row-requirements (program Program) (class Class) (instance Instance) (loc Loc))
      (→ Unit)
      (! compile)
      (let ((tails (concatenate (map row-variable (row-arguments class (● instance types)))))
            (required (concatenate (map (lambda (constraint)
                                          (requirement-row-variables program constraint))
                                        (● instance requires)))))
        (unless (and (every? (lambda (row) (any? (lambda (tail) (rigid-named? row tail)) tails))
                             required)
                     (every? (lambda (tail) (any? (lambda (row) (rigid-named? row tail)) required))
                             tails))
          (compile-error loc (row-usage (● class name))))))

    ;; The variables a requirement gives its class's row parameters, where
    ;; it gives a variable rather than a closed row.

    (define (requirement-row-variables (program Program) (constraint Constraint)) (→ (List Type))
      (filter (lambda (row)
                (match row
                  ((TRigid _) #t)
                  (_ #f)))
              (row-arguments (program-class program (● constraint class))
                             (● constraint types))))

    (define (rigid-named? (type Type) (name String)) (→ Bool)
      (match type
        ((TRigid other) (string=? other name))
        (_ #f)))

    (define (row-usage (class String)) (→ String)
      (if (lifecycle-class? class)
          (lifecycle-row-usage class)
          (string-append (instance-noun class)
                         "'s rows are closed, (! label ...), or end with the row e its"
                         " requirements give a row class, as (! label ... e) with (⊨ ("
                         (short-name class)
                         " e A))")))

    ;; Each requirement runs the class's method at one of the instance's
    ;; variables in the row its head ends with, so one row holds what all
    ;; of them perform; without one, the row is closed.

    (define (check-lifecycle-requirements (class String)
                                          (instance Instance)
                                          (tail (Option Type))
                                          (loc Loc))
      (→ Unit)
      (! compile)
      (let ((required (● instance requires)))
        (for-each (lambda (constraint)
                    (unless (string=? (● constraint class) class)
                      (compile-error loc
                                     (string-append (instance-noun class)
                                                    " can require only (Copy A) and ("
                                                    (short-name class)
                                                    " e A)")))
                    (match (Pair tail (● constraint types))
                      ((Pair (Some (TRigid name)) (Cons (TRigid row) (Cons (TRigid var) (Nil))))
                       (unless (and (string=? name row) (member? var (● instance vars)))
                         (compile-error loc (lifecycle-row-usage class))))
                      (_ (compile-error loc (lifecycle-row-usage class)))))
                  required)
        (match (Pair tail required)
          ((Pair (Some _) (Nil)) (compile-error loc (lifecycle-row-usage class)))
          (_ (unit)))))

    (define (lifecycle-row-usage (class String)) (→ String)
      (string-append (instance-noun class)
                     "'s row is closed, (! label ...), or ends with the row e of its requirements ("
                     (short-name class)
                     " e A), as (! label ... e)"))

    (define (instance-noun (class String)) (→ String)
      (string-append "a " (short-name class) " instance"))

    ;; It is declared beside its type, for the type at distinct variables,
    ;; so a type has one of each class, which its name finds, and its
    ;; library alone may take the type's values apart when it has a Drop
    ;; instance.

    (define (check-lifecycle-head (cx Context)
                                  (class String)
                                  (name String)
                                  (args (List Type))
                                  (loc Loc))
      (→ Unit)
      (! compile)
      (unless (string=? (name-owner name) (● cx prefix))
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

    (define (instance-with-methods (instance Instance) (methods (List MethodDefinition)))
      (→ Instance)
      (Instance-methods-set instance
                            (map (lambda (method)
                                   (Pair (● method method)
                                         (● method global)))
                                 methods)))

    ;; Unbound identifiers in an instance head are its type variables.

    (define (declared-instance (cx Context)
                               (env Env)
                               (class Class)
                               (type-args (List Syntax))
                               (requires (List Syntax))
                               (equations (List Syntax))
                               (loc Loc))
      (→ (Pair Instance Context))
      (! compile)
      (let* ((vars (delete-duplicates string=?
                                      (concatenate
                                       (map (lambda (type) (free-type-names cx env type))
                                            type-args))))
             (scope (type-scope env (map (lambda (name) (Ident name (None) loc)) vars)))
             (requirements (resolve-requirements cx scope vars requires))
             (types (map (lambda (type) (resolve-type cx (● requirements env) type))
                         type-args))
             (outputs (instance-outputs cx (● requirements env) class equations loc)))
        (when (and (not (null? (● class outputs)))
                   (not (= (length types)
                           (- (length (● class params)) (length (● class outputs))))))
          (compile-error loc
                         "instance head gives each declared class parameter; associated types belong in its body"))
        (expanding cx ((name (fresh-global (short-name (● class name)))))
                   (Pair (Instance name (● class name) (● requirements vars)
                                   (append types outputs) (● requirements constraints)
                                   (● requirements copy) (Nil) (instance-owner env))
                         cx))))

    (define (instance-outputs (cx Context)
                              (env Env)
                              (class Class)
                              (equations (List Syntax))
                              (loc Loc))
      (→ (List Type))
      (! compile)
      (let ((definitions (map associated-equation equations)))
        (unless (and (= (length definitions) (length (● class outputs)))
                     (= (length definitions)
                        (length (delete-duplicates string=?
                                                   (map (lambda (record) (● record first))
                                                        definitions))))
                     (every? (lambda (entry) (member? (● entry first) (● class outputs)))
                             definitions))
          (compile-error loc "an instance defines each associated type exactly once"))
        (map (lambda (name)
               (match (assoc-ref definitions name)
                 ((Some type) (resolve-type cx env type))
                 ((None) (compile-error loc (string-append "missing associated type " name)))))
             (● class outputs))))

    (define (associated-equation (syntax Syntax)) (→ (Pair String Syntax)) (! compile)
      (match syntax
        ((Form (Cons _ (Cons (Ident name _ _) (Cons type (Nil)))) _) (Pair name type))
        (_ (compile-error (syntax-loc syntax) "expected (type Output Type)"))))

    (define (fresh-global (cx Context) (base String)) (→ (Pair String Context))
      (expanding cx ((name (fresh base)))
                 (Pair (global-name cx name) cx)))

    ;; A body may start with `(⊨ (Class type ...) ...)`.

    (define (split-requires (items (List Syntax))) (→ (Pair (List Syntax) (List Syntax)))
      (match items
        ((Cons (Form (Cons (Ident "⊨" _ _) constraints) _) rest) (Pair constraints rest))
        (_ (Pair (Nil) items))))

    ;; One method of an instance: the class method it implements, the global
    ;; that holds its definition, and the step that expands it.
    (struct MethodDefinition
      ((method String)
       (global String)
       (expand (Fn Context → Context ! compile))))

    (define (instance-method (cx Context)
                             (env Env)
                             (class Class)
                             (instance Instance)
                             (definition Syntax))
      (→ (Pair MethodDefinition Context))
      (! compile)
      (unless (core-form? cx env definition "define")
        (compile-error (syntax-loc definition) "expected a method definition"))
      (let* ((parsed (parse-definition definition)) (ident (● parsed name))
             (method
              (match (find (lambda (method)
                             (string=? (short-name method)
                                       (Ident-name ident)))
                           (● class methods))
                ((Some method) method)
                ((None)
                 (compile-error (syntax-loc ident)
                                (string-append "not a method of this class: "
                                               (Ident-name ident)))))))
        (expanding cx ((global (fresh-global (short-name method)))
                       (then (add-value global
                                        (Defined (Some (instance-method-scheme (● cx program)
                                                                               class
                                                                               method
                                                                               instance))
                                          (None)
                                          #f))))
                   (Pair (MethodDefinition method global
                                           (lambda (cx)
                                             (expanding cx ((value
                                                             (definition-value env parsed)))
                                                        (add-item cx
                                                                  (Define global
                                                                    (top-level-value
                                                                     (annotated-definition-value cx
                                                                                                 env
                                                                                                 parsed
                                                                                                 value)))))))
                         cx))))

    (define (instance-method-scheme (program Program)
                                    (class Class)
                                    (method String)
                                    (instance Instance))
      (→ Scheme)
      (match (program-value program method)
        ((Some (Method _ (Scheme method-vars (Cons _ own) copy type)))
         (let* ((class-vars (● class params))
                (locals (rename-method-variables (list-drop method-vars (length class-vars))
                                                 (● instance vars)))
                (substitution (append (zip class-vars (● instance types))
                                      (map (lambda (binding)
                                             (Pair (● binding first)
                                                   (TRigid (● binding second))))
                                           locals))))
           (Scheme (append (● instance vars) (map (lambda (record) (● record second)) locals))
                   (append (● instance requires)
                           (map (lambda (c) (substitute-constraint substitution c)) own))
                   (append (● instance copy)
                           (map (lambda (name) (renamed-variable locals name)) copy))
                   (substitute substitution type))))
        (_ (panic "internal error: not a method"))))

    ;; An instance and a polymorphic method have separate quantifiers.
    ;; Fresh names keep their associated output slots separate when those
    ;; schemes are combined for the implementation; argument order stays fixed.

    (define (rename-method-variables (vars (List String)) (taken (List String)))
      (→ (List (Pair String String)))
      (match vars
        ((Nil) (Nil))
        ((Cons var rest)
         (let ((name (fresh-type-variable (string-append "$method." var) taken)))
           (Cons (Pair var name) (rename-method-variables rest (Cons name taken)))))))

    (define (fresh-type-variable (name String) (taken (List String))) (→ String)
      (if (member? name taken) (fresh-type-variable (string-append "$" name) taken) name))

    (define (renamed-variable (names (List (Pair String String))) (name String)) (→ String)
      (match (assoc-ref names name)
        ((Some renamed) renamed)
        ((None) name)))

    ;; Instance selection matches heads, so two heads may never both match
    ;; the same types. A type variable in either head matches anything.

    (define (check-overlap (program Program) (instance Instance) (loc Loc)) (→ Unit) (! compile)
      (check-instance-overlap
       program instance
       (filter (lambda (other)
                 (match (Pair (● instance set) (● other set))
                   ((Pair (None) (None)) #t)
                   ((Pair (Some name) (Some other)) (string=? name other))
                   (_ #f)))
               (class-instances program (● instance class))) loc))

    (define (check-instance-methods (class Class) (methods (List MethodDefinition)) (loc Loc))
      (→ Unit)
      (! compile)
      (for-each (lambda (method)
                  (unless (any? (lambda (definition)
                                  (string=? (● definition method) method))
                                methods)
                    (compile-error loc
                                   (string-append "instance is missing a method: "
                                                  (short-name method)))))
                (● class methods)))

    (define (free-type-names (cx Context) (env Env) (syntax Syntax)) (→ (List String))
      (match syntax
        ((Ident name _ _)
         (match (resolve cx env syntax)
           ((Some _) (Nil))
           ((None) (list name))))
        ((Form (Cons (Ident "!" _ _) labels) _)
         (concatenate (map (lambda (label) (free-type-names cx env label)) labels)))
        ((Form items _) (concatenate (map (lambda (item) (free-type-names cx env item)) items)))
        (_ (Nil))))

    (define (declare-extern (cx Context) (env Env) (form Syntax)) (→ Context) (! compile)
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

    (define (check-host-parameters (type Type) (loc Loc)) (→ Unit) (! compile)
      (match type
        ((TFun params _ _)
         (unless (staged-last? params)
           (compile-error loc
                          "a host function can take a String or Bytes only as its last argument")))
        (_ (unit))))

    (define (staged-last? (params (List Type))) (→ Bool)
      (match params
        ((Cons param (Cons next rest))
         (and (not (buffer-type? param)) (staged-last? (Cons next rest))))
        (_ #t)))

    ;; Operations perform their effect. A `default` clause after them names
    ;; Snail Scheme implementations, whose definitions expand with the
    ;; library's bodies, in the steps this returns.

    (define (declare-effect (cx Context) (env Env) (form Syntax))
      (→ (Pair (List (Fn Context → Context ! compile)) Context))
      (! compile)
      (match form
        ((Form (Cons _ (Cons name (Cons operations clauses))) loc)
         (let ((id (match (resolve cx env name)
                     ((Some (EffectName id)) id)
                     (_ (panic "internal error: effect")))))
           (expanding cx ((declared
                           (each (lambda (cx operation) (declare-operation cx env id operation))
                                 (form-items operations "a list of operations"))))
                      (let ((operations (map (lambda (record) (● record first)) declared))
                            (control (map (lambda (record) (● record first))
                                          (filter (lambda (record) (● record second)) declared))))
                        (expanding cx ((snail (snail-defaults env
                                                              operations
                                                              control
                                                              (default-clauses clauses))))
                                   (let ((effect (Effect id
                                                         operations
                                                         control
                                                         (effect-defaults snail loc)
                                                         (around-main? clauses))))
                                     (Pair (map (lambda (record) (● record expand)) snail)
                                           (Context-program-set cx
                                                                (program-with-effect
                                                                 (● cx program)
                                                                 effect)))))))))
        (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))"))))

    ;; `(name type)` declares an operation whose implementation returns to
    ;; its caller, `(ctl name type)` one whose implementation is handed the
    ;; rest of the handled computation as `resume`. The global name, and
    ;; whether it is a control operation.

    (define (declare-operation (cx Context) (env Env) (effect String) (operation Syntax))
      (→ (Pair (Pair String Bool) Context))
      (! compile)
      (match (● (split-annotations operation (operation-form-arity operation)) first)
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

    (define (declare-operation-type (cx Context)
                                    (env Env)
                                    (effect String)
                                    (name Syntax)
                                    (type Syntax)
                                    (control? Bool))
      (→ (Pair (Pair String Bool) Context))
      (! compile)
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

    (define (default-clauses (clauses (List Syntax))) (→ (List Syntax)) (! compile)
      (filter (lambda (clause)
                (match clause
                  ((Form (Cons (Ident "default" _ _) _) _) #t)
                  ((Form (Cons (Ident "around-main" _ _) (Nil)) _) #f)
                  (_ (compile-error (syntax-loc clause)
                                    "expected a default clause or (around-main)"))))
              clauses))

    (define (around-main? (clauses (List Syntax))) (→ Bool)
      (any? (lambda (clause)
              (match clause
                ((Form (Cons (Ident "around-main" _ _) (Nil)) _) #t)
                (_ #f)))
            clauses))

    ;; Every default the clauses give, at most one per operation.

    (define (effect-defaults (snail (List DefaultDefinition)) (loc Loc))
      (→ (List (Pair String String)))
      (! compile)
      (let ((defaults (map (lambda (d)
                             (Pair (● d operation) (● d global)))
                           snail)))
        (unless (= (length
                    (delete-duplicates string=? (map (lambda (record) (● record first)) defaults)))
                   (length defaults))
          (compile-error loc "an operation has at most one default"))
        defaults))

    ;; One Snail Scheme default: its operation, the global that holds its
    ;; definition, and the step that expands it.
    (struct DefaultDefinition
      ((operation String)
       (global String)
       (expand (Fn Context → Context ! compile))))

    ;; `(default ((operation implementation) ...))` defines each
    ;; implementation as a function of this library whose type is its
    ;; operation's, latent row included, as an instance method has its
    ;; class method's. Its entry is its signature, so the unused-effect
    ;; rule holds it to that row, which every performer is charged. A
    ;; control operation has none: no handler is in scope where a default
    ;; runs, to be handed the rest of the computation.

    (define (snail-defaults (cx Context)
                            (env Env)
                            (operations (List String))
                            (control (List String))
                            (clauses (List Syntax)))
      (→ (Pair (List DefaultDefinition) Context))
      (! compile)
      (each cx
            (lambda (cx entry) (snail-default cx env operations control entry))
            (concatenate (map default-entries clauses))))

    (define (default-entries (clause Syntax)) (→ (List Syntax)) (! compile)
      (match clause
        ((Form (Cons _ (Cons (Form entries _) (Nil))) _) entries)
        (_ (compile-error (syntax-loc clause)
                          "expected (default ((operation implementation) ...))"))))

    (define (snail-default (cx Context)
                           (env Env)
                           (operations (List String))
                           (control (List String))
                           (entry Syntax))
      (→ (Pair DefaultDefinition Context))
      (! compile)
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

    (define (default-scheme (cx Context) (operation String) (loc Loc)) (→ Scheme) (! compile)
      (match (program-value (● cx program) operation)
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

    (define (expand-default (cx Context)
                            (env Env)
                            (global String)
                            (operation String)
                            (syntax Syntax)
                            (loc Loc))
      (→ Context)
      (! compile)
      (expanding cx ((value (expand-expr env syntax)))
                 (match (● value term)
                   ((Lambda _ _ _) (add-item cx (Define global (top-level-value value))))
                   ((Var _ _ _)
                    (expanding cx ((value (eta-expand value (operation-arity cx operation) loc)))
                               (add-item cx (Define global value))))
                   (_ (compile-error loc "a default is a lambda or the name of a function")))))

    (define (eta-expand (cx Context) (function Expr) (arity I64) (loc Loc)) (→ (Pair Expr Context))
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

    (define (operation-arity (cx Context) (operation String)) (→ I64)
      (match (program-value (● cx program) operation)
        ((Some (Operation _ (Scheme _ _ _ (TFun params _ _)))) (length params))
        (_ (panic "internal error: not an operation"))))

    ;; ---- Primitives ----

    ;; (snail core primitive) is a library file like any other, whose body
    ;; holds only primitive declarations. `(primitive name type)` declares an
    ;; operation the backend implements, as `extern` declares a foreign
    ;; function: it binds `name` to the global `prim:name`, the name the
    ;; checker, mono and `emit-primitive` know it by, and the value there is
    ;; a Primitive of the type's scheme. Elsewhere the form is an error.

    (define (primitive-library? (cx Context)) (→ Bool)
      (string=? (● cx prefix) "snail.core.primitive"))

    (define (declare-primitive (cx Context) (env Env) (form Syntax)) (→ Context) (! compile)
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

    (define (resolve-primitive-scheme (cx Context) (env Env) (global String) (syntax Syntax))
      (→ Scheme) (! compile)
      (cond ((string=? global "prim:once")
             (let ((signature (TRigid "F")))
               (Scheme (list "F") (Nil) (Nil)
                       (TFun (list signature) (TCon "FnOnce" (list signature)) empty-row))))
            ((string=? global "prim:weak-rc-upgrade")
             (let ((value (TRigid "T")))
               (Scheme (list "T") (Nil) (Nil)
                       (TFun (list (TCon "WeakRc" (list value)))
                             (TCon "snail.core.base:Option" (list (TCon "Rc" (list value))))
                             mut-row))))
            (else (operational-scheme (resolve-scheme cx env syntax)))))

    ;; ---- Types ----

    ;; Requirements bind hidden output variables and a projection scope.
    ;; No projection survives expansion: method and projection share the
    ;; same ordinary type argument of the same evidence requirement.
    (struct Requirements
      ((constraints (List Constraint))
       (copy (List String))
       (vars (List String))
       (env Env)))

    (define (resolve-scheme (cx Context) (env Env) (syntax Syntax)) (→ Scheme) (! compile)
      (resolve-raw-scheme cx env syntax))

    ;; A primitive, method or operation describes executable code, rather
    ;; than introducing a source closure identity of its own.

    (define (operational-scheme (scheme Scheme)) (→ Scheme)
      (Scheme (● scheme vars) (● scheme constraints) (● scheme copy)
              (fn-arrow (● scheme type))))

    (define (resolve-raw-scheme (cx Context) (env Env) (syntax Syntax)) (→ Scheme) (! compile)
      (match syntax
        ((Form (Cons (Ident "∀" _ _) (Cons (Form params _) rest)) loc)
         (let* ((params (map (lambda (param) (expect-ident param "a type variable")) params))
                (vars (map Ident-name params)) (scope (type-scope env params))
                (parts (split-requires rest))
                (requirements (resolve-requirements cx scope vars (● parts first))))
           (match (● parts second)
             ((Cons type (Nil))
              (Scheme (● requirements vars) (● requirements constraints)
                      (● requirements copy)
                      (resolve-type cx (● requirements env) type)))
             (_ (compile-error loc
                               "expected (∀ (variable ...) [(⊨ constraint ...)] type)")))))
        (_ (mono-scheme (resolve-type cx env syntax)))))

    ;; Argument-position impl introduces a caller-chosen type and evidence.
    ;; The outer impl belongs to this definition; checking gives it the
    ;; definition's concrete identity. Results and storage use explicit dyn.







    (define (resolve-requirements (cx Context)
                                  (env Env)
                                  (vars (List String))
                                  (requirements (List Syntax)))
      (→ Requirements)
      (! compile)
      (fold-left (lambda (found requirement) (resolve-requirement cx found requirement))
                 (Requirements (Nil) (Nil) vars env) requirements))

    (define (resolve-requirement (cx Context) (found Requirements) (syntax Syntax))
      (→ Requirements)
      (! compile)
      (match syntax
        ((Form (Cons (Ident "Copy" _ _) args) loc)
         (Requirements-copy-set found
                                (append (● found copy)
                                        (list (copy-variable (● found vars) args loc)))))
        (_ (let* ((constraint (resolve-constraint cx (● found env) syntax
                                                  (length (● found constraints))))
                  (hidden (filter (lambda (name) (and (>= (string-length name) 12)
                                                      (string=? (substring name 0 12)
                                                                "$associated.")))
                                  (concatenate (map type-names (● constraint types))))))
             (Requirements (append (● found constraints) (list constraint))
                           (● found copy)
                           (delete-duplicates string=? (append (● found vars) hidden))
                           (EvidenceScope (list constraint) (● found env)))))))

    (define (copy-variable (vars (List String)) (args (List Syntax)) (loc Loc))
      (→ String)
      (! compile)
      (match args
        ((Cons (Ident name _ _) (Nil))
         (if (member? name vars)
             name
             (compile-error loc
                            (string-append "Copy names a quantified type variable, not " name))))
        (_ (compile-error loc "expected (Copy variable)"))))

    (define (resolve-constraint (cx Context) (env Env) (syntax Syntax) (index I64))
      (→ Constraint)
      (! compile)
      (match syntax
        ((Form (Cons class types) loc)
         (match (resolve cx env (expect-ident class "a typeclass"))
           ((Some (ClassName id))
            (checked-constraint cx env id types index loc))
           (_ (compile-error loc "expected a typeclass constraint"))))
        (_ (compile-error (syntax-loc syntax) "expected (Class type ...)"))))



    ;; The constraint of a class at resolved types, checked against the
    ;; class's parameters.

    (define (checked-constraint (cx Context)
                                (env Env)
                                (id String)
                                (arguments (List Syntax))
                                (index I64)
                                (loc Loc))
      (→ Constraint)
      (! compile)
      (let* ((class (program-class (● cx program) id))
             (types (map (lambda (type) (resolve-type cx env type))
                         (filter (lambda (form) (not (associated-form? form))) arguments)))
             (equalities (map associated-equation (filter associated-form? arguments)))
             (outputs (map (lambda (name)
                             (match (assoc-ref equalities name)
                               ((Some type) (resolve-type cx env type))
                               ((None)
                                (TRigid
                                 (string-append "$associated." (i64->string index) "." name)))))
                           (● class outputs)))
             (constraint (Constraint id (append types outputs))))
        (unless (and (= (length equalities)
                        (length (delete-duplicates string=?
                                                   (map (lambda (record) (● record first))
                                                        equalities))))
                     (every? (lambda (entry) (member? (● entry first) (● class outputs)))
                             equalities))
          (compile-error loc "constraint has an unknown or repeated associated type equality"))
        (check-constraint (● cx program) constraint loc)
        constraint))

    ;; A constraint gives each of its class's parameters, and a row or a
    ;; row variable to each its methods perform. While signatures are
    ;; resolved, a class the same library declares is not in the program
    ;; yet, so a definition checks its signature's again
    ;; (`check-signature`).

    (define (check-constraint (program Program) (constraint Constraint) (loc Loc))
      (→ Unit)
      (! compile)
      (match (table-ref (● program classes) (● constraint class))
        ((Some class)
         (unless (= (length (● constraint types)) (length (● class params)))
           (compile-error loc
                          (string-append
                           "a constraint gives each of the class's parameters, as in ("
                           (string-join (Cons (short-name (● class name))
                                              (● class params))
                                        " ")
                           ")")))
         (for-each (lambda (row)
                     (match (● row second)
                       ((TRow _ _) (unit))
                       ((TRigid _) (unit))
                       (_ (compile-error loc
                                         (string-append
                                          "a constraint gives the class's row parameter "
                                          (● row first)
                                          " a row")))))
                   (zip (● class rows) (row-arguments class (● constraint types)))))
        ((None) (unit))))

    (define (resolve-type (cx Context) (env Env) (syntax Syntax)) (→ Type) (! compile)
      (match syntax
        ((Ident _ _ loc) (resolve-type-name cx env syntax (Nil) loc))
        ((Form (Cons (Ident "!" _ _) labels) loc) (resolve-row cx env labels loc))
        ((Form (Cons (Ident kind _ _) items) loc)
         (if (member? kind (list "Fn" "FnOnce" "fn"))
             (let ((arrow (resolve-callable-arrow cx env items (Nil) loc)))
               (if (string=? kind "Fn") arrow (TCon kind (list arrow))))
             (resolve-type-application cx env syntax loc)))
        ((Form (Cons head args) loc)
         (resolve-type-name cx env (expect-ident head "a type constructor") args loc))
        (_ (compile-error (syntax-loc syntax) "expected a type"))))

    (define (resolve-type-application (cx Context) (env Env) (syntax Syntax) (loc Loc))
      (→ Type)
      (! compile)
      (match syntax
        ((Form (Cons head args) _)
         (resolve-type-name cx env (expect-ident head "a type constructor") args loc))
        (_ (compile-error loc "expected a type application"))))



    (define (resolve-type-name (cx Context) (env Env) (ident Syntax) (args (List Syntax)) (loc Loc))
      (→ Type)
      (! compile)
      (match (resolve cx env ident)
        ((Some (TypeName name arity _))
         (unless (= arity (length args))
           (compile-error loc
                          (string-append "wrong number of type arguments: " (Ident-name ident))))
         (TCon name (map (lambda (arg) (resolve-type cx env arg)) args)))
        ((Some (Associated class member))
         (resolve-projection env class member
                             (map (lambda (arg) (resolve-type cx env arg)) args)
                             (program-class (● cx program) class) loc))
        ((Some (TypeVar type))
         (if (null? args) type (compile-error loc "a type variable takes no arguments")))
        ((Some (Alias name params body alias-env))
         (unless (= (length params) (length args))
           (compile-error loc
                          (string-append "wrong number of alias arguments: " (Ident-name ident))))
         (when (member? name (● cx aliases))
           (compile-error loc (string-append "type alias refers to itself: " (Ident-name ident))))
         (let ((scope (fold-left (lambda (scope pair)
                                   (extend scope
                                           (● pair first)
                                           (TypeVar (resolve-type cx env (● pair second)))))
                                 alias-env (zip params args))))
           (resolve-type (Context-aliases-set cx (Cons name (● cx aliases))) scope body)))
        (_ (compile-error loc (string-append "not a type: " (Ident-name ident))))))

    (define (resolve-projection (env Env)
                                (id String)
                                (member String)
                                (args (List Type))
                                (class Class)
                                (loc Loc))
      (→ Type)
      (! compile)
      (unless (= (length args) (- (length (● class params)) (length (● class outputs))))
        (compile-error loc "associated projection gives each declared class parameter"))
      (match (filter (lambda (constraint)
                       (and (string=? id (● constraint class))
                            (types=? (type-arguments class args)
                                     (type-arguments class (● constraint types)))))
                     (enclosing-requirements env))
        ((Cons constraint (Nil))
         (match (assoc-ref (zip (● class params) (● constraint types)) member)
           ((Some type) type)
           ((None) (panic "internal error: associated member"))))
        ((Nil) (compile-error loc "associated projection needs a matching ⊨ constraint"))
        (_ (compile-error loc "associated projection matches multiple requirements"))))

    (define (enclosing-requirements (env Env)) (→ (List Constraint))
      (match env
        ((EvidenceScope constraints rest) (append constraints (enclosing-requirements rest)))
        ((InstanceScope _ rest) (enclosing-requirements rest))
        ((InstanceOwner _ rest) (enclosing-requirements rest))
        ((Frame _ _ rest) (enclosing-requirements rest))
        ((Top _ _) (Nil))))

    ;; Function formers separate their parameters from one result with
    ;; `→`; only `!` and the effect row may follow that result.

    (define (resolve-callable-arrow (cx Context)
                                    (env Env)
                                    (items (List Syntax))
                                    (params (List Type))
                                    (loc Loc))
      (→ Type)
      (! compile)
      (match items
        ((Cons (Ident "→" _ _) rest)
         (resolve-callable-result cx env (reverse params) rest loc))
        ((Cons (Ident "!" _ _) _)
         (compile-error loc
                        "a callable signature puts → before its result and ! before its effects"))
        ((Cons param rest)
         (resolve-callable-arrow cx env rest (Cons (resolve-type cx env param) params) loc))
        ((Nil) (compile-error loc "a callable signature needs → followed by one result type"))))

    (define (resolve-callable-result (cx Context)
                                     (env Env)
                                     (params (List Type))
                                     (items (List Syntax))
                                     (loc Loc))
      (→ Type)
      (! compile)
      (match items
        ((Cons (Ident "→" _ _) _) (compile-error loc "a callable signature has only one →"))
        ((Cons (Ident "!" _ _) _)
         (compile-error loc "a callable signature needs a result before !"))
        ((Cons result (Nil)) (TFun params (resolve-type cx env result) empty-row))
        ((Cons result (Cons (Ident "!" _ _) labels))
         (TFun params (resolve-type cx env result) (resolve-row cx env labels loc)))
        (_ (compile-error loc
                          "expected one result type after →, optionally followed by ! effects"))))



    (define (resolve-row (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ Type)
      (! compile)
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

    (define (expand-artifact-files (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (match items
        ((Cons _ (Cons (Atom (DString name) _) (Cons file (Cons cons (Cons nil (Nil))))))
         (expanding cx ((files (resolve-artifact-files name loc)))
                    (expand-expr cx env (fold-right (lambda (entry rest)
                                                      (Form (list cons
                                                                  (Form (list file
                                                                              (Atom
                                                                               (DString
                                                                                (● entry first))
                                                                               loc)
                                                                              (Atom
                                                                               (DBytes
                                                                                (● entry second))
                                                                               loc))
                                                                        loc)
                                                                  rest)
                                                            loc))
                                                    (Form (list nil) loc) files))))
        (_ (compile-error loc "artifact-bundle expects a literal target name"))))

    ;; Each library owns its uses, including when expansion loads another
    ;; library during deriving. Record an actual invocation once; unused
    ;; macro templates never enter this accumulator.

    (define (resolve-artifact-files (cx Context) (name String) (loc Loc))
      (→ (Pair ArtifactFiles Context))
      (! compile)
      (match (find (lambda (use) (string=? name (● use name))) (● cx artifact-uses))
        ((Some use) (Pair (● use files) cx))
        ((None)
         (expanding cx ((files (artifact-files name loc)))
                    (Pair files
                          (Context-artifact-uses-set cx
                                                     (Cons (ArtifactUse name loc files)
                                                           (● cx artifact-uses))))))))

    ;; Expands macro uses at the head of a form until the head is not a macro.

    (define (expand-head (cx Context) (env Env) (syntax Syntax))
      (→ (Pair Syntax Context))
      (! compile)
      (match (head-binding cx env syntax)
        ((Some (Macro _ literals rules scope))
         (expanding cx ((expanded (apply-macro env syntax literals rules scope)))
                    (expand-head cx env expanded)))
        (_ (Pair syntax cx))))

    (define (expr (term Term) (loc Loc)) (→ Expr)
      (Expr term unchecked loc))

    (define (expand-expr (cx Context) (env Env) (syntax Syntax)) (→ (Pair Expr Context)) (! compile)
      (expanding cx ((syntax (expand-head env syntax)))
                 (match syntax
                   ((Atom value loc) (Pair (expr (Lit value) loc) cx))
                   ((Ident _ _ loc) (Pair (expand-reference cx env syntax loc) cx))
                   ((Form (Nil) loc) (compile-error loc "empty application"))
                   ((Form (Cons _ _) loc) (expand-application cx env syntax loc)))))

    (define (expand-application (cx Context) (env Env) (syntax Syntax) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (match syntax
        ((Form (Cons head args) _)
         (match (head-binding cx env syntax)
           ((Some (Core keyword)) (expand-core cx env keyword (Form-items syntax) loc))
           (_ (expanding cx ((callee (expand-expr env head))
                             (arguments (expand-each env args)))
                         (Pair (expr (App callee arguments) loc) cx)))))
        (_ (panic "internal error: not an application"))))

    (define (expand-each (cx Context) (env Env) (forms (List Syntax)))
      (→ (Pair (List Expr) Context))
      (! compile)
      (each cx (lambda (cx form) (expand-expr cx env form)) forms))

    (define (expand-reference (cx Context) (env Env) (ident Syntax) (loc Loc)) (→ Expr) (! compile)
      (match (resolve cx env ident)
        ((Some (Local name)) (expr (Var name (Nil) (Nil)) loc))
        ((Some (Global name))
         (match (program-value (● cx program) name)
           ((Some (Replacer case _ _))
            (check-own-library cx (● case type) loc "replace its fields"))
           (_ (unit)))
         (expr (Var name (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (Some constructor))) (expr (Var constructor (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (None)))
         (compile-error loc (string-append "a type is not a value: " (Ident-name ident))))
        ((Some (Core "field-read")) (compile-error loc field-read-message))
        ((None) (compile-error loc (string-append "unbound identifier " (Ident-name ident))))
        (_ (compile-error loc (string-append "syntax used as a value: " (Ident-name ident))))))

    ;; The receiver is expanded once. Each label selects a real struct slot;
    ;; type checking resolves the record type and any pointer traversal.
    (define (expand-field-read (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context)) (! compile)
      (match items
        ((Cons receiver (Cons first rest))
         (let ((labels (map (lambda (label)
                              (Ident-name (expect-ident label "a field label")))
                            (Cons first rest))))
           (expanding cx ((value (expand-expr env receiver)))
                      (Pair (fold-left (lambda (value label)
                                         (expr (FieldRead value label (None)) loc))
                                       value labels) cx))))
        (_ (compile-error loc "expected (● receiver field ...) with at least one field"))))

    (define (expand-core (cx Context) (env Env) (keyword String) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (case keyword
        (("●") (expand-field-read cx env (list-drop items 1) loc))
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

    (define (expand-lambda (cx Context)
                           (env Env)
                           (params (List Syntax))
                           (body (List Syntax))
                           (captures? Bool)
                           (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (expanding cx ((locals (bind-locals env params))
                     (body (expand-body (● locals first) body loc)))
                 (Pair (expr (Lambda (● locals second) body captures?) loc) cx)))

    ;; Binds each identifier to a fresh local, in order; returns the longer
    ;; environment and the unique names.

    (define (bind-locals (cx Context) (env Env) (idents (List Syntax)))
      (→ (Pair (Pair Env (List String)) Context))
      (! compile)
      (expanding cx ((names (each (lambda (cx ident)
                                    (fresh cx (Ident-name (expect-ident ident "a variable name"))))
                                  idents)))
                 (Pair (Pair (fold-left (lambda (env bound)
                                          (extend env
                                                  (● bound first)
                                                  (Local (● bound second))))
                                        env
                                        (zip idents names))
                             names)
                       cx)))

    (define (expand-body (cx Context) (env Env) (forms (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (when (null? forms) (compile-error loc "empty body"))
      (expand-body-forms cx env forms (None) loc))

    ;; A local body is sequential: each definition is visible to the forms
    ;; after it, and a function definition is also visible to itself. A
    ;; signature annotates the definition that follows it.

    (define (expand-body-forms (cx Context)
                               (scope Env)
                               (forms (List Syntax))
                               (signature (Option (Pair String Type)))
                               (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
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
                                                   (Pair (expr (Seq value more) (● value loc))
                                                         cx))))))))))

    (define (local-signature (cx Context) (scope Env) (form Syntax))
      (→ (Pair String Type))
      (! compile)
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (Pair (Ident-name (expect-ident name "a name"))
               (● (resolve-scheme cx scope type) type)))
        (_ (compile-error (syntax-loc form) "expected (: name type)"))))

    (define (expand-local-definition (cx Context)
                                     (scope Env)
                                     (form Syntax)
                                     (rest (List Syntax))
                                     (signature (Option (Pair String Type)))
                                     (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (let* ((definition (parse-definition form)) (ident (● definition name)))
        (expanding cx ((name (fresh (Ident-name ident))))
                   (let ((inner (extend scope ident (Local name)))
                         (function? (match (● definition parameters)
                                      ((Some _) #t)
                                      ((None)
                                       (let ((value (list-ref (● definition body) 0)))
                                         (or (core-form? cx scope value "lambda")
                                             (core-form? cx scope value "fn")))))))
                     (expanding cx ((value (definition-value (if function? inner scope) definition))
                                    (body (expand-body-forms inner rest (None) loc)))
                                (Pair (expr (Let name
                                                 (signed-value (annotated-definition-value cx
                                                                                           scope
                                                                                           definition
                                                                                           value)
                                                               signature (Ident-name ident))
                                                 body)
                                            (syntax-loc form))
                                      cx))))))

    ;; A local definition's value, annotated with the signature before it
    ;; when the signature names it.

    (define (signed-value (value Expr) (signature (Option (Pair String Type))) (name String))
      (→ Expr)
      (match signature
        ((Some (Pair signed type))
         (if (string=? signed name) (expr (Ann value type) (● value loc)) value))
        ((None) value)))

    ;; `(let ((name value) ...) body ...)` or the named-let loop form.

    (define (expand-let (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (match items
        ((Cons _ (Cons head (Cons more body)))
         (match head
           ((Ident _ _ _)
            (expand-named-let cx env head (form-items more "a list of bindings") body loc))
           ((Form bindings _) (expand-plain-let cx env bindings (Cons more body) loc))
           (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))
        (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))

    (define (expand-named-let (cx
                               Context)
              (env Env)
              (ident Syntax)
              (bindings (List Syntax))
              (body (List Syntax))
              (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
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

    (define (expand-plain-let (cx
                               Context)
              (env Env)
              (bindings (List Syntax))
              (body (List Syntax))
              (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (expanding cx ((values
                      (each (lambda (cx binding) (expand-expr cx env (binding-value binding)))
                            bindings))
                     (locals (bind-locals env (map binding-name bindings)))
                     (body (expand-body (● locals first) body loc)))
                 (Pair (fold-right (lambda (pair body)
                                     (expr (Let (● pair first) (● pair second) body) loc))
                                   body
                                   (zip (● locals second) values))
                       cx)))

    (define (binding-name (binding Syntax)) (→ Syntax) (! compile)
      (match (form-items binding "a (name value) binding")
        ((Cons name _) (expect-ident name "a binding name"))
        ((Nil) (compile-error (syntax-loc binding) "expected (name value)"))))

    (define (binding-value (binding Syntax)) (→ Syntax) (! compile)
      (match binding
        ((Form (Cons _ (Cons value (Nil))) _) value)
        (_ (compile-error (syntax-loc binding) "expected (name value)"))))

    (define (expand-handle (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
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

    (define (expand-implementation (cx Context) (env Env) (effect String) (implementation Syntax))
      (→ (Pair (Pair String Expr) Context))
      (! compile)
      (match implementation
        ((Form (Cons name (Cons value (Nil))) _)
         (let ((operation (operation-name cx effect name)))
           (expanding cx ((value (expand-expr env value)))
                      (Pair (Pair operation value) cx))))
        (_ (compile-error (syntax-loc implementation) "expected (operation implementation)"))))

    ;; A handler names operations by their names within the effect, so they
    ;; need not be imported.

    (define (operation-name (cx Context) (effect String) (ident Syntax)) (→ String) (! compile)
      (named-operation (● (program-effect (● cx program) effect) operations) ident))

    (define (named-operation (operations (List String)) (ident Syntax)) (→ String) (! compile)
      (let ((name (Ident-name (expect-ident ident "an operation name"))))
        (match (find (lambda (operation) (string=? (short-name operation) name)) operations)
          ((Some operation) operation)
          ((None)
           (compile-error (syntax-loc ident)
                          (string-append "not an operation of this effect: " name))))))

    (define (constructor-case-id (cx Context) (env Env) (constructor Syntax)) (→ I64) (! compile)
      (match (program-value (● cx program) (pattern-constructor cx env constructor))
        ((Some (Constructor case _)) (case-type-id (● cx program) case))
        (_ (compile-error (syntax-loc constructor) "not a constructor"))))

    ;; ---- Deriving ----

    ;; Derived instances are ordinary instance declarations, built as syntax.
    ;; Identifiers they introduce are marked to resolve in an environment of
    ;; the implicit libraries, whatever the declaring library imports.

    (define implicit-libraries (→ (List (List String)))
      (list (list "snail" "core" "forms")
            (list "snail" "core" "primitive")
            (list "snail" "core" "base")
            (list "snail" "shell" "wire")))

    (define (derived-instances (cx Context) (form Syntax) (enum? Bool))
      (→ (Pair (List Syntax) Context))
      (! fs compile generator)
      (let* ((head (declaration-head form)) (loc (syntax-loc form))
             (cases (if enum?
                        (map (lambda (form)
                               (let ((case (parse-case form)))
                                 (Pair (● case name) (length (● case fields)))))
                             (enum-cases form))
                        (list (Pair (declared-name head) (length (struct-fields form)))))))

        (each cx
              (lambda (cx class)
                (match class
                  ((Ident "Repr" _ _) (repr-instance cx head cases loc))
                  ((Ident "Serialize" _ _) (serialize-instance cx head cases loc))
                  ((Ident "Deserialize" _ _) (deserialize-instance cx head cases loc))
                  (_ (compile-error (syntax-loc class)
                                    "only Move, Repr, Serialize and Deserialize can be derived"))))
              (derived-instance-classes form))))

    ;; The scope derived instances resolve in, made at the build's first
    ;; deriving clause, which loads the implicit libraries, and shared by
    ;; every later one. The library notes the declaration at `loc`, so that
    ;; each expansion loads their current declarations.

    (define (deriving-scope (cx Context) (loc Loc)) (→ (Pair I64 Context)) (! fs compile generator)
      (let ((cx (Context-derives-set cx (Some loc))))
        (match (● cx deriving)
          ((Some scope) (Pair scope cx))
          ((None)
           (expanding cx ((exports
                           (each (lambda (cx name) (load-library cx name loc)) implicit-libraries))
                          (env (new-top (fold-left (lambda (table entry)
                                                     (table-set table
                                                                (● entry first)
                                                                (● entry second)))
                                                   empty-table (concatenate exports))))
                          (scope (register-scope env)))
                      (Pair scope (Context-deriving-set cx (Some scope))))))))

    ;; Deriving may inspect only Copy values. Check after all declarations,
    ;; since a later Drop instance can make a type own an external resource.
    (define (check-repr-types (cx Context) (pending (List Pending))) (→ Unit) (! compile)
      (for-each (lambda (entry)
                  (when (and (member? (● entry keyword) (list "struct" "enum"))
                             (any? (lambda (class)
                                     (match class ((Ident "Repr" _ _) #t) (_ #f)))
                                   (derived-classes (● entry form))))
                    (check-repr-type cx entry)))
                pending))

    (define (check-repr-type (cx Context) (entry Pending)) (→ Unit) (! compile)
      (let ((name (declared-name (declaration-head (● entry form)))))
        (match (resolve cx (● entry env) name)
          ((Some (TypeName id _ _))
           (let ((params (● (program-type (● cx program) id) params)))
             (when (linear-type? (● cx program) params (TCon id (map TRigid params)))
               (compile-error (syntax-loc name) "deriving Repr requires a Copy type"))))
          (_ (panic "internal error: represented type")))))

    ;; Builds the syntax of a derived instance; `w` marks introduced identifiers.
    (struct Deriver
      ((scope I64)
       (loc Loc)))

    (define (w (deriver Deriver) (name String)) (→ Syntax)
      (let ((loc (● deriver loc)))
        (Ident name
               (Some (Mark (string-append name "%deriving")
                           (Ident name (None) loc)
                           (● deriver scope)))
               loc)))

    (define (f (deriver Deriver) (items (List Syntax))) (→ Syntax)
      (Form items (● deriver loc)))

    (define (field-idents (deriver Deriver) (count I64)) (→ (List Syntax))
      (map (lambda (index) (w deriver (string-append "field" (i64->string index)))) (iota count)))

    (define (instance-head (d Deriver) (class String) (head Syntax)) (→ (List Syntax)) (! compile)
      (let ((params (declared-params head)))
        (append (list (w d "instance") (f d (list (w d class) head)))
                (if (null? params)
                    (Nil)
                    (list (f d
                             (Cons (w d "⊨")
                                   (concatenate
                                    (map (lambda (param)
                                           (let ((requirement (f d (list (w d class) param))))
                                             (if (string=? class "Repr")
                                                 (list (f d (list (w d "Copy") param))
                                                       (f d (list (w d "Drop")
                                                                  (f d (list (w d "!"))) param))
                                                       requirement)
                                                 (list requirement))))
                                         params)))))))))

    ;; A derived method inherits its class's signature. Its lambda keeps
    ;; that inference without introducing an unannotated function head.
    (define (derived-method (d Deriver) (name String) (parameters (List Syntax)) (body Syntax))
      (→ Syntax)
      (f d (list (w d "define") (w d name)
                 (f d (list (w d "lambda") (f d parameters) body)))))

    ;; Constructor notation is ordinary pure code, with no runtime reflection.
    (define (repr-instance (cx Context) (head Syntax) (cases (List (Pair Syntax I64))) (loc Loc))
      (→ (Pair Syntax Context))
      (! fs compile generator)
      (expanding cx ((scope (deriving-scope loc)))
                 (let* ((d (Deriver scope loc)) (value (w d "value"))
                        (body (f d (Cons (w d "match")
                                         (Cons value
                                               (map (lambda (case) (repr-case d case)) cases))))))
                   (Pair (f d (append (instance-head d "Repr" head)
                                      (list (derived-method d "repr" (list value) body))))
                         cx))))

    (define (repr-case (d Deriver) (case (Pair Syntax I64))) (→ Syntax)
      (let* ((fields (field-idents d (● case second)))
             (open (Atom (DString (string-append "(" (Ident-name (● case first)))) (● d loc)))
             (space (Atom (DString " ") (● d loc)))
             (close (Atom (DString ")") (● d loc)))
             (pieces (Cons open
                           (append (concatenate (map (lambda (field)
                                                       (list space (f d (list (w d "repr") field))))
                                                     fields))
                                   (list close)))))
        (f d (list (f d (Cons (● case first) fields))
                   (f d (list (w d "string-concatenate") (f d (Cons (w d "list") pieces))))))))

    ;; Each case writes its TypeId, then its fields in order.

    (define (serialize-instance (cx Context)
                                (head Syntax)
                                (cases (List (Pair Syntax I64)))
                                (loc Loc))
      (→ (Pair Syntax Context))
      (! fs compile generator)
      (expanding cx ((scope (deriving-scope loc)))
                 (let* ((d (Deriver scope loc)) (value (w d "value")) (encoder (w d "encoder")))
                   (Pair (f d (append (instance-head d "Serialize" head)
                                      (list (derived-method d "encode" (list value encoder)
                                                            (f d (Cons (w d "match")
                                                                       (Cons value
                                                                             (map (lambda (case)
                                                                                    (serialize-case
                                                                                     d
                                                                                     case
                                                                                     encoder))
                                                                                  cases))))))))
                         cx))))

    (define (serialize-case (d Deriver) (case (Pair Syntax I64)) (encoder Syntax)) (→ Syntax)
      (let ((fields (field-idents d (● case second))))
        (f d (Cons (f d (Cons (● case first) fields))
                   (Cons (f d
                            (list (w d "encode-case-id")
                                  encoder
                                  (f d (list (w d "case-id") (● case first)))))
                         (append
                          (map (lambda (field) (f d (list (w d "encode") field encoder))) fields)
                          (list (f d (list (w d "unit"))))))))))

    ;; The TypeId read selects the case; an unknown one is a schema mismatch.

    (define (deserialize-instance (cx Context)
                                  (head Syntax)
                                  (cases (List (Pair Syntax I64)))
                                  (loc Loc))
      (→ (Pair Syntax Context))
      (! fs compile generator)
      (expanding cx ((scope (deriving-scope loc)))
                 (let* ((d (Deriver scope loc)) (decoder (w d "decoder")) (id (w d "id")))
                   (Pair (f d (append (instance-head d "Deserialize" head)
                                      (list
                                       (derived-method d "decode" (list decoder)
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
                                                                                            (list
                                                                                             (w d
                                                                                                "case-id=?")
                                                                                             id
                                                                                             (f d
                                                                                                (list
                                                                                                 (w
                                                                                                  d
                                                                                                  "case-id")
                                                                                                 (●
                                                                                                  case
                                                                                                  first)))))
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
                                                                            cases)))))))
                         cx))))

    (define (deserialize-case (d Deriver) (case (Pair Syntax I64)) (decoder Syntax)) (→ Syntax)
      (let ((fields (field-idents d (● case second))))
        (fold-right (lambda (field body)
                      (f d
                         (list (w d "let")
                               (f d (list (f d (list field (f d (list (w d "decode") decoder))))))
                               body)))
                    (f d (Cons (● case first) fields)) fields)))

    ;; ---- Patterns ----

    (define (expand-match (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (! compile)
      (match items
        ((Cons _ (Cons scrutinee clauses))
         (expanding cx ((scrutinee (expand-expr env scrutinee))
                        (clauses (each (lambda (cx clause) (expand-clause cx env clause)) clauses)))
                    (Pair (expr (Match scrutinee clauses) loc) cx)))
        (_ (compile-error loc "expected (match expression clause ...)"))))

    ;; A clause binds its pattern's variables first, so the pattern itself
    ;; only looks names up.

    (define (expand-clause (cx Context) (env Env) (clause Syntax))
      (→ (Pair Clause Context))
      (! compile)
      (match (form-items clause "a match clause")
        ((Cons pattern body)
         (expanding cx ((locals (bind-locals env (pattern-variables pattern))))
                    (let* ((scope (● locals first))
                           (pattern (expand-pattern cx env scope pattern)))
                      (expanding cx ((body (expand-body scope body (syntax-loc clause))))
                                 (Pair (Clause pattern body) cx)))))
        ((Nil) (compile-error (syntax-loc clause) "expected (pattern body ...)"))))

    ;; The variables of a pattern, in order, each named once.

    (define (pattern-variables (syntax Syntax)) (→ (List Syntax)) (! compile)
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

    (define (pattern-idents (syntax Syntax)) (→ (List Syntax))
      (match syntax
        ((Ident "_" _ _) (Nil))
        ((Ident _ _ _) (list syntax))
        ((Form (Cons _ args) _) (concatenate (map pattern-idents args)))
        (_ (Nil))))

    ;; Bare identifiers are `_` or variables bound in `scope`; constructors
    ;; resolve in `env` and are always applied, as in `(None)`.

    (define (expand-pattern (cx Context) (env Env) (scope Env) (syntax Syntax))
      (→ Pattern)
      (! compile)
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

    (define (pattern-constructor (cx Context) (env Env) (head Syntax)) (→ String) (! compile)
      (let ((name (constructor-name cx env (expect-ident head "a constructor"))))
        (match (program-value (● cx program) name)
          ((Some (Constructor case _))
           (check-own-library cx
                              (● case type)
                              (syntax-loc head)
                              "take it apart; drop it instead"))
          (_ (unit)))
        name))

    ;; A type with a Drop instance is taken apart, or has a field replaced,
    ;; only in its own library, which the instance trusts to release what a
    ;; value holds; elsewhere a value of it is dropped, or given to a
    ;; function of its library.

    (define (check-own-library (cx Context) (type String) (loc Loc) (what String))
      (→ Unit)
      (! compile)
      (match (lifecycle-instance (● cx program) drop-class type)
        ((Some _)
         (unless (string=? (name-owner type) (● cx prefix))
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

    (define (macro-form (form Syntax)) (→ MacroForm) (! compile)
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

    (define (define-top-macro (cx Context) (env Env) (form Syntax)) (→ Context) (! compile)
      (let ((parts (macro-form form)))
        (expanding cx ((id (fresh "%macro")) (scope (register-scope env)))
                   (bind-top cx
                             env
                             (● parts name)
                             (Macro id (● parts literals) (● parts rules) scope)))))

    (define (define-local-macro (cx Context) (env Env) (form Syntax))
      (→ (Pair Env Context))
      (! compile)
      (let ((parts (macro-form form)))
        (expanding cx ((scope (register-scope env)) (id (fresh "%macro")))
                   (let ((inner (extend env
                                        (● parts name)
                                        (Macro id
                                               (● parts literals)
                                               (● parts rules)
                                               scope))))
                     (Pair inner (scope-set cx scope inner))))))

    (define (apply-macro (cx Context)
                         (env Env)
                         (form Syntax)
                         (literals (List Syntax))
                         (rules (List Syntax))
                         (scope I64))
      (→ (Pair Syntax Context))
      (! compile)
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

    (define (literal? (ident Syntax) (literals (List Syntax))) (→ Bool)
      (any? (lambda (literal) (string=? (ident-key literal) (ident-key ident))) literals))

    (define (match-pattern (cx Context)
                           (pattern Syntax)
                           (input Syntax)
                           (literals (List Syntax))
                           (env Env)
                           (macro-env Env))
      (→ (Option Bindings))
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

    (define (same-binding? (cx Context) (env Env) (input Syntax) (macro-env Env) (literal Syntax))
      (→ Bool)
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

    (define (match-items (cx Context)
                         (patterns (List Syntax))
                         (inputs (List Syntax))
                         (literals (List Syntax))
                         (env Env)
                         (macro-env Env))
      (→ (Option Bindings))
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

    (define (match-ellipsis (cx Context)
                            (repeated Syntax)
                            (after (List Syntax))
                            (inputs (List Syntax))
                            (literals (List Syntax))
                            (env Env)
                            (macro-env Env))
      (→ (Option Bindings))
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

    (define (all-matched (matches (List (Option Bindings)))) (→ (Option (List Bindings)))
      (fold-right (lambda (match-result rest)
                    (match match-result
                      ((Some bindings)
                       (match rest ((Some more) (Some (Cons bindings more))) ((None) (None))))
                      ((None) (None))))
                  (Some (Nil)) matches))

    (define (bound-ref (bindings Bindings) (key String)) (→ Bound)
      (match (assoc-ref bindings key)
        ((Some bound) bound)
        ((None) (panic "internal error: unbound pattern variable"))))

    (define (pattern-keys (pattern Syntax) (literals (List Syntax))) (→ (List String))
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

    (define (transcribe (template Syntax) (bindings Bindings) (expansion Expansion))
      (→ Syntax)
      (! compile)
      (match template
        ((Ident name _ _)
         (match (assoc-ref bindings (ident-key template))
           ((None) (rename-ident template expansion))
           ((Some (Many _))
            (compile-error (● expansion loc)
                           (string-append "pattern variable used without an ellipsis: " name)))
           ((Some (One syntax)) syntax)))
        ((Atom _ _) template)
        ((Form items _)
         (Form (transcribe-items items bindings expansion) (● expansion loc)))))

    (define (transcribe-items (items (List Syntax)) (bindings Bindings) (expansion Expansion))
      (→ (List Syntax))
      (! compile)
      (match items
        ((Nil) (Nil))
        ((Cons item (Cons (Ident "..." _ _) rest))
         (append (transcribe-repeated item bindings expansion)
                 (transcribe-items rest bindings expansion)))
        ((Cons item rest)
         (Cons (transcribe item bindings expansion) (transcribe-items rest bindings expansion)))))

    ;; The repeated template iterates over every variable it uses that matched
    ;; under an ellipsis; such variables must have equal lengths.

    (define (transcribe-repeated (template Syntax) (bindings Bindings) (expansion Expansion))
      (→ (List Syntax))
      (! compile)
      (let ((repeated (concatenate (map (lambda (key)
                                          (match (assoc-ref bindings key)
                                            ((Some (Many matches)) (list (Pair key matches)))
                                            (_ (Nil))))
                                        (delete-duplicates string=? (template-keys template))))))
        (match repeated
          ((Nil)
           (compile-error (● expansion loc)
                          "ellipsis follows a template without pattern variables"))
          ((Cons first _)
           (let ((count (length (● first second))))
             (unless (every? (lambda (entry) (= count (length (● entry second)))) repeated)
               (compile-error (● expansion loc)
                              "pattern variables under one ellipsis matched different lengths"))
             (map (lambda (index)
                    (transcribe template
                                (append (map (lambda (entry)
                                               (Pair (● entry first)
                                                     (list-ref (● entry second) index)))
                                             repeated)
                                        bindings)
                                expansion))
                  (iota count)))))))

    (define (template-keys (template Syntax)) (→ (List String))
      (match template
        ((Ident _ _ _) (list (ident-key template)))
        ((Form items _) (concatenate (map template-keys items)))
        (_ (Nil))))

    ;; A template's identifier becomes the same marked identifier wherever it
    ;; appears in one expansion: its mark is its key with the expansion's
    ;; stamp, resolved in the macro's scope.

    (define (rename-ident (ident Syntax) (expansion Expansion)) (→ Syntax)
      (Ident (Ident-name ident)
             (Some (Mark (string-append (ident-key ident) "%" (● expansion stamp))
                         ident
                         (● expansion scope)))
             (● expansion loc)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-expand)
    (import
     (only (snail stage0 system) create-directory*)
     (only (snail stage0 system) string-contains)
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
      (define test-expand
        (lambda (directory library) (test-callable-signatures)
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
                  (test-deriving-key (string-append directory "/deriving-key") library))))

      (define test-callable-signatures
        (lambda () (expect (callable-signature "(→ Unit)")
                           (TFun (Nil) (TCon "Unit" (Nil)) empty-row))
                (expect (callable-signature "(I64 (Vector String) → Bool ! mut)")
                        (TFun (list (TCon "I64" (Nil)) (TCon "Vector" (list (TCon "String" (Nil)))))
                              (TCon "Bool" (Nil)) mut-row))
                (for-each (lambda (source)
                            (expect
                             (and (compile-failure (lambda () (callable-signature source))) #t)
                             #t))
                          (list "(I64 -> Unit)" "()" "(I64 Unit)" "(I64 ! mut → Unit)"
                                "(I64 →)" "(I64 → ! mut)" "(I64 → → Unit)"
                                "(I64 → Unit Bool)"))))

      (define callable-signature
        (lambda (text)
          (let* ((cx (new-context (Nil) no-inputs (Supplied)))
                 (imports (fold-left (lambda (table entry)
                                       (table-set table (● entry first) (● entry second)))
                                     empty-table (core-library)))
                 (env (● (new-top cx imports) first)))
            (match (read-text text "callable.sld")
              ((Cons (Form items loc) (Nil)) (resolve-callable-arrow cx env items (Nil) loc))))))

      ;; Metadata follows canonical declarations through imports and repeated builds.
      ;; Updating only a field's documentation does not change its wire or
      ;; dynamic type identity, and equal field names have distinct owners.
      (define test-annotation-metadata
        (lambda (directory library) (create-directory* (string-append directory "/sample"))
                (let ((source (string-append directory "/main.sld"))
                      (module (string-append directory "/sample/docs.sld"))
                      (directories (list directory library)))
                  (write-file source
                              "(import (snail core forms) (prefix (sample docs) renamed-)) (define example (renamed-Entry \"ok\"))")
                  (write-file module (annotation-library "original"))
                  (let* ((first (expand-program directories
                                                annotation-generator
                                                no-inputs
                                                source))
                         (repeated
                          (expand-program directories annotation-generator no-inputs source))
                         (program (● repeated program))
                         (entry (program-type program "sample.docs:Entry")))
                    (expect
                     (annotation-documentation (program-annotations program "sample.docs:Entry"))
                     (Some "A record.\nIts fields are immutable."))
                    (expect (annotation-documentation
                             (program-field-annotations program "sample.docs:Entry" "value"))
                            (Some "original"))
                    (expect (annotation-documentation
                             (program-field-annotations program "sample.docs:Other" "value"))
                            (Some "A different field."))
                    (expect (program-annotations program "sample.docs:Entry-value") (Nil))
                    (expect
                     (annotation-documentation (program-annotations program "sample.docs:label"))
                     (Some "Name this value."))
                    (expect (annotation-documentation
                             (program-annotations program "sample.docs:count"))
                            (Some "An inline definition."))
                    (expect
                     (annotation-documentation (program-annotations program "sample.docs:Waiting"))
                     (Some "No value yet."))
                    (expect (annotation-documentation
                             (program-annotations program "sample.docs:read-name"))
                            (Some "Read a name."))
                    (write-file module (annotation-library "updated"))
                    (let* ((changed
                            (expand-program directories
                                            annotation-generator
                                            no-inputs
                                            source))
                           (next (● changed program)))
                      (expect (annotation-documentation
                               (program-field-annotations next "sample.docs:Entry" "value"))
                              (Some "updated"))
                      (expect (any-type-id next (TCon "sample.docs:Entry" (Nil)))
                              (any-type-id program (TCon "sample.docs:Entry" (Nil))))
                      (expect (case-type-id next
                                            (list-ref
                                             (● (program-type next "sample.docs:Entry") cases)
                                             0))
                              (case-type-id program (list-ref (● entry cases) 0))))))))

      (define annotation-generator
        (lambda (loading forms) (panic "annotation fixture must not request a generator")))

      (define annotation-library
        (lambda (documentation) (string-append
                                 "(define-library (sample docs) (export Entry) (import (snail core base)) (begin\n"
                                 "(struct Entry ((value String (annotations (doc "
                                 (datum->string (DString documentation))
                                 ")))) (annotations (doc \"A record.\") (doc \"Its fields are immutable.\")))\n"
                                 "(struct Other ((value I64 (annotations (doc \"A different field.\")))))\n"
                                 "(enum Readiness (Waiting (annotations (doc \"No value yet.\"))))\n"
                                 "(define count (→ I64) (annotations (doc \"An inline definition.\")) 0)\n"
                                 "(typeclass (Named T) (: label (Fn T → String) (annotations (doc \"Name this value.\"))))\n"
                                 "(effect names ((read-name (Fn Unit → String) (annotations (doc \"Read a name.\")))))\n"
                                 "))")))

      ;; A producer names its recipe after its imports, as the path the
      ;; recipe was found at.
      (define test-library-file
        (lambda (directories) (let ((loc (Loc "test.sld" 1 1)))
                                (expect (library-file directories (list "snail" "core" "forms") loc)
                                        (DefinedLibrary (Nil)))
                                (expect (map syntax->string
                                             (section-items
                                              (DefinedLibrary-sections (library-file directories
                                                                                     (list "sample"
                                                                                           "top")
                                                                                     loc))
                                              "import"))
                                        (list "(sample made)"))
                                (expect (map syntax->string
                                             (GeneratedLibrary-forms
                                              (library-file directories
                                                            (list "sample" "made")
                                                            loc)))
                                        (list
                                         "(import (snail core base) (sample helper) (only (snail shell syntax) write-generated-library))"
                                         (string-append "(recipe "
                                                        (datum->string
                                                         (DString
                                                          (string-append (list-ref directories
                                                                                   0)
                                                                         "/sample/made.sld")))
                                                        ")")
                                         "(define main (lambda () (write-generated-library (lambda () (unit)))))")))))

      (define test-library-closure
        (lambda (directories)
          (let* ((imports (program-imports (read-text "(import (sample top)) (unit)" "main.sld")))
                 (cold (library-closure directories no-inputs (Nil) imports))
                 (made (list-ref cold 0))
                 (inputs (supply-generated no-inputs (producer-text directories (● made forms))
                                           (generated-library-bytes
                                            "(define-library (sample made) (export) (import (sample inner)) (begin))")))
                 (warm (library-closure directories inputs (Nil) imports)))
            (expect (map (lambda (record) (● record library)) cold) (list (list "sample" "made")))
            (expect (● made loading) (list "sample.made" "sample.top"))
            (expect (map (lambda (record) (● record library)) warm)
                    (list (list "sample" "made") (list "sample" "inner")))
            (expect (● (list-ref warm 1) loading)
                    (list "sample.inner" "sample.made" "sample.top"))
            (expect (closure-error directories made) #t))))

      ;; The producer of (sample made) imports (sample helper), which
      ;; imports (sample made) while it is still loading.
      (define closure-error
        (lambda (directories made) (let ((message (compile-failure (lambda ()
                                                                     (library-closure directories
                                                                                      no-inputs
                                                                                      (● made
                                                                                         loading)
                                                                                      (program-imports
                                                                                       (● made
                                                                                          forms)))))))
                                     (and message
                                          (string-contains message "helper.sld:1:")
                                          (string-contains message
                                                           "library import cycle through sample.made")
                                          #t))))

      (define test-discovery
        (lambda (directories root)
          (let* ((assets (library-file directories (list "sample" "assets") (Loc "test.sld" 1 1)))
                 (inputs (supply-generated no-inputs
                                           (producer-text directories
                                                          (GeneratedLibrary-forms assets))
                                           (generated-library-bytes assets-output)))
                 (uses (discover-artifacts directories inputs (string-append root "/main.sld"))))
            (expect (map (lambda (record) (● record name)) uses) (list "admin" "client"))
            (expect (map (lambda (use) (● (● use loc) file)) uses)
                    (list (string-append root "/sample/assets.sld")
                          (string-append root "/main.sld"))))))

      ;; A linked path is made canonical against its library's directory,
      ;; and the file is named for the digest of its bytes, once however
      ;; many uses or paths reach the same bytes. A path that leaves the
      ;; directory, or a file that is not there, is an error naming the
      ;; library and the path.
      (define test-links
        (lambda (root) (create-directory* (string-append root "/sample/data"))
                (write-file (string-append root "/sample/data/pixel.bin") "pixel")
                (write-file (string-append root "/notes.txt") "notes")
                (write-file (string-append root "/copy.txt") "notes")
                (write-file (string-append root "/sample/linked.sld")
                            "(define-library (sample linked) (export pixel) (import (snail core forms)) (begin (define pixel (link-handle \"data/./x/../pixel.bin\"))))")
                (let ((expansion (link-expansion root
                                                 "(import (snail core forms) (sample linked)) (define notes (link-handle \"notes.txt\")) (define other (link-handle \"notes.txt\")) (define copy (link-handle \"copy.txt\"))")))
                  (expect (map (lambda (record) (● record digest)) (program-links expansion))
                          (list "3f8d7379e2f0f7d0c845a06f7b67ef80cacce0c686254aced769c1698f3fe59a"
                                "ab5aa97074c454a0632057e704220d9a6678fbf773a0a5806fc09b8173b07309"))
                  (expect
                   (map (lambda (record) (● record path)) (library-links expansion "sample.linked"))
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
                                       "/absent.bin"))))

      (define link-expansion
        (lambda (root body) (write-file (string-append root "/main.sld") body)
                (expand-program (list root)
                                (lambda (loading forms) (panic "unexpected producer"))
                                no-inputs
                                (string-append root "/main.sld"))))

      (define link-error
        (lambda (root path) (let ((message (compile-failure
                                            (lambda ()
                                              (link-expansion root
                                                              (string-append
                                                               "(import (snail core forms)) (define linked (link-handle \""
                                                               path
                                                               "\"))"))))))
                              (if message
                                  (substring message
                                             (+ (string-contains message
                                                                 ": ")
                                                2)
                                             (string-length message))
                                  "accepted"))))

      ;; Loading (snail core primitive) binds each primitive's value under
      ;; `prim:NAME`, quantified over the variables its declaration names, in
      ;; their order, and records no run of items, since the library has no
      ;; module.
      (define test-primitives
        (lambda (root library) (create-directory* root)
                (write-file (string-append root "/main.sld")
                            "(import (snail core forms) (snail core primitive)) (define (main) (→ Unit) (unit))")
                (let ((program (● (expand-program (list root library)
                                                  (lambda (loading forms)
                                                    (panic "unexpected producer"))
                                                  no-inputs
                                                  (string-append root "/main.sld")) program)))
                  (expect (primitive-scheme program "vector-ref")
                          (list (list "A") "(Fn (Vector A) I64 → A)"))
                  (expect (primitive-scheme program "vector-generate")
                          (list (list "A" "e")
                                "(Fn I64 (Fn I64 → A ! e) → (Vector A) ! e)"))
                  (expect (primitive-scheme program "array-ref")
                          (list (list "A") "(Fn (Array A) I64 → A)"))
                  (expect (primitive-scheme program "inherit-handlers")
                          (list (list "A" "e")
                                "(Fn (FnOnce → A ! e) → (FnOnce → A ! host) ! e)"))
                  (expect (map (lambda (record) (● record first))
                               (library-items program (program-items program)))
                          (list "main")))))

      ;; A library that derives without importing (snail shell wire) loads
      ;; it at its first deriving clause, and the wire's run of items comes
      ;; before the library's, not inside it: each run holds only the
      ;; definitions of the library it names, and the library's are the two
      ;; methods it derived. Repeating expansion preserves that order,
      ;; including when nothing else imports the wire.
      (define test-deriving-runs
        (lambda (root library) (create-directory* (string-append root "/sample"))
                (write-file (string-append root "/sample/shape.sld")
                            (string-append
                             "(define-library (sample shape) (export Shape) (import (snail core base))"
                             " (begin (struct Shape ((side I64)) (deriving Serialize Deserialize))))"))
                (write-file (string-append root "/main.sld")
                            "(import (snail core base) (sample shape)) (define example (Shape 2))")
                (let* ((expand (lambda ()
                                 (expand-program (list root library)
                                                 (lambda (loading forms)
                                                   (panic "unexpected producer"))
                                                 no-inputs
                                                 (string-append root "/main.sld"))))
                       (first (expand)))
                  (expect (every? own-run? (expansion-runs first)) #t)
                  (expect (run-length first "sample.shape") 2)
                  (expect (deriving-order first) (list "snail.shell.wire" "sample.shape" "main"))
                  (expect (deriving-order (expand))
                          (list "snail.shell.wire" "sample.shape" "main")))))

      ;; A library's derived instances hold while the implicit libraries'
      ;; interfaces do (#546): a definition added to the wire changes its
      ;; interface, so the library that derives is expanded under a new
      ;; key, though its text is the same. A body edit also re-expands the
      ;; wire's instance methods with fresh identities; derived evidence
      ;; must follow them. An unchanged build keeps its key. The wire is a
      ;; copy of the standard one, found first.
      (define test-deriving-key
        (lambda (root library)
          (let* ((wire (read-file (string-append library "/snail/shell/wire.sld")))
                 (end (- (string-length wire) 2))
                 (marked (lambda (value)
                           (string-append (substring wire 0 end)
                                          " (begin (: wire-marker I64) (define wire-marker "
                                          value
                                          ")))\n")))
                 (expand (lambda (text)
                           (write-file (string-append root "/snail/shell/wire.sld") text)
                           (expand-program (list root library)
                                           (lambda (loading forms) (panic "unexpected producer"))
                                           no-inputs
                                           (string-append root "/main.sld"))))
                 (key (lambda (expansion) (library-key expansion "sample.shape"))))
            (expect (substring wire end (string-length wire)) ")\n")
            (create-directory* (string-append root "/sample"))
            (create-directory* (string-append root "/snail/shell"))
            (write-file (string-append root "/sample/shape.sld")
                        (string-append
                         "(define-library (sample shape) (export Shape) (import (snail core base))"
                         " (begin (struct Shape ((side I64)) (deriving Serialize))))"))
            (write-file (string-append root "/main.sld")
                        "(import (snail core base) (sample shape)) (define example (Shape 2))")
            (let* ((first (expand wire))
                   (second (expand (marked "1")))
                   (third (expand (marked "2")))
                   (fourth (expand (marked "2"))))
              (expect (string=? (key first) (key second)) #f)
              (expect (string=? (key second) (key third)) #f)
              (expect (key fourth) (key third))))))

      (define expansion-runs
        (lambda (expansion) (let ((program (● expansion program)))
                              (library-items program (program-items program)))))

      (define own-run?
        (lambda (run) (every? (lambda (item)
                                (match item
                                  ((Define name _) (string=? (name-owner name) (● run first)))
                                  (_ #t)))
                              (● run second))))

      (define run-length
        (lambda (expansion name)
          (match (find (lambda (run) (string=? (● run first) name)) (expansion-runs expansion))
            ((Some run) (length (● run second)))
            ((None) -1))))

      (define deriving-order
        (lambda (expansion)
          (filter (lambda (name) (member? name (list "snail.shell.wire" "sample.shape" "main")))
                  (map (lambda (record) (● record first)) (expansion-runs expansion)))))

      (define primitive-scheme
        (lambda (program name) (match (program-value program (string-append "prim:" name))
                                 ((Some (Primitive scheme))
                                  (list (● scheme vars) (type->string (● scheme type))))
                                 (_ (list)))))

      (define assets-output
        (string-append
         "(define-library (sample assets) (export admin-bundle) (import (snail core base) (snail shell artifact)) "
         "(begin (: admin-bundle ArtifactBundle) (define admin-bundle (artifact-bundle \"admin\"))))"))

      (define write-sources
        (lambda (directory) (create-directory* (string-append directory "/walk/sample"))
                (create-directory* (string-append directory "/discover/sample"))
                (for-each (lambda (source)
                            (write-file (string-append directory "/" (● source first))
                                        (● source second)))
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
                                (Pair "discover/main.sld" discovery-main)))))

      (define discovery-main
        (string-append
         "(import (snail core base) (rename (snail shell artifact) (artifact-bundle bundle)) (sample assets))\n"
         "(define-syntax client-snapshot (syntax-rules () ((_) (bundle \"client\"))))\n"
         "(define-syntax unused (syntax-rules () ((_) (bundle \"does-not-exist\"))))\n"
         "(define snapshot (client-snapshot))\n"
         "(define again (client-snapshot))\n"))))
   (else)))
