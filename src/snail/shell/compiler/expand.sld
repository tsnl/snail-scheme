;; Located syntax to the core program. The expander is the only pass that knows
;; `snail-scheme`'s binding forms. It loads libraries, resolves every identifier to a
;; binding, runs `syntax-rules` macros, records declared entities in the
;; program tables, and emits core expressions with unique names.
(define-library (snail shell compiler expand)
  (export
   ExpandedProgram
   expand-program
   Generate
   LinkedFile
   program-links)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler inputs)
         generating-stack
         read-source-file)
   (snail shell compiler library)
   (snail shell compiler core)
   (snail shell compiler sha256))
  (begin

    ;; ---- Bindings and environments ----

    ;; What an identifier denotes. A record's name is both a type and its
    ;; constructor. A top-level value is read by calling its thunk, the
    ;; global `name`, which keeps the result. A macro remembers the scope it
    ;; was defined in by number, because the marks on the identifiers it
    ;; introduces refer to it.
    (enum Binding
      (Local
       ((name String)))
      (Global
       ((name String)))
      (Thunk
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
        ((Thunk name) name)
        ((TypeName name _ _) name)
        ((Alias name _ _ _) name)
        ((TypeVar _) "%type-variable")
        ((ClassName name) name)
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

    (define (extend (env Env) (ident Syntax) (binding Binding)) (→ Env)
      (Frame (ident-key ident) binding env))

    ;; A marked identifier is keyed by its mark, so the same name introduced by
    ;; two expansions binds two variables.

    (define (ident-key (ident Syntax)) (→ String)
      (match ident
        ((Ident _ (Some mark) _) (● mark key))
        ((Ident name (None) _) name)
        (_ (panic "internal error: not an identifier"))))

    ;; The name of syntax the caller already knows is an identifier.

    (define (ident-name (ident Syntax)) (→ String)
      (match ident
        ((Ident name _ _) name)
        (_ (panic "internal error: expected Ident"))))

    ;; An unbound marked identifier resolves as its original in the scope of
    ;; the macro that introduced it.

    (define (resolve (cx Context) (env Env) (ident Syntax)) (→ (Option Binding))
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
                   (resolve cx (scope-env cx (● mark scope)) (● mark original)))
                  (_ (None))))))))))

    ;; What a top level binds `key` to: its own definition, or else an
    ;; import.

    (define (top-binding (cx Context) (top String) (imports (Table Binding)) (key String))
      (→ (Option Binding))
      (match (table-ref (top-definitions cx top) key)
        ((Some binding) (Some binding))
        ((None) (table-ref imports key))))

    (define (expect-ident (syntax Syntax) (what String)) (→ Syntax)
      (match syntax
        ((Ident _ _ _) syntax)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items of a form, or an error naming what was expected.

    (define (form-items (syntax Syntax) (what String)) (→ (List Syntax))
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
    ;; What the build is given, which never changes: `fs` reads the
    ;; sources and linked files; `generate` runs a producer and answers
    ;; what it wrote; `directories` are searched for libraries; and
    ;; `recipe`, in a producer program, is the recipe its printed copy
    ;; stands for.
    ;;
    ;; Scope, which loading a library replaces and which the importer gets
    ;; back unchanged: `prefix` names the library being expanded, so its
    ;; globals are `prefix:name`; `loading` the libraries whose imports are
    ;; being loaded, innermost first, so a library requested while it loads
    ;; is part of an import cycle; `aliases` the type aliases whose bodies
    ;; are being resolved, innermost first, so an alias that refers to itself
    ;; is caught; and what the library itself uses and makes, newest first:
    ;; `links`, the files it links, and
    ;; files its `link-handle` uses name, `items`, the items its body has
    ;; added so far, which join the program as one run when the body is
    ;; done.
    ;;
    ;; What the build has learned, which flows forward out of every library:
    ;; `program` is the program built so far, and `expanded` holds each
    ;; library this build has expanded, with its exports and linked files.
    ;; `counter` numbers fresh names. `scopes` holds the environments that marks refer
    ;; to, by number, and `scope-count` is the next number; `tops` holds
    ;; each top level's definitions, by key, and `top-count` makes the next
    ;; key. `deriving` is the scope a deriving macro's name resolves in,
    ;; once one is made.
    ;; Runs the producer program of a `generate-library`, given the
    ;; libraries loading when it was reached, and answers the bytes of the
    ;; syntax it writes.
    (type Generate (Fn (List String) (List Syntax) → Bytes))

    (record Context
      ((fs Fs)
       (generate Generate)
       (directories (List String))
       (target (Option (List String)))
       (known (Table LinkedFile))
       (recipe (Option Recipe))
       (prefix String)
       (loading (List String))
       (aliases (List String))
       (links (List LinkUse))
       (items (List Item))
       (program Program)
       (expanded (Table Expanded))
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
      (new Context (fs (● outer fs))
           (generate (● outer generate))
           (directories (● outer directories))
           (target (● outer target))
           (known (● outer known))
           (recipe (● outer recipe))
           (prefix (● outer prefix))
           (loading (● outer loading))
           (aliases (● outer aliases))
           (links (● outer links))
           (items (● outer items))
           (program (● inner program))
           (expanded (● inner expanded))
           (counter (● inner counter))
           (scopes (● inner scopes))
           (scope-count (● inner scope-count))
           (tops (● inner tops))
           (top-count (● inner top-count))
           (deriving (● inner deriving))))

    (type Exports (List (Pair String Binding)))

    ;; A file a library links rather than embeds, which the build places
    ;; beside the payload: `digest`, the SHA-256 of its bytes in hex, is the
    ;; name the payload asks its host for and the build ships it under, and
    ;; `path` is where the build finds the file. `size` and `modified` are
    ;; the file's when its bytes were read for the digest.
    (record LinkedFile
      ((digest String)
       (path String)
       (size I64)
       (modified I64)))

    ;; A `link-handle` as the library's body expands: the global its
    ;; expression calls, its path made canonical, where that finds the
    ;; file, and where the library names it.
    (record LinkUse
      ((handle String)
       (relative String)
       (path String)
       (loc Loc)))

    ;; Exports and linked files of a library already expanded in this build.
    ;; The next build starts with an empty table.
    (record Expanded
      ((exports Exports)
       (links (List LinkedFile))))

    (record ExpandedProgram
      ((program Program)
       (libraries (Table Expanded))))

    (define (new-context (fs Fs)
                         (generate Generate)
                         (directories (List String))
                         (target (Option (List String)))
                         (known (List LinkedFile)))
      (→ Context)
      (new Context
        (fs fs)
        (generate generate)
        (directories directories)
        (target target)
        (known
         (fold-left (lambda (table file) (table-set table (● file path) file)) (empty-table) known))
        (recipe (None))
        (prefix "")
        (loading (Nil))
        (aliases (Nil))
        (links (Nil))
        (items (Nil))
        (program empty-program)
        (expanded (empty-table))
        (counter 0)
        (scopes (empty-table))
        (scope-count 0)
        (tops (empty-table))
        (top-count 0)
        (deriving (None))))

    (define (expanded-program (cx Context)) (→ ExpandedProgram)
      (new ExpandedProgram (program (● cx program)) (libraries (● cx expanded))))

    ;; Each addition hands back the context with a larger program, except
    ;; that an item joins the library's own items until its run is done.

    (define (add-value (cx Context) (name String) (value Value)) (→ Context)
      (Context-program-set cx (program-with-value (● cx program) name value)))

    (define (add-item (cx Context) (item Item)) (→ Context)
      (Context-items-set cx (Cons item (● cx items))))

    (define (fresh (cx Context) (base String)) (→ (Pair String Context))
      (let ((count (+ (● cx counter) 1)))
        (new Pair
          (first (string-append base "." (i64->string count)))
          (second (Context-counter-set cx count)))))

    (define (global-name (cx Context) (key String)) (→ String)
      (string-append (● cx prefix) ":" key))

    ;; Numbers `env` as the next scope.

    (define (register-scope (cx Context) (env Env)) (→ (Pair I64 Context))
      (let ((number (● cx scope-count)))
        (new Pair
          (first number)
          (second (scope-set (Context-scope-count-set cx (+ number 1)) number env)))))

    (define (scope-set (cx Context) (number I64) (env Env)) (→ Context)
      (Context-scopes-set cx (table-set (● cx scopes) (i64->string number) env)))

    (define (scope-env (cx Context) (number I64)) (→ Env)
      (match (table-ref (● cx scopes) (i64->string number))
        ((Some env) env)
        ((None) (panic "internal error: unknown scope"))))

    ;; A top level over `imports` that defines nothing yet.

    (define (new-top (cx Context) (imports (Table Binding))) (→ (Pair Env Context))
      (let ((number (● cx top-count)))
        (new Pair
          (first (Top (i64->string number) imports))
          (second (Context-top-count-set cx (+ number 1))))))

    (define (top-definitions (cx Context) (top String)) (→ (Table Binding))
      (match (table-ref (● cx tops) top)
        ((Some definitions) definitions)
        ((None) (empty-table))))

    ;; Binds a name at a top level, once.

    (define (bind-top (cx Context) (env Env) (ident Syntax) (binding Binding))
      (→ Context)
      (let ((identifier-name (ident-name ident)))
        (match env
          ((Top top _)
           (let ((definitions (top-definitions cx top)))
             (when (table-contains? definitions (ident-key ident))
               (compile-error (syntax-loc ident)
                              (string-append "duplicate top-level definition " identifier-name)))
             (Context-tops-set cx
                               (table-set (● cx tops)
                                          top
                                          (table-set definitions (ident-key ident) binding)))))
          (_ (panic "internal error: not a top level")))))

    ;; ---- The core library ----

    ;; (snail core forms) is the one library without a file: the core forms
    ;; and the builtin types, both listed in core.sld. Every other library,
    ;; (snail core primitive) among them, is a file.

    (define core-library (→ Exports)
      (append (map (lambda (name) (new Pair (first name) (second (Core name)))) core-keywords)
              (map (lambda (entry)
                     (new Pair (first (● entry first))
                          (second (TypeName (● entry first) (● entry second) (None)))))
                   builtin-types)))

    (define (builtin-library? (key String)) (→ Bool)
      (string=? key "snail.core.forms"))

    ;; ---- Libraries ----

    ;; A library's exports, resolved when an import asks: the compiler's own
    ;; for (snail core forms), else the library as this build expanded it,
    ;; which happens once, under the library's own scope, resumed in the
    ;; importer's.

    (define (load-library (cx Context) (name (List String)) (loc Loc))
      (→ (Pair Exports Context))
      (let ((key (string-join name ".")))
        (cond ((builtin-library? key) (new Pair (first core-library) (second cx)))
              ((member? key (● cx loading))
               (compile-error loc (string-append "library import cycle through " key)))
              (else (match (table-ref (● cx expanded) key)
                      ((Some entry) (new Pair (first (● entry exports)) (second cx)))
                      ((None)
                       (match (read-library (Context-loading-set cx (Cons key (● cx loading)))
                                            name
                                            loc)
                         ((Pair exports loaded)
                          (new Pair (first exports) (second (resumed cx loaded)))))))))))

    (define (read-library (cx Context) (name (List String)) (loc Loc))
      (→ (Pair Exports Context))
      (let ((path (library-path (● cx fs) (● cx directories) name loc)))
        (expand-library-file cx name (file-library name (read-source-file (● cx fs) path) path))))

    ;; A defined library expands its sections; a generated one expands the
    ;; library its producer's output declares.

    (define (expand-library-file (cx Context) (name (List String)) (file LibraryFile))
      (→ (Pair Exports Context))
      (match file
        ((DefinedLibrary sections)
         (expand-sections (Context-prefix-set cx (string-join name ".")) sections))
        ((GeneratedLibrary forms loc)
         (expand-library-file cx name (output-library-file name (generated-bytes cx forms) loc)))))

    ;; What a producer wrote, as the driver's `generate` produces it: the
    ;; policy is this invocation's, and the context carries it to the one
    ;; place that asks. A request keeps the exact loading stack, so
    ;; recursive compilation still detects cycles.

    (define (generated-bytes (cx Context) (forms (List Syntax))) (→ Bytes)
      ((● cx generate) (● cx loading) forms))

    ;; ---- Sources ----

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
    ;; the bytes. The path is relative to the file it is written in and
    ;; may be absolute or leave that file's directory. The
    ;; form is a call to a global of the library's, which `bind-links`
    ;; binds, once the body has expanded, to an import from
    ;; "snail.runtime.link" named for the file's digest: the module records
    ;; the content it needs where its host must see it, and the host reads
    ;; it only when the program asks for its bytes. Expanding an expression
    ;; reads no file, so the digest waits for the body.

    (define (expand-link-file (cx Context) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (match items
        ((Cons _ (Cons (Atom (DString path) path-loc) (Nil)))
         (let* ((relative (linked-path path path-loc))
                (handle (global-name cx (string-append "%link " relative))))
           (new Pair (first (expr (App (expr (Var handle (Nil) (Nil)) loc) (Nil)) loc))
                (second (record-link cx handle relative path-loc)))))
        (_ (compile-error loc "link-file expects a literal relative path"))))

    ;; Records a use on the library, once for each global. A macro whose
    ;; template holds the path names a file beside the macro's library, so
    ;; two files could claim one global; that is an error.

    (define (record-link (cx Context) (handle String) (relative String) (loc Loc))
      (→ Context)
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
           (Context-links-set cx
                              (Cons (new LinkUse
                                      (handle handle)
                                      (relative relative)
                                      (path path)
                                      (loc loc))
                                    (● cx links)))))))

    ;; A linked path in its canonical form: names separated by `/`, where
    ;; `.` is the directory it is in and `..` its parent, so
    ;; `data/../pixel.png` is `pixel.png`. It may be absolute, or leave the
    ;; library's directory, as a path into a producer's output does: the
    ;; build ships every linked file under its digest. A path with an empty
    ;; name, or that names nothing, is refused.

    (define (linked-path (path String) (loc Loc)) (→ String)
      (let* ((absolute? (and (> (string-length path) 0) (char=? (string-ref path 0) #\/)))
             (names (canonical-names (path-names (if absolute?
                                                     (substring path 1 (string-length path))
                                                     path))
                                     path
                                     loc)))
        (when (null? names) (compile-error loc (string-append "link-file names no file: " path)))
        (string-append (if absolute? "/" "") (string-join names "/"))))

    ;; Each `..` takes the name before it, unless there is none to take.

    (define (canonical-names (names (List String)) (path String) (loc Loc)) (→ (List String))
      (reverse (fold-left (lambda (kept name)
                            (match (new Pair (first name) (second kept))
                              ((Pair "" _)
                               (compile-error loc (string-append
                                                   "link-file takes a path with no empty names: "
                                                   path)))
                              ((Pair "." _) kept)
                              ((Pair ".." (Cons parent rest))
                               (if (string=? parent "..") (Cons name kept) rest))
                              (_ (Cons name kept))))
                          (Nil)
                          names)))

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
      (let ((linked
             (map (lambda (use) (new Pair (first use) (second (linked-file cx use))))
                  uses)))
        (new Pair
          (first (delete-duplicates (lambda (a b) (string=? (● a digest) (● b digest)))
                                    (map (lambda (record) (● record second)) linked)))
          (second (fold-left (lambda (cx entry)
                               (add-value cx
                                          (● (● entry first) handle)
                                          (link-import (● entry second))))
                             cx linked)))))

    ;; The file a use names, with its digest. A missing file fails the
    ;; library's expansion, naming the library and the path.

    (define (linked-file (cx Context) (use LinkUse)) (→ LinkedFile)
      (let ((path (● use path)))
        (match (followed-status (● cx fs) path)
          ((Ok status) (digested (● cx fs) (● cx known) path status))
          ((Err _)
           (compile-error (● use loc)
                          (string-append "the library " (● cx prefix) " links " (● use relative)
                                         ", but there is no file at " path))))))

    ;; The build's digest of the file, the one it already knows while the
    ;; file has the size and modification time it had when the build read
    ;; it, as make trusts a time; otherwise the digest of its bytes. The
    ;; status is taken before the bytes are read, so a file written in
    ;; between is read again by the next build.

    (define (digested (fs Fs) (known (Table LinkedFile)) (path String) (status FileStatus))
      (→ LinkedFile)
      (match (table-ref known path)
        ((Some file)
         (if (and (= (● file size) (● status size)) (= (● file modified) (● status modified)))
             file
             (read-digest fs path status)))
        ((None) (read-digest fs path status))))

    (define (read-digest (fs Fs) (path String) (status FileStatus)) (→ LinkedFile)
      (new LinkedFile
        (digest (file-digest fs path))
        (path path)
        (size (● status size))
        (modified (● status modified))))

    (define (link-import (file LinkedFile)) (→ Value)
      (Foreign (new Import (module "snail.runtime.link") (symbol (● file digest)))
               (mono-scheme (TFun (Nil) (TCon "I32" (Nil))))))

    (define (file-digest (fs Fs) (path String)) (→ String)
      (bytes->hex (sha256 (read-bytes fs path))))

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

    (define (expand-sections (cx Context) (sections (List (Pair String (List Syntax)))))
      (→ (Pair Exports Context))
      (threading cx ((env (import-env (section-items sections "import"))))
                 (let ((cx (Context-items-set (Context-links-set cx (Nil)) (Nil))))
                   (expand-recorded cx sections env))))

    ;; The primitive library's body is its declarations, which add no items,
    ;; so it records no run and has no module.

    (define (expand-library-body (cx Context)
                                 (sections (List (Pair String (List Syntax))))
                                 (env Env))
      (→ (Pair Exports Context))
      (let* ((forms (section-items sections "begin"))
             (cx (if (primitive-library? cx)
                     (fold-left (lambda (cx form) (declare-primitive cx env form)) cx forms)
                     (expand-library-run cx env forms))))
        (new Pair
          (first (map (lambda (spec) (export-entry cx env spec)) (section-items sections "export")))
          (second cx))))

    ;; The body's items are the library's run, which joins the program
    ;; whole once the body is expanded, so the program's items divide back
    ;; into libraries. A library loaded meanwhile, as the implicit libraries
    ;; are at the build's first deriving clause, has joined already, so its
    ;; items come before the run, as an import's do, and never inside it.

    (define (expand-library-run (cx Context) (env Env) (forms (List Syntax)))
      (→ Context)
      (let* ((cx (expand-top-level cx env forms))
             (cx (if (string=? (● cx prefix) "main") (with-entry cx) cx)))
        (Context-program-set cx
                             (program-with-library (● cx program)
                                                   (● cx prefix)
                                                   (● cx items)))))

    ;; ---- Entries ----

    ;; Only the root program's own main and exposed functions are entries:
    ;; an imported function called main remains an ordinary function. A
    ;; build for a target runs them through the target library. Main's
    ;; start takes the host's scheduler and calls the target's `start` with
    ;; it and a thunk that calls main, which runs as the scheduler's first
    ;; task.
    ;;
    ;; An entry asks its target for capabilities by its parameters' types.
    ;; A target provides a type by exporting a function of no parameters
    ;; that answers it, and the entry is called with that function's
    ;; answer. Every parameter of main is a capability; the parameters of
    ;; an exposed function that its target does not provide are the host's
    ;; arguments.

    (define (with-entry (cx Context)) (→ Context)
      (match (new Pair (first (● cx target)) (second (entry-loc cx)))
        ((Pair (Some library) (Some loc))
         (threading cx ((exports (load-library library loc)))
                    (let ((provided (providers cx exports)))
                      (with-target-exposures
                       (with-target-main cx
                                         library
                                         (target-function exports library "start" loc)
                                         provided)
                       provided))))
        (_ (with-plain-main cx))))

    (define (root-main (cx Context)) (→ (Option Item))
      (find (lambda (item) (match item ((Define "main:main" _) #t) (_ #f))) (● cx items)))

    (define (entry-loc (cx Context)) (→ (Option Loc))
      (match (find (lambda (item)
                     (match item ((Define "main:main" _) #t) ((Expose _ _ _) #t) (_ #f)))
                   (● cx items))
        ((Some (Define _ value)) (Some (● value loc)))
        ((Some (Expose _ _ loc)) (Some loc))
        (_ (None))))

    (define (target-function (exports Exports) (library (List String)) (name String) (loc Loc))
      (→ String)
      (match (assoc-ref exports name)
        ((Some (Global global)) global)
        (_ (compile-error loc
                          (string-append "the target library " (string-join library ".")
                                         " exports no function " name)))))

    ;; What a target provides: each type that one of its exported functions
    ;; of no parameters answers, with that function.
    (type Provided (List (Pair Type String)))

    (define (providers (cx Context) (exports Exports)) (→ Provided)
      (concatenate
       (map (lambda (entry)
              (match (● entry second)
                ((Global name)
                 (match (program-value (● cx program) name)
                   ((Some (Defined (Some (Scheme (Nil) (Nil) (TFun (Nil) result))) _))
                    (list (new Pair (first result) (second name))))
                   (_ (Nil))))
                (_ (Nil))))
            exports)))

    (define (provider (provided Provided) (type Type)) (→ (Option String))
      (match (find (lambda (entry) (type=? (● entry first) type)) provided)
        ((Some entry) (Some (● entry second)))
        ((None) (None))))

    ;; The parameter types an entry's signature states; without a
    ;; signature it asks for nothing.
    (define (entry-parameters (cx Context) (name String)) (→ (List Type))
      (match (program-value (● cx program) name)
        ((Some (Defined (Some (Scheme _ _ (TFun params _))) _)) params)
        (_ (Nil))))

    (define (with-plain-main (cx Context)) (→ Context)
      (match (root-main cx)
        ((Some (Define name value)) (add-item cx (Entry name name (● value loc))))
        (_ cx)))

    (define (with-target-main (cx Context)
                              (library (List String))
                              (start String)
                              (provided Provided))
      (→ Context)
      (match (root-main cx)
        ((Some (Define name value))
         (check-main-parameters cx library provided name value)
         (threading cx ((arguments (entry-arguments provided name (● value loc))))
                    (with-started-main cx name start arguments (● value loc))))
        (_ cx)))

    ;; Every parameter of main is a capability its target provides.
    (define (check-main-parameters (cx Context)
                                   (library (List String))
                                   (provided Provided)
                                   (name String)
                                   (value Expr))
      (→ Unit)
      (let ((asked (entry-parameters cx name)))
        (when (and (null? asked) (takes-arguments? value))
          (compile-error (● value loc)
                         "the parameters of main need types: each asks its target for a capability"))
        (for-each (lambda (type)
                    (match (provider provided type)
                      ((Some _) (unit))
                      ((None)
                       (compile-error (● value loc)
                                      (string-append "main asks for "
                                                     (type->string type)
                                                     ", which the target library "
                                                     (string-join library ".")
                                                     " does not provide")))))
                  asked)))

    (define (takes-arguments? (value Expr)) (→ Bool)
      (match (● value term)
        ((Lambda params _) (not (null? params)))
        (_ #f)))

    ;; `(define (started scheduler)
    ;;    (start scheduler (lambda () (main argument ...) (unit))))`,
    ;; under a name no source can write. The thunk is Unit whatever main
    ;; returns, so the checker's entry check is what rejects a wrong main.
    (define (with-started-main (cx Context)
                               (main String)
                               (start String)
                               (arguments (List Supplied))
                               (loc Loc))
      (→ Context)
      (let* ((local (fresh cx "scheduler"))
             (var (lambda (name) (expr (Var name (Nil) (Nil)) loc)))
             (run (expr (Seq (entry-call main arguments loc) (expr (Lit (DUnit)) loc)) loc))
             (call (App (var start) (list (var (● local first)) (expr (Lambda (Nil) run) loc))))
             (started (string-append main " started")))
        (add-item (add-item (● local second)
                            (Define started
                              (expr (Lambda (list (● local first)) (expr call loc)) loc)))
                  (Entry main started loc))))

    ;; Each exposure, in its order.
    (define (with-target-exposures (cx Context) (provided Provided)) (→ Context)
      (let ((exposure? (lambda (item) (match item ((Expose _ _ _) #t) (_ #f)))))
        (fold-left (lambda (cx item) (with-exposure cx provided item))
                   (Context-items-set cx (filter (lambda (item) (not (exposure? item)))
                                                 (● cx items)))
                   (reverse (filter exposure? (● cx items))))))

    ;; An exposure that asks for no capability is exposed as it is. One
    ;; that does is exposed through
    ;; `(define (exposed parameter ...) (f argument ...))`, under a name no
    ;; source can write. The wrapper is the program's, whatever library f
    ;; is from, and its name says so: a name's prefix is the module that
    ;; holds it.
    (define (with-exposure (cx Context) (provided Provided) (item Item)) (→ Context)
      (match item
        ((Expose name symbol loc)
         (threading cx ((arguments (entry-arguments provided name loc)))
                    (if (every? (lambda (supplied) (not (provided? supplied))) arguments)
                        (add-item cx item)
                        (with-exposed-wrapper cx name symbol arguments loc))))
        (_ (panic "internal error: expected an exposure"))))

    (define (with-exposed-wrapper (cx Context)
                                  (name String)
                                  (symbol String)
                                  (arguments (List Supplied))
                                  (loc Loc))
      (→ Context)
      (let ((params (concatenate (map (lambda (supplied)
                                        (match (● supplied parameter)
                                          ((Some name) (list name))
                                          ((None) (Nil))))
                                      arguments)))
            (exposed (string-append (● cx prefix) ":" name " exposed")))
        (add-item (add-item (add-value cx exposed (Defined (None) (None)))
                            (Define exposed
                              (expr (Lambda params (entry-call name arguments loc)) loc)))
                  (Expose exposed symbol loc))))

    ;; ---- Supplying an entry ----

    ;; One of an entry's arguments: a call of the provider of its
    ;; parameter's type, or the wrapper's own parameter, which the host
    ;; passes. Main and an exposed function are supplied alike; main's
    ;; target must provide every one.
    (record Supplied
      ((argument Expr)
       (parameter (Option String))))

    (define (provided? (supplied Supplied)) (→ Bool)
      (match (● supplied parameter)
        ((None) #t)
        ((Some _) #f)))

    (define (entry-arguments (cx Context) (provided Provided) (name String) (loc Loc))
      (→ (Pair (List Supplied) Context))
      (each cx (lambda (cx type) (supplied cx provided type loc)) (entry-parameters cx name)))

    (define (supplied (cx Context) (provided Provided) (type Type) (loc Loc))
      (→ (Pair Supplied Context))
      (match (provider provided type)
        ((Some function)
         (new Pair
           (first (new Supplied
                    (argument (expr (App (expr (Var function (Nil) (Nil)) loc) (Nil)) loc))
                    (parameter (None))))
           (second cx)))
        ((None)
         (match (fresh cx "argument")
           ((Pair name cx)
            (new Pair
              (first (new Supplied
                       (argument (expr (Var name (Nil) (Nil)) loc))
                       (parameter (Some name))))
              (second cx)))))))

    ;; The entry called with what it is supplied.
    (define (entry-call (name String) (arguments (List Supplied)) (loc Loc)) (→ Expr)
      (expr (App (expr (Var name (Nil) (Nil)) loc)
                 (map (lambda (supplied) (● supplied argument)) arguments))
            loc))

    ;; ---- Programs ----

    ;; A program is a sequence of imports followed by a body, which counts as
    ;; a library named `main` that exports nothing. Every build starts with
    ;; fresh names and scopes. A producer program begins
    ;; with `(generating ...)`, and its imports load inside the libraries
    ;; that form names, so one that leads back to them is a cycle.

    (define (expand-program (fs Fs)
                            (directories (List String))
                            (generate Generate)
                            (target (Option (List String)))
                            (known (List LinkedFile))
                            (path String))
      (→ ExpandedProgram)
      (expanded-program (expand-source (new-context fs generate directories target known) path)))

    (define (expand-source (cx Context) (path String)) (→ Context)
      (let* ((source (generating-stack (read-source-file (● cx fs) path)))
             (parts (program-parts (● source second)))
             (body (producer-body path (● source first) (● parts second)))
             (cx (Context-recipe-set
                  (Context-loading-set (Context-prefix-set cx "main") (● source first))
                  (● body first))))
        (● (expand-sections cx
                            (list (new Pair (first "import") (second (● parts first)))
                                  (new Pair (first "begin") (second (● body second))))) second)))

    ;; A producer program's printed copy, at `copy`, and the recipe it was
    ;; printed from, at `file`.
    (record Recipe
      ((copy String)
       (file String)))

    ;; The body of the program at `path`, and the recipe it stands for when
    ;; it is a producer, printed with the libraries `loading` when it was
    ;; reached: such a body begins with `(recipe "src/sample/blob.sld")`.

    (define (producer-body (path String) (loading (List String)) (body (List Syntax)))
      (→ (Pair (Option Recipe) (List Syntax)))
      (match body
        ((Cons (Form (Cons (Ident "recipe" _ _) (Cons (Atom (DString file) _) (Nil))) _) rest)
         (if (null? loading)
             (new Pair (first (None)) (second body))
             (new Pair (first (Some (new Recipe (copy path) (file file)))) (second rest))))
        (_ (new Pair (first (None)) (second body)))))

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
           (new Pair (first (append specs (● parts first))) (second (● parts second)))))
        (_ (new Pair (first (Nil)) (second forms)))))

    ;; Publish this library's exports and links to the rest of this build.
    (define (expand-recorded (cx Context)
                             (sections (List (Pair String (List Syntax))))
                             (env Env))
      (→ (Pair Exports Context))
      (threading cx ((exports (expand-library-body sections env))
                     (links (bind-links (reverse (● cx links)))))
                 (new Pair (first exports)
                      (second (Context-expanded-set cx
                                                    (table-set (● cx expanded)
                                                               (● cx prefix)
                                                               (new Expanded
                                                                 (exports exports)
                                                                 (links links))))))))

    ;; ---- Imports and exports ----

    ;; A top level over the bindings the specs provide, each loaded and
    ;; merged in turn.

    (define (import-env (cx Context) (specs (List Syntax)))
      (→ (Pair Env Context))
      (let loop ((cx cx) (specs specs) (imports (empty-table)))
        (match specs
          ((Nil) (new-top cx imports))
          ((Cons spec rest)
           (threading cx ((entries (import-set spec)))
                      (loop cx
                            rest
                            (fold-left (lambda (imports entry)
                                         (import-binding imports entry (syntax-loc spec)))
                                       imports
                                       entries)))))))

    (define (import-binding (imports (Table Binding)) (entry (Pair String Binding)) (loc Loc))
      (→ (Table Binding))
      (match (table-ref imports (● entry first))
        ((Some existing)
         (if (string=? (binding-identity existing) (binding-identity (● entry second)))
             imports
             (compile-error loc (string-append "conflicting imports of " (● entry first)))))
        ((None) (table-set imports (● entry first) (● entry second)))))

    ;; The (name . binding) entries an import set provides.

    (define (import-set (cx Context) (spec Syntax))
      (→ (Pair Exports Context))
      (match spec
        ((Form (Cons (Ident "only" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (threading cx ((entries (checked-import-set inner idents)))
                      (new Pair
                        (first (filter (lambda (entry) (member? (● entry first) names)) entries))
                        (second cx)))))
        ((Form (Cons (Ident "except" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (threading cx ((entries (checked-import-set inner idents)))
                      (new Pair
                        (first
                         (filter (lambda (entry) (not (member? (● entry first) names))) entries))
                        (second cx)))))
        ((Form (Cons (Ident "prefix" _ _) (Cons inner (Cons (Ident prefix _ _) (Nil)))) _)
         (threading cx ((entries (import-set inner)))
                    (new Pair (first (map (lambda (entry)
                                            (new Pair (first (string-append prefix (● entry first)))
                                                 (second (● entry second))))
                                          entries))
                         (second cx))))
        ((Form (Cons (Ident "rename" _ _) (Cons inner pairs)) _)
         (let ((renames (map rename-pair pairs)))
           (threading cx ((entries (checked-import-set inner
                                                       (map (lambda (pair)
                                                              (match pair
                                                                ((Form (Cons from _) _) from)
                                                                (_ pair)))
                                                            pairs))))
                      (new Pair (first (map (lambda (entry)
                                              (match (assoc-ref renames (● entry first))
                                                ((Some renamed)
                                                 (new Pair
                                                   (first renamed)
                                                   (second (● entry second))))
                                                ((None) entry)))
                                            entries))
                           (second cx)))))
        (_ (load-library cx (library-name spec) (syntax-loc spec)))))

    (define (checked-import-set (cx Context) (spec Syntax) (idents (List Syntax)))
      (→ (Pair Exports Context))
      (threading cx ((entries (import-set spec)))
                 (for-each (lambda (ident)
                             (let ((identifier-name (ident-name ident)))
                               (match (assoc-ref entries identifier-name)
                                 ((Some _) (unit))
                                 ((None) (compile-error (syntax-loc ident)
                                                        (string-append
                                                         "import names an identifier the library does not export: "
                                                         identifier-name))))))
                           idents)
                 (new Pair (first entries) (second cx))))

    (define (expect-name (syntax Syntax) (what String)) (→ String)
      (match syntax
        ((Ident name _ _) name)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    (define (ident-names (idents (List Syntax))) (→ (List String))
      (map (lambda (ident) (expect-name ident "an identifier")) idents))

    (define (rename-pair (syntax Syntax)) (→ (Pair String String))
      (match syntax
        ((Form (Cons (Ident from _ _) (Cons (Ident to _ _) (Nil))) _)
         (new Pair (first from) (second to)))
        (_ (compile-error (syntax-loc syntax) "expected (name new-name)"))))

    (define (export-entry (cx Context) (env Env) (spec Syntax))
      (→ (Pair String Binding))
      (match spec
        ((Ident name _ _)
         (new Pair
           (first name)
           (second (defined-binding cx env spec "exported name is not defined"))))
        ((Form (Cons (Ident "rename" _ _) (Cons inner (Cons (Ident outer _ _) (Nil)))) _)
         (new Pair
           (first outer)
           (second (defined-binding cx env inner "exported name is not defined"))))
        (_ (compile-error (syntax-loc spec) "expected an export specification"))))

    ;; The binding of an identifier that must be bound.

    (define (defined-binding (cx Context) (env Env) (ident Syntax) (message String))
      (→ Binding)
      (let ((identifier-name (ident-name ident)))
        (match (resolve cx env (expect-ident ident "an identifier"))
          ((Some binding) binding)
          ((None)
           (compile-error (syntax-loc ident) (string-append message ": " identifier-name))))))

    ;; The unique name of a top-level definition the scan bound.

    (define (global-binding (cx Context) (env Env) (ident Syntax)) (→ String)
      (let ((identifier-name (ident-name ident)))
        (match (defined-binding cx env ident "undefined name")
          ((Global name) name)
          ((Thunk name) name)
          (_ (compile-error (syntax-loc ident)
                            (string-append "not a top-level definition: " identifier-name))))))

    ;; ---- Top-level bodies ----

    ;; Definition headers describe the value before any body is expanded.
    ;; Parameters and fields have the same (name Type) shape. The header's
    ;; variables scope over every type in the definition, even its head.
    (record DefinitionHeader
      ((result (Option Syntax))
       (variables (List Syntax))
       (constraints (List Syntax))))

    (record DefinitionSyntax
      ((name Syntax)
       (parameters (Option (List (Pair Syntax Syntax))))
       (header DefinitionHeader)
       (body (List Syntax))
       (loc Loc)))

    (define (definition-clause (form Syntax)) (→ String)
      (match form
        ((Form (Cons (Ident name _ _) _) _)
         (if (member? name (list "→" "∀" "⊨")) name ""))
        (_ "")))

    (define (definition-parameter (form Syntax)) (→ (Pair Syntax Syntax))
      (match form
        ((Form (Cons name (Cons type (Nil))) _)
         (new Pair (first (expect-ident name "a parameter name")) (second type)))
        (_ (compile-error (syntax-loc form) "a function parameter needs (name Type)"))))

    (define (definition-header-clause (header DefinitionHeader) (name String) (form Syntax))
      (→ DefinitionHeader)
      (let ((items (form-tail form)))
        (case name
          (("→")
           (match items
             ((Cons result (Nil)) (DefinitionHeader-result-set header (Some result)))
             (_ (compile-error (syntax-loc form) "expected (→ Type)"))))
          (("∀")
           (let ((variables
                  (match items
                    ((Cons (Form binders _) (Nil))
                     (map (lambda (item) (expect-ident item "a quantified variable")) binders))
                    (_ (compile-error (syntax-loc form) "expected (∀ (variable ...))")))))
             (unless (= (length variables)
                        (length (delete-duplicates string=? (ident-names variables))))
               (compile-error (syntax-loc form) "duplicate quantified variable"))
             (DefinitionHeader-variables-set header variables)))
          (("⊨") (DefinitionHeader-constraints-set header items))
          (else (panic "internal error: definition clause")))))

    (define (definition-header (forms (List Syntax)))
      (→ (Pair DefinitionHeader (List Syntax)))
      (let loop ((forms forms)
                 (header (new DefinitionHeader
                           (result (None))
                           (variables (Nil))
                           (constraints (Nil))))
                 (seen (Nil)))
        (match forms
          ((Nil) (new Pair (first header) (second forms)))
          ((Cons form rest)
           (let ((name (definition-clause form)))
             (if (string=? name "") (new Pair (first header) (second (clause-free forms)))
                 (begin
                   (when (member? name seen)
                     (compile-error (syntax-loc form)
                                    (string-append "duplicate definition clause " name)))
                   (loop rest (definition-header-clause header name form) (Cons name seen)))))))))

    (define (clause-free (body (List Syntax))) (→ (List Syntax))
      (for-each (lambda (item)
                  (unless (string=? (definition-clause item) "")
                    (compile-error (syntax-loc item) "definition clauses must precede the body")))
                body)
      body)

    (define (parse-definition (cx Context) (env Env) (form Syntax)) (→ DefinitionSyntax)
      (let ((definition (parse-definition-parts form)))
        (when (null? (● definition body))
          (compile-error (syntax-loc form) "a definition needs a body"))
        (check-definition-header (● definition parameters) (● definition header)
                                 (● definition body) (syntax-loc form))
        (lambda-definition cx env definition)))

    ;; `(define (name parameter ...) clause ... body ...)` is shorthand for
    ;; `(define name (lambda (parameter ...) clause ... body ...))`, so a
    ;; definition whose initializer is a typed lambda is the function
    ;; definition that lambda spells out.

    (define (lambda-definition (cx Context) (env Env) (definition DefinitionSyntax))
      (→ DefinitionSyntax)
      (match (new Pair (first (● definition parameters)) (second (● definition body)))
        ((Pair (None) (Cons initializer (Nil)))
         (if (and (core-form? cx env initializer "lambda") (typed-lambda? initializer))
             (match (● (● definition header) result)
               ((Some _) (compile-error (● definition loc)
                                        "the lambda states this definition's type; write it once"))
               ((None) (DefinitionSyntax-name-set (parse-lambda initializer) (● definition name))))
             definition))
        (_ definition)))

    ;; A lambda takes a function definition's header: every parameter as
    ;; (name Type), then (→ Result) and the optional clauses. A lambda that
    ;; annotates nothing has its type inferred.

    (define (typed-lambda? (form Syntax)) (→ Bool)
      (match form
        ((Form (Cons _ (Cons (Form parameters _) rest)) _)
         (or (any? (lambda (parameter) (match parameter ((Form _ _) #t) (_ #f))) parameters)
             (match rest
               ((Cons clause _) (not (string=? (definition-clause clause) "")))
               ((Nil) #f))))
        (_ #f)))

    (define (parse-lambda (form Syntax)) (→ DefinitionSyntax)
      (match form
        ((Form (Cons keyword (Cons (Form parameters _) forms)) loc)
         (let* ((parsed (definition-header forms))
                (parameters (Some (map definition-parameter parameters))))
           (check-definition-header parameters (● parsed first) (● parsed second) loc)
           (new DefinitionSyntax
             (name keyword)
             (parameters parameters)
             (header (● parsed first))
             (body (● parsed second)) (loc loc))))
        (_ (compile-error (syntax-loc form) "expected (lambda (parameter ...) body ...)"))))

    ;; Definitions and method declarations have one header grammar. The caller
    ;; decides whether a body is required or forbidden.
    (define (parse-definition-parts (form Syntax)) (→ DefinitionSyntax)
      (match (form-tail form)
        ((Cons head forms)
         (let* ((parsed (definition-header forms))
                (parameters (match head
                              ((Form (Cons _ parameters) _)
                               (Some (map definition-parameter parameters)))
                              (_ (None)))))
           (new DefinitionSyntax
             (name (definition-name form))
             (parameters parameters)
             (header (● parsed first))
             (body (● parsed second)) (loc (syntax-loc form)))))
        (_ (compile-error (syntax-loc form) "expected a definition"))))

    (define (parse-declaration (form Syntax)) (→ DefinitionSyntax)
      (unless (match form ((Form (Cons (Ident "declare" _ _) _) _) #t) (_ #f))
        (compile-error (syntax-loc form)
                       "expected (declare (method (parameter Type) ...) (→ Result) ...), or (type Output)"))
      (let ((definition (parse-definition-parts form)))
        (unless (null? (● definition body))
          (compile-error (syntax-loc form) "a declaration has no body"))
        (match (● definition parameters)
          ((None) (compile-error (syntax-loc form) "a declaration needs a function header"))
          (_ (unit)))
        (check-definition-header (● definition parameters)
                                 (● definition header)
                                 (Nil)
                                 (syntax-loc form))
        definition))

    (define (check-definition-header (parameters (Option (List (Pair Syntax Syntax))))
                                     (header DefinitionHeader)
                                     (body (List Syntax))
                                     (loc Loc))
      (→ Unit)
      (match parameters
        ((Some _)
         (match (● header result)
           ((None) (compile-error loc "a function definition needs (→ Result)"))
           (_ (unit))))
        ((None)
         (unless (= (length body) 1)
           (compile-error loc "a value definition needs one initializer"))))
      (when (and (or (not (null? (● header variables))) (not (null? (● header constraints))))
                 (match (● header result) ((None) #t) (_ #f)))
        (compile-error loc "a polymorphic definition needs (→ Type)")))

    ;; Reuse the callable and quantified type parsers: this construction is
    ;; the only translation from a definition header to its complete type.

    (define (definition-type (definition DefinitionSyntax)) (→ Syntax)
      (let* ((header (● definition header)) (loc (● definition loc))
             (result (match (● header result)
                       ((Some type) type)
                       (_ (panic "internal error: unsigned definition"))))
             (type (match (● definition parameters)
                     ((None) result)
                     ((Some parameters)
                      (definition-callable-type parameters result loc)))))
        (if (and (null? (● header variables)) (null? (● header constraints))) type
            (Form (list (Ident "∀" (None) loc) (Form (● header variables) loc)
                        (Form (Cons (Ident "⊨" (None) loc) (● header constraints)) loc) type)
                  loc))))

    (define (definition-callable-type (parameters (List (Pair Syntax Syntax)))
              (result Syntax)
              (loc Loc))
      (→ Syntax)
      (let ((arguments (map (lambda (record) (● record second)) parameters)))
        (Form (Cons (Ident "Fn" (None) loc)
                    (append arguments (list (Ident "→" (None) loc) result)))
              loc)))

    (define (definition-scope (env Env) (definition DefinitionSyntax)) (→ Env)
      (type-scope env (● (● definition header) variables)))

    ;; Pass 1 discovers every top-level name, so definitions may refer to later
    ;; ones. Signatures then resolve, needing only those names. Pass 2
    ;; resolves declarations, which enter the program as it goes, and
    ;; returns one step per definition or expression, from context to
    ;; context, that expands it. The steps then run as a fold, in the order
    ;; the scan found them, each handed the context the one before left, so
    ;; every body sees every declaration and the bodies before it. The
    ;; first two passes stop at an error, since what follows needs every
    ;; name and type; the bodies go on past one (`expand-bodies`).
    ;;
    ;; What pass 1 leaves of a top-level form is its kind, decided once from
    ;; its head, with what that kind's later work needs. A type alias leaves
    ;; nothing: binding its name is all of it. Every form, a macro's
    ;; expansion and a derived instance among them, resolves in the
    ;; library's one top level, which the later passes take beside it.
    (enum Pending
      (PendingDefinition
       ((definition DefinitionSyntax)
        (value? Bool)))
      (PendingData
       ((form Syntax)
        (enum? Bool)))
      (PendingClass ((form Syntax)))
      (PendingInstance ((form Syntax)))
      (PendingExtern ((form Syntax)))
      (PendingExposure ((form Syntax))))

    (define (expand-top-level (cx Context) (env Env) (forms (List Syntax)))
      (→ Context)
      (threading cx ((scanned (each (lambda (cx form) (scan-top-level cx env form)) forms)))
                 (let* ((pending (concatenate scanned))
                        (signatures
                         (fold-left (lambda (table entry) (with-signature cx env table entry))
                                    (empty-table)
                                    pending)))
                   (threading cx
                              ((bodies (each (lambda (cx entry) (declare cx env signatures entry))
                                             pending)))
                              (expand-bodies cx (concatenate bodies))))))

    ;; A body that fails leaves the context as it was before it, and the
    ;; bodies after it are expanded all the same, so one compile reports
    ;; each body's error. Nothing a later body resolves can be missing for
    ;; it, since pass 1 bound every name. The library then fails with what
    ;; every failed body found, in order, and is never checked.

    (define (expand-bodies (cx Context) (bodies (List (Fn Context → Context))))
      (→ Context)
      (let ((run (fold-left (lambda (run body)
                              (match (recovering (lambda () (body (● run first))))
                                ((Ok cx) (new Pair (first cx) (second (● run second))))
                                ((Err found)
                                 (new Pair (first (● run first))
                                      (second (append (● run second) (diagnostics->list found)))))))
                            (new Pair (first cx) (second (Nil)))
                            bodies)))
        (fail-if-found (● run second))
        (● run first)))

    (define (scan-top-level (cx Context) (env Env) (form Syntax))
      (→ (Pair (List Pending) Context))
      (threading cx ((form (expand-head env form)))
                 (scan-top-level-form cx env form)))

    (define (scan-top-level-form (cx Context) (env Env) (form Syntax))
      (→ (Pair (List Pending) Context))
      (match (head-binding cx env form)
        ((Some (Core "begin"))
         (threading cx ((scanned (each (lambda (cx item) (scan-top-level cx env item))
                                       (form-tail form))))
                    (new Pair (first (concatenate scanned)) (second cx))))
        ((Some (Core "define-syntax"))
         (new Pair (first (Nil)) (second (define-top-macro cx env form))))
        ((Some (Core "primitive"))
         (compile-error (syntax-loc form)
                        "primitives are declared only in (snail core primitive)"))
        ((Some (Core "define")) (scan-definition cx env form))
        ((Some (Core "record")) (scan-data cx env form #f))
        ((Some (Core "enum")) (scan-data cx env form #t))
        ((Some (Core "type")) (new Pair (first (Nil)) (second (scan-alias cx env form))))
        ((Some (Core "typeclass"))
         (new Pair (first (list (PendingClass form))) (second (scan-class cx env form))))
        ((Some (Core "extern"))
         (new Pair
           (first (list (PendingExtern form)))
           (second (bind-member cx env (declaration-head form)))))
        ((Some (Core "instance")) (new Pair (first (list (PendingInstance form))) (second cx)))
        ((Some (Core "expose")) (new Pair (first (list (PendingExposure form))) (second cx)))
        (_ (compile-error (syntax-loc form)
                          "a top level holds definitions alone: a program's entry is its main"))))

    (define (scan-definition (cx Context) (env Env) (form Syntax))
      (→ (Pair (List Pending) Context))
      (let* ((definition (parse-definition cx env form)) (ident (● definition name))
             (value? (top-level-value? cx env definition))
             (global (unique-name cx ident))
             (cx (bind-top cx env ident (if value? (Thunk global) (Global global)))))
        (when value? (check-value-header definition))
        (new Pair (first (list (PendingDefinition definition value?))) (second cx))))

    ;; A record or enum binds its names, then the instances it derives are
    ;; scanned after it.

    (define (scan-data (cx Context) (env Env) (form Syntax) (enum? Bool))
      (→ (Pair (List Pending) Context))
      (let ((cx (if enum? (scan-enum cx env form) (scan-record cx env form))))
        (threading cx ((derived (derived-instances form enum?))
                       (scanned (each (lambda (cx instance) (scan-top-level cx env instance))
                                      derived)))
                   (new Pair
                     (first (Cons (PendingData form enum?) (concatenate scanned)))
                     (second cx)))))

    ;; A top-level definition whose initializer is not a lambda is a value:
    ;; a thunk its module runs at most once, on the first read, and whose
    ;; result every read shares.

    (define (top-level-value? (cx Context) (env Env) (definition DefinitionSyntax)) (→ Bool)
      (match (● definition parameters)
        ((Some _) #f)
        ((None) (not (core-form? cx env (list-ref (● definition body) 0) "lambda")))))

    ;; One slot holds a value, so it has one type.

    (define (check-value-header (definition DefinitionSyntax)) (→ Unit)
      (let ((header (● definition header)))
        (unless (and (null? (● header variables)) (null? (● header constraints)))
          (compile-error (● definition loc)
                         "a top-level value has one type; write a generic one as a function of no arguments"))))

    ;; The type a definition states, if it states one. A value states its
    ;; result, and its thunk takes nothing.

    (define (stated-type (definition DefinitionSyntax) (value? Bool)) (→ (Option Syntax))
      (match (● (● definition header) result)
        ((None) (None))
        ((Some result)
         (Some (if value?
                   (definition-callable-type (Nil) result (● definition loc))
                   (definition-type definition))))))

    ;; `prim:cached-thunk` keeps a thunk's result for its module. The thunk
    ;; takes nothing, so an initializer holds no capability: it reaches
    ;; nothing of the host's.

    (define (cached-thunk (value Expr)) (→ Expr)
      (let ((loc (● value loc)))
        (expr (App (expr (Var "prim:cached-thunk" (Nil) (Nil)) loc)
                   (list (expr (Lambda (Nil) value) loc)))
              loc)))

    (define (definition-name (form Syntax)) (→ Syntax)
      (match form
        ((Form (Cons _ (Cons (Form (Cons name _) _) _)) _) (expect-ident name "a definition name"))
        ((Form (Cons _ (Cons name _)) _) (expect-ident name "a definition name"))
        (_ (compile-error (syntax-loc form)
                          "expected (define name value) or (define (name (parameter Type) ...) (→ Result) body ...)"))))

    ;; Pass 2: a declaration enters the program now; a definition or an
    ;; exposure answers the step that expands it once every declaration is in.

    (define (declare (cx Context) (env Env) (signatures (Table (Pair Scheme (Option Loc))))
              (pending Pending))
      (→ (Pair (List (Fn Context → Context)) Context))
      (match pending
        ((PendingData form enum?)
         (new Pair (first (Nil)) (second (declare-data cx env form enum?))))
        ((PendingClass form) (new Pair (first (Nil)) (second (declare-class cx env form))))
        ((PendingInstance form) (declare-instance cx env form))
        ((PendingExtern form) (new Pair (first (Nil)) (second (declare-extern cx env form))))
        ((PendingDefinition definition value?)
         (new Pair
           (first (list (lambda (cx) (define-top-level cx signatures env definition value?))))
           (second cx)))
        ((PendingExposure form)
         (new Pair
           (first (list (lambda (cx) (add-item cx (expose-item cx env form)))))
           (second cx)))))

    (define (expose-item (cx Context) (env Env) (form Syntax)) (→ Item)
      (match form
        ((Form (Cons _ (Cons name (Cons (Atom (DString symbol) _) (Nil)))) loc)
         (match (resolve cx env (expect-ident name "a function name"))
           ((Some (Global global)) (Expose global symbol loc))
           (_ (compile-error (syntax-loc name)
                             (string-append "only a top-level function can be exposed: "
                                            (ident-name name))))))
        (_ (compile-error (syntax-loc form) expose-usage))))

    (define expose-usage (→ String) "expected (expose name \"symbol\")")

    (define (define-top-level (cx Context)
              (signatures (Table (Pair Scheme (Option Loc))))
              (env Env) (definition DefinitionSyntax) (value? Bool))
      (→ Context)
      (let ((name (global-binding cx env (● definition name))))
        (threading cx ((value (definition-value env definition)))
                   (let ((binding (match (table-ref signatures name)
                                    ((Some (Pair scheme loc)) (Defined (Some scheme) loc))
                                    ((None) (Defined (None) (None))))))
                     (add-item (add-value cx name binding)
                               (Define name (if value? (cached-thunk value) value)))))))

    (define (definition-value (cx Context) (env Env) (definition DefinitionSyntax))
      (→ (Pair Expr Context))
      (expand-definition-body cx (definition-scope env definition) definition))

    (define (expand-definition-body (cx Context) (scope Env) (definition DefinitionSyntax))
      (→ (Pair Expr Context))
      (match (● definition parameters)
        ((Some parameters)
         (expand-lambda cx scope (map (lambda (record) (● record first)) parameters)
                        (● definition body) (● definition loc)))
        ((None) (expand-expr cx scope (list-ref (● definition body) 0)))))

    (define (annotated-definition-value (cx Context)
                                        (env Env)
                                        (definition DefinitionSyntax)
                                        (value Expr))
      (→ Expr)
      (match (● (● definition header) result)
        ((None) value)
        ((Some _)
         (expr (Ann value (● (resolve-scheme cx env (definition-type definition)) type))
               (● definition loc)))))

    ;; ---- Declarations ----

    ;; Pass 1 binds the names a declaration introduces; pass 2 resolves types.

    ;; A declared name is global in the library that declares it.

    (define (unique-name (cx Context) (ident Syntax)) (→ String)
      (global-name cx (ident-key ident)))

    ;; A record's name is both its type and its constructor.

    (define (scan-record (cx Context) (env Env) (form Syntax)) (→ Context)
      (let* ((head (declaration-head form)) (name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (Some (unique-name cx name))))))
        (bind-replacements cx env name (record-fields form))))

    (define (scan-enum (cx Context) (env Env) (form Syntax)) (→ Context)
      (let* ((head (declaration-head form)) (name (declared-name head))
             (cx (bind-top cx
                           env
                           name
                           (TypeName (unique-name cx name)
                                     (length (declared-params head))
                                     (None)))))
        (fold-left (lambda (cx case) (scan-case cx env case)) cx (enum-cases form))))

    (define (scan-alias (cx Context) (env Env) (form Syntax)) (→ Context)
      (let* ((head (declaration-head form)) (name (declared-name head)))
        (match (list-drop (form-tail form) 1)
          ((Cons body (Nil))
           (bind-top cx env name (Alias (unique-name cx name) (declared-params head) body env)))
          (_ (compile-error (syntax-loc form) "expected (type Name type)")))))

    ;; Register the class's shape during scanning: signatures may precede
    ;; its declaration.

    (define (scan-class (cx Context) (env Env) (form Syntax)) (→ Context)
      (let* ((head (declaration-head form)) (name (declared-name head)) (id (unique-name cx name))
             (params (ident-names (declared-params head)))
             (cx (bind-top cx env name (ClassName id))))
        (unless (= (length params) (length (delete-duplicates string=? params)))
          (compile-error (syntax-loc head) "class parameters must be distinct"))
        (fold-left (lambda (cx declaration)
                     (bind-member cx env (● (parse-declaration declaration) name)))
                   (Context-program-set cx
                                        (program-with-class (● cx program)
                                                            (new Class
                                                              (name id)
                                                              (params params)
                                                              (methods (Nil)))))
                   (list-drop (form-tail form) 1))))

    (define (bind-member (cx Context) (env Env) (ident Syntax)) (→ Context)
      (let ((ident (expect-ident ident "a name")))
        (bind-top cx env ident (Global (unique-name cx ident)))))

    (record CaseSyntax
      ((name Syntax)
       (fields (List Syntax))))

    (define (parse-case (case Syntax)) (→ CaseSyntax)
      (match case
        ((Form (Cons name (Nil)) _)
         (new CaseSyntax (name (expect-ident name "a case name")) (fields (Nil))))
        ((Form (Cons name (Cons fields (Nil))) _)
         (new CaseSyntax
           (name (expect-ident name "a case name"))
           (fields (form-items fields "a field list"))))
        (_ (compile-error (syntax-loc case) "expected (Case) or (Case ((field type) ...))"))))

    ;; A data type's cases: an enum's as declared, a record's one case named
    ;; after the record.

    (define (data-cases (form Syntax) (enum? Bool)) (→ (List CaseSyntax))
      (if enum?
          (map parse-case (enum-cases form))
          (list (new CaseSyntax
                  (name (declared-name (declaration-head form)))
                  (fields (record-fields form))))))

    (define (scan-case (cx Context) (env Env) (case Syntax)) (→ Context)
      (bind-member cx env (● (parse-case case) name)))

    ;; A field is `(name type)`.
    ;; All fields are mutable; there is no second field grammar.
    (record FieldSyntax
      ((name Syntax)
       (type Syntax)))

    (define (parse-field (field Syntax)) (→ FieldSyntax)
      (match field
        ((Form (Cons name (Cons type (Nil))) _)
         (new FieldSyntax (name (expect-ident name "a field name")) (type type)))
        (_ (compile-error (syntax-loc field) "expected (field type)"))))

    ;; Only a record's fields have a name a program writes: the pure
    ;; replacement `Name-label-set`. Reads and writes use resolved paths;
    ;; enum fields are bound by patterns.
    (define (bind-replacements (cx Context) (env Env) (name Syntax) (fields (List Syntax)))
      (→ Context)
      (fold-left (lambda (cx field)
                   (bind-member cx env (replacer-ident name (● (parse-field field) name))))
                 cx fields))

    (define (replacer-ident (name Syntax) (label Syntax)) (→ Syntax)
      (suffixed-ident name
                      (string-append "-" (expect-name label "a field name") "-set")
                      (syntax-loc label)))

    ;; A name made from a declared one shares its mark, so a record a macro
    ;; introduces has replacers only that expansion sees.

    (define (suffixed-ident (name Syntax) (text String) (loc Loc)) (→ Syntax)
      (match name
        ((Ident identifier-name identifier-mark _)
         (Ident (string-append identifier-name text)
                (match identifier-mark
                  ((Some mark)
                   (Some (new Mark (key (string-append (● mark key) text))
                              (original (● mark original))
                              (scope (● mark scope)))))
                  ((None) (None))) loc))
        (_ (panic "internal error: expected Ident"))))

    (define (declared-name (head Syntax)) (→ Syntax)
      (match head
        ((Form (Cons name _) _) (expect-ident name "a type name"))
        (_ (expect-ident head "a type name"))))

    (define (declared-params (head Syntax)) (→ (List Syntax))
      (match head
        ((Form (Cons _ params) _)
         (map (lambda (param) (expect-ident param "a type parameter")) params))
        (_ (Nil))))

    ;; A record or enum may end with `(deriving Class ...)`.

    (define (deriving-clause? (syntax Syntax)) (→ Bool)
      (match syntax
        ((Form (Cons (Ident "deriving" _ _) _) _) #t)
        (_ #f)))

    ;; The declaration's items after its head, without deriving clauses.

    (define (declaration-body (form Syntax)) (→ (List Syntax))
      (match (form-tail form)
        ((Cons _ rest) (filter (lambda (item) (not (deriving-clause? item))) rest))
        ((Nil) (Nil))))

    (define (declaration-head (form Syntax)) (→ Syntax)
      (match (form-tail form)
        ((Cons head _) head)
        ((Nil) (compile-error (syntax-loc form) "expected a declaration"))))

    (define (record-fields (form Syntax)) (→ (List Syntax))
      (match (declaration-body form)
        ((Nil) (Nil))
        ((Cons fields (Nil)) (form-items fields "a field list"))
        (_ (compile-error (syntax-loc form) "expected (record Name ((field type) ...))"))))

    (define (enum-cases (form Syntax)) (→ (List Syntax))
      (declaration-body form))

    (define (derived-classes (form Syntax)) (→ (List Syntax))
      (concatenate (map form-tail (filter deriving-clause? (form-tail form)))))

    ;; A type parameter scope binds each parameter to a rigid variable.

    (define (type-scope (env Env) (params (List Syntax))) (→ Env)
      (fold-left (lambda (scope param) (extend scope param (TypeVar (TRigid (ident-name param)))))
                 env
                 params))

    ;; A case is its name followed by an optional field list; a record is one
    ;; case named after the record.

    (define (declare-data (cx Context) (env Env) (form Syntax) (enum? Bool)) (→ Context)
      (let* ((head (declaration-head form)) (params (declared-params head))
             (id (match (resolve cx env (declared-name head))
                   ((Some (TypeName id _ _)) id)
                   (_ (panic "internal error: type"))))
             (scope (type-scope env params))
             (cases (data-cases form enum?))
             (data (new DataType (name id)
                        (params (ident-names params))
                        (cases (map-indexed (lambda (tag case) (resolve-case cx scope case id tag))
                                            cases))
                        (enum? enum?))))
        (Context-program-set cx
                             (fold-left (lambda (program case)
                                          (with-case-values program data case))
                                        (program-with-type (● cx program) data)
                                        (● data cases)))))

    (define (resolve-case (cx Context) (scope Env) (case CaseSyntax) (type String) (tag I64))
      (→ Case)
      (new Case (name (constructor-name cx scope (● case name))) (type type) (tag tag)
           (fields (map (lambda (field) (resolve-field cx scope field)) (● case fields)))))

    (define (resolve-field (cx Context) (scope Env) (field Syntax)) (→ Field)
      (let ((parsed (parse-field field)))
        (new Field (name (expect-name (● parsed name) "a field name"))
             (type (resolve-type cx scope (● parsed type))))))

    (define (constructor-name (cx Context) (env Env) (ident Syntax)) (→ String)
      (let ((identifier-name (ident-name ident)))
        (match (resolve cx env ident)
          ((Some (Global name)) name)
          ((Some (TypeName _ _ (Some constructor))) constructor)
          (_ (compile-error (syntax-loc ident)
                            (string-append "not a constructor: " identifier-name))))))

    ;; A case's constructor, and for a record its fields' accessors and
    ;; replacers, all pure: an enum's fields are read by match.

    (define (with-case-values (program Program) (data DataType) (case Case)) (→ Program)
      (let* ((self (TCon (● data name) (map TRigid (● data params))))
             (field-types (map (lambda (field) (● field type)) (● case fields)))
             (constructor (Constructor case (generic-scheme data field-types self)))
             (program (program-with-value program (● case name) constructor)))
        (if (● data enum?)
            program
            (fold-left (lambda (program index) (with-field-values program data case self index))
                       program (iota (length (● case fields)))))))

    (define (with-field-values (program Program) (data DataType) (case Case) (self Type)
                               (index I64))
      (→ Program)
      (let* ((field (list-ref (● case fields) index)) (type (● field type))
             (accessor (Accessor case index (generic-scheme data (list self) type)))
             (writer (Writer case index
                             (new Scheme
                               (vars (● data params))
                               (constraints (Nil))
                               (type (TFun (list self type) (TCon "Unit" (Nil)))))))
             (replacer (Replacer case index (generic-scheme data (list self type) self))))
        (program-with-value
         (program-with-value (program-with-value program (accessor-name case index) accessor)
                             (writer-name case index)
                             writer)
         (string-append (● case name) "-" (● field name) "-set")
         replacer)))

    ;; A pure function generic over the data type's parameters.

    (define (generic-scheme (data DataType) (arguments (List Type)) (result Type))
      (→ Scheme)
      (new Scheme
        (vars (● data params))
        (constraints (Nil))
        (type (TFun arguments result))))

    ;; Resolve definition headers before expanding bodies so recursive calls
    ;; and importers see the same declared contract.

    (define (with-signature (cx Context) (env Env) (signatures (Table (Pair Scheme (Option Loc))))
                            (pending Pending))
      (→ (Table (Pair Scheme (Option Loc))))
      (match pending
        ((PendingDefinition definition value?)
         (match (stated-type definition value?)
           ((None) signatures)
           ((Some type)
            (add-signature cx signatures env (● definition name) type (● definition loc)))))
        (_ signatures)))

    (define (add-signature (cx Context)
                           (signatures (Table (Pair Scheme (Option Loc))))
                           (env Env)
                           (name Syntax)
                           (type Syntax)
                           (loc Loc))
      (→ (Table (Pair Scheme (Option Loc))))
      (let ((global (global-binding cx env name)))
        (match (table-ref signatures global)
          ((Some _) (compile-error loc "a definition has only one type signature"))
          ((None)
           (table-set signatures
                      global
                      (new Pair (first (resolve-scheme cx env type)) (second (Some loc))))))))

    (define (declare-class (cx Context) (env Env) (form Syntax)) (→ Context)
      (let* ((head (declaration-head form))
             (id (match (resolve cx env (declared-name head))
                   ((Some (ClassName id)) id)
                   (_ (panic "internal error: class"))))
             (class (program-class (● cx program) id))
             (params (declared-params head))
             (self (new Constraint
                     (class id)
                     (types (map (lambda (param) (TRigid (ident-name param))) params))))
             (scope (type-scope env params)))
        (threading cx ((methods (each (lambda (cx signature)
                                        (declare-method cx env scope id params self signature))
                                      (list-drop (form-tail form) 1))))
                   (Context-program-set cx
                                        (program-with-class (● cx program)
                                                            (Class-methods-set class methods))))))

    (define (declare-method (cx Context) (env Env) (scope Env) (class String)
                            (params (List Syntax)) (self Constraint) (signature Syntax))
      (→ (Pair String Context))
      (let* ((definition (parse-declaration signature))
             (own (resolve-scheme cx scope (definition-type definition)))
             (global (global-binding cx env (● definition name))))
        (new Pair (first global)
             (second (add-value cx global
                                (Method class
                                        (new Scheme
                                          (vars (append (ident-names params) (● own vars)))
                                          (constraints (Cons self (● own constraints)))
                                          (type (● own type)))))))))

    ;; Returns one step per method, which expands its definition.

    (define (declare-instance (cx Context) (env Env) (form Syntax))
      (→ (Pair (List (Fn Context → Context)) Context))
      (match form
        ((Form (Cons _ (Cons (Form (Cons class-ident type-args) _) body)) loc)
         (let ((parts (split-requires body)) (class (instance-class cx env class-ident)))
           (threading cx ((declared (declared-instance env class type-args (● parts first) loc))
                          (methods
                           (each (lambda (cx definition)
                                   (instance-method cx
                                                    (● declared second)
                                                    class
                                                    (● declared first)
                                                    definition))
                                 (● parts second))))
                      (check-instance-methods class methods loc)
                      (check-instance-overlap (● declared first)
                                              (class-instances (● cx program) (● class name))
                                              loc)
                      (new Pair (first (map (lambda (record) (● record expand)) methods))
                           (second (Context-program-set cx
                                                        (program-with-instance (● cx program)
                                                                               (instance-with-methods
                                                                                (● declared first)
                                                                                methods))))))))
        (_
         (compile-error (syntax-loc form) "expected (instance (Class type ...) definition ...)"))))

    (define (instance-class (cx Context) (env Env) (class-ident Syntax)) (→ Class)
      (match (resolve cx env class-ident)
        ((Some (ClassName id)) (program-class (● cx program) id))
        (_ (compile-error (syntax-loc class-ident)
                          "instance of something that is not a typeclass"))))

    ;; An instance gives each of its class's parameters a type.

    (define (check-instance-head (class Class) (types (List Type)) (loc Loc)) (→ Unit)
      (unless (= (length types) (length (● class params)))
        (compile-error loc
                       (string-append "a "
                                      (short-name (● class name))
                                      " instance gives each of the class's parameters a type, as in ("
                                      (string-join (Cons (short-name (● class name))
                                                         (● class params))
                                                   " ")
                                      ")"))))

    (define (instance-with-methods (instance Instance) (methods (List MethodDefinition)))
      (→ Instance)
      (Instance-methods-set instance
                            (map (lambda (method)
                                   (new Pair (first (● method method))
                                        (second (● method global))))
                                 methods)))

    ;; Unbound identifiers in an instance head are its type variables.

    (define (declared-instance (cx Context)
                               (env Env)
                               (class Class)
                               (type-args (List Syntax))
                               (requires (List Syntax))
                               (loc Loc))
      (→ (Pair (Pair Instance Env) Context))
      (let* ((vars (delete-duplicates string=?
                                      (concatenate
                                       (map (lambda (type) (free-type-names cx env type))
                                            type-args))))
             (scope (type-scope env (map (lambda (name) (Ident name (None) loc)) vars)))
             (requirements (map (lambda (requirement) (resolve-constraint cx scope requirement))
                                requires))
             (types (map (lambda (type) (resolve-type cx scope type)) type-args)))
        (check-instance-head class types loc)
        (threading cx ((name (fresh-global (short-name (● class name)))))
                   (new Pair
                     (first (new Pair
                              (first (new Instance
                                       (name name)
                                       (class (● class name))
                                       (vars vars)
                                       (types types)
                                       (requires requirements)
                                       (methods (Nil))))
                              (second scope)))
                     (second cx)))))

    (define (fresh-global (cx Context) (base String)) (→ (Pair String Context))
      (threading cx ((name (fresh base)))
                 (new Pair (first (global-name cx name)) (second cx))))

    ;; A body may start with `(⊨ (Class type ...) ...)`.

    (define (split-requires (items (List Syntax))) (→ (Pair (List Syntax) (List Syntax)))
      (match items
        ((Cons (Form (Cons (Ident "⊨" _ _) constraints) _) rest)
         (new Pair (first constraints) (second rest)))
        (_ (new Pair (first (Nil)) (second items)))))

    ;; One method of an instance: the class method it implements, the global
    ;; that holds its definition, and the step that expands it.
    (record MethodDefinition
      ((method String)
       (global String)
       (expand (Fn Context → Context))))

    (define (instance-method (cx Context) (env Env) (class Class)
                             (instance Instance) (definition Syntax))
      (→ (Pair MethodDefinition Context))
      (unless (core-form? cx env definition "define")
        (compile-error (syntax-loc definition) "expected a method definition"))
      (let* ((parsed (parse-definition cx env definition))
             (method (instance-method-name class (● parsed name)))
             (scheme (instance-method-scheme (● cx program) class method instance)))
        (threading cx ((global (fresh-global (short-name method)))
                       (then (add-value global (Defined (Some scheme) (None)))))
                   (new Pair (first (new MethodDefinition (method method) (global global)
                                         (expand (lambda (cx)
                                                   (threading cx ((value (instance-method-value env
                                                                                                instance
                                                                                                scheme
                                                                                                parsed)))
                                                              (add-item cx
                                                                        (Define global value)))))))
                        (second cx)))))

    (define (instance-method-name (class Class) (ident Syntax)) (→ String)
      (let ((name (expect-name ident "a method name")))
        (match (find (lambda (method) (string=? (short-name method) name)) (● class methods))
          ((Some method) method)
          ((None)
           (compile-error (syntax-loc ident)
                          (string-append "not a method of this class: " name))))))

    ;; An instance's variables and a method's quantifiers have different scopes.
    ;; Match the method's written binders to its class signature, then resolve
    ;; body annotations in that same scope.
    (define (instance-method-value (cx Context) (env Env) (instance Instance)
                                   (expected Scheme) (definition DefinitionSyntax))
      (→ (Pair Expr Context))
      (match (● (● definition header) result)
        ((None)
         (threading cx ((value (definition-value env definition)))
                    (check-method-function value)
                    (new Pair (first value) (second cx))))
        ((Some _)
         (let* ((own (resolve-scheme cx env (definition-type definition)))
                (names (list-drop (● expected vars) (length (● instance vars)))))
           (unless (= (length (● own vars)) (length names))
             (compile-error (● definition loc)
                            "a method header must quantify its class method's variables"))
           (let* ((substitution (zip (● own vars) (map TRigid names)))
                  (scope (instance-method-scope env definition substitution)))
             (check-method-requirements own expected substitution (● definition loc))
             (threading cx ((value (expand-definition-body scope definition)))
                        (check-method-function value)
                        (new Pair (first (expr (Ann value (substitute substitution (● own type)))
                                               (● definition loc))) (second cx))))))))

    ;; A method's global is code, so its definition is a lambda.

    (define (check-method-function (value Expr)) (→ Unit)
      (match (● value term)
        ((Lambda _ _) (unit))
        ((Ann inner _) (check-method-function inner))
        (_ (compile-error (● value loc) "a method's definition must be a function"))))

    ;; A written header cannot add obligations to callers of the class method.
    (define (check-method-requirements (own Scheme) (expected Scheme)
                                       (substitution Substitution) (loc Loc))
      (→ Unit)
      (unless (every? (lambda (required)
                        (let ((required (substitute-constraint substitution required)))
                          (any? (lambda (given)
                                  (and (string=? (● required class) (● given class))
                                       (types=? (● required types) (● given types))))
                                (● expected constraints))))
                      (● own constraints))
        (compile-error loc "a method header cannot require more than its class and instance")))

    (define (instance-method-scope (env Env)
                                   (definition DefinitionSyntax)
                                   (substitution Substitution))
      (→ Env)
      (fold-left (lambda (scope ident)
                   (extend scope
                           ident
                           (TypeVar (substitute substitution (TRigid (ident-name ident))))))
                 env (● (● definition header) variables)))

    (define (instance-method-scheme (program Program)
                                    (class Class)
                                    (method String)
                                    (instance Instance))
      (→ Scheme)
      (match (program-value program method)
        ((Some (Method _ (Scheme method-vars (Cons _ own) type)))
         (let* ((class-vars (● class params))
                (locals (rename-method-variables (list-drop method-vars (length class-vars))
                                                 (● instance vars)))
                (substitution (append (zip class-vars (● instance types))
                                      (map (lambda (binding)
                                             (new Pair (first (● binding first))
                                                  (second (TRigid (● binding second)))))
                                           locals))))
           (new Scheme
             (vars (append (● instance vars) (map (lambda (record) (● record second)) locals)))
             (constraints (append (● instance requires)
                                  (map (lambda (c) (substitute-constraint substitution c)) own)))
             (type (substitute substitution type)))))
        (_ (panic "internal error: not a method"))))

    ;; An instance and a polymorphic method have separate quantifiers.
    ;; Fresh names keep them apart when those schemes are combined for the
    ;; implementation; argument order stays fixed.

    (define (rename-method-variables (vars (List String)) (taken (List String)))
      (→ (List (Pair String String)))
      (match vars
        ((Nil) (Nil))
        ((Cons var rest)
         (let ((name (fresh-type-variable (string-append "$method." var) taken)))
           (Cons (new Pair (first var) (second name))
                 (rename-method-variables rest (Cons name taken)))))))

    (define (fresh-type-variable (name String) (taken (List String))) (→ String)
      (if (member? name taken) (fresh-type-variable (string-append "$" name) taken) name))

    (define (check-instance-methods (class Class) (methods (List MethodDefinition)) (loc Loc))
      (→ Unit)
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
        ((Form items _) (concatenate (map (lambda (item) (free-type-names cx env item)) items)))
        (_ (Nil))))

    (define (declare-extern (cx Context) (env Env) (form Syntax)) (→ Context)
      (match form
        ((Form (Cons _
                     (Cons name
                           (Cons (Atom (DString module) _)
                                 (Cons (Atom (DString symbol) _) (Cons type (Nil))))))
               _)
         (let ((resolved (resolve-type cx env type)))
           (check-host-parameters resolved (syntax-loc type))
           (add-value cx
                      (global-binding cx env name)
                      (Foreign (new Import (module module) (symbol symbol))
                               (mono-scheme resolved)))))
        (_ (compile-error (syntax-loc form) "expected (extern name \"module\" \"symbol\" type)"))))

    ;; The host reads only scalars, and one String or Bytes argument, which
    ;; the caller stages in the runtime's buffer just before the call; so a
    ;; host function may take a buffer only as its last argument.

    (define (check-host-parameters (type Type) (loc Loc)) (→ Unit)
      (match type
        ((TFun params _)
         (unless (staged-last? params)
           (compile-error loc
                          "a host function can take a String or Bytes only as its last argument")))
        (_ (unit))))

    (define (staged-last? (params (List Type))) (→ Bool)
      (match params
        ((Cons param (Cons next rest))
         (and (not (buffer-type? param)) (staged-last? (Cons next rest))))
        (_ #t)))

    ;; ---- Primitives ----

    ;; (snail core primitive) is a library file like any other, whose body
    ;; holds only primitive declarations. `(primitive name type)` declares an
    ;; operation the backend implements, as `extern` declares a foreign
    ;; function: it binds `name` to the global `prim:name`, the name the
    ;; checker, mono and `emit-primitive` know it by, and the value there is
    ;; a Primitive of the type's scheme. Elsewhere the form is an error.

    (define (primitive-library? (cx Context)) (→ Bool)
      (string=? (● cx prefix) "snail.core.primitive"))

    (define (declare-primitive (cx Context) (env Env) (form Syntax)) (→ Context)
      (unless (core-form? cx env form "primitive")
        (compile-error (syntax-loc form)
                       "(snail core primitive) holds only primitive declarations"))
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (let* ((global (primitive-global (expect-name name "a primitive name")))
                (cx (bind-top cx env name (Global global))))
           (add-value cx global (Primitive (resolve-scheme cx env type)))))
        (_ (compile-error (syntax-loc form) "expected (primitive name type)"))))

    ;; ---- Types ----

    (define (resolve-scheme (cx Context) (env Env) (syntax Syntax)) (→ Scheme)
      (match syntax
        ((Form (Cons (Ident "∀" _ _) (Cons (Form params _) rest)) loc)
         (let* ((params (map (lambda (param) (expect-ident param "a type variable")) params))
                (scope (type-scope env params))
                (parts (split-requires rest)))
           (match (● parts second)
             ((Cons type (Nil))
              (new Scheme
                (vars (ident-names params))
                (constraints (map (lambda (requirement) (resolve-constraint cx scope requirement))
                                  (● parts first)))
                (type (resolve-type cx scope type))))
             (_ (compile-error loc
                               "expected (∀ (variable ...) [(⊨ constraint ...)] type)")))))
        (_ (mono-scheme (resolve-type cx env syntax)))))

    ;; The constraint of a class at resolved types, one for each of the
    ;; class's parameters. The scan put every class the library declares in
    ;; the program, so a signature may come before its class.

    (define (resolve-constraint (cx Context) (env Env) (syntax Syntax)) (→ Constraint)
      (match syntax
        ((Form (Cons class types) loc)
         (match (resolve cx env (expect-ident class "a typeclass"))
           ((Some (ClassName id))
            (let ((types (map (lambda (type) (resolve-type cx env type)) types)))
              (check-constraint-arity (program-class (● cx program) id) (length types) loc)
              (new Constraint (class id) (types types))))
           (_ (compile-error loc "expected a typeclass constraint"))))
        (_ (compile-error (syntax-loc syntax) "expected (Class type ...)"))))

    (define (check-constraint-arity (class Class) (count I64) (loc Loc)) (→ Unit)
      (unless (= count (length (● class params)))
        (compile-error loc
                       (string-append "a constraint gives each of the class's parameters, as in ("
                                      (string-join (Cons (short-name (● class name))
                                                         (● class params))
                                                   " ")
                                      ")"))))

    (define (resolve-type (cx Context) (env Env) (syntax Syntax)) (→ Type)
      (match syntax
        ((Ident _ _ loc) (resolve-type-name cx env syntax (Nil) loc))
        ((Form (Cons (Ident "Fn" _ _) items) loc) (resolve-callable-arrow cx env items (Nil) loc))
        ((Form (Cons head args) loc)
         (resolve-type-name cx env (expect-ident head "a type constructor") args loc))
        (_ (compile-error (syntax-loc syntax) "expected a type"))))

    (define (resolve-type-name (cx Context) (env Env) (ident Syntax) (args (List Syntax)) (loc Loc))
      (→ Type)
      (let ((identifier-name (ident-name ident)))
        (match (resolve cx env ident)
          ((Some (TypeName name arity _))
           (unless (= arity (length args))
             (compile-error loc (string-append "wrong number of type arguments: " identifier-name)))
           (TCon name (map (lambda (arg) (resolve-type cx env arg)) args)))
          ((Some (TypeVar type))
           (if (null? args)
               type
               (compile-error loc "a type variable takes no arguments")))
          ((Some (Alias name params body alias-env))
           (unless (= (length params) (length args))
             (compile-error loc
                            (string-append "wrong number of alias arguments: " identifier-name)))
           (when (member? name (● cx aliases))
             (compile-error loc (string-append "type alias refers to itself: " identifier-name)))
           (let ((scope (fold-left (lambda (scope pair)
                                     (extend scope
                                             (● pair first)
                                             (TypeVar (resolve-type cx env (● pair second)))))
                                   alias-env
                                   (zip params args))))
             (resolve-type (Context-aliases-set cx (Cons name (● cx aliases))) scope body)))
          (_ (compile-error loc (string-append "not a type: " identifier-name))))))

    ;; Function formers separate their parameters from one result with
    ;; `→`; nothing follows that result.

    (define (resolve-callable-arrow (cx Context)
                                    (env Env)
                                    (items (List Syntax))
                                    (params (List Type))
                                    (loc Loc))
      (→ Type)
      (match items
        ((Cons (Ident "→" _ _) rest)
         (resolve-callable-result cx env (reverse params) rest loc))
        ((Cons param rest)
         (resolve-callable-arrow cx env rest (Cons (resolve-type cx env param) params) loc))
        ((Nil) (compile-error loc "a callable signature needs → followed by one result type"))))

    (define (resolve-callable-result (cx Context)
                                     (env Env)
                                     (params (List Type))
                                     (items (List Syntax))
                                     (loc Loc))
      (→ Type)
      (match items
        ((Cons (Ident "→" _ _) _) (compile-error loc "a callable signature has only one →"))
        ((Cons result (Nil)) (TFun params (resolve-type cx env result)))
        (_ (compile-error loc "expected one result type after →"))))

    ;; ---- Expressions ----

    ;; Expands macro uses at the head of a form until the head is not a macro.

    (define (expand-head (cx Context) (env Env) (syntax Syntax))
      (→ (Pair Syntax Context))
      (match (head-binding cx env syntax)
        ((Some (Macro _ literals rules scope))
         (threading cx ((expanded (apply-macro env syntax literals rules scope)))
                    (expand-head cx env expanded)))
        (_ (new Pair (first syntax) (second cx)))))

    (define (expr (term Term) (loc Loc)) (→ Expr)
      (new Expr (term term) (type unchecked) (loc loc)))

    (define (expand-expr (cx Context) (env Env) (syntax Syntax)) (→ (Pair Expr Context))
      (threading cx ((syntax (expand-head env syntax)))
                 (match syntax
                   ((Atom value loc) (new Pair (first (expr (Lit value) loc)) (second cx)))
                   ((Ident _ _ loc)
                    (new Pair (first (expand-reference cx env syntax loc)) (second cx)))
                   ((Form (Nil) loc) (compile-error loc "empty application"))
                   ((Form (Cons _ _) loc) (expand-application cx env syntax loc)))))

    (define (expand-application (cx Context) (env Env) (syntax Syntax) (loc Loc))
      (→ (Pair Expr Context))
      (match syntax
        ((Form (Cons head args) _)
         (match (head-binding cx env syntax)
           ((Some (Core keyword)) (expand-core cx env keyword (Cons head args) loc))
           ((Some (TypeName "Any" _ _))
            (match args
              ((Cons value (Nil))
               (threading cx ((value (expand-expr env value)))
                          (new Pair (first (expr (BoxAny value) loc)) (second cx))))
              (_ (compile-error loc "expected (Any expression)"))))
           (_ (threading cx ((callee (expand-expr env head))
                             (arguments (expand-each env args)))
                         (new Pair (first (expr (App callee arguments) loc)) (second cx))))))
        (_ (panic "internal error: not an application"))))

    (define (expand-each (cx Context) (env Env) (forms (List Syntax)))
      (→ (Pair (List Expr) Context))
      (each cx (lambda (cx form) (expand-expr cx env form)) forms))

    (define (expand-reference (cx Context) (env Env) (ident Syntax) (loc Loc)) (→ Expr)
      (let ((identifier-name (ident-name ident)))
        (match (resolve cx env ident)
          ((Some (Local name)) (expr (Var name (Nil) (Nil)) loc))
          ((Some (Global name))
           (check-constructor-reference cx name loc)
           (expr (Var name (Nil) (Nil)) loc))
          ((Some (Thunk name)) (expr (App (expr (Var name (Nil) (Nil)) loc) (Nil)) loc))
          ((Some (TypeName _ _ (Some constructor)))
           (expr (Var (check-constructor-reference cx constructor loc) (Nil) (Nil)) loc))
          ((Some (TypeName _ _ (None)))
           (compile-error loc (string-append "a type is not a value: " identifier-name)))
          ((None) (compile-error loc (string-append "unbound identifier " identifier-name)))
          (_ (compile-error loc (string-append "syntax used as a value: " identifier-name))))))

    (define (check-constructor-reference (cx Context) (name String) (loc Loc))
      (→ String)
      (match (program-value (● cx program) name)
        ((Some (Constructor case _))
         (unless (● (program-type (● cx program) (● case type)) enum?)
           (compile-error loc "construct records with (new Record (field expression) ...)")))
        (_ (unit)))
      name)

    ;; `(● receiver label ...)`: the receiver is expanded once, and each
    ;; label but the last reads a field of the record before it. The last
    ;; label is the field the path names, which a read reads and a write
    ;; writes; type checking resolves each record type.

    (record FieldPath
      ((record Expr)
       (label String)))

    (define (expand-field-path (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair FieldPath Context))
      (match items
        ((Cons receiver (Cons first rest))
         (let ((label (expect-name first "a field label"))
               (rest (map (lambda (label) (expect-name label "a field label")) rest)))
           (threading cx ((value (expand-expr env receiver)))
                      (new Pair (first (field-path value label rest loc)) (second cx)))))
        (_ (compile-error loc "expected (● receiver field ...) with at least one field"))))

    (define (field-path (record Expr) (label String) (rest (List String)) (loc Loc)) (→ FieldPath)
      (match rest
        ((Nil) (new FieldPath (record record) (label label)))
        ((Cons next rest) (field-path (expr (FieldRead record label (None)) loc) next rest loc))))

    (define (expand-field-read (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (threading cx ((path (expand-field-path env items loc)))
                 (new Pair
                   (first (expr (FieldRead (● path record) (● path label) (None)) loc))
                   (second cx))))

    ;; `(set! (● receiver label ...) value)` writes the field the path
    ;; names, and is located where the place is, as a read of it would be.
    ;; Only a field is a place: a local or a parameter is not.

    (define (expand-field-write (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (match items
        ((Cons place (Cons value (Nil)))
         (match (head-binding cx env place)
           ((Some (Core "●"))
            (let ((at (syntax-loc place)))
              (threading cx ((path (expand-field-path env (form-tail place) at))
                             (value (expand-expr env value)))
                         (new Pair
                           (first
                            (expr (FieldWrite (● path record) (● path label) value (None)) at))
                           (second cx)))))
           (_ (compile-error (syntax-loc place) "a place must select a field"))))
        (_ (compile-error loc "expected (set! (● receiver field ...) value)"))))

    ;; Resolve names once into slots. The checker supplies each initializer's
    ;; field type before lowering this form to ordinary bindings and a call.
    (define (expand-new (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (match items
        ((Cons name entries)
         (let* ((case (new-case cx env name))
                (labels (map (lambda (field) (● field name)) (● case fields))))
           (threading cx ((fields (each (lambda (cx entry) (expand-initializer cx env labels entry))
                                        entries)))
                      (check-initializers fields labels loc)
                      (new Pair
                        (first (expr (New (expr (Var (● case name) (Nil) (Nil)) loc) fields) loc))
                        (second cx)))))
        (_ (compile-error loc "expected (new Record (field expression) ...)"))))

    (define (new-case (cx Context) (env Env) (name Syntax)) (→ Case)
      (let ((id (constructor-name cx env (expect-ident name "a record constructor"))))
        (match (program-value (● cx program) id)
          ((Some (Constructor case _))
           (if (● (program-type (● cx program) (● case type)) enum?)
               (compile-error (syntax-loc name)
                              "new requires a record; apply enum constructors directly")
               case))
          (_ (compile-error (syntax-loc name) "new requires a record constructor")))))

    (define (expand-initializer (cx Context) (env Env) (labels (List String)) (entry Syntax))
      (→ (Pair Initializer Context))
      (match entry
        ((Form (Cons label (Cons value (Nil))) loc)
         (let* ((label (expect-name label "a field label"))
                (slot (list-index (lambda (name) (string=? name label)) labels)))
           (match slot
             ((Some slot)
              (threading cx ((name (fresh "field")) (value (expand-expr env value)))
                         (new Pair
                           (first (new Initializer (slot slot) (name name) (value value)))
                           (second cx))))
             (_ (compile-error loc (string-append "unknown record field: " label))))))
        (_ (compile-error (syntax-loc entry) "expected (field expression)"))))

    (define (check-initializers (fields (List Initializer)) (labels (List String)) (loc Loc))
      (→ Unit)
      (let loop ((fields fields) (seen (Nil)))
        (match fields
          ((Cons field rest)
           (when (member? (● field slot) seen)
             (compile-error (● (● field value) loc)
                            (string-append "duplicate record field: "
                                           (list-ref labels (● field slot)))))
           (loop rest (Cons (● field slot) seen)))
          ((Nil)
           (for-each (lambda (slot)
                       (unless (member? slot seen)
                         (compile-error loc
                                        (string-append "missing record field: "
                                                       (list-ref labels slot)))))
                     (iota (length labels)))))))

    (define (expand-core (cx Context) (env Env) (keyword String) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (case keyword
        (("new") (expand-new cx env (list-drop items 1) loc))
        (("●") (expand-field-read cx env (list-drop items 1) loc))
        (("set!") (expand-field-write cx env (list-drop items 1) loc))
        (("lambda")
         (match items
           ((Cons _ (Cons params body))
            (if (typed-lambda? (Form items loc))
                (expand-typed-lambda cx env (parse-lambda (Form items loc)))
                (expand-lambda cx env (form-items params "a parameter list") body loc)))
           (_ (compile-error loc "expected (lambda (parameter ...) body ...)"))))
        (("if")
         ;; `then` is `threading`'s own keyword, so the branches are named
         ;; otherwise.
         (match items
           ((Cons _ (Cons test (Cons consequent (Cons alternative (Nil)))))
            (threading cx ((test (expand-expr env test))
                           (consequent (expand-expr env consequent))
                           (alternative (expand-expr env alternative)))
                       (new Pair (first (expr (If test consequent alternative) loc)) (second cx))))
           ((Cons _ (Cons test (Cons consequent (Nil))))
            (threading cx ((test (expand-expr env test)) (consequent (expand-expr env consequent)))
                       (new Pair
                         (first (expr (If test consequent (expr (Lit (DUnit)) loc)) loc))
                         (second cx))))
           (_ (compile-error loc "expected (if test then [else])"))))
        (("begin") (expand-body cx env (list-tail items 1) loc))
        (("let") (expand-let cx env items loc))
        (("match") (expand-match cx env items loc))
        (("link-handle") (expand-link-file cx items loc))
        (("ann")
         (match items
           ((Cons _ (Cons value (Cons type (Nil))))
            (threading cx ((value (expand-expr env value)))
                       (new Pair
                         (first (expr (Ann value (resolve-type cx env type)) loc))
                         (second cx))))
           (_ (compile-error loc "expected (ann expression type)"))))
        (("constant-array") (expand-constant-array cx env items loc))
        (("downcast")
         (match items
           ((Cons _ (Cons type (Cons value (Nil))))
            (threading cx ((value (expand-expr env value)))
                       (new Pair
                         (first (expr (Downcast value (resolve-type cx env type)) loc))
                         (second cx))))
           (_ (compile-error loc "expected (downcast type expression)"))))
        (("case-id")
         (match items
           ((Cons _ (Cons constructor (Nil)))
            (new Pair
              (first (expr (Ann (expr (Lit (DInt (constructor-case-id cx env constructor))) loc)
                                (TCon "I32" (Nil)))
                           loc))
              (second cx)))
           (_ (compile-error loc "expected (case-id Constructor)"))))
        (("quote")
         (match items
           ((Cons _ (Cons (Atom value _) (Nil)))
            (new Pair (first (expr (Lit value) loc)) (second cx)))
           (_ (compile-error loc "only literals can be quoted"))))
        (else
         (compile-error loc (string-append "this form is only valid as a definition: " keyword)))))

    (define (expand-lambda (cx Context)
                           (env Env)
                           (params (List Syntax))
                           (body (List Syntax))
                           (loc Loc))
      (→ (Pair Expr Context))
      (threading cx ((locals (bind-locals env params))
                     (body (expand-body (● locals first) body loc)))
                 (new Pair (first (expr (Lambda (● locals second) body) loc)) (second cx))))

    ;; A typed lambda is checked against the type its header states, as a
    ;; local function definition is.

    (define (expand-typed-lambda (cx Context) (env Env) (definition DefinitionSyntax))
      (→ (Pair Expr Context))
      (threading cx ((value (definition-value env definition)))
                 (new Pair
                   (first (annotated-definition-value cx env definition value))
                   (second cx))))

    ;; Binds each identifier to a fresh local, in order; returns the longer
    ;; environment and the unique names.

    (define (bind-locals (cx Context) (env Env) (idents (List Syntax)))
      (→ (Pair (Pair Env (List String)) Context))
      (threading cx ((names (each (lambda (cx ident)
                                    (fresh cx (expect-name ident "a variable name")))
                                  idents)))
                 (new Pair (first (new Pair (first (fold-left (lambda (env bound)
                                                                (extend env
                                                                        (● bound first)
                                                                        (Local (● bound second))))
                                                              env
                                                              (zip idents names)))
                                       (second names)))
                      (second cx))))

    (define (expand-body (cx Context) (env Env) (forms (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (when (null? forms) (compile-error loc "empty body"))
      (expand-body-forms cx env forms loc))

    ;; A local body is sequential: each definition is visible to the forms
    ;; after it, and a function definition is also visible to itself.

    (define (expand-body-forms (cx Context)
                               (scope Env)
                               (forms (List Syntax))
                               (loc Loc))
      (→ (Pair Expr Context))
      (match forms
        ((Nil) (compile-error loc "a body must end with an expression"))
        ((Cons form rest)
         (threading cx ((form (expand-head scope form)))
                    (match (head-binding cx scope form)
                      ((Some (Core "begin"))
                       (expand-body-forms cx scope (append (form-tail form) rest) loc))
                      ((Some (Core "define-syntax"))
                       (threading cx ((inner (define-local-macro scope form)))
                                  (expand-body-forms cx inner rest loc)))
                      ((Some (Core "define"))
                       (expand-local-definition cx scope form rest loc))
                      (_ (threading cx ((value (expand-expr scope form)))
                                    (if (null? rest)
                                        (new Pair (first value) (second cx))
                                        (threading cx ((more
                                                        (expand-body-forms scope rest loc)))
                                                   (new Pair
                                                     (first (expr (Seq value more) (● value loc)))
                                                     (second cx)))))))))))

    (define (expand-local-definition (cx Context) (scope Env) (form Syntax)
                                     (rest (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (let* ((definition (parse-definition cx scope form)) (ident (● definition name)))
        (threading cx ((name (fresh (expect-name ident "a local name"))))
                   (let ((inner (extend scope ident (Local name)))
                         (function? (match (● definition parameters)
                                      ((Some _) #t)
                                      ((None)
                                       (core-form? cx
                                                   scope
                                                   (list-ref (● definition body) 0)
                                                   "lambda")))))
                     (threading cx ((value (definition-value (if function? inner scope) definition))
                                    (body (expand-body-forms inner rest loc)))
                                (new Pair (first (expr (Let name
                                                            (annotated-definition-value cx
                                                                                        scope
                                                                                        definition
                                                                                        value)
                                                            body)
                                                       (syntax-loc form))) (second cx)))))))

    ;; `(let ((name value) ...) body ...)` or the named-let loop form.

    (define (expand-let (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (match items
        ((Cons _ (Cons head (Cons more body)))
         (match head
           ((Ident _ _ _)
            (expand-named-let cx env head (form-items more "a list of bindings") body loc))
           ((Form bindings _) (expand-plain-let cx env bindings (Cons more body) loc))
           (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))
        (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))

    (define (expand-named-let (cx Context)
              (env Env)
              (ident Syntax)
              (bindings (List Syntax))
              (body (List Syntax))
              (loc Loc))
      (→ (Pair Expr Context))
      (threading cx ((name (fresh (ident-name ident)))
                     (loop (expand-lambda (extend env ident (Local name))
                                          (map binding-name bindings)
                                          body
                                          loc))
                     (initial
                      (each (lambda (cx binding) (expand-expr cx env (binding-value binding)))
                            bindings)))
                 (new Pair
                   (first (expr (Let name
                                     loop
                                     (expr (App (expr (Var name (Nil) (Nil)) loc) initial) loc))
                                loc))
                   (second cx))))

    (define (expand-plain-let (cx
                               Context)
              (env Env)
              (bindings (List Syntax))
              (body (List Syntax))
              (loc Loc))
      (→ (Pair Expr Context))
      (threading cx ((values
                      (each (lambda (cx binding) (expand-expr cx env (binding-value binding)))
                            bindings))
                     (locals (bind-locals env (map binding-name bindings)))
                     (body (expand-body (● locals first) body loc)))
                 (new Pair (first (fold-right (lambda (pair body)
                                                (expr (Let (● pair first) (● pair second) body)
                                                      loc))
                                              body
                                              (zip (● locals second) values)))
                      (second cx))))

    (define (binding-name (binding Syntax)) (→ Syntax)
      (match (form-items binding "a (name value) binding")
        ((Cons name _) (expect-ident name "a binding name"))
        ((Nil) (compile-error (syntax-loc binding) "expected (name value)"))))

    (define (binding-value (binding Syntax)) (→ Syntax)
      (match binding
        ((Form (Cons _ (Cons value (Nil))) _) value)
        (_ (compile-error (syntax-loc binding) "expected (name value)"))))

    (define (constructor-case-id (cx Context) (env Env) (constructor Syntax)) (→ I64)
      (match (program-value (● cx program) (pattern-constructor cx env constructor))
        ((Some (Constructor case _)) (case-type-id (● cx program) case))
        (_ (compile-error (syntax-loc constructor) "not a constructor"))))

    ;; ---- Constant arrays ----

    ;; `(constant-array TYPE (VALUE ...))`: a table of literals of a scalar
    ;; type, which the backend builds once, as data, and every use shares.
    ;; A float table is a table of its bits, an I64 table read through
    ;; bits->f64: only the assembler knows a float literal's bits.
    ;; Each value is checked against the type here, so the table is known
    ;; whole before it is typed.

    (define (expand-constant-array (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (match items
        ((Cons _ (Cons type (Cons (Form values _) (Nil))))
         (let ((element (constant-element cx env type)))
           (new Pair
             (first (expr (Lit (DConstants element
                                           (map (lambda (value) (constant-value element value))
                                                values)))
                          loc))
             (second cx))))
        (_ (compile-error loc "expected (constant-array TYPE (VALUE ...))"))))

    (define (constant-element (cx Context) (env Env) (type Syntax)) (→ String)
      (match (resolve-type cx env type)
        ((TCon name (Nil))
         (if (member? name (list "U8" "I32" "I64" "Bool" "Char"))
             name
             (not-a-constant-element type)))
        (_ (not-a-constant-element type))))

    (define (not-a-constant-element (type Syntax)) (→ A) (∀ (A))
      (compile-error (syntax-loc type)
                     "a constant array holds U8, I32, I64, Bool or Char"))

    ;; A value as the table holds it: an integer in its type's range, a
    ;; Boolean, or a character.

    (define (constant-value (element String) (value Syntax)) (→ Datum)
      (match value
        ((Atom (DInt n) loc)
         (cond ((string=? element "U8") (in-range n 0 255 element loc))
               ((string=? element "I32") (in-range n -2147483648 2147483647 element loc))
               ((string=? element "I64") (DInt n))
               (else (not-a-constant-value element loc))))
        ((Atom (DBool b) loc)
         (if (string=? element "Bool") (DBool b) (not-a-constant-value element loc)))
        ((Atom (DChar c) loc)
         (if (string=? element "Char") (DChar c) (not-a-constant-value element loc)))
        (_ (not-a-constant-value element (syntax-loc value)))))

    (define (in-range (n I64) (low I64) (high I64) (element String) (loc Loc)) (→ Datum)
      (if (and (<= low n) (<= n high))
          (DInt n)
          (compile-error loc (string-append (i64->string n) " is not a " element))))

    (define (not-a-constant-value (element String) (loc Loc)) (→ A) (∀ (A))
      (compile-error loc (string-append "expected a literal " element)))

    ;; ---- Deriving ----

    ;; A derived instance is a use of a macro its class's library defines
    ;; beside the class: `derive-repr` in (snail core base),
    ;; `derive-serialize` and `derive-deserialize` in (snail shell wire).
    ;; The expander writes only the use, marking the macro's name to resolve
    ;; among those libraries' exports, whatever the declaring library
    ;; imports. A use is the declaration's own keyword, `record` or `enum`,
    ;; its head with its parameters, then each case:
    ;;
    ;;   (derive-repr enum (Option T) (None "None") (Some "Some" (field0 value "value" T)))
    ;;
    ;; A case is its name, the name as text and, for each field, a fresh
    ;; variable, the label, the label as text and the field's type. A macro binds the
    ;; variable, since a case may repeat a label and `_` binds nothing.

    (define implicit-libraries (→ (List (List String)))
      (list (list "snail" "core" "base") (list "snail" "shell" "wire")))

    ;; A declaration that derives nothing loads no implicit library.

    (define (derived-instances (cx Context) (form Syntax) (enum? Bool))
      (→ (Pair (List Syntax) Context))
      (match (derived-classes form)
        ((Nil) (new Pair (first (Nil)) (second cx)))
        (classes
         (let ((loc (syntax-loc form)))
           (threading cx ((scope (deriving-scope loc)))
                      (let* ((d (new Deriver (scope scope) (loc loc)))
                             (arguments (deriving-arguments d form enum?)))
                        (new Pair
                          (first (map (lambda (class)
                                        (Form (Cons (deriving-macro d class) arguments) loc))
                                      classes))
                          (second cx))))))))

    ;; `derive-pod` is the one macro outside the implicit libraries: a
    ;; declaration deriving Pod imports (snail shell graphics pod), so its
    ;; name resolves where the declaration is.

    (define (deriving-macro (d Deriver) (class Syntax)) (→ Syntax)
      (match class
        ((Ident "Repr" _ _) (marked d "derive-repr"))
        ((Ident "Serialize" _ _) (marked d "derive-serialize"))
        ((Ident "Deserialize" _ _) (marked d "derive-deserialize"))
        ((Ident "Pod" _ _) (Ident "derive-pod" (None) (syntax-loc class)))
        (_ (compile-error (syntax-loc class)
                          "only Repr, Serialize, Deserialize and Pod can be derived"))))

    ;; The scope derived instances resolve in, made at the build's first
    ;; deriving clause, which loads the implicit libraries, and shared by
    ;; every later one. The library notes the declaration at `loc`, so that
    ;; each expansion loads their current declarations.

    (define (deriving-scope (cx Context) (loc Loc)) (→ (Pair I64 Context))
      (match (● cx deriving)
        ((Some scope) (new Pair (first scope) (second cx)))
        ((None)
         (threading cx ((exports
                         (each (lambda (cx name) (load-library cx name loc)) implicit-libraries))
                        (env (new-top (fold-left (lambda (table entry)
                                                   (table-set table
                                                              (● entry first)
                                                              (● entry second)))
                                                 (empty-table) (concatenate exports))))
                        (scope (register-scope env)))
                    (new Pair (first scope) (second (Context-deriving-set cx (Some scope))))))))

    ;; What the uses of one declaration's macros share: the scope their
    ;; marked identifiers resolve in, and where the declaration is.
    (record Deriver
      ((scope I64)
       (loc Loc)))

    (define (marked (deriver Deriver) (name String)) (→ Syntax)
      (let ((loc (● deriver loc)))
        (Ident name
               (Some (new Mark (key (string-append name "%deriving"))
                          (original (Ident name (None) loc))
                          (scope (● deriver scope))))
               loc)))

    (define (derived-head (form Syntax)) (→ Syntax)
      (match (declaration-head form)
        ((Form items loc) (Form items loc))
        (name (Form (list name) (syntax-loc name)))))

    (define (deriving-arguments (d Deriver) (form Syntax) (enum? Bool)) (→ (List Syntax))
      (Cons (form-keyword form)
            (Cons (derived-head form)
                  (map (lambda (case) (derived-case d case)) (data-cases form enum?)))))

    (define (form-keyword (form Syntax)) (→ Syntax)
      (match form
        ((Form (Cons keyword _) _) keyword)
        (_ (panic "internal error: a declaration is a form"))))

    (define (derived-case (d Deriver) (case CaseSyntax)) (→ Syntax)
      (Form (Cons (● case name)
                  (Cons (Atom (DString (expect-name (● case name) "a constructor")) (● d loc))
                        (map-indexed
                         (lambda (index field) (derived-field d index (parse-field field)))
                         (● case fields))))
            (● d loc)))

    (define (derived-field (d Deriver) (index I64) (field FieldSyntax)) (→ Syntax)
      (Form (list (marked d (string-append "field" (i64->string index)))
                  (● field name)
                  (Atom (DString (expect-name (● field name) "a field label")) (● d loc))
                  (● field type))
            (● d loc)))

    ;; ---- Patterns ----

    (define (expand-match (cx Context) (env Env) (items (List Syntax)) (loc Loc))
      (→ (Pair Expr Context))
      (match items
        ((Cons _ (Cons scrutinee clauses))
         (threading cx ((scrutinee (expand-expr env scrutinee))
                        (clauses (each (lambda (cx clause) (expand-clause cx env clause)) clauses)))
                    (new Pair (first (expr (Match scrutinee clauses) loc)) (second cx))))
        (_ (compile-error loc "expected (match expression clause ...)"))))

    ;; A clause binds its pattern's variables first, so the pattern itself
    ;; only looks names up.

    (define (expand-clause (cx Context) (env Env) (clause Syntax))
      (→ (Pair Clause Context))
      (match (form-items clause "a match clause")
        ((Cons pattern body)
         (threading cx ((locals (bind-locals env (pattern-variables pattern))))
                    (let* ((scope (● locals first))
                           (pattern (expand-pattern cx env scope pattern)))
                      (threading cx ((body (expand-body scope body (syntax-loc clause))))
                                 (new Pair
                                   (first (new Clause (pattern pattern) (body body)))
                                   (second cx))))))
        ((Nil) (compile-error (syntax-loc clause) "expected (pattern body ...)"))))

    ;; The variables of a pattern, in order, each named once.

    (define (pattern-variables (syntax Syntax)) (→ (List Syntax))
      (let ((variables (pattern-idents syntax)))
        (for-each (lambda (variable)
                    (let ((identifier-name (ident-name variable)))
                      (when (< 1
                               (length (filter (lambda (other)
                                                 (string=? (ident-key other) (ident-key variable)))
                                               variables)))
                        (compile-error (syntax-loc variable)
                                       (string-append "pattern variable bound twice: "
                                                      identifier-name)))))
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
      (match syntax
        ((Ident "_" _ _) (PWild unchecked))
        ((Ident _ _ _)
         (match (resolve cx scope syntax)
           ((Some (Local name)) (PVar name unchecked))
           (_ (panic "internal error: unbound pattern variable"))))
        ((Atom (DBytes _) loc) (compile-error loc "a byte array cannot be a pattern"))
        ((Atom value _) (PLit value unchecked))
        ((Form (Cons head args) _)
         (PCon (pattern-constructor cx env head)
               (map (lambda (arg) (expand-pattern cx env scope arg)) args)
               unchecked))
        (_ (compile-error (syntax-loc syntax) "expected a pattern"))))

    (define (pattern-constructor (cx Context) (env Env) (head Syntax)) (→ String)
      (constructor-name cx env (expect-ident head "a constructor")))

    ;; ---- Syntax rules ----

    (record MacroForm
      ((name Syntax)
       (literals (List Syntax))
       (rules (List Syntax))))

    (define (macro-form (form Syntax)) (→ MacroForm)
      (match form
        ((Form (Cons _
                     (Cons name
                           (Cons
                            (Form (Cons (Ident "syntax-rules" _ _) (Cons (Form literals _) rules))
                                  _)
                            (Nil))))
               _)
         (new MacroForm
           (name (expect-ident name "a macro name"))
           (literals literals)
           (rules rules)))
        (_ (compile-error (syntax-loc form)
                          "expected (define-syntax name (syntax-rules (literal ...) rule ...))"))))

    ;; A macro's template resolves in the environment of its definition,
    ;; which includes the macro, so it may expand to a use of itself.

    (define (define-top-macro (cx Context) (env Env) (form Syntax)) (→ Context)
      (let ((parts (macro-form form)))
        (threading cx ((id (fresh "%macro")) (scope (register-scope env)))
                   (bind-top cx
                             env
                             (● parts name)
                             (Macro id (● parts literals) (● parts rules) scope)))))

    (define (define-local-macro (cx Context) (env Env) (form Syntax))
      (→ (Pair Env Context))
      (let ((parts (macro-form form)))
        (threading cx ((scope (register-scope env)) (id (fresh "%macro")))
                   (let ((inner (extend env
                                        (● parts name)
                                        (Macro id
                                               (● parts literals)
                                               (● parts rules)
                                               scope))))
                     (new Pair (first inner) (second (scope-set cx scope inner)))))))

    (define (apply-macro (cx Context)
                         (env Env)
                         (form Syntax)
                         (literals (List Syntax))
                         (rules (List Syntax))
                         (scope I64))
      (→ (Pair Syntax Context))
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
                 (threading cx ((stamp (fresh "m")))
                            (new Pair
                              (first (transcribe template
                                                 bindings
                                                 (new Expansion
                                                   (stamp stamp)
                                                   (scope scope)
                                                   (loc loc))))
                              (second cx))))
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
          ((not (literal? pattern literals))
           (Some (list (new Pair (first (ident-key pattern)) (second (One input))))))
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
      (let ((identifier-name (ident-name literal)))
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
                ((None) (string=? name identifier-name))))))
          (_ #f))))

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
                                       (new Pair (first key)
                                            (second
                                             (Many (map (lambda (bindings) (bound-ref bindings key))
                                                        matches)))))
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
    (record Expansion
      ((stamp String)
       (scope I64)
       (loc Loc)))

    (define (transcribe (template Syntax) (bindings Bindings) (expansion Expansion))
      (→ Syntax)
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
      (let ((repeated (concatenate (map (lambda (key)
                                          (match (assoc-ref bindings key)
                                            ((Some (Many matches))
                                             (list (new Pair (first key) (second matches))))
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
                                               (new Pair (first (● entry first))
                                                    (second (list-ref (● entry second) index))))
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
      (let ((identifier-name (ident-name ident)))
        (Ident identifier-name
               (Some (new Mark (key (string-append (ident-key ident) "%" (● expansion stamp)))
                          (original ident)
                          (scope (● expansion scope))))
               (● expansion loc))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-expand)
    (import
     (only (snail stage0 system) create-directory*)
     (only (snail stage0 system) string-contains)
     (snail stage0 testing))
    (begin

      ;; The tests read and write real files, through the host's own.
      (define test-fs (→ Fs) (host-fs (unsafe-host)))

      ;; The primitive library is read from its file. The sources are
      ;; written into `directory`; `library` holds the standard libraries.
      (define test-expand
        (lambda (directory library) (test-callable-signatures)
                (test-links (string-append directory "/links"))
                (test-primitives (string-append directory "/primitive") library)
                (test-deriving-runs (string-append directory "/deriving") library)))

      (define test-callable-signatures
        (lambda () (expect (callable-signature "(→ Unit)") (TFun (Nil) (TCon "Unit" (Nil))))
                (expect (callable-signature "(I64 (Array String) → Bool)")
                        (TFun (list (TCon "I64" (Nil)) (TCon "Array" (list (TCon "String" (Nil)))))
                              (TCon "Bool" (Nil))))
                (for-each (lambda (source)
                            (expect
                             (and (compile-failure (lambda () (callable-signature source))) #t)
                             #t))
                          (list "(I64 -> Unit)" "()" "(I64 Unit)" "(I64 →)" "(I64 → → Unit)"
                                "(I64 → Unit Bool)" "(I64 → Unit ! mut)"))))

      (define callable-signature
        (lambda (text)
          (let* ((cx (new-context test-fs
                                  (lambda (loading forms) (panic "unexpected producer"))
                                  (Nil)
                                  (None)
                                  (Nil)))
                 (imports (fold-left (lambda (table entry)
                                       (table-set table (● entry first) (● entry second)))
                                     (empty-table) core-library))
                 (env (● (new-top cx imports) first)))
            (match (read-text text "callable.sld")
              ((Cons (Form items loc) (Nil)) (resolve-callable-arrow cx env items (Nil) loc))))))

      ;; A linked path is made canonical against its library's directory,
      ;; and the file is named for the digest of its bytes, once however
      ;; many uses or paths reach the same bytes. A path that leaves the
      ;; directory, or a file that is not there, is an error naming the
      ;; library and the path.
      (define test-links
        (lambda (root) (create-directory* (string-append root "/sample/data"))
                (write-file test-fs (string-append root "/sample/data/pixel.bin") "pixel")
                (write-file test-fs (string-append root "/notes.txt") "notes")
                (write-file test-fs (string-append root "/copy.txt") "notes")
                (write-file test-fs (string-append root "/sample/linked.sld")
                            "(define-library (sample linked) (export pixel) (import (snail core forms)) (begin (define (pixel) (→ I32) (link-handle \"data/./x/../pixel.bin\"))))")
                (let ((expansion (link-expansion root
                                                 "(import (snail core forms) (sample linked)) (define (notes) (→ I32) (link-handle \"notes.txt\")) (define (other) (→ I32) (link-handle \"notes.txt\")) (define (copy) (→ I32) (link-handle \"copy.txt\"))")))
                  (expect (map (lambda (record) (● record digest)) (program-links expansion))
                          (list "3f8d7379e2f0f7d0c845a06f7b67ef80cacce0c686254aced769c1698f3fe59a"
                                "ab5aa97074c454a0632057e704220d9a6678fbf773a0a5806fc09b8173b07309"))
                  (expect
                   (map (lambda (record) (● record path)) (library-links expansion "sample.linked"))
                   (list (string-append root "/sample/data/pixel.bin"))))
                (expect (link-error (string-append root "/sample") "../notes.txt") "accepted")
                (expect (link-error root (string-append root "/x/../notes.txt")) "accepted")
                (expect (link-error root "./")
                        "link-file takes a path with no empty names: ./")
                (expect (link-error root "x/..") "link-file names no file: x/..")
                (expect (link-error root "absent.bin")
                        (string-append "the library main links absent.bin, but there is no file at "
                                       root
                                       "/absent.bin"))))

      (define link-expansion
        (lambda (root body) (write-file test-fs (string-append root "/main.sld") body)
                (expand-program test-fs (list root)
                                (lambda (loading forms) (panic "unexpected producer"))
                                (None)
                                (Nil)
                                (string-append root "/main.sld"))))

      (define link-error
        (lambda (root path) (let ((message (compile-failure
                                            (lambda ()
                                              (link-expansion root
                                                              (string-append
                                                               "(import (snail core forms)) (define (linked) (→ I32) (link-handle \""
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
                (write-file test-fs (string-append root "/main.sld")
                            "(import (snail core forms) (snail core primitive)) (define (main) (→ Unit) (unit))")
                (let ((program (● (expand-program test-fs (list root library)
                                                  (lambda (loading forms)
                                                    (panic "unexpected producer"))
                                                  (None)
                                                  (Nil)
                                                  (string-append root "/main.sld")) program)))
                  (expect (primitive-scheme program "array-ref")
                          (list (list "A") "(Fn (Array A) I64 → A)"))
                  (expect (primitive-scheme program "array-generate")
                          (list (list "A") "(Fn I64 (Fn I64 → A) → (Array A))"))
                  (expect (primitive-scheme program "array-ref")
                          (list (list "A") "(Fn (Array A) I64 → A)"))
                  (expect (primitive-scheme program "suspend")
                          (list (list "S" "R") "(Fn (Prompt S R) S → R)"))
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
                (write-file test-fs (string-append root "/sample/shape.sld")
                            (string-append
                             "(define-library (sample shape) (export Shape) (import (snail core base))"
                             " (begin (record Shape ((side I64)) (deriving Serialize Deserialize))))"))
                (write-file test-fs (string-append root "/main.sld")
                            "(import (snail core base) (sample shape)) (define (example) (→ Shape) (new Shape (side 2)))")
                (let* ((expand (lambda ()
                                 (expand-program test-fs (list root library)
                                                 (lambda (loading forms)
                                                   (panic "unexpected producer"))
                                                 (None)
                                                 (Nil)
                                                 (string-append root "/main.sld"))))
                       (first (expand)))
                  (expect (every? own-run? (expansion-runs first)) #t)
                  (expect (run-length first "sample.shape") 2)
                  (expect (deriving-order first) (list "snail.shell.wire" "sample.shape" "main"))
                  (expect (deriving-order (expand))
                          (list "snail.shell.wire" "sample.shape" "main")))))

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
                                 (_ (list)))))))
   (else)))
