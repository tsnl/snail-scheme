;; Located syntax to the core program. The expander is the only pass that knows
;; Snail-Core's binding forms. It loads libraries, resolves every identifier to a
;; binding, runs `syntax-rules` macros, records declared entities in the
;; program tables, and emits core expressions with unique names.
(define-library (snail-core compiler expand)
  (export
   ExpandedProgram
   ExpandedProgram-program
   empty-expansion
   library-key
   expand-program
   ArtifactUse
   ArtifactUse-name
   ArtifactUse-loc
   discover-artifacts
   LinkedFile
   LinkedFile-name
   LinkedFile-path
   library-links
   program-links
   LibraryFile
   DefinedLibrary
   GeneratedLibrary
   library-file
   program-imports
   implicit-libraries
   Reached
   Reached-library
   Reached-forms
   Reached-loc
   Reached-loading
   library-closure)
  (import
   (snail-core base)
   (snail-core table)
   (snail-core io)
   (snail-core compiler read)
   (only (snail-core compiler inputs)
         ArtifactFiles
         Inputs
         Inputs-artifacts
         producer-text
         generated-output
         ArtifactInput
         request-input!
         generating-stack)
   (snail-core compiler core)
   (snail-core compiler capabilities))
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
    (: binding-identity (-> Binding String))
    (define (binding-identity binding)
      (match binding
        ((Local name) name)
        ((Global name) name)
        ((TypeName name _ _) name)
        ((Alias name _ _ _) name)
        ((TypeVar _) "%type-variable")
        ((ClassName name) name)
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
      (Top
       ((key String)
        (imports (Table Binding)))))

    (: extend (-> Env Syntax Binding Env))
    (define (extend env ident binding)
      (Frame (ident-key ident) binding env))

    ;; A marked identifier is keyed by its mark, so the same name introduced by
    ;; two expansions binds two variables.
    (: ident-key (-> Syntax String))
    (define (ident-key ident)
      (match ident
        ((Ident _ (Some mark) _) (Mark-key mark))
        ((Ident name (None) _) name)
        (_ (panic "internal error: not an identifier"))))

    ;; An unbound marked identifier resolves as its original in the scope of
    ;; the macro that introduced it.
    (: resolve (-> Context Env Syntax (Option Binding)))
    (define (resolve cx env ident)
      (let ((key (ident-key ident)))
        (let lookup ((env env))
          (match env
            ((Frame other binding rest) (if (string=? other key) (Some binding) (lookup rest)))
            ((Top top imports)
             (match (top-binding cx top imports key)
               ((Some binding) (Some binding))
               ((None)
                (match ident
                  ((Ident _ (Some mark) _)
                   (resolve cx (scope-env cx (Mark-scope mark)) (Mark-original mark)))
                  (_ (None))))))))))

    ;; What a top level binds `key` to: its own definition, or else an
    ;; import.
    (: top-binding (-> Context String (Table Binding) String (Option Binding)))
    (define (top-binding cx top imports key)
      (match (table-ref (top-definitions cx top) key)
        ((Some binding) (Some binding))
        ((None) (table-ref imports key))))

    (: expect-ident (-> Syntax String Syntax))
    (define (expect-ident syntax what)
      (match syntax
        ((Ident _ _ _) syntax)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items of a form, or an error naming what was expected.
    (: form-items (-> Syntax String (List Syntax)))
    (define (form-items syntax what)
      (match syntax
        ((Form items _) items)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items after a form's head.
    (: form-tail (-> Syntax (List Syntax)))
    (define (form-tail syntax)
      (match syntax
        ((Form (Cons _ rest) _) rest)
        (_ (Nil))))

    (: head-binding (-> Context Env Syntax (Option Binding)))
    (define (head-binding cx env syntax)
      (match syntax
        ((Form (Cons head _) _)
         (match head
           ((Ident _ _ _) (resolve cx env head))
           (_ (None))))
        (_ (None))))

    (: core-form? (-> Context Env Syntax String Bool))
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
    ;; because running a program means compiling one; and `inputs` holds
    ;; what the build supplies in memory: completed targets' files and
    ;; producers' outputs.
    ;;
    ;; Scope, which loading a library replaces and which the importer gets
    ;; back unchanged: `prefix` names the library being expanded, so its
    ;; globals are `prefix:name`; `loading` the libraries whose imports are
    ;; being loaded, innermost first, so a library requested while it loads
    ;; is part of an import cycle; `aliases` the type aliases whose bodies
    ;; are being resolved, innermost first, so an alias that refers to itself
    ;; is caught; and what the library itself uses, newest first:
    ;; `artifact-uses`, the targets whose files it embeds, and `links`, the
    ;; files its `link-file` uses name.
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
       (generate (-> (List String) (List Syntax) Bytes ! fs))
       (inputs Inputs)
       (prefix String)
       (loading (List String))
       (aliases (List String))
       (artifact-uses (List ArtifactUse))
       (links (List LinkedFile))
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
    (: resumed (-> Context Context Context))
    (define (resumed outer inner)
      (Context (Context-predecessor outer)
               (Context-directories outer)
               (Context-generate outer)
               (Context-inputs outer)
               (Context-prefix outer)
               (Context-loading outer)
               (Context-aliases outer)
               (Context-artifact-uses outer)
               (Context-links outer)
               (Context-program inner)
               (Context-expanded inner)
               (Context-artifacts inner)
               (Context-counter inner)
               (Context-scopes inner)
               (Context-scope-count inner)
               (Context-tops inner)
               (Context-top-count inner) (Context-deriving inner)))

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
       (All (A B e)
            (-> Context (-> Context A (Pair B Context) ! e) (List A) (Pair (List B) Context) ! e)))
    (define (each cx step items)
      (let ((done (fold-left (lambda (done item)
                               (match (step (Pair-second done) item)
                                 ((Pair value cx) (Pair (Cons value (Pair-first done)) cx))))
                             (Pair (Nil) cx) items)))
        (Pair (reverse (Pair-first done)) (Pair-second done))))

    (type Exports (List (Pair String Binding)))

    ;; A library's use of a completed target's files, with the snapshot it
    ;; embedded.
    (struct ArtifactUse
      ((name String)
       (loc Loc)
       (files ArtifactFiles)))

    ;; A file a library links rather than embeds, which the build places
    ;; beside the payload: `name` is what the payload asks its host for, and
    ;; `path` where the build finds the file; `loc` is where the library
    ;; names it.
    (struct LinkedFile
      ((name String)
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

    (: artifact-files (-> Context String Loc (Pair ArtifactFiles Context)))
    (define (artifact-files cx name loc)
      (match (Context-artifacts cx)
        ((Supplied)
         (match (table-ref (Inputs-artifacts (Context-inputs cx)) name)
           ((Some files) (Pair files cx))
           ((None) (request-input! (ArtifactInput name loc)))))
        ((Discovering uses)
         (Pair (Nil)
               (Context-artifacts-set cx (Discovering (Cons (ArtifactUse name loc (Nil)) uses)))))))

    ;; A library as a build expanded it: its build key, the canonical text
    ;; of its declarations with the interfaces of its imports, which decides
    ;; whether a later build may replay it; its own interface; its exports;
    ;; everything it added to the program; the targets whose files it
    ;; embeds; and the files it links.
    (struct Expanded
      ((key String)
       (body-key String)
       (interface String)
       (exports Exports)
       (delta Program)
       (artifacts (List ArtifactUse))
       (links (List LinkedFile))))

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
       (-> (List String)
           (-> (List String) (List Syntax) Bytes ! fs)
           Inputs
           ArtifactSource
           ExpandedProgram
           Context))
    (define (new-context directories generate inputs artifacts predecessor)
      (Context (ExpandedProgram-libraries predecessor)
               directories
               generate
               inputs
               ""
               (Nil)
               (Nil)
               (Nil)
               (Nil)
               empty-program
               empty-table
               artifacts
               (ExpandedProgram-counter predecessor)
               (ExpandedProgram-scopes predecessor)
               (ExpandedProgram-scope-count predecessor)
               (ExpandedProgram-tops predecessor)
               (ExpandedProgram-top-count predecessor)
               (None)))

    ;; What a finished build hands the next: everything it learned.
    (: expanded-program (-> Context ExpandedProgram))
    (define (expanded-program cx)
      (ExpandedProgram (Context-program cx)
                       (Context-expanded cx)
                       (Context-counter cx)
                       (Context-scope-count cx)
                       (Context-scopes cx)
                       (Context-tops cx) (Context-top-count cx)))

    ;; Each addition hands back the context with a larger program.
    (: add-value (-> Context String Value Context))
    (define (add-value cx name value)
      (Context-program-set cx (program-with-value (Context-program cx) name value)))

    (: add-item (-> Context Item Context))
    (define (add-item cx item)
      (Context-program-set cx (program-with-item (Context-program cx) item)))

    (: fresh (-> Context String (Pair String Context)))
    (define (fresh cx base)
      (let ((count (+ (Context-counter cx) 1)))
        (Pair (string-append base "." (i64->string count)) (Context-counter-set cx count))))

    (: global-name (-> Context String String))
    (define (global-name cx key)
      (string-append (Context-prefix cx) ":" key))

    ;; Numbers `env` as the next scope.
    (: register-scope (-> Context Env (Pair I64 Context)))
    (define (register-scope cx env)
      (let ((number (Context-scope-count cx)))
        (Pair number (scope-set (Context-scope-count-set cx (+ number 1)) number env))))

    (: scope-set (-> Context I64 Env Context))
    (define (scope-set cx number env)
      (Context-scopes-set cx (table-set (Context-scopes cx) (i64->string number) env)))

    (: scope-env (-> Context I64 Env))
    (define (scope-env cx number)
      (match (table-ref (Context-scopes cx) (i64->string number))
        ((Some env) env)
        ((None) (panic "internal error: unknown scope"))))

    ;; A top level over `imports` that defines nothing yet.
    (: new-top (-> Context (Table Binding) (Pair Env Context)))
    (define (new-top cx imports)
      (let ((number (Context-top-count cx)))
        (Pair (Top (i64->string number) imports) (Context-top-count-set cx (+ number 1)))))

    (: top-definitions (-> Context String (Table Binding)))
    (define (top-definitions cx top)
      (match (table-ref (Context-tops cx) top)
        ((Some definitions) definitions)
        ((None) empty-table)))

    ;; Binds a name at a top level, once.
    (: bind-top (-> Context Env Syntax Binding Context))
    (define (bind-top cx env ident binding)
      (match env
        ((Top top _)
         (let ((definitions (top-definitions cx top)))
           (when (table-contains? definitions (ident-key ident))
             (compile-error (syntax-loc ident)
                            (string-append "duplicate top-level definition " (Ident-name ident))))
           (Context-tops-set cx
                             (table-set (Context-tops cx)
                                        top
                                        (table-set definitions (ident-key ident) binding)))))
        (_ (panic "internal error: not a top level"))))

    ;; ---- The core library ----

    ;; (snail-core core) is the one library without a file: the core forms
    ;; and the builtin types, both listed in core.sld, and the effects the
    ;; compiler itself performs. Every other library, (snail-core primitive)
    ;; among them, is a file.
    (: core-library (-> Exports))
    (define (core-library)
      (append (map (lambda (name) (Pair name (Core name))) core-keywords)
              (append (map (lambda (entry)
                             (Pair (Pair-first entry)
                                   (TypeName (Pair-first entry) (Pair-second entry) (None))))
                           builtin-types)
                      (list (Pair "mut" (EffectName "mut")) (Pair "tasks" (EffectName "tasks"))))))

    (: builtin-library? (-> String Bool))
    (define (builtin-library? key)
      (string=? key "snail-core.core"))

    ;; ---- Libraries ----

    ;; `(snail-core base)` is the list ("snail-core" "base"); its globals are prefixed
    ;; `snail-core.base` and its source is `snail-core/base.sld` in a search directory.
    (: library-name (-> Syntax (List String)))
    (define (library-name syntax)
      (map (lambda (part)
             (match part
               ((Ident name _ _) name)
               ((Atom (DInt number) _) (i64->string number))
               (_ (compile-error (syntax-loc part) "expected a library name part"))))
           (form-items syntax "a library name")))

    (: check-library-name (-> Syntax (List String) Loc Unit))
    (define (check-library-name declared name loc)
      (when (string=? (string-join name ".") "prim")
        (compile-error loc "the prim library name is reserved for compiler primitives"))
      (unless (string=? (string-join (library-name declared) ".") (string-join name "."))
        (compile-error loc "library name does not match its path")))

    ;; A library's exports, resolved when an import asks: the compiler's own
    ;; for (snail-core core), else the library as this build expanded it,
    ;; which happens once, under the library's own scope, resumed in the
    ;; importer's.
    (: load-library (-> Context (List String) Loc (Pair Exports Context) ! fs))
    (define (load-library cx name loc)
      (let ((key (string-join name ".")))
        (cond ((builtin-library? key) (Pair (core-library) cx))
              ((member? key (Context-loading cx))
               (compile-error loc (string-append "library import cycle through " key)))
              (else (match (table-ref (Context-expanded cx) key)
                      ((Some entry) (Pair (Expanded-exports entry) cx))
                      ((None)
                       (match (read-library (Context-loading-set cx (Cons key (Context-loading cx)))
                                            name
                                            loc)
                         ((Pair exports loaded) (Pair exports (resumed cx loaded))))))))))

    (: read-library (-> Context (List String) Loc (Pair Exports Context) ! fs))
    (define (read-library cx name loc)
      (let ((path (library-path (Context-directories cx) name loc)))
        (expand-library-file cx name (file-library name (read-source path) path))))

    ;; Where a library's source is: the first search directory holding it.
    (: find-library (-> (List String) (List String) (Option String) ! fs))
    (define (find-library directories name)
      (let ((relative (string-append (string-join name "/") ".sld")))
        (find file-exists?
              (map (lambda (directory) (string-append directory "/" relative)) directories))))

    (: library-path (-> (List String) (List String) Loc String ! fs))
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
    (: file-library (-> (List String) (List Syntax) String LibraryFile ! fs))
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
          (producer (map with-included-bytes imports) (with-included-bytes expression) loc)
          (syntax-loc expression)))
        (_ (compile-error (Loc path 1 1)
                          "expected exactly one define-library or generate-library form"))))

    ;; The library a producer's output declares, as if it were written at
    ;; `loc` in the recipe's file.
    (: output-library-file (-> (List String) Bytes Loc LibraryFile ! fs))
    (define (output-library-file name bytes loc)
      (file-library name (list (with-included-bytes (decode-syntax bytes loc))) (Loc-file loc)))

    ;; A defined library expands its sections; a generated one expands the
    ;; library its producer's output declares.
    (: expand-library-file (-> Context (List String) LibraryFile (Pair Exports Context) ! fs))
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
    (: generated-bytes (-> Context (List Syntax) Bytes ! fs))
    (define (generated-bytes cx forms)
      (match (generated-output (Context-inputs cx) (producer-text (Context-directories cx) forms))
        ((Some bytes) bytes)
        ((None) ((Context-generate cx) (Context-loading cx) forms))))

    ;; The producer imports what the recipe imports and writes the syntax
    ;; its expression returns, a `(snail-core syntax)` Syntax.
    (: producer (-> (List Syntax) Syntax Loc (List Syntax)))
    (define (producer imports expression loc)
      (let ((write-library (Ident "write-generated-library" (None) loc)))
        (list (Form (Cons (Ident "import" (None) loc)
                          (append imports
                                  (list (Form (list (Ident "only" (None) loc)
                                                    (Form (list (Ident "snail-core" (None) loc)
                                                                (Ident "syntax" (None) loc))
                                                          loc)
                                                    write-library)
                                              loc))))
                    loc)
              (Form (list write-library expression) loc))))

    ;; ---- Sources ----

    ;; A source file's forms. `(include-bytes "path")` is another spelling
    ;; of a byte vector literal, which reads as `#u8(...)` holding the bytes
    ;; of the file at `path`, relative to the file the form is written in.
    (: read-source (-> String (List Syntax) ! fs))
    (define (read-source path)
      (map with-included-bytes (read-text (read-file path) path)))

    (: with-included-bytes (-> Syntax Syntax ! fs))
    (define (with-included-bytes syntax)
      (match syntax
        ((Form (Cons (Ident "include-bytes" _ _) args) loc)
         (Atom (DBytes (included-bytes args loc)) loc))
        ((Form items loc) (Form (map with-included-bytes items) loc))
        (_ syntax)))

    (: included-bytes (-> (List Syntax) Loc Bytes ! fs))
    (define (included-bytes args loc)
      (match args
        ((Cons (Atom (DString path) _) (Nil))
         (let ((resolved (beside (Loc-file loc) path)))
           (if (file-exists? resolved)
               (read-bytes resolved)
               (compile-error loc (string-append "no file to include at " resolved)))))
        (_ (compile-error loc "expected (include-bytes \"path\")"))))

    ;; `path` in the directory holding `file`, unless it is absolute.
    (: beside (-> String String String))
    (define (beside file path)
      (if (and (> (string-length path) 0) (char=? (string-ref path 0) #\/))
          path
          (let loop ((end (string-length file)))
            (cond ((= end 0) path)
                  ((char=? (string-ref file (- end 1)) #\/)
                   (string-append (substring file 0 end) path))
                  (else (loop (- end 1)))))))

    ;; ---- Linked files ----

    ;; `(link-file "path")` names a file the library links: it ships beside
    ;; the payload instead of in it, and the program gets a handle rather
    ;; than the bytes. The path is relative to the file it is written in, as
    ;; `include-bytes`'s is, and may not leave that file's directory. The
    ;; file ships under a name made from the library and the path, the same
    ;; on every host and in every build: `data/pixel.png` in (sample assets)
    ;; is `sample.assets/data/pixel.png`. The handle is what an import from
    ;; "snail.link" under that name returns, so the module records the
    ;; files it links where its host must see them: a host reads each before
    ;; it instantiates the module, and a module cannot be instantiated
    ;; without its files. Only the name enters the build key; the file's
    ;; bytes do not, so editing the file rebuilds nothing, and the build
    ;; only places it again.
    (: expand-link-file (-> Context (List Syntax) Loc (Pair Expr Context)))
    (define (expand-link-file cx items loc)
      (match items
        ((Cons _ (Cons (Atom (DString path) path-loc) (Nil)))
         (let ((relative (linked-path path path-loc)))
           (expanding cx ((name (record-link relative path-loc)))
                      (let ((handle (global-name cx (string-append "%link " relative))))
                        (Pair (expr (App (expr (Var handle (Nil) (Nil)) loc) (Nil)) loc)
                              (add-value cx
                                         handle
                                         (Foreign (Import "snail.link" name)
                                                  (mono-scheme
                                                   (TFun (Nil) (TCon "I32" (Nil)) empty-row)))))))))
        (_ (compile-error loc "link-bytes expects a literal relative path"))))

    ;; Records the file a use names on the library, once, and returns the
    ;; name it ships under. A macro whose template holds the path names a
    ;; file beside the macro's library, so two files could claim one name;
    ;; that is an error.
    (: record-link (-> Context String Loc (Pair String Context)))
    (define (record-link cx relative loc)
      (let ((name (string-append (Context-prefix cx) "/" relative))
            (path (beside (Loc-file loc) relative)))
        (match (find (lambda (link) (string=? (LinkedFile-name link) name)) (Context-links cx))
          ((Some link)
           (unless (string=? (LinkedFile-path link) path)
             (compile-error loc
                            (string-append "two files link as "
                                           name
                                           ": "
                                           (LinkedFile-path link)
                                           " and "
                                           path)))
           (Pair name cx))
          ((None)
           (Pair name
                 (Context-links-set cx (Cons (LinkedFile name path loc) (Context-links cx))))))))

    ;; A linked path in its canonical form: names separated by `/`, where
    ;; `.` is the directory it is in and `..` its parent, so
    ;; `data/../pixel.png` is `pixel.png`. A path that is absolute, has an
    ;; empty name, names nothing, or climbs out of the directory is refused,
    ;; since the payload could not ship its file under a name of its own.
    (: linked-path (-> String Loc String))
    (define (linked-path path loc)
      (let loop ((names (path-names path)) (kept (Nil)))
        (match names
          ((Nil)
           (if (null? kept)
               (compile-error loc (string-append "link-bytes names no file: " path))
               (string-join (reverse kept) "/")))
          ((Cons "." rest) (loop rest kept))
          ((Cons ".." rest)
           (match kept
             ((Cons _ parent) (loop rest parent))
             ((Nil)
              (compile-error loc
                             (string-append "link-bytes may not leave the library's directory: "
                                            path)))))
          ((Cons "" _)
           (compile-error loc
                          (string-append
                           "link-bytes takes a path relative to the library, with no empty names: "
                           path)))
          ((Cons name rest) (loop rest (Cons name kept))))))

    (: path-names (-> String (List String)))
    (define (path-names path)
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (path-names (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    ;; A library's linked files must exist when it expands, though the build
    ;; copies them only later; the message names the library and the path.
    (: check-linked-file (-> String LinkedFile Unit ! fs))
    (define (check-linked-file library link)
      (unless (linked-file-present? link)
        (compile-error (LinkedFile-loc link)
                       (string-append "the library " library " links "
                                      (substring (LinkedFile-name link)
                                                 (+ (string-length library) 1)
                                                 (string-length (LinkedFile-name link)))
                                      ", but there is no file at " (LinkedFile-path link)))))

    ;; A replayed library checks only that its files are still there: their
    ;; names are in its key, and their bytes in no key at all.
    (: linked-file-present? (-> LinkedFile Bool ! fs))
    (define (linked-file-present? link)
      (file-exists? (LinkedFile-path link)))

    ;; The files a library links, as the build expanded it, in the order
    ;; its uses were reached.
    (: library-links (-> ExpandedProgram String (List LinkedFile)))
    (define (library-links expansion name)
      (match (table-ref (ExpandedProgram-libraries expansion) name)
        ((Some entry) (Expanded-links entry))
        ((None) (Nil))))

    ;; The files the whole program links: each library's, in program order.
    (: program-links (-> ExpandedProgram (List LinkedFile)))
    (define (program-links expansion)
      (let ((program (ExpandedProgram-program expansion)))
        (concatenate (map (lambda (library) (library-links expansion (Pair-first library)))
                          (library-items program (program-items program))))))

    ;; Loads the imports, then replays the library from the build before
    ;; where it may, or expands it; either way the library is recorded for
    ;; the next build. Its uses and links start empty, after its imports
    ;; have loaded with their own.
    (: expand-sections (-> Context (List (Pair String (List Syntax))) (Pair Exports Context) ! fs))
    (define (expand-sections cx sections)
      (expanding cx ((env (import-env (section-items sections "import"))))
                 (let* ((key (sections-key cx sections))
                        (cx (Context-links-set (Context-artifact-uses-set cx (Nil)) (Nil))))
                   (expanding cx ((previous (replayable key)))
                              (match previous
                                ((Some entry) (replay cx entry))
                                ((None) (expand-recorded cx sections env key)))))))

    ;; The primitive library's body is its declarations, which add no items,
    ;; so it records no run and has no module.
    (: expand-library-body
       (-> Context (List (Pair String (List Syntax))) Env (Pair Exports Context) ! fs))
    (define (expand-library-body cx sections env)
      (let* ((forms (section-items sections "begin"))
             (cx (if (primitive-library? cx)
                     (fold-left (lambda (cx form) (declare-primitive cx env form)) cx forms)
                     (expand-library-run cx env forms))))
        (Pair (map (lambda (spec) (export-entry cx env spec)) (section-items sections "export"))
              cx)))

    ;; The body's items follow those of the library's imports, and the
    ;; program records how many it added, so its items divide back into
    ;; libraries.
    (: expand-library-run (-> Context Env (List Syntax) Context ! fs))
    (define (expand-library-run cx env forms)
      (let* ((before (length (program-items (Context-program cx))))
             (cx (expand-top-level cx env forms))
             (count (- (length (program-items (Context-program cx))) before)))
        (Context-program-set cx
                             (program-with-library (Context-program cx)
                                                   (Context-prefix cx)
                                                   count))))

    ;; Each declaration is a section of imports, exports or definitions, or a
    ;; `cond-expand` choosing more declarations.
    (: library-sections (-> Syntax (List (Pair String (List Syntax)))))
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
    (: cond-expand-sections (-> (List Syntax) (List (Pair String (List Syntax)))))
    (define (cond-expand-sections clauses)
      (match clauses
        ((Nil) (Nil))
        ((Cons (Form (Cons requirement declarations) _) rest)
         (if (feature? requirement)
             (concatenate (map library-sections declarations))
             (cond-expand-sections rest)))
        ((Cons clause _)
         (compile-error (syntax-loc clause) "expected (requirement declaration ...)"))))

    (: feature? (-> Syntax Bool))
    (define (feature? requirement)
      (match requirement
        ((Ident name _ _) (or (string=? name "snail-core") (string=? name "else")))
        ((Form (Cons (Ident "and" _ _) items) _) (every? feature? items))
        ((Form (Cons (Ident "or" _ _) items) _) (any? feature? items))
        ((Form (Cons (Ident "not" _ _) (Cons item (Nil))) _) (not (feature? item)))
        (_ #f)))

    (: section-items (-> (List (Pair String (List Syntax))) String (List Syntax)))
    (define (section-items sections kind)
      (concatenate
       (map Pair-second (filter (lambda (section) (string=? (Pair-first section) kind)) sections))))

    ;; A program is a sequence of imports followed by a body, which counts as
    ;; a library named `main` that exports nothing. A build replays what it
    ;; can of `predecessor`, the build before. A producer program begins
    ;; with `(generating ...)`, and its imports load inside the libraries
    ;; that form names, so one that leads back to them is a cycle.
    (: expand-program
       (-> (List String)
           (-> (List String) (List Syntax) Bytes ! fs)
           Inputs
           String
           ExpandedProgram
           ExpandedProgram
           ! fs))
    (define (expand-program directories generate inputs path predecessor)
      (expanded-program
       (expand-source (new-context directories generate inputs (Supplied) predecessor) path)))

    (: expand-source (-> Context String Context ! fs))
    (define (expand-source cx path)
      (let* ((source (generating-stack (read-source path)))
             (parts (program-parts (Pair-second source)))
             (cx (Context-loading-set (Context-prefix-set cx "main") (Pair-first source))))
        (Pair-second (expand-sections cx
                                      (list (Pair "import" (Pair-first parts))
                                            (Pair "begin" (Pair-second parts)))))))

    ;; A program's leading `import` forms' specs, and the body after them.
    (: program-parts (-> (List Syntax) (Pair (List Syntax) (List Syntax))))
    (define (program-parts forms)
      (match forms
        ((Cons (Form (Cons (Ident "import" _ _) specs) _) rest)
         (let ((parts (program-parts rest)))
           (Pair (append specs (Pair-first parts)) (Pair-second parts))))
        (_ (Pair (Nil) forms))))

    ;; The import specs of a program's leading `import` forms.
    (: program-imports (-> (List Syntax) (List Syntax)))
    (define (program-imports forms)
      (Pair-first (program-parts forms)))

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
    (: library-closure (-> (List String) Inputs (List String) (List Syntax) (List Reached) ! fs))
    (define (library-closure directories inputs loading imports)
      (let* ((walk (walk-imports (Walk directories inputs empty-table (Nil)) loading imports))
             (walk (fold-left (lambda (walk name) (walk-implicit walk loading name))
                              walk
                              implicit-libraries)))
        (reverse (Walk-reached walk))))

    (: walk-imports (-> Walk (List String) (List Syntax) Walk ! fs))
    (define (walk-imports walk loading specs)
      (fold-left (lambda (walk spec)
                   (walk-library walk loading (library-name (spec-library spec)) (syntax-loc spec)))
                 walk
                 specs))

    ;; Only a library that derives loads these, so one need not exist.
    (: walk-implicit (-> Walk (List String) (List String) Walk ! fs))
    (define (walk-implicit walk loading name)
      (match (find-library (Walk-directories walk) name)
        ((Some path) (walk-library walk loading name (Loc path 1 1)))
        ((None) walk)))

    ;; The checks are `load-library`'s, in its order: (snail-core core) has
    ;; no file, and a library already loading is a cycle.
    (: walk-library (-> Walk (List String) (List String) Loc Walk ! fs))
    (define (walk-library walk loading name loc)
      (let ((key (string-join name ".")))
        (cond ((builtin-library? key) walk)
              ((member? key loading)
               (compile-error loc (string-append "library import cycle through " key)))
              ((table-contains? (Walk-visited walk) key) walk)
              (else (walk-file (Walk-visited-set walk (table-set (Walk-visited walk) key #t))
                               (Cons key loading)
                               name
                               (library-file (Walk-directories walk) name loc))))))

    (: walk-file (-> Walk (List String) (List String) LibraryFile Walk ! fs))
    (define (walk-file walk loading name file)
      (match file
        ((DefinedLibrary sections) (walk-imports walk loading (section-items sections "import")))
        ((GeneratedLibrary forms loc)
         (let ((walk (Walk-reached-set walk
                                       (Cons (Reached name forms loc loading)
                                             (Walk-reached walk)))))
           (match (generated-output (Walk-inputs walk)
                                    (producer-text (Walk-directories walk) forms))
             ((Some bytes) (walk-file walk loading name (output-library-file name bytes loc)))
             ((None) walk))))))

    ;; A library's file as a walk reads it: as `read-library` does, except
    ;; that the files a defined library includes are not read, since they
    ;; cannot name a library. (snail-core core) needs nothing.
    (: library-file (-> (List String) (List String) Loc LibraryFile ! fs))
    (define (library-file directories name loc)
      (if (builtin-library? (string-join name "."))
          (DefinedLibrary (Nil))
          (let ((path (library-path directories name loc)))
            (file-library name (read-text (read-file path) path) path))))

    ;; ---- Discovering artifact uses ----

    ;; The targets whose files the program at `path` embeds: each
    ;; `artifact-files` use, once for each library that makes it, in the
    ;; order expansion reaches it. This is the expander itself, supplied no
    ;; target's files, so a use that only an unexpanded macro template
    ;; names is no use. Each producer the program reaches must have its
    ;; output in `inputs`: discovery is for a program whose closure waits
    ;; for nothing.
    (: discover-artifacts (-> (List String) Inputs String (List ArtifactUse) ! fs))
    (define (discover-artifacts directories inputs path)
      (match (Context-artifacts (expand-source (new-context directories
                                                            unsupplied-producer
                                                            inputs
                                                            (Discovering (Nil))
                                                            empty-expansion)
                                               path))
        ((Discovering uses) (reverse uses))
        ((Supplied) (Nil))))

    (: unsupplied-producer (-> (List String) (List Syntax) Bytes))
    (define (unsupplied-producer loading forms)
      (panic "internal error: discovery reached a producer whose output was not supplied"))

    ;; ---- Replaying libraries ----

    ;; Ordinary source/import eligibility is checked before these requests:
    ;; a changed body may have removed an old dependency. Every candidate
    ;; replay still requires the recorded inputs and compares exact file
    ;; contents. Removing an invocation must not require its obsolete input.
    (: artifacts-current? (-> Context (List ArtifactUse) (Pair Bool Context)))
    (define (artifacts-current? cx uses)
      (match uses
        ((Nil) (Pair #t cx))
        ((Cons use rest)
         (expanding cx ((files (artifact-files (ArtifactUse-name use) (ArtifactUse-loc use))))
                    (if (artifact-files=? (ArtifactUse-files use) files)
                        (artifacts-current? cx rest)
                        (Pair #f cx))))))

    (: artifact-files=? (-> ArtifactFiles ArtifactFiles Bool))
    (define (artifact-files=? left right)
      (match (Pair left right)
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons a rest-a) (Cons b rest-b))
         (and (string=? (Pair-first a) (Pair-first b))
              (bytes=? (Pair-second a) (Pair-second b))
              (artifact-files=? rest-a rest-b)))
        (_ #f)))

    ;; The library as the build before expanded it, if this build may replay
    ;; it: its declarations and its imports' interfaces are unchanged, its
    ;; embedded files current and its linked files present.
    (: replayable (-> Context String (Pair (Option Expanded) Context) ! fs))
    (define (replayable cx key)
      (match (table-ref (Context-predecessor cx) (Context-prefix cx))
        ((Some entry)
         (if (string=? (Expanded-key entry) key)
             (expanding cx ((current (artifacts-current? (Expanded-artifacts entry))))
                        (Pair (if (and current (every? linked-file-present? (Expanded-links entry)))
                                  (Some entry)
                                  (None))
                              cx))
             (Pair (None) cx)))
        ((None) (Pair (None) cx))))

    ;; A library replayed adds what it added in the build before. The
    ;; generation handoff is functional: `expand-program` takes the previous
    ;; generation as an argument, `Context-predecessor` holds it read-only,
    ;; and `program-with` unions persistent tables, so a replayed library's
    ;; values alias the ones it produced before rather than being rebuilt.
    (: replay (-> Context Expanded (Pair Exports Context)))
    (define (replay cx entry)
      (Pair (Expanded-exports entry)
            (record
             (Context-program-set cx (program-with (Context-program cx) (Expanded-delta entry)))
             entry)))

    ;; The fresh artifact stamp identifies each new artifact-bearing
    ;; expansion. The counter continues from the last
    ;; successful build; replay keeps its old stamp. It enters both the
    ;; checked-body key and importers' interface keys, including generic
    ;; importers that specialize this library's body into their own module.
    ;; Stamps identify entries in one session lineage, not global content.
    (: artifact-stamp (-> Context (List ArtifactUse) (Pair String Context)))
    (define (artifact-stamp cx uses)
      (if (null? uses) (Pair "" cx) (fresh cx " artifact-")))

    (: expand-recorded
       (-> Context (List (Pair String (List Syntax))) Env String (Pair Exports Context) ! fs))
    (define (expand-recorded cx sections env key)
      (expanding cx ((exports (expand-library-body sections env)))
                 (let ((uses (Context-artifact-uses cx)) (links (reverse (Context-links cx))))
                   (expanding cx ((stamp (artifact-stamp uses)))
                              (for-each (lambda (link) (check-linked-file (Context-prefix cx) link))
                                        links)
                              (Pair exports
                                    (record cx
                                            (Expanded key
                                                      (string-append key stamp)
                                                      (string-append (interface-hash cx sections)
                                                                     stamp)
                                                      exports
                                                      (library-delta cx) uses links)))))))

    ;; What the library added, which a later build replays.
    (: library-delta (-> Context Program))
    (define (library-delta cx)
      (if (primitive-library? cx)
          (primitive-delta (Context-program cx))
          (program-delta (Context-program cx) (Context-prefix cx))))

    (: record (-> Context Expanded Context))
    (define (record cx entry)
      (Context-expanded-set cx (table-set (Context-expanded cx) (Context-prefix cx) entry)))

    ;; ---- Build keys ----

    ;; A library's build key: the canonical text of its declarations, with
    ;; the interfaces of its imports.
    (: sections-key (-> Context (List (Pair String (List Syntax))) String))
    (define (sections-key cx sections)
      (string-append (string-join (map (lambda (section)
                                         (string-append (Pair-first section)
                                                        " "
                                                        (forms-text (Pair-second section))))
                                       sections)
                                  "\n")
                     "\n" (imports-interfaces cx sections)))

    (: forms-text (-> (List Syntax) String))
    (define (forms-text forms)
      (string-join (map syntax->key forms) "\n"))

    ;; Syntax as text that keys a build. A byte vector shows only its length
    ;; and a hash of its bytes, so a library that embeds megabytes keys on a
    ;; few characters.
    (: syntax->key (-> Syntax String))
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
    (: bytes-hash (-> Bytes I64))
    (define (bytes-hash bytes)
      (vector-fold (lambda (hash byte) (fnv-step hash (i32->i64 (u8->i32 byte)))) fnv-offset bytes))

    ;; Each imported library's interface, as this build expanded it; the
    ;; compiler's own libraries never change.
    (: imports-interfaces (-> Context (List (Pair String (List Syntax))) String))
    (define (imports-interfaces cx sections)
      (string-join (map (lambda (spec)
                          (match (table-ref (Context-expanded cx)
                                            (string-join (library-name (spec-library spec)) "."))
                            ((Some entry) (Expanded-interface entry))
                            ((None) "builtin")))
                        (section-items sections "import"))
                   " "))

    ;; The key a build expanded a library under. Anything made from the
    ;; library's expansion, such as its checked items, stays valid while its
    ;; key is unchanged.
    (: library-key (-> ExpandedProgram String String))
    (define (library-key expansion name)
      (match (table-ref (ExpandedProgram-libraries expansion) name)
        ((Some entry) (Expanded-body-key entry))
        ((None) "")))

    (: spec-library (-> Syntax Syntax))
    (define (spec-library spec)
      (match spec
        ((Form (Cons (Ident keyword _ _) (Cons inner _)) _)
         (if (member? keyword (list "only" "except" "prefix" "rename")) (spec-library inner) spec))
        (_ spec)))

    ;; What importers depend on: every declaration except the bodies of
    ;; definitions whose signatures are not generic, which only the
    ;; library's own module uses; and its imports' interfaces, since its
    ;; generic code carries theirs into importers.
    (: interface-hash (-> Context (List (Pair String (List Syntax))) String))
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
                                            "\n" (imports-interfaces cx sections))))))

    (: interface-form (-> Syntax (List String) String))
    (define (interface-form form signed)
      (match form
        ((Form (Cons (Ident "define" _ _) _) _)
         (let ((name (Ident-name (definition-name form))))
           (if (member? name signed) (string-append "(define " name ")") (syntax->key form))))
        (_ (syntax->key form))))

    (: monomorphic-signatures (-> (List Syntax) (List String)))
    (define (monomorphic-signatures forms)
      (concatenate (map (lambda (form)
                          (match form
                            ((Form (Cons (Ident ":" _ _)
                                         (Cons (Ident name _ _)
                                               (Cons (Form (Cons (Ident "All" _ _) _) _) (Nil))))
                                   _)
                             (Nil))
                            ((Form (Cons (Ident ":" _ _) (Cons (Ident name _ _) (Cons _ (Nil)))) _)
                             (list name))
                            (_ (Nil))))
                        forms)))

    ;; ---- Imports and exports ----

    ;; A top level over the bindings the specs provide, each loaded and
    ;; merged in turn.
    (: import-env (-> Context (List Syntax) (Pair Env Context) ! fs))
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

    (: import-binding (-> (Table Binding) (Pair String Binding) Loc (Table Binding)))
    (define (import-binding imports entry loc)
      (match (table-ref imports (Pair-first entry))
        ((Some existing)
         (if (string=? (binding-identity existing) (binding-identity (Pair-second entry)))
             imports
             (compile-error loc (string-append "conflicting imports of " (Pair-first entry)))))
        ((None) (table-set imports (Pair-first entry) (Pair-second entry)))))

    ;; The (name . binding) entries an import set provides.
    (: import-set (-> Context Syntax (Pair Exports Context) ! fs))
    (define (import-set cx spec)
      (match spec
        ((Form (Cons (Ident "only" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (expanding cx ((entries (checked-import-set inner idents)))
                      (Pair (filter (lambda (entry) (member? (Pair-first entry) names)) entries)
                            cx))))
        ((Form (Cons (Ident "except" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (expanding cx ((entries (checked-import-set inner idents)))
                      (Pair
                       (filter (lambda (entry) (not (member? (Pair-first entry) names))) entries)
                       cx))))
        ((Form (Cons (Ident "prefix" _ _) (Cons inner (Cons (Ident prefix _ _) (Nil)))) _)
         (expanding cx ((entries (import-set inner)))
                    (Pair (map (lambda (entry)
                                 (Pair (string-append prefix (Pair-first entry))
                                       (Pair-second entry)))
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
                                   (match (assoc-ref renames (Pair-first entry))
                                     ((Some renamed) (Pair renamed (Pair-second entry)))
                                     ((None) entry)))
                                 entries)
                            cx))))
        (_ (load-library cx (library-name spec) (syntax-loc spec)))))

    (: checked-import-set (-> Context Syntax (List Syntax) (Pair Exports Context) ! fs))
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

    (: ident-names (-> (List Syntax) (List String)))
    (define (ident-names idents)
      (map (lambda (ident) (Ident-name (expect-ident ident "an identifier"))) idents))

    (: rename-pair (-> Syntax (Pair String String)))
    (define (rename-pair syntax)
      (match syntax
        ((Form (Cons (Ident from _ _) (Cons (Ident to _ _) (Nil))) _) (Pair from to))
        (_ (compile-error (syntax-loc syntax) "expected (name new-name)"))))

    (: export-entry (-> Context Env Syntax (Pair String Binding)))
    (define (export-entry cx env spec)
      (match spec
        ((Ident name _ _) (Pair name (defined-binding cx env spec "exported name is not defined")))
        ((Form (Cons (Ident "rename" _ _) (Cons inner (Cons (Ident outer _ _) (Nil)))) _)
         (Pair outer (defined-binding cx env inner "exported name is not defined")))
        (_ (compile-error (syntax-loc spec) "expected an export specification"))))

    ;; The binding of an identifier that must be bound.
    (: defined-binding (-> Context Env Syntax String Binding))
    (define (defined-binding cx env ident message)
      (match (resolve cx env (expect-ident ident "an identifier"))
        ((Some binding) binding)
        ((None)
         (compile-error (syntax-loc ident) (string-append message ": " (Ident-name ident))))))

    ;; The unique name of a top-level definition the scan bound.
    (: global-binding (-> Context Env Syntax String))
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
    ;; every body sees every declaration and the bodies before it.
    (struct Pending
      ((keyword String)
       (form Syntax)
       (env Env)))

    (: declaration-keywords (List String))
    (define declaration-keywords
      (list ":" "struct" "enum" "type" "typeclass" "instance" "extern" "effect" "expose"))

    (: expand-top-level (-> Context Env (List Syntax) Context ! fs))
    (define (expand-top-level cx env forms)
      (expanding cx ((scanned (each (lambda (cx form) (scan-top-level cx env form)) forms)))
                 (let* ((pending (concatenate scanned))
                        (signatures
                         (fold-left (lambda (table entry) (with-signature cx table entry))
                                    empty-table
                                    pending)))
                   (expanding cx ((bodies (each (lambda (cx entry) (declare cx signatures entry))
                                                pending)))
                              (fold-left (lambda (cx body) (body cx)) cx (concatenate bodies))))))

    (: scan-top-level (-> Context Env Syntax (Pair (List Pending) Context) ! fs))
    (define (scan-top-level cx env form)
      (expanding cx ((form (expand-head env form)))
                 (match (head-binding cx env form)
                   ((Some (Core "begin"))
                    (expanding cx ((scanned (each (lambda (cx item) (scan-top-level cx env item))
                                                  (form-tail form))))
                               (Pair (concatenate scanned) cx)))
                   ((Some (Core "define-syntax")) (Pair (Nil) (define-top-macro cx env form)))
                   ((Some (Core "primitive"))
                    (compile-error (syntax-loc form)
                                   "primitives are declared only in (snail-core primitive)"))
                   ((Some (Core "define"))
                    (let ((ident (definition-name form)))
                      (Pair (list (Pending "define" form env))
                            (bind-top cx env ident (Global (unique-name cx ident))))))
                   ((Some (Core keyword))
                    (if (member? keyword declaration-keywords)
                        (scan-declared cx env keyword form)
                        (Pair (list (Pending "expression" form env)) cx)))
                   (_ (Pair (list (Pending "expression" form env)) cx)))))

    ;; A declaration binds its names, then the instances a struct or enum
    ;; derives are scanned after it.
    (: scan-declared (-> Context Env String Syntax (Pair (List Pending) Context) ! fs))
    (define (scan-declared cx env keyword form)
      (expanding cx ((then (scan-declaration env keyword form)))
                 (if (or (string=? keyword "struct") (string=? keyword "enum"))
                     (expanding cx ((derived (derived-instances form (string=? keyword "enum")))
                                    (scanned
                                     (each (lambda (cx instance) (scan-top-level cx env instance))
                                           derived)))
                                (Pair (Cons (Pending keyword form env) (concatenate scanned)) cx))
                     (Pair (list (Pending keyword form env)) cx))))

    (: definition-name (-> Syntax Syntax))
    (define (definition-name form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons name _) _) _)) _) (expect-ident name "a definition name"))
        ((Form (Cons _ (Cons name (Cons _ (Nil)))) _) (expect-ident name "a definition name"))
        (_ (compile-error (syntax-loc form)
                          "expected (define name value) or (define (name parameter ...) body ...)"))))

    (: declare
       (-> Context
           (Table (Pair Scheme (Option Loc)))
           Pending
           (Pair (List (-> Context Context)) Context)))
    (define (declare cx signatures pending)
      (let ((form (Pending-form pending)) (env (Pending-env pending)))
        (case (Pending-keyword pending)
          ((":") (Pair (Nil) cx))
          (("struct") (Pair (Nil) (declare-data cx env form #f)))
          (("enum") (Pair (Nil) (declare-data cx env form #t)))
          (("typeclass") (Pair (Nil) (declare-class cx env form)))
          (("instance") (declare-instance cx env form))
          (("extern") (Pair (Nil) (declare-extern cx env form)))
          (("effect") (Pair (Nil) (declare-effect cx env form)))
          (("define") (Pair (list (lambda (cx) (define-top-level cx signatures env form))) cx))
          (("expose") (Pair (list (lambda (cx) (add-item cx (expose-item cx env form)))) cx))
          (("expression")
           (Pair (list (lambda (cx)
                         (expanding cx ((value (expand-expr env form))) (add-item cx (Do value)))))
                 cx))
          (else (Pair (Nil) cx)))))

    ;; `(expose name "symbol")` exports a top-level function to the host.
    (: expose-item (-> Context Env Syntax Item))
    (define (expose-item cx env form)
      (match form
        ((Form (Cons _ (Cons name (Cons (Atom (DString symbol) _) (Nil)))) loc)
         (match (resolve cx env (expect-ident name "a function name"))
           ((Some (Global global)) (Expose global symbol loc))
           (_ (compile-error (syntax-loc name)
                             (string-append "only a top-level function can be exposed: "
                                            (Ident-name name))))))
        (_ (compile-error (syntax-loc form) "expected (expose name \"symbol\")"))))

    (: define-top-level (-> Context (Table (Pair Scheme (Option Loc))) Env Syntax Context))
    (define (define-top-level cx signatures env form)
      (let ((name (global-binding cx env (definition-name form))))
        (expanding cx ((then (add-value name (match (table-ref signatures name)
                                               ((Some (Pair scheme loc))
                                                (Defined (Some scheme) loc))
                                               ((None) (Defined (None) (None))))))
                       (value (definition-value env form)))
                   (add-item cx (Define name value)))))

    (: definition-value (-> Context Env Syntax (Pair Expr Context)))
    (define (definition-value cx env form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons _ params) _) body)) loc)
         (expand-lambda cx env params body loc))
        ((Form (Cons _ (Cons _ (Cons value (Nil)))) _) (expand-expr cx env value))
        (_ (compile-error (syntax-loc form) "expected a definition"))))

    ;; ---- Declarations ----

    ;; Pass 1 binds the names a declaration introduces; pass 2 resolves types.
    (: scan-declaration (-> Context Env String Syntax Context))
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
    (: unique-name (-> Context Syntax String))
    (define (unique-name cx ident)
      (global-name cx (ident-key ident)))

    ;; A struct's name is both its type and its constructor.
    (: scan-struct (-> Context Env Syntax Syntax Context))
    (define (scan-struct cx env head form)
      (let* ((name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (Some (unique-name cx name))))))
        (bind-fields cx env name (struct-fields form) #t)))

    (: scan-enum (-> Context Env Syntax Syntax Context))
    (define (scan-enum cx env head form)
      (let* ((name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (None)))))
        (fold-left (lambda (cx case) (scan-case cx env case)) cx (enum-cases form))))

    (: scan-alias (-> Context Env Syntax (List Syntax) Syntax Context))
    (define (scan-alias cx env head rest form)
      (let ((name (declared-name head)))
        (match rest
          ((Cons body (Nil))
           (bind-top cx env name (Alias (unique-name cx name) (declared-params head) body env)))
          (_ (compile-error (syntax-loc form) "expected (type Name type)")))))

    (: scan-class (-> Context Env Syntax (List Syntax) Context))
    (define (scan-class cx env head signatures)
      (let* ((name (declared-name head))
             (cx (bind-top cx env name (ClassName (unique-name cx name)))))
        (fold-left (lambda (cx signature)
                     (match signature
                       ((Form (Cons _ (Cons method _)) _) (bind-member cx env method))
                       (_ (compile-error (syntax-loc signature) "expected (: method type)"))))
                   cx signatures)))

    (: scan-effect (-> Context Env Syntax (List Syntax) Syntax Context))
    (define (scan-effect cx env head rest form)
      (let* ((name (expect-ident head "an effect name"))
             (cx (bind-top cx env name (EffectName (unique-name cx name)))))
        (match rest
          ((Cons operations _)
           (fold-left (lambda (cx operation)
                        (match operation
                          ((Form (Cons (Ident "ctl" _ _) (Cons operation-name (Cons _ (Nil)))) _)
                           (bind-member cx env operation-name))
                          ((Form (Cons operation-name _) _) (bind-member cx env operation-name))
                          (_ (compile-error (syntax-loc operation)
                                            "expected (operation type) or (ctl operation type)"))))
                      cx (form-items operations "a list of operations")))
          (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))")))))

    (: bind-member (-> Context Env Syntax Context))
    (define (bind-member cx env ident)
      (let ((ident (expect-ident ident "a name")))
        (bind-top cx env ident (Global (unique-name cx ident)))))

    (: scan-case (-> Context Env Syntax Context))
    (define (scan-case cx env case)
      (match (form-items case "an enum case")
        ((Cons name fields)
         (let ((cx (bind-member cx env name)))
           (bind-fields cx
                        env
                        name
                        (match fields
                          ((Cons fields _) (form-items fields "a field list"))
                          ((Nil) (Nil)))
                        #f)))
        ((Nil) (compile-error (syntax-loc case) "expected an enum case"))))

    ;; Accessors are `Name-field`; structs also get replacements `Name-field-set`.
    (: bind-fields (-> Context Env Syntax (List Syntax) Bool Context))
    (define (bind-fields cx env name fields setters?)
      (fold-left (lambda (cx field)
                   (match (form-items field "a field")
                     ((Cons field-name _)
                      (let ((cx (bind-member cx env (field-ident name field-name ""))))
                        (if setters? (bind-member cx env (field-ident name field-name "-set")) cx)))
                     ((Nil) (compile-error (syntax-loc field) "expected (field type)"))))
                 cx fields))

    ;; A field identifier shares the mark of its type's name, so a struct a
    ;; macro introduces has accessors only that expansion sees.
    (: field-ident (-> Syntax Syntax String Syntax))
    (define (field-ident name field suffix)
      (let ((text (string-append "-" (Ident-name (expect-ident field "a field name")) suffix)))
        (Ident (string-append (Ident-name name) text)
               (match (Ident-mark name)
                 ((Some mark)
                  (Some (Mark (string-append (Mark-key mark) text)
                              (Mark-original mark)
                              (Mark-scope mark))))
                 ((None) (None)))
               (syntax-loc field))))

    (: declared-name (-> Syntax Syntax))
    (define (declared-name head)
      (match head
        ((Form (Cons name _) _) (expect-ident name "a type name"))
        (_ (expect-ident head "a type name"))))

    (: declared-params (-> Syntax (List Syntax)))
    (define (declared-params head)
      (match head
        ((Form (Cons _ params) _)
         (map (lambda (param) (expect-ident param "a type parameter")) params))
        (_ (Nil))))

    ;; A struct or enum may end with `(deriving Class ...)`.
    (: deriving-clause? (-> Syntax Bool))
    (define (deriving-clause? syntax)
      (match syntax
        ((Form (Cons (Ident "deriving" _ _) _) _) #t)
        (_ #f)))

    ;; The declaration's items after its head, without deriving clauses.
    (: declaration-body (-> Syntax (List Syntax)))
    (define (declaration-body form)
      (match (form-tail form)
        ((Cons _ rest) (filter (lambda (item) (not (deriving-clause? item))) rest))
        ((Nil) (Nil))))

    (: declaration-head (-> Syntax Syntax))
    (define (declaration-head form)
      (match (form-tail form)
        ((Cons head _) head)
        ((Nil) (compile-error (syntax-loc form) "expected a declared name"))))

    (: struct-fields (-> Syntax (List Syntax)))
    (define (struct-fields form)
      (match (declaration-body form)
        ((Nil) (Nil))
        ((Cons fields (Nil)) (form-items fields "a field list"))
        (_ (compile-error (syntax-loc form) "expected (struct Name ((field type) ...))"))))

    (: enum-cases (-> Syntax (List Syntax)))
    (define (enum-cases form)
      (declaration-body form))

    (: derived-classes (-> Syntax (List Syntax)))
    (define (derived-classes form)
      (concatenate (map form-tail (filter deriving-clause? (form-tail form)))))

    ;; A type parameter scope binds each parameter to a rigid variable.
    (: type-scope (-> Env (List Syntax) Env))
    (define (type-scope env params)
      (fold-left (lambda (scope param) (extend scope param (TypeVar (TRigid (Ident-name param)))))
                 env
                 params))

    ;; A case is its name followed by an optional field list; a struct is one
    ;; case named after the struct.
    (: declare-data (-> Context Env Syntax Bool Context))
    (define (declare-data cx env form enum?)
      (let* ((head (declaration-head form)) (params (declared-params head))
             (id (match (resolve cx env (declared-name head))
                   ((Some (TypeName id _ _)) id)
                   (_ (panic "internal error: type"))))
             (scope (type-scope env params))
             (cases (if enum?
                        (map (lambda (case) (form-items case "an enum case")) (enum-cases form))
                        (list (Cons (declared-name head) (declaration-body form)))))
             (data (DataType id
                             (map Ident-name params)
                             (map-indexed (lambda (tag case) (resolve-case cx scope case id tag))
                                          cases)
                             enum?)))
        (Context-program-set cx
                             (fold-left (lambda (program case)
                                          (with-case-values program data case (not enum?)))
                                        (program-with-type (Context-program cx) data)
                                        (DataType-cases data)))))

    (: resolve-case (-> Context Env (List Syntax) String I64 Case))
    (define (resolve-case cx scope case type tag)
      (match case
        ((Cons name fields)
         (Case (constructor-name cx scope name) type tag
               (map (lambda (field) (resolve-field cx scope field))
                    (match fields
                      ((Cons fields _) (form-items fields "a field list"))
                      ((Nil) (Nil))))))
        ((Nil) (panic "internal error: empty case"))))

    (: resolve-field (-> Context Env Syntax Field))
    (define (resolve-field cx scope field)
      (match field
        ((Form (Cons name (Cons type (Nil))) _)
         (Field (Ident-name (expect-ident name "a field name")) (resolve-type cx scope type)))
        (_ (compile-error (syntax-loc field) "expected (field type)"))))

    (: constructor-name (-> Context Env Syntax String))
    (define (constructor-name cx env ident)
      (match (resolve cx env ident)
        ((Some (Global name)) name)
        ((Some (TypeName _ _ (Some constructor))) constructor)
        (_ (compile-error (syntax-loc ident)
                          (string-append "not a constructor: " (Ident-name ident))))))

    ;; A case's constructor, then each field's accessor and, for a struct,
    ;; its replacement.
    (: with-case-values (-> Program DataType Case Bool Program))
    (define (with-case-values program data case setters?)
      (let* ((params (DataType-params data)) (self (TCon (DataType-name data) (map TRigid params)))
             (constructor (Constructor case
                                       (Scheme params
                                               (Nil)
                                               (TFun (map Field-type (Case-fields case))
                                                     self
                                                     empty-row)))))
        (fold-left (lambda (program indexed)
                     (with-field-values program
                                        data
                                        case
                                        (Pair-first indexed)
                                        (Pair-second indexed)
                                        setters?))
                   (program-with-value program (Case-name case) constructor)
                   (zip (iota (length (Case-fields case))) (Case-fields case)))))

    (: with-field-values (-> Program DataType Case I64 Field Bool Program))
    (define (with-field-values program data case index field setters?)
      (let* ((params (DataType-params data))
             (self (TCon (DataType-name data) (map TRigid params)))
             (type (Field-type field))
             (accessor (string-append (Case-name case) "-" (Field-name field)))
             (program (program-with-value program
                                          accessor
                                          (Accessor case
                                                    index
                                                    (Scheme params
                                                            (Nil)
                                                            (TFun (list self) type empty-row))))))
        (if setters?
            (program-with-value program
                                (string-append accessor "-set")
                                (Replacer case
                                          index
                                          (Scheme params
                                                  (Nil)
                                                  (TFun (list self type) self empty-row))))
            program)))

    ;; The signatures with the one a `(: name type)` declares, and where it
    ;; was written. A signature a macro writes is held to each expansion's
    ;; body like any other, so a macro that cannot know the row takes it as
    ;; an argument.
    (: with-signature
       (-> Context (Table (Pair Scheme (Option Loc))) Pending (Table (Pair Scheme (Option Loc)))))
    (define (with-signature cx signatures pending)
      (if (string=? (Pending-keyword pending) ":")
          (match (Pending-form pending)
            ((Form (Cons _ (Cons name (Cons type (Nil)))) loc)
             (match (resolve cx (Pending-env pending) (expect-ident name "a name"))
               ((Some (Global global))
                (table-set signatures
                           global
                           (Pair (resolve-scheme cx (Pending-env pending) type) (Some loc))))
               (_ (compile-error (syntax-loc name)
                                 (string-append
                                  "signature names an undefined top-level definition: "
                                  (Ident-name name))))))
            (form (compile-error (syntax-loc form) "expected (: name type)")))
          signatures))

    (: declare-class (-> Context Env Syntax Context))
    (define (declare-class cx env form)
      (let* ((head (declaration-head form)) (params (declared-params head))
             (id (match (resolve cx env (declared-name head))
                   ((Some (ClassName id)) id)
                   (_ (panic "internal error: class"))))
             (scope (type-scope env params))
             (self (Constraint id (map (lambda (param) (TRigid (Ident-name param))) params))))
        (expanding cx ((methods (each (lambda (cx signature)
                                        (declare-method cx env scope id params self signature))
                                      (match (form-tail form)
                                        ((Cons _ signatures) signatures)
                                        ((Nil) (Nil))))))
                   (Context-program-set cx
                                        (program-with-class (Context-program cx)
                                                            (Class id
                                                                   (map Ident-name params)
                                                                   methods))))))

    (: declare-method
       (-> Context Env Env String (List Syntax) Constraint Syntax (Pair String Context)))
    (define (declare-method cx env scope class params self signature)
      (match signature
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (let ((own (resolve-scheme cx scope type)) (global (global-binding cx env name)))
           (Pair global
                 (add-value cx global
                            (Method class
                                    (Scheme (append (map Ident-name params) (Scheme-vars own))
                                            (Cons self (Scheme-constraints own))
                                            (Scheme-type own)))))))
        (_ (compile-error (syntax-loc signature) "expected (: method type)"))))

    ;; Returns one step per method, which expands its definition.
    (: declare-instance (-> Context Env Syntax (Pair (List (-> Context Context)) Context)))
    (define (declare-instance cx env form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons class-ident type-args) _) body)) loc)
         (let* ((class (match (resolve cx env class-ident)
                         ((Some (ClassName id)) (program-class (Context-program cx) id))
                         (_ (compile-error (syntax-loc class-ident)
                                           "instance of something that is not a typeclass"))))
                (parts (split-requires body)))
           (expanding cx ((instance (declared-instance env class type-args (Pair-first parts) loc))
                          (methods (each (lambda (cx definition)
                                           (instance-method cx env class instance definition))
                                         (Pair-second parts))))
                      (check-instance-methods class methods loc)
                      (check-overlap (Context-program cx) instance loc)
                      (Pair (map MethodDefinition-expand methods)
                            (Context-program-set cx
                                                 (program-with-instance (Context-program cx)
                                                                        (instance-with-methods
                                                                         instance
                                                                         methods)))))))
        (_
         (compile-error (syntax-loc form) "expected (instance (Class type ...) definition ...)"))))

    (: instance-with-methods (-> Instance (List MethodDefinition) Instance))
    (define (instance-with-methods instance methods)
      (Instance-methods-set instance
                            (map (lambda (method)
                                   (Pair (MethodDefinition-method method)
                                         (MethodDefinition-global method)))
                                 methods)))

    ;; Unbound identifiers in an instance head are its type variables.
    (: declared-instance
       (-> Context Env Class (List Syntax) (List Syntax) Loc (Pair Instance Context)))
    (define (declared-instance cx env class type-args requires loc)
      (when (capability-class? (Class-name class))
        (compile-error loc "Send and Sync instances are compiler-owned"))
      (let* ((vars (delete-duplicates string=?
                                      (concatenate
                                       (map (lambda (type) (free-type-names cx env type))
                                            type-args))))
             (scope (type-scope env (map (lambda (name) (Ident name (None) loc)) vars))))
        (expanding cx ((name (fresh-global (short-name (Class-name class)))))
                   (Pair (Instance name
                                   (Class-name class)
                                   vars
                                   (map (lambda (type) (resolve-type cx scope type)) type-args)
                                   (map (lambda (c) (resolve-constraint cx scope c)) requires)
                                   (Nil))
                         cx))))

    (: fresh-global (-> Context String (Pair String Context)))
    (define (fresh-global cx base)
      (expanding cx ((name (fresh base)))
                 (Pair (global-name cx name) cx)))

    ;; A body may start with `(requires (Class type ...) ...)`.
    (: split-requires (-> (List Syntax) (Pair (List Syntax) (List Syntax))))
    (define (split-requires items)
      (match items
        ((Cons (Form (Cons (Ident "requires" _ _) constraints) _) rest) (Pair constraints rest))
        (_ (Pair (Nil) items))))

    ;; One method of an instance: the class method it implements, the global
    ;; that holds its definition, and the step that expands it.
    (struct MethodDefinition
      ((method String)
       (global String)
       (expand (-> Context Context))))

    (: instance-method (-> Context Env Class Instance Syntax (Pair MethodDefinition Context)))
    (define (instance-method cx env class instance definition)
      (unless (core-form? cx env definition "define")
        (compile-error (syntax-loc definition) "expected a method definition"))
      (let* ((ident (definition-name definition))
             (method
              (match (find (lambda (method) (string=? (short-name method) (Ident-name ident)))
                           (Class-methods class))
                ((Some method) method)
                ((None)
                 (compile-error (syntax-loc ident)
                                (string-append "not a method of this class: "
                                               (Ident-name ident)))))))
        (expanding cx ((global (fresh-global (short-name method)))
                       (then (add-value global
                                        (Defined (Some (instance-method-scheme (Context-program cx)
                                                                               class
                                                                               method
                                                                               instance))
                                          (None)))))
                   (Pair (MethodDefinition method global
                                           (lambda (cx)
                                             (expanding cx ((value
                                                             (definition-value env definition)))
                                                        (add-item cx (Define global value)))))
                         cx))))

    (: instance-method-scheme (-> Program Class String Instance Scheme))
    (define (instance-method-scheme program class method instance)
      (match (program-value program method)
        ((Some (Method _ (Scheme method-vars (Cons _ own) type)))
         (let* ((class-vars (Class-params class))
                (substitution (zip class-vars (Instance-types instance))))
           (Scheme (append (Instance-vars instance) (drop method-vars (length class-vars)))
                   (append (Instance-requires instance)
                           (map (lambda (c) (substitute-constraint substitution c)) own))
                   (substitute substitution type))))
        (_ (panic "internal error: not a method"))))

    ;; Instance selection matches heads, so two heads may never both match
    ;; the same types. A type variable in either head matches anything.
    (: check-overlap (-> Program Instance Loc Unit))
    (define (check-overlap program instance loc)
      (for-each (lambda (other)
                  (when (heads-overlap? (Instance-types instance) (Instance-types other))
                    (compile-error loc "this instance overlaps another instance of the class")))
                (class-instances program (Instance-class instance))))

    (: heads-overlap? (-> (List Type) (List Type) Bool))
    (define (heads-overlap? as bs)
      (every? (lambda (pair) (head-overlaps? (Pair-first pair) (Pair-second pair))) (zip as bs)))

    (: head-overlaps? (-> Type Type Bool))
    (define (head-overlaps? a b)
      (match a
        ((TCon name args)
         (match b
           ((TCon other others) (and (string=? name other) (heads-overlap? args others)))
           ((TRigid _) #t)
           (_ #f)))
        (_ #t)))

    (: check-instance-methods (-> Class (List MethodDefinition) Loc Unit))
    (define (check-instance-methods class methods loc)
      (for-each (lambda (method)
                  (unless (any? (lambda (definition)
                                  (string=? (MethodDefinition-method definition) method))
                                methods)
                    (compile-error loc
                                   (string-append "instance is missing a method: "
                                                  (short-name method)))))
                (Class-methods class)))

    (: free-type-names (-> Context Env Syntax (List String)))
    (define (free-type-names cx env syntax)
      (match syntax
        ((Ident name _ _)
         (match (resolve cx env syntax)
           ((Some _) (Nil))
           ((None) (list name))))
        ((Form items _) (concatenate (map (lambda (item) (free-type-names cx env item)) items)))
        (_ (Nil))))

    (: declare-extern (-> Context Env Syntax Context))
    (define (declare-extern cx env form)
      (match form
        ((Form (Cons _
                     (Cons name
                           (Cons (Atom (DString module) _)
                                 (Cons (Atom (DString symbol) _) (Cons type (Nil))))))
               _)
         (add-value cx
                    (global-binding cx env name)
                    (Foreign (Import module symbol) (mono-scheme (resolve-type cx env type)))))
        (_ (compile-error (syntax-loc form) "expected (extern name \"module\" \"symbol\" type)"))))

    ;; Operations perform their effect; host defaults name Wasm imports.
    (: declare-effect (-> Context Env Syntax Context))
    (define (declare-effect cx env form)
      (match form
        ((Form (Cons _ (Cons name (Cons operations host))) _)
         (let ((id (match (resolve cx env name)
                     ((Some (EffectName id)) id)
                     (_ (panic "internal error: effect")))))
           (expanding cx ((declared
                           (each (lambda (cx operation) (declare-operation cx env id operation))
                                 (form-items operations "a list of operations"))))
                      (let* ((control (map Pair-first (filter Pair-second declared)))
                             (defaults (match host
                                         ((Cons clause (Nil)) (host-defaults cx env clause control))
                                         (_ (Nil)))))
                        (Context-program-set cx
                                             (program-with-effect (Context-program cx)
                                                                  (Effect id
                                                                          (map Pair-first declared)
                                                                          control
                                                                          defaults)))))))
        (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))"))))

    ;; `(name type)` declares an operation whose implementation returns to
    ;; its caller, `(ctl name type)` one whose implementation is handed the
    ;; rest of the handled computation as `resume`. The global name, and
    ;; whether it is a control operation.
    (: declare-operation (-> Context Env String Syntax (Pair (Pair String Bool) Context)))
    (define (declare-operation cx env effect operation)
      (match operation
        ((Form (Cons (Ident "ctl" _ _) (Cons name (Cons type (Nil)))) _)
         (declare-operation-type cx env effect name type #t))
        ((Form (Cons name (Cons type (Nil))) _) (declare-operation-type cx env effect name type #f))
        (_ (compile-error (syntax-loc operation)
                          "expected (operation type) or (ctl operation type)"))))

    (: declare-operation-type
       (-> Context Env String Syntax Syntax Bool (Pair (Pair String Bool) Context)))
    (define (declare-operation-type cx env effect name type control?)
      (match (resolve-scheme cx env type)
        ((Scheme vars constraints (TFun params result (TRow (Nil) (None))))
         (let ((global (global-binding cx env name)))
           (Pair (Pair global control?)
                 (add-value cx
                            global
                            (Operation effect
                                       (Scheme vars
                                               constraints
                                               (TFun params
                                                     result
                                                     (TRow (list effect) (None)))))))))
        (_ (compile-error (syntax-loc type)
                          "an operation has a total function type; its effect is implied"))))

    (: host-defaults (-> Context Env Syntax (List String) (List (Pair String Import))))
    ;; A control operation has no host default: the host cannot be handed
    ;; the rest of a computation, so a control effect must be handled.
    (define (host-defaults cx env syntax control)
      (match syntax
        ((Form (Cons (Ident "host" _ _) (Cons (Atom (DString module) _) (Cons operations (Nil)))) _)
         (map (lambda (operation)
                (match operation
                  ((Form (Cons name (Cons (Atom (DString symbol) _) (Nil))) _)
                   (let ((global (global-binding cx env name)))
                     (when (member? global control)
                       (compile-error (syntax-loc operation)
                                      "a control operation has no host default"))
                     (Pair global (Import module symbol))))
                  (_ (compile-error (syntax-loc operation) "expected (operation \"symbol\")"))))
              (form-items operations "a list of host operations")))
        (_ (compile-error (syntax-loc syntax)
                          "expected (host \"module\" ((operation \"symbol\") ...))"))))

    ;; ---- Primitives ----

    ;; (snail-core primitive) is a library file like any other, whose body
    ;; holds only primitive declarations. `(primitive name type)` declares an
    ;; operation the backend implements, as `extern` declares a foreign
    ;; function: it binds `name` to the global `prim:name`, the name the
    ;; checker, mono and `emit-primitive` know it by, and the value there is
    ;; a Primitive of the type's scheme. Elsewhere the form is an error.
    (: primitive-library? (-> Context Bool))
    (define (primitive-library? cx)
      (string=? (Context-prefix cx) "snail-core.primitive"))

    (: declare-primitive (-> Context Env Syntax Context))
    (define (declare-primitive cx env form)
      (unless (core-form? cx env form "primitive")
        (compile-error (syntax-loc form)
                       "(snail-core primitive) holds only primitive declarations"))
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (let* ((global (primitive-global (Ident-name (expect-ident name "a primitive name"))))
                (cx (bind-top cx env name (Global global))))
           (add-value cx global (Primitive (resolve-scheme cx env type)))))
        (_ (compile-error (syntax-loc form) "expected (primitive name type)"))))

    ;; ---- Types ----

    ;; `(All (A e) (requires (Class A) ...) type)` or a plain type.
    (: resolve-scheme (-> Context Env Syntax Scheme))
    (define (resolve-scheme cx env syntax)
      (match syntax
        ((Form (Cons (Ident "All" _ _) (Cons (Form params _) rest)) loc)
         (let* ((params (map (lambda (param) (expect-ident param "a type variable")) params))
                (scope (type-scope env params)) (parts (split-requires rest)))
           (match (Pair-second parts)
             ((Cons type (Nil))
              (Scheme (map Ident-name params)
                      (map (lambda (c) (resolve-constraint cx scope c)) (Pair-first parts))
                      (resolve-type cx scope type)))
             (_ (compile-error loc
                               "expected (All (variable ...) [(requires constraint ...)] type)")))))
        (_ (mono-scheme (resolve-type cx env syntax)))))

    (: resolve-constraint (-> Context Env Syntax Constraint))
    (define (resolve-constraint cx env syntax)
      (match syntax
        ((Form (Cons class types) loc)
         (match (resolve cx env (expect-ident class "a typeclass"))
           ((Some (ClassName id))
            (Constraint id (map (lambda (type) (resolve-type cx env type)) types)))
           (_ (compile-error loc "expected a typeclass constraint"))))
        (_ (compile-error (syntax-loc syntax) "expected (Class type ...)"))))

    (: resolve-type (-> Context Env Syntax Type))
    (define (resolve-type cx env syntax)
      (match syntax
        ((Ident _ _ loc) (resolve-type-name cx env syntax (Nil) loc))
        ((Form (Cons (Ident "->" _ _) items) loc) (resolve-arrow cx env items (Nil) loc))
        ((Form (Cons head args) loc)
         (resolve-type-name cx env (expect-ident head "a type constructor") args loc))
        (_ (compile-error (syntax-loc syntax) "expected a type"))))

    (: resolve-type-name (-> Context Env Syntax (List Syntax) Loc Type))
    (define (resolve-type-name cx env ident args loc)
      (match (resolve cx env ident)
        ((Some (TypeName name arity _))
         (unless (= arity (length args))
           (compile-error loc
                          (string-append "wrong number of type arguments: " (Ident-name ident))))
         (TCon name (map (lambda (arg) (resolve-type cx env arg)) args)))
        ((Some (TypeVar type))
         (if (null? args) type (compile-error loc "a type variable takes no arguments")))
        ((Some (Alias name params body alias-env))
         (unless (= (length params) (length args))
           (compile-error loc
                          (string-append "wrong number of alias arguments: " (Ident-name ident))))
         (when (member? name (Context-aliases cx))
           (compile-error loc (string-append "type alias refers to itself: " (Ident-name ident))))
         (let ((scope (fold-left (lambda (scope pair)
                                   (extend scope
                                           (Pair-first pair)
                                           (TypeVar (resolve-type cx env (Pair-second pair)))))
                                 alias-env (zip params args))))
           (resolve-type (Context-aliases-set cx (Cons name (Context-aliases cx))) scope body)))
        (_ (compile-error loc (string-append "not a type: " (Ident-name ident))))))

    ;; `(-> A B R)` or `(-> A B R ! label ... [row-variable])`.
    (: resolve-arrow (-> Context Env (List Syntax) (List Type) Loc Type))
    (define (resolve-arrow cx env items params loc)
      (match items
        ((Nil) (compile-error loc "an arrow needs a result type"))
        ((Cons result (Nil)) (TFun (reverse params) (resolve-type cx env result) empty-row))
        ((Cons result (Cons (Ident "!" _ _) labels))
         (TFun (reverse params) (resolve-type cx env result) (resolve-row cx env labels loc)))
        ((Cons param rest)
         (resolve-arrow cx env rest (Cons (resolve-type cx env param) params) loc))))

    (: resolve-row (-> Context Env (List Syntax) Loc Type))
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
    (: expand-artifact-files (-> Context Env (List Syntax) Loc (Pair Expr Context)))
    (define (expand-artifact-files cx env items loc)
      (match items
        ((Cons _ (Cons (Atom (DString name) _) (Cons file (Cons cons (Cons nil (Nil))))))
         (expanding cx ((files (resolve-artifact-files name loc)))
                    (expand-expr cx env (fold-right (lambda (entry rest)
                                                      (Form (list cons
                                                                  (Form (list file
                                                                              (Atom
                                                                               (DString
                                                                                (Pair-first entry))
                                                                               loc)
                                                                              (Atom
                                                                               (DBytes (Pair-second
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
    (: resolve-artifact-files (-> Context String Loc (Pair ArtifactFiles Context)))
    (define (resolve-artifact-files cx name loc)
      (match (find (lambda (use) (string=? name (ArtifactUse-name use))) (Context-artifact-uses cx))
        ((Some use) (Pair (ArtifactUse-files use) cx))
        ((None)
         (expanding cx ((files (artifact-files name loc)))
                    (Pair files
                          (Context-artifact-uses-set cx
                                                     (Cons (ArtifactUse name loc files)
                                                           (Context-artifact-uses cx))))))))

    ;; Expands macro uses at the head of a form until the head is not a macro.
    (: expand-head (-> Context Env Syntax (Pair Syntax Context)))
    (define (expand-head cx env syntax)
      (match (head-binding cx env syntax)
        ((Some (Macro _ literals rules scope))
         (expanding cx ((expanded (apply-macro env syntax literals rules scope)))
                    (expand-head cx env expanded)))
        (_ (Pair syntax cx))))

    (: expr (-> Term Loc Expr))
    (define (expr term loc)
      (Expr term unchecked loc))

    (: expand-expr (-> Context Env Syntax (Pair Expr Context)))
    (define (expand-expr cx env syntax)
      (expanding cx ((syntax (expand-head env syntax)))
                 (match syntax
                   ((Atom value loc) (Pair (expr (Lit value) loc) cx))
                   ((Ident _ _ loc) (Pair (expand-reference cx env syntax loc) cx))
                   ((Form (Nil) loc) (compile-error loc "empty application"))
                   ((Form (Cons head args) loc)
                    (match (head-binding cx env syntax)
                      ((Some (Core keyword)) (expand-core cx env keyword (Form-items syntax) loc))
                      (_ (expanding cx ((callee (expand-expr env head))
                                        (arguments (expand-each env args)))
                                    (Pair (expr (App callee arguments) loc) cx))))))))

    (: expand-each (-> Context Env (List Syntax) (Pair (List Expr) Context)))
    (define (expand-each cx env forms)
      (each cx (lambda (cx form) (expand-expr cx env form)) forms))

    (: expand-reference (-> Context Env Syntax Loc Expr))
    (define (expand-reference cx env ident loc)
      (match (resolve cx env ident)
        ((Some (Local name)) (expr (Var name (Nil) (Nil)) loc))
        ((Some (Global name)) (expr (Var name (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (Some constructor))) (expr (Var constructor (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (None)))
         (compile-error loc (string-append "a type is not a value: " (Ident-name ident))))
        ((None) (compile-error loc (string-append "unbound identifier " (Ident-name ident))))
        (_ (compile-error loc (string-append "syntax used as a value: " (Ident-name ident))))))

    (: expand-core (-> Context Env String (List Syntax) Loc (Pair Expr Context)))
    (define (expand-core cx env keyword items loc)
      (case keyword
        (("lambda")
         (match items
           ((Cons _ (Cons params body))
            (expand-lambda cx env (form-items params "a parameter list") body loc))
           (_ (compile-error loc "expected (lambda (parameter ...) body ...)"))))
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
        (("begin") (expand-body cx env (list-tail items 1) loc))
        (("let") (expand-let cx env items loc))
        (("match") (expand-match cx env items loc))
        (("artifact-files") (expand-artifact-files cx env items loc))
        (("link-file") (expand-link-file cx items loc))
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

    (: expand-lambda (-> Context Env (List Syntax) (List Syntax) Loc (Pair Expr Context)))
    (define (expand-lambda cx env params body loc)
      (expanding cx ((locals (bind-locals env params))
                     (body (expand-body (Pair-first locals) body loc)))
                 (Pair (expr (Lambda (Pair-second locals) body) loc) cx)))

    ;; Binds each identifier to a fresh local, in order; returns the longer
    ;; environment and the unique names.
    (: bind-locals (-> Context Env (List Syntax) (Pair (Pair Env (List String)) Context)))
    (define (bind-locals cx env idents)
      (expanding cx ((names (each (lambda (cx ident)
                                    (fresh cx (Ident-name (expect-ident ident "a variable name"))))
                                  idents)))
                 (Pair (Pair (fold-left (lambda (env bound)
                                          (extend env
                                                  (Pair-first bound)
                                                  (Local (Pair-second bound))))
                                        env
                                        (zip idents names))
                             names)
                       cx)))

    (: expand-body (-> Context Env (List Syntax) Loc (Pair Expr Context)))
    (define (expand-body cx env forms loc)
      (when (null? forms) (compile-error loc "empty body"))
      (expand-body-forms cx env forms (None) loc))

    ;; A local body is sequential: each definition is visible to the forms
    ;; after it, and a function definition is also visible to itself. A
    ;; signature annotates the definition that follows it.
    (: expand-body-forms
       (-> Context Env (List Syntax) (Option (Pair String Type)) Loc (Pair Expr Context)))
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
                                                   (Pair (expr (Seq value more) (Expr-loc value))
                                                         cx))))))))))

    (: local-signature (-> Context Env Syntax (Pair String Type)))
    (define (local-signature cx scope form)
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (Pair (Ident-name (expect-ident name "a name"))
               (Scheme-type (resolve-scheme cx scope type))))
        (_ (compile-error (syntax-loc form) "expected (: name type)"))))

    (: expand-local-definition
       (-> Context Env Syntax (List Syntax) (Option (Pair String Type)) Loc (Pair Expr Context)))
    (define (expand-local-definition cx scope form rest signature loc)
      (let ((ident (definition-name form)))
        (expanding cx ((name (fresh (Ident-name ident))))
                   (let ((inner (extend scope ident (Local name)))
                         (function? (match form
                                      ((Form (Cons _ (Cons (Form _ _) _)) _) #t)
                                      ((Form (Cons _ (Cons _ (Cons value (Nil)))) _)
                                       (core-form? cx scope value "lambda"))
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
    (: signed-value (-> Expr (Option (Pair String Type)) String Expr))
    (define (signed-value value signature name)
      (match signature
        ((Some (Pair signed type))
         (if (string=? signed name) (expr (Ann value type) (Expr-loc value)) value))
        ((None) value)))

    ;; `(let ((name value) ...) body ...)` or the named-let loop form.
    (: expand-let (-> Context Env (List Syntax) Loc (Pair Expr Context)))
    (define (expand-let cx env items loc)
      (match items
        ((Cons _ (Cons head (Cons more body)))
         (match head
           ((Ident _ _ _)
            (expand-named-let cx env head (form-items more "a list of bindings") body loc))
           ((Form bindings _) (expand-plain-let cx env bindings (Cons more body) loc))
           (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))
        (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))

    (: expand-named-let (-> Context Env Syntax (List Syntax) (List Syntax) Loc (Pair Expr Context)))
    (define (expand-named-let cx env ident bindings body loc)
      (expanding cx ((name (fresh (Ident-name ident)))
                     (loop (expand-lambda (extend env ident (Local name))
                                          (map binding-name bindings)
                                          body
                                          loc))
                     (initial
                      (each (lambda (cx binding) (expand-expr cx env (binding-value binding)))
                            bindings)))
                 (Pair
                  (expr (Let name loop (expr (App (expr (Var name (Nil) (Nil)) loc) initial) loc))
                        loc)
                  cx)))

    (: expand-plain-let (-> Context Env (List Syntax) (List Syntax) Loc (Pair Expr Context)))
    (define (expand-plain-let cx env bindings body loc)
      (expanding cx ((values
                      (each (lambda (cx binding) (expand-expr cx env (binding-value binding)))
                            bindings))
                     (locals (bind-locals env (map binding-name bindings)))
                     (body (expand-body (Pair-first locals) body loc)))
                 (Pair (fold-right (lambda (pair body)
                                     (expr (Let (Pair-first pair) (Pair-second pair) body) loc))
                                   body
                                   (zip (Pair-second locals) values))
                       cx)))

    (: binding-name (-> Syntax Syntax))
    (define (binding-name binding)
      (match (form-items binding "a (name value) binding")
        ((Cons name _) (expect-ident name "a binding name"))
        ((Nil) (compile-error (syntax-loc binding) "expected (name value)"))))

    (: binding-value (-> Syntax Syntax))
    (define (binding-value binding)
      (match binding
        ((Form (Cons _ (Cons value (Nil))) _) value)
        (_ (compile-error (syntax-loc binding) "expected (name value)"))))

    (: expand-handle (-> Context Env (List Syntax) Loc (Pair Expr Context)))
    (define (expand-handle cx env items loc)
      (match items
        ((Cons _ (Cons effect (Cons (Form implementations _) body)))
         (let ((id (match (resolve cx env (expect-ident effect "an effect name"))
                     ((Some (EffectName id)) id)
                     (_ (compile-error (syntax-loc effect)
                                       (string-append "not an effect: " (Ident-name effect)))))))
           (expanding cx ((implementations (each (lambda (cx implementation)
                                                   (expand-implementation cx env id implementation))
                                                 implementations))
                          (body (expand-body env body loc)))
                      (Pair (expr (Handle id implementations body) loc) cx))))
        (_
         (compile-error loc "expected (handle Effect ((operation implementation) ...) body ...)"))))

    (: expand-implementation (-> Context Env String Syntax (Pair (Pair String Expr) Context)))
    (define (expand-implementation cx env effect implementation)
      (match implementation
        ((Form (Cons name (Cons value (Nil))) _)
         (let ((operation (operation-name cx effect name)))
           (expanding cx ((value (expand-expr env value)))
                      (Pair (Pair operation value) cx))))
        (_ (compile-error (syntax-loc implementation) "expected (operation implementation)"))))

    ;; A handler names operations by their names within the effect, so they
    ;; need not be imported.
    (: operation-name (-> Context String Syntax String))
    (define (operation-name cx effect ident)
      (let ((name (Ident-name (expect-ident ident "an operation name"))))
        (match (find (lambda (operation) (string=? (short-name operation) name))
                     (Effect-operations (program-effect (Context-program cx) effect)))
          ((Some operation) operation)
          ((None)
           (compile-error (syntax-loc ident)
                          (string-append "not an operation of this effect: " name))))))

    (: constructor-case-id (-> Context Env Syntax I64))
    (define (constructor-case-id cx env constructor)
      (match (program-value (Context-program cx) (pattern-constructor cx env constructor))
        ((Some (Constructor case _)) (case-type-id (Context-program cx) case))
        (_ (compile-error (syntax-loc constructor) "not a constructor"))))

    ;; ---- Deriving ----

    ;; Derived instances are ordinary instance declarations, built as syntax.
    ;; Identifiers they introduce are marked to resolve in an environment of
    ;; the implicit libraries, whatever the declaring library imports.
    (: implicit-libraries (List (List String)))
    (define implicit-libraries
      (list (list "snail-core" "core") (list "snail-core" "primitive") (list "snail-core" "wire")))

    (: derived-instances (-> Context Syntax Bool (Pair (List Syntax) Context) ! fs))
    (define (derived-instances cx form enum?)
      (let* ((head (declaration-head form)) (loc (syntax-loc form))
             (cases (if enum?
                        (map (lambda (case)
                               (match (form-items case "an enum case")
                                 ((Cons name (Cons fields _))
                                  (Pair name (length (form-items fields "a field list"))))
                                 ((Cons name (Nil)) (Pair name 0))
                                 ((Nil) (compile-error (syntax-loc case) "expected an enum case"))))
                             (enum-cases form))
                        (list (Pair (declared-name head) (length (struct-fields form)))))))
        (each cx
              (lambda (cx class)
                (match class
                  ((Ident "Serialize" _ _) (serialize-instance cx head cases loc))
                  ((Ident "Deserialize" _ _) (deserialize-instance cx head cases loc))
                  (_ (compile-error (syntax-loc class)
                                    "only Serialize and Deserialize can be derived"))))
              (derived-classes form))))

    (: deriving-scope (-> Context Loc (Pair I64 Context) ! fs))
    (define (deriving-scope cx loc)
      (match (Context-deriving cx)
        ((Some scope) (Pair scope cx))
        ((None)
         (expanding cx ((exports
                         (each (lambda (cx name) (load-library cx name loc)) implicit-libraries))
                        (env (new-top (fold-left (lambda (table entry)
                                                   (table-set table
                                                              (Pair-first entry)
                                                              (Pair-second entry)))
                                                 empty-table (concatenate exports))))
                        (scope (register-scope env)))
                    (Pair scope (Context-deriving-set cx (Some scope)))))))

    ;; Builds the syntax of a derived instance; `w` makes wire identifiers.
    (struct Deriver
      ((scope I64)
       (loc Loc)))

    (: w (-> Deriver String Syntax))
    (define (w deriver name)
      (let ((loc (Deriver-loc deriver)))
        (Ident name
               (Some (Mark (string-append name "%deriving")
                           (Ident name (None) loc)
                           (Deriver-scope deriver)))
               loc)))

    (: f (-> Deriver (List Syntax) Syntax))
    (define (f deriver items)
      (Form items (Deriver-loc deriver)))

    (: field-idents (-> Deriver I64 (List Syntax)))
    (define (field-idents deriver count)
      (map (lambda (index) (w deriver (string-append "field" (i64->string index)))) (iota count)))

    (: instance-head (-> Deriver String Syntax (List Syntax)))
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
       (-> Context Syntax (List (Pair Syntax I64)) Loc (Pair Syntax Context) ! fs))
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

    (: serialize-case (-> Deriver (Pair Syntax I64) Syntax Syntax))
    (define (serialize-case d case encoder)
      (let ((fields (field-idents d (Pair-second case))))
        (f d (Cons (f d (Cons (Pair-first case) fields))
                   (Cons (f d
                            (list (w d "encode-case-id")
                                  encoder
                                  (f d (list (w d "case-id") (Pair-first case)))))
                         (append
                          (map (lambda (field) (f d (list (w d "encode") field encoder))) fields)
                          (list (f d (list (w d "unit"))))))))))

    ;; The TypeId read selects the case; an unknown one is a schema mismatch.
    (: deserialize-instance
       (-> Context Syntax (List (Pair Syntax I64)) Loc (Pair Syntax Context) ! fs))
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
                                                                                                 (Pair-first
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

    (: deserialize-case (-> Deriver (Pair Syntax I64) Syntax Syntax))
    (define (deserialize-case d case decoder)
      (let ((fields (field-idents d (Pair-second case))))
        (fold-right (lambda (field body)
                      (f d
                         (list (w d "let")
                               (f d (list (f d (list field (f d (list (w d "decode") decoder))))))
                               body)))
                    (f d (Cons (Pair-first case) fields)) fields)))

    ;; ---- Patterns ----

    (: expand-match (-> Context Env (List Syntax) Loc (Pair Expr Context)))
    (define (expand-match cx env items loc)
      (match items
        ((Cons _ (Cons scrutinee clauses))
         (expanding cx ((scrutinee (expand-expr env scrutinee))
                        (clauses (each (lambda (cx clause) (expand-clause cx env clause)) clauses)))
                    (Pair (expr (Match scrutinee clauses) loc) cx)))
        (_ (compile-error loc "expected (match expression clause ...)"))))

    ;; A clause binds its pattern's variables first, so the pattern itself
    ;; only looks names up.
    (: expand-clause (-> Context Env Syntax (Pair Clause Context)))
    (define (expand-clause cx env clause)
      (match (form-items clause "a match clause")
        ((Cons pattern body)
         (expanding cx ((locals (bind-locals env (pattern-variables pattern))))
                    (let* ((scope (Pair-first locals))
                           (pattern (expand-pattern cx env scope pattern)))
                      (expanding cx ((body (expand-body scope body (syntax-loc clause))))
                                 (Pair (Clause pattern body) cx)))))
        ((Nil) (compile-error (syntax-loc clause) "expected (pattern body ...)"))))

    ;; The variables of a pattern, in order, each named once.
    (: pattern-variables (-> Syntax (List Syntax)))
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

    (: pattern-idents (-> Syntax (List Syntax)))
    (define (pattern-idents syntax)
      (match syntax
        ((Ident "_" _ _) (Nil))
        ((Ident _ _ _) (list syntax))
        ((Form (Cons _ args) _) (concatenate (map pattern-idents args)))
        (_ (Nil))))

    ;; Bare identifiers are `_` or variables bound in `scope`; constructors
    ;; resolve in `env` and are always applied, as in `(None)`.
    (: expand-pattern (-> Context Env Env Syntax Pattern))
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

    (: pattern-constructor (-> Context Env Syntax String))
    (define (pattern-constructor cx env head)
      (constructor-name cx env (expect-ident head "a constructor")))

    ;; ---- Syntax rules ----

    (struct MacroForm
      ((name Syntax)
       (literals (List Syntax))
       (rules (List Syntax))))

    (: macro-form (-> Syntax MacroForm))
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
    (: define-top-macro (-> Context Env Syntax Context))
    (define (define-top-macro cx env form)
      (let ((parts (macro-form form)))
        (expanding cx ((id (fresh "%macro")) (scope (register-scope env)))
                   (bind-top cx
                             env
                             (MacroForm-name parts)
                             (Macro id (MacroForm-literals parts) (MacroForm-rules parts) scope)))))

    (: define-local-macro (-> Context Env Syntax (Pair Env Context)))
    (define (define-local-macro cx env form)
      (let ((parts (macro-form form)))
        (expanding cx ((scope (register-scope env)) (id (fresh "%macro")))
                   (let ((inner (extend env
                                        (MacroForm-name parts)
                                        (Macro id
                                               (MacroForm-literals parts)
                                               (MacroForm-rules parts)
                                               scope))))
                     (Pair inner (scope-set cx scope inner))))))

    (: apply-macro (-> Context Env Syntax (List Syntax) (List Syntax) I64 (Pair Syntax Context)))
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

    (: literal? (-> Syntax (List Syntax) Bool))
    (define (literal? ident literals)
      (any? (lambda (literal) (string=? (ident-key literal) (ident-key ident))) literals))

    (: match-pattern (-> Context Syntax Syntax (List Syntax) Env Env (Option Bindings)))
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
    (: same-binding? (-> Context Env Syntax Env Syntax Bool))
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

    (: match-items (-> Context (List Syntax) (List Syntax) (List Syntax) Env Env (Option Bindings)))
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
       (-> Context Syntax (List Syntax) (List Syntax) (List Syntax) Env Env (Option Bindings)))
    (define (match-ellipsis cx repeated after inputs literals env macro-env)
      (let ((count (- (length inputs) (length after))))
        (if (< count 0)
            (None)
            (match (match-items cx after (drop inputs count) literals env macro-env)
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
    (: all-matched (-> (List (Option Bindings)) (Option (List Bindings))))
    (define (all-matched matches)
      (fold-right (lambda (match-result rest)
                    (match match-result
                      ((Some bindings)
                       (match rest ((Some more) (Some (Cons bindings more))) ((None) (None))))
                      ((None) (None))))
                  (Some (Nil)) matches))

    (: bound-ref (-> Bindings String Bound))
    (define (bound-ref bindings key)
      (match (assoc-ref bindings key)
        ((Some bound) bound)
        ((None) (panic "internal error: unbound pattern variable"))))

    (: pattern-keys (-> Syntax (List Syntax) (List String)))
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

    (: transcribe (-> Syntax Bindings Expansion Syntax))
    (define (transcribe template bindings expansion)
      (match template
        ((Ident name _ _)
         (match (assoc-ref bindings (ident-key template))
           ((None) (rename-ident template expansion))
           ((Some (Many _))
            (compile-error (Expansion-loc expansion)
                           (string-append "pattern variable used without an ellipsis: " name)))
           ((Some (One syntax)) syntax)))
        ((Atom _ _) template)
        ((Form items _)
         (Form (transcribe-items items bindings expansion) (Expansion-loc expansion)))))

    (: transcribe-items (-> (List Syntax) Bindings Expansion (List Syntax)))
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
    (: transcribe-repeated (-> Syntax Bindings Expansion (List Syntax)))
    (define (transcribe-repeated template bindings expansion)
      (let ((repeated (concatenate (map (lambda (key)
                                          (match (assoc-ref bindings key)
                                            ((Some (Many matches)) (list (Pair key matches)))
                                            (_ (Nil))))
                                        (delete-duplicates string=? (template-keys template))))))
        (match repeated
          ((Nil)
           (compile-error (Expansion-loc expansion)
                          "ellipsis follows a template without pattern variables"))
          ((Cons first _)
           (let ((count (length (Pair-second first))))
             (unless (every? (lambda (entry) (= count (length (Pair-second entry)))) repeated)
               (compile-error (Expansion-loc expansion)
                              "pattern variables under one ellipsis matched different lengths"))
             (map (lambda (index)
                    (transcribe template
                                (append (map (lambda (entry)
                                               (Pair (Pair-first entry)
                                                     (list-ref (Pair-second entry) index)))
                                             repeated)
                                        bindings)
                                expansion))
                  (iota count)))))))

    (: template-keys (-> Syntax (List String)))
    (define (template-keys template)
      (match template
        ((Ident _ _ _) (list (ident-key template)))
        ((Form items _) (concatenate (map template-keys items)))
        (_ (Nil))))

    ;; A template's identifier becomes the same marked identifier wherever it
    ;; appears in one expansion: its mark is its key with the expansion's
    ;; stamp, resolved in the macro's scope.
    (: rename-ident (-> Syntax Expansion Syntax))
    (define (rename-ident ident expansion)
      (Ident (Ident-name ident)
             (Some (Mark (string-append (ident-key ident) "%" (Expansion-stamp expansion))
                         ident
                         (Expansion-scope expansion)))
             (Expansion-loc expansion)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-expand)
    (import
     (only (scheme base) guard error-object? error-object-message)
     (only (chibi filesystem) create-directory*)
     (only (chibi string) string-contains string-cursor->index)
     (snail-core testing)
     (only (snail-core compiler inputs) no-inputs supply-generated))
    (begin

      ;; A walk reads imports through `cond-expand`, stops at a producer
      ;; whose output is missing, reads on through one supplied, and fails
      ;; where a producer's imports lead back to the library it makes.
      ;; Discovery finds the uses expansion reaches, in program order, one
      ;; of them in a supplied output, and not one only an unused macro
      ;; names. The primitive library is read from its file. The sources are
      ;; written into `directory`; `library` holds the standard libraries.
      (define (test-expand directory library)
        (write-sources directory)
        (let ((walk (list (string-append directory "/walk") library))
              (discover (string-append directory "/discover")))
          (test-library-file walk)
          (test-library-closure walk)
          (test-discovery (list discover library) discover)
          (test-links (string-append directory "/links"))
          (test-primitives (string-append directory "/primitive") library)))

      (define (test-library-file directories)
        (let ((loc (Loc "test.sld" 1 1)))
          (expect (library-file directories (list "snail-core" "core") loc) (DefinedLibrary (Nil)))
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
                   "(import (snail-core base) (sample helper) (only (snail-core syntax) write-generated-library))"
                   "(write-generated-library (unit))"))))

      (define (test-library-closure directories)
        (let* ((imports (program-imports (read-text "(import (sample top)) (unit)" "main.sld")))
               (cold (library-closure directories no-inputs (Nil) imports))
               (made (list-ref cold 0))
               (inputs (supply-generated no-inputs (producer-text directories (Reached-forms made))
                                         (generated-library-bytes
                                          "(define-library (sample made) (export) (import (sample inner)) (begin))")))
               (warm (library-closure directories inputs (Nil) imports)))
          (expect (map Reached-library cold) (list (list "sample" "made")))
          (expect (Reached-loading made) (list "sample.made" "sample.top"))
          (expect (map Reached-library warm) (list (list "sample" "made") (list "sample" "inner")))
          (expect (Reached-loading (list-ref warm 1))
                  (list "sample.inner" "sample.made" "sample.top"))
          (expect (closure-error directories made) #t)))

      ;; The producer of (sample made) imports (sample helper), which
      ;; imports (sample made) while it is still loading.
      (define (closure-error directories made)
        (guard (failure ((error-object? failure)
                         (let ((message (error-object-message failure)))
                           (and (string-contains message "helper.sld:1:")
                                (string-contains message "library import cycle through sample.made")
                                #t))))
          (library-closure directories
                           no-inputs
                           (Reached-loading made)
                           (program-imports (Reached-forms made)))
          #f))

      (define (test-discovery directories root)
        (let* ((assets (library-file directories (list "sample" "assets") (Loc "test.sld" 1 1)))
               (inputs (supply-generated no-inputs
                                         (producer-text directories (GeneratedLibrary-forms assets))
                                         (generated-library-bytes assets-output)))
               (uses (discover-artifacts directories inputs (string-append root "/main.sld"))))
          (expect (map ArtifactUse-name uses) (list "admin" "client"))
          (expect (map (lambda (use) (Loc-file (ArtifactUse-loc use))) uses)
                  (list (string-append root "/sample/assets.sld")
                        (string-append root "/main.sld")))))

      ;; A linked path is made canonical against its library's directory and
      ;; named for the library; the program body links as `main`. A path
      ;; that leaves the directory, or a file that is not there, is an error
      ;; naming the library and the path.
      (define (test-links root)
        (create-directory* (string-append root "/sample/data"))
        (write-file (string-append root "/sample/data/pixel.bin") "pixel")
        (write-file (string-append root "/notes.txt") "notes")
        (write-file (string-append root "/sample/linked.sld")
                    "(define-library (sample linked) (export pixel) (import (snail-core core)) (begin (define pixel (link-file \"data/./x/../pixel.bin\"))))")
        (let ((expansion (link-expansion root
                                         "(import (snail-core core) (sample linked)) (define notes (link-file \"notes.txt\")) (link-file \"notes.txt\")")))
          (expect (map LinkedFile-name (program-links expansion))
                  (list "sample.linked/data/pixel.bin" "main/notes.txt"))
          (expect (map LinkedFile-path (library-links expansion "sample.linked"))
                  (list (string-append root "/sample/data/pixel.bin"))))
        (expect (link-error root "../notes.txt")
                "link-bytes may not leave the library's directory: ../notes.txt")
        (expect (link-error root "/notes.txt")
                "link-bytes takes a path relative to the library, with no empty names: /notes.txt")
        (expect (link-error root "./")
                "link-bytes takes a path relative to the library, with no empty names: ./")
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
        (guard (failure ((error-object? failure)
                         (let* ((message (error-object-message failure))
                                (start (string-contains message ": ")))
                           (substring message
                                      (+ (string-cursor->index message start) 2)
                                      (string-length message)))))
          (link-expansion root
                          (string-append "(import (snail-core core)) (link-file \"" path "\")"))
          "accepted"))

      ;; Loading (snail-core primitive) binds each primitive's value under
      ;; `prim:NAME`, quantified over the variables its declaration names, in
      ;; their order, and records no run of items, since the library has no
      ;; module.
      (define (test-primitives root library)
        (create-directory* root)
        (write-file (string-append root "/main.sld") "(import (snail-core primitive)) (unit)")
        (let ((program (ExpandedProgram-program (expand-program (list root library)
                                                                (lambda (loading forms)
                                                                  (panic "unexpected producer"))
                                                                no-inputs
                                                                (string-append root "/main.sld")
                                                                empty-expansion))))
          (expect (primitive-scheme program "vector-ref") (list (list "A") "(-> (Vector A) I64 A)"))
          (expect (primitive-scheme program "vector-generate")
                  (list (list "A" "e") "(-> I64 (-> I64 A ! e) (Vector A) ! e)"))
          (expect (primitive-scheme program "ref-get") (list (list "A") "(-> (Ref A) A ! mut)"))
          (expect (primitive-scheme program "dispatch-local")
                  (list (list "e") "(-> (Once (-> Unit ! e)) Unit ! tasks e)"))
          (expect (map Pair-first (library-items program (program-items program))) (list "main"))))

      (define (primitive-scheme program name)
        (match (program-value program (string-append "prim:" name))
          ((Some (Primitive scheme))
           (list (Scheme-vars scheme) (type->string (Scheme-type scheme))))
          (_ (list))))

      (define assets-output
        (string-append
         "(define-library (sample assets) (export admin-bundle) (import (snail-core base) (snail-core artifact)) "
         "(begin (: admin-bundle ArtifactBundle) (define admin-bundle (artifact-bundle \"admin\"))))"))

      (define (write-sources directory)
        (create-directory* (string-append directory "/walk/sample"))
        (create-directory* (string-append directory "/discover/sample"))
        (for-each (lambda (source)
                    (write-file (string-append directory "/" (Pair-first source))
                                (Pair-second source)))
                  (list (Pair "walk/sample/top.sld"
                              "(define-library (sample top) (export) (cond-expand ((not snail-core) (import (sample never))) (else (import (sample made)))) (begin))")
                        (Pair "walk/sample/made.sld"
                              "(generate-library (sample made) (import (snail-core base) (sample helper)) (unit))")
                        (Pair "walk/sample/helper.sld"
                              "(define-library (sample helper) (export) (import (sample made)) (begin))")
                        (Pair "walk/sample/inner.sld"
                              "(generate-library (sample inner) (import (snail-core base)) (unit))")
                        (Pair "discover/sample/assets.sld"
                              "(generate-library (sample assets) (import (snail-core base)) (unit))")
                        (Pair "discover/main.sld" discovery-main))))

      (define discovery-main
        (string-append
         "(import (snail-core base) (rename (snail-core artifact) (artifact-bundle bundle)) (sample assets))\n"
         "(define-syntax client-snapshot (syntax-rules () ((_) (bundle \"client\"))))\n"
         "(define-syntax unused (syntax-rules () ((_) (bundle \"does-not-exist\"))))\n"
         "(define snapshot (client-snapshot))\n"
         "(define again (client-snapshot))\n"))))
   (else)))
