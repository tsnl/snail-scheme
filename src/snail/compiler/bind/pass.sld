;; The pass `bind`: an expanded library, and what the build found for it,
;; become the library bound, or the targets it waits for. It works in two
;; steps. First it finds what the library needs among what the build
;; supplied, and decides what a miss means, as (snail compiler bind needs)
;; says. Then it walks the library, handed what was found and threading
;; only numbers. Each file the library links is declared once, by a
;; LinkImport that binds a handle of the library's to the import named
;; for the file's digest, and each `link-handle` form becomes a call of
;; its file's handle, as the old expander binds them once a library's body
;; has expanded. Each `artifact-files` form becomes the list of its
;; target's files, built from the form's three expressions, which the old
;; expander writes as syntax and expands again for each file; here a
;; repeated expression is a copy with locals of its own, so the library
;; still binds each local once.
(define-library (snail compiler bind pass)
  (export
   BindOutcome
   BoundLibrary
   WantsTargets
   bind)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries)
   (prefix (snail compiler expand language) expanded-)
   (only (snail compiler names globals) Global TopGlobal)
   (only (snail compiler literals constant) Text ByteVector)
   (snail compiler expand links)
   (snail compiler expand targets)
   (snail compiler bind language)
   (snail compiler bind supply)
   (snail compiler bind needs)
   (snail compiler bind state)
   (only (snail compiler names numbering) Numbering fresh-global))
  (begin

    ;; ---- The pass ----

    ;; A library bound, or the targets it waits for: each it asks for that
    ;; the build did not supply, in the order it first asks.
    (enum BindOutcome
      (BoundLibrary
       ((bound Bound)))
      (WantsTargets
       ((requests (List TargetRequest)))))

    ;; What the library needs is found in the old expander's order: first
    ;; the targets it asks for, all of them; then the files it links, a
    ;; clash before a missing file. A program's globals are in
    ;; `program-library`.
    (: bind (impl (Fn expanded-Expanded Supply -> (Result BindOutcome (List Feedback)))))
    (define (bind expanded supply)
      (let ((name (library-name expanded)))
        (match (targets-supplied (requested-targets expanded) (::targets supply))
          ((Unsupplied requests) (Ok (WantsTargets requests)))
          ((Supplied targets)
           (result-let* ((links (found-links name
                                             (::printed supply)
                                             (linked-files expanded)
                                             (::digests supply))))
             (Ok (BoundLibrary (bound-library expanded name links targets))))))))

    (: library-name (impl (Fn expanded-Expanded -> LibraryName)))
    (define (library-name expanded)
      (match expanded
        ((expanded-Defined name _ _ _) name)
        ((expanded-Program _ _) program-library)))

    ;; ---- The walk ----

    ;; The library `name` bound with the files it links and the files of
    ;; the targets it asks for. The handles are numbered first, from the
    ;; first number the library has not used, then the copies' locals; the
    ;; bound library's root holds the first number left.
    (: bound-library
       (impl (Fn expanded-Expanded LibraryName (List FoundLink) (List TargetFiles) -> Bound)))
    (define (bound-library expanded name links targets)
      (match expanded
        ((expanded-Defined _ tops first-unused loc)
         (state-let* ((site numbering (found-site (Numbering name first-unused) links targets))
                      (bound state (bound-tops (binding-from numbering) site tops)))
           (Defined name (append (link-imports site) bound) (::next (::numbering state)) loc)))
        ((expanded-Program tops first-unused)
         (state-let* ((site numbering (found-site (Numbering name first-unused) links targets))
                      (bound state (bound-tops (binding-from numbering) site tops)))
           (Program (append (link-imports site) bound) (::next (::numbering state)))))))

    ;; ---- What was found ----

    ;; What a library's expressions are bound with: a handle for each file
    ;; it links, and the files of each target it asks for.
    (struct Site
      ((handles (List LinkHandle))
       (targets (List TargetFiles))))

    ;; A file the library links, and the Global its uses call.
    (struct LinkHandle
      ((global Global)
       (link FoundLink)))

    ;; Each linked file's handle is a Global of the library named
    ;; "link-handle", numbered in the order the library first links the
    ;; files, so no other Global of it has that serial.
    (: found-site
       (impl (Fn Numbering (List FoundLink) (List TargetFiles) -> (Pair Site Numbering))))
    (define (found-site numbering links targets)
      (state-let* ((handles numbering (map-with-state numbering link-handle links)))
        (Pair (Site handles targets) numbering)))

    (: link-handle (impl (Fn Numbering FoundLink -> (Pair LinkHandle Numbering))))
    (define (link-handle numbering link)
      (state-let* ((global numbering (fresh-global numbering "link-handle")))
        (Pair (LinkHandle global link) numbering)))

    ;; The LinkImport of each handle, in the order of its serial.
    (: link-imports (impl (Fn Site -> (List Top))))
    (define (link-imports site)
      (map (lambda (handle)
             (let ((link (::link handle)))
               (LinkImport (::global handle)
                           (::path link)
                           (::digest link)
                           (::file link)
                           (::loc link))))
           (::handles site)))

    ;; ---- Copies ----

    ;; `expr` bound again, as a copy with locals of its own, as (snail
    ;; compiler bind state) renames them.
    (: copied (impl (Fn Binding Site expanded-Expr -> (Pair Expr Binding))))
    (define (copied state site expr)
      (state-let* ((copy inner (bound-expr (copying state) site expr)))
        (Pair copy (copy-done state inner))))

    ;; ---- Declarations ----

    (: bound-tops (impl (Fn Binding Site (List expanded-Top) -> (Pair (List Top) Binding))))
    (define (bound-tops state site tops)
      (map-with-state state (lambda (state top) (bound-top state site top)) tops))

    ;; Each declaration as it was, with the expressions it holds bound.
    (: bound-top (impl (Fn Binding Site expanded-Top -> (Pair Top Binding))))
    (define (bound-top state site top)
      (match top
        ((expanded-Define global value loc)
         (state-let* ((value state (bound-expr state site value)))
           (Pair (Define global value loc) state)))
        ((expanded-Signature target scheme annotations loc)
         (Pair (Signature target scheme annotations loc) state))
        ((expanded-Statement expr)
         (state-let* ((expr state (bound-expr state site expr)))
           (Pair (Statement expr) state)))
        ((expanded-Expose target symbol dynamic? loc)
         (Pair (Expose target symbol dynamic? loc) state))
        ((expanded-Struct global parameters fields derivations annotations name-loc loc)
         (Pair (Struct global parameters fields derivations annotations name-loc loc) state))
        ((expanded-Enum global parameters cases derivations annotations loc)
         (Pair (Enum global parameters cases derivations annotations loc) state))
        ((expanded-Alias global parameters annotations loc)
         (Pair (Alias global parameters annotations loc) state))
        ((expanded-Class global parameters members annotations loc)
         (Pair (Class global parameters members annotations loc) state))
        ((expanded-TopInstance instance)
         (state-let* ((instance state (bound-instance state site instance)))
           (Pair (TopInstance instance) state)))
        ((expanded-InstanceSet global members loc)
         (state-let* ((members state (map-with-state state
                                                     (lambda (state member)
                                                       (bound-member state site member))
                                                     members)))
           (Pair (InstanceSet global members loc) state)))
        ((expanded-InstanceScope sets tops loc)
         (state-let* ((tops state (bound-tops state site tops)))
           (Pair (InstanceScope sets tops loc) state)))
        ((expanded-Extern global module symbol type annotations loc)
         (Pair (Extern global module symbol type annotations loc) state))
        ((expanded-Effect global operations defaults around-main? annotations loc)
         (state-let* ((defaults state (map-with-state state
                                                      (lambda (state default)
                                                        (bound-default state site default))
                                                      defaults)))
           (Pair (Effect global operations defaults around-main? annotations loc) state)))
        ((expanded-Primitive global type loc) (Pair (Primitive global type loc) state))))

    (: bound-instance (impl (Fn Binding Site expanded-Instance -> (Pair Instance Binding))))
    (define (bound-instance state site instance)
      (state-let* ((body state (bound-instance-body state site (::body instance))))
        (Pair (Instance (::class instance)
                        (::variables instance)
                        (::types instance)
                        (::requirements instance)
                        (::equations instance)
                        body
                        (::loc instance))
              state)))

    (: bound-instance-body
       (impl (Fn Binding Site expanded-InstanceBody -> (Pair InstanceBody Binding))))
    (define (bound-instance-body state site body)
      (match body
        ((expanded-Dispatch types loc) (Pair (Dispatch types loc) state))
        ((expanded-Methods methods)
         (state-let* ((methods state (map-with-state state
                                                     (lambda (state method)
                                                       (bound-method state site method))
                                                     methods)))
           (Pair (Methods methods) state)))))

    (: bound-method
       (impl (Fn Binding Site expanded-InstanceMethod -> (Pair InstanceMethod Binding))))
    (define (bound-method state site method)
      (state-let* ((value state (bound-expr state site (::value method))))
        (Pair (InstanceMethod (::name method) value) state)))

    (: bound-member (impl (Fn Binding Site expanded-SetMember -> (Pair SetMember Binding))))
    (define (bound-member state site member)
      (match member
        ((expanded-SetInstance instance)
         (state-let* ((instance state (bound-instance state site instance)))
           (Pair (SetInstance instance) state)))
        ((expanded-DynamicInstances class pairs loc)
         (Pair (DynamicInstances class pairs loc) state))))

    (: bound-default (impl (Fn Binding Site expanded-Default -> (Pair Default Binding))))
    (define (bound-default state site default)
      (state-let* ((value state (bound-expr state site (::value default))))
        (Pair (Default (::label default) value (::loc default)) state)))

    ;; ---- Expressions ----

    ;; Each expression as it was, with the expressions inside it bound, a
    ;; binder's local renamed in a copy, and a linked file and a request
    ;; for a target's files replaced.
    (: bound-expr (impl (Fn Binding Site expanded-Expr -> (Pair Expr Binding))))
    (define (bound-expr state site expr)
      (match expr
        ((expanded-Literal constant loc) (Pair (Literal constant loc) state))
        ((expanded-LocalRef local loc) (Pair (LocalRef (reference state local) loc) state))
        ((expanded-TopRef value loc) (Pair (TopRef value loc) state))
        ((expanded-Path labels loc) (Pair (Path labels loc) state))
        ((expanded-PathApply labels record loc)
         (state-let* ((record state (bound-expr state site record)))
           (Pair (PathApply labels record loc) state)))
        ((expanded-Lambda parameters body loc)
         (state-let* ((parameters state (binders state parameters))
                      (body state (bound-expr state site body)))
           (Pair (Lambda parameters body loc) state)))
        ((expanded-ClosedLambda parameters body loc)
         (state-let* ((parameters state (binders state parameters))
                      (body state (bound-expr state site body)))
           (Pair (ClosedLambda parameters body loc) state)))
        ((expanded-Call callee arguments loc)
         (state-let* ((callee state (bound-expr state site callee))
                      (arguments state (bound-exprs state site arguments)))
           (Pair (Call callee arguments loc) state)))
        ((expanded-If test consequent alternative loc)
         (state-let* ((test state (bound-expr state site test))
                      (consequent state (bound-expr state site consequent))
                      (alternative state (bound-expr state site alternative)))
           (Pair (If test consequent alternative loc) state)))
        ((expanded-Seq first rest loc)
         (state-let* ((first state (bound-expr state site first))
                      (rest state (bound-expr state site rest)))
           (Pair (Seq first rest loc) state)))
        ((expanded-Let local signature value body loc)
         (state-let* ((local state (binder state local))
                      (value state (bound-expr state site value))
                      (body state (bound-expr state site body)))
           (Pair (Let local signature value body loc) state)))
        ((expanded-LocalSignature scheme body loc)
         (state-let* ((body state (bound-expr state site body)))
           (Pair (LocalSignature scheme body loc) state)))
        ((expanded-Match scrutinee clauses loc)
         (state-let* ((scrutinee state (bound-expr state site scrutinee))
                      (clauses state (map-with-state state
                                                     (lambda (state clause)
                                                       (bound-clause state site clause))
                                                     clauses)))
           (Pair (Match scrutinee clauses loc) state)))
        ((expanded-Handle effect implementations body loc)
         (state-let* ((implementations state
                                       (map-with-state state
                                                       (lambda (state implementation)
                                                         (bound-implementation state
                                                                               site
                                                                               implementation))
                                                       implementations))
                      (body state (bound-expr state site body)))
           (Pair (Handle effect implementations body loc) state)))
        ((expanded-WithInstances sets body loc)
         (state-let* ((body state (bound-expr state site body)))
           (Pair (WithInstances sets body loc) state)))
        ((expanded-Ann value type loc)
         (state-let* ((value state (bound-expr state site value)))
           (Pair (Ann value type loc) state)))
        ((expanded-Convert value type loc)
         (state-let* ((value state (bound-expr state site value)))
           (Pair (Convert value type loc) state)))
        ((expanded-TryConvert value type loc)
         (state-let* ((value state (bound-expr state site value)))
           (Pair (TryConvert value type loc) state)))
        ((expanded-TypeTest value type loc)
         (state-let* ((value state (bound-expr state site value)))
           (Pair (TypeTest value type loc) state)))
        ((expanded-CaseId constructor constructor-loc loc)
         (Pair (CaseId constructor constructor-loc loc) state))
        ((expanded-LinkedFile path _ loc) (Pair (linked-call site path loc) state))
        ((expanded-ArtifactFiles target file prepend empty loc)
         (target-list state site (target-files site target) (ListParts file prepend empty loc)))))

    (: bound-exprs (impl (Fn Binding Site (List expanded-Expr) -> (Pair (List Expr) Binding))))
    (define (bound-exprs state site exprs)
      (map-with-state state (lambda (state expr) (bound-expr state site expr)) exprs))

    ;; The pattern's locals are bound before the body that names them.
    (: bound-clause (impl (Fn Binding Site expanded-Clause -> (Pair Clause Binding))))
    (define (bound-clause state site clause)
      (state-let* ((pattern state (bound-pattern state (::pattern clause)))
                   (body state (bound-expr state site (::body clause))))
        (Pair (Clause pattern body (::loc clause)) state)))

    (: bound-implementation
       (impl (Fn Binding Site expanded-Implementation -> (Pair Implementation Binding))))
    (define (bound-implementation state site implementation)
      (state-let* ((value state (bound-expr state site (::value implementation))))
        (Pair (Implementation (::label implementation) value (::loc implementation)) state)))

    ;; ---- Patterns ----

    (: bound-pattern (impl (Fn Binding expanded-Pattern -> (Pair Pattern Binding))))
    (define (bound-pattern state pattern)
      (match pattern
        ((expanded-Wild loc) (Pair (Wild loc) state))
        ((expanded-Bind local loc)
         (state-let* ((local state (binder state local)))
           (Pair (Bind local loc) state)))
        ((expanded-Equals datum loc) (Pair (Equals datum loc) state))
        ((expanded-Destructure constructor arguments loc)
         (state-let* ((arguments state (map-with-state state bound-pattern arguments)))
           (Pair (Destructure constructor arguments loc) state)))))

    ;; ---- Linked files ----

    ;; `(link-handle "path")`: a call of its file's handle, at the form.
    (: linked-call (impl (Fn Site (List String) Loc -> Expr)))
    (define (linked-call site path loc)
      (Call (TopRef (TopGlobal (::global (path-handle site path))) loc) (Nil) loc))

    ;; The handle of the file the library links at `path`. The first step
    ;; found a file for every path `linked-files` answers over this same
    ;; tree, or the walk does not run, so a miss means the query skipped
    ;; a node the walk reaches: a bug in the compiler.
    (: path-handle (impl (Fn Site (List String) -> LinkHandle)))
    (define (path-handle site path)
      (match (find (lambda (handle) (same-link-path? (::path (::link handle)) path))
                   (::handles site))
        ((Some handle) handle)
        ((None) (panic "internal error: the links query skipped a file the walk reaches"))))

    ;; ---- Target files ----

    ;; An `artifact-files` form's three expressions, and where it is.
    (struct ListParts
      ((file expanded-Expr)
       (prepend expanded-Expr)
       (empty expanded-Expr)
       (loc Loc)))

    ;; The files the build supplied for `target`. The first step found the
    ;; files of every target `requested-targets` answers over this same
    ;; tree, or the walk does not run, so a miss means the query skipped
    ;; a node the walk reaches: a bug in the compiler.
    (: target-files (impl (Fn Site String -> (List TargetFile))))
    (define (target-files site target)
      (match (find (lambda (files) (string=? (::target files) target)) (::targets site))
        ((Some files) (::files files))
        ((None) (panic "internal error: the targets query skipped a request the walk reaches"))))

    ;; For each file, `(prepend (file path bytes) rest)`, and `(empty)`
    ;; after the last, each call at the form. The first file's `prepend`
    ;; and `file` are the expressions as expand wrote them, and each later
    ;; file's are copies; `empty` is used once.
    (: target-list
       (impl (Fn Binding Site (List TargetFile) ListParts -> (Pair Expr Binding))))
    (define (target-list state site files parts)
      (match files
        ((Nil) (ended-list state site parts))
        ((Cons first rest)
         (state-let* ((prepend state (bound-expr state site (::prepend parts)))
                      (file state (bound-expr state site (::file parts)))
                      (later state (copied-list state site rest parts)))
           (Pair (prepended prepend file first later (::loc parts)) state)))))

    ;; The list of the files after the first, whose `prepend` and `file`
    ;; are copies.
    (: copied-list
       (impl (Fn Binding Site (List TargetFile) ListParts -> (Pair Expr Binding))))
    (define (copied-list state site files parts)
      (match files
        ((Nil) (ended-list state site parts))
        ((Cons first rest)
         (state-let* ((prepend state (copied state site (::prepend parts)))
                      (file state (copied state site (::file parts)))
                      (later state (copied-list state site rest parts)))
           (Pair (prepended prepend file first later (::loc parts)) state)))))

    ;; `(empty)`, which ends the list.
    (: ended-list (impl (Fn Binding Site ListParts -> (Pair Expr Binding))))
    (define (ended-list state site parts)
      (state-let* ((empty state (bound-expr state site (::empty parts))))
        (Pair (Call empty (Nil) (::loc parts)) state)))

    ;; `(prepend (file path bytes) later)`.
    (: prepended (impl (Fn Expr Expr TargetFile Expr Loc -> Expr)))
    (define (prepended prepend file target-file later loc)
      (Call prepend
            (list (Call file
                        (list (Literal (Text (::path target-file)) loc)
                              (Literal (ByteVector (::bytes target-file)) loc))
                        loc)
                  later)
            loc))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-bind)
    (import
     (snail core table)
     (only (snail compiler names globals) Local ClassGlobal Label)
     (only (snail compiler literals constant) Integer)
     (snail stage0 testing))
    (begin
      (define (test-bind)
        (test-declarations)
        (test-linked-files)
        (test-target-files)
        (test-copies)
        (test-needs-first))

      ;; ---- Helpers ----

      (define (at column)
        (Loc "lib/a.sld" 1 column))

      (define a (list "a"))

      (define (global name)
        (Global a name 0))

      (define (local name number)
        (Local name number))

      (define (top-ref name column)
        (expanded-TopRef (TopGlobal (global name)) (at column)))

      (define (handle serial)
        (Global a "link-handle" serial))

      (define (handle-call serial column)
        (Call (TopRef (TopGlobal (handle serial)) (at column)) (list) (at column)))

      (define (library tops first-unused)
        (expanded-Defined a tops first-unused (at 1)))

      (define no-supply
        (Supply (None) empty-table empty-table))

      (define (targets-supply target files)
        (Supply (None) empty-table (table-set empty-table target files)))

      (define (bound-as library)
        (Ok (BoundLibrary library)))

      (define (bytes numbers)
        (list->vector numbers))

      ;; ---- Cases ----

      ;; Declarations that hold no expression are as they were; every
      ;; expression is bound wherever it is, a program's statement too, and
      ;; nothing is numbered.
      (define (test-declarations)
        (let* ((value (expanded-Literal (Integer 1) (at 9)))
               (scheme (expanded-Scheme (list) (list) (expanded-Variable "a" (at 4)) (at 4)))
               (method (expanded-InstanceMethod (expanded-MemberName (Label "show" (at 5)))
                                                value))
               (instance (expanded-Instance (ClassGlobal (global "Show"))
                                            (list)
                                            (list)
                                            (list)
                                            (list)
                                            (expanded-Methods (list method))
                                            (at 3))))
          (expect (bind (library (list (expanded-Signature (TopGlobal (global "x"))
                                                           scheme
                                                           (list)
                                                           (at 2))
                                       (expanded-InstanceScope
                                        (list (global "set"))
                                        (list (expanded-Define (global "x") value (at 2))
                                              (expanded-TopInstance instance))
                                        (at 1))
                                       (expanded-Effect (global "e")
                                                        (list)
                                                        (list (expanded-Default
                                                               (Label "op" (at 6))
                                                               value
                                                               (at 6)))
                                                        #f
                                                        (list)
                                                        (at 6)))
                          5)
                        no-supply)
                  (bound-as
                   (Defined a
                     (list (Signature (TopGlobal (global "x")) scheme (list) (at 2))
                           (InstanceScope (list (global "set"))
                                          (list (Define (global "x")
                                                  (Literal (Integer 1) (at 9))
                                                  (at 2))
                                                (TopInstance
                                                 (Instance (ClassGlobal (global "Show"))
                                                           (list)
                                                           (list)
                                                           (list)
                                                           (list)
                                                           (Methods
                                                            (list (InstanceMethod
                                                                   (expanded-MemberName
                                                                    (Label "show" (at 5)))
                                                                   (Literal (Integer 1)
                                                                            (at 9)))))
                                                           (at 3))))
                                          (at 1))
                           (Effect (global "e")
                                   (list)
                                   (list (Default (Label "op" (at 6))
                                           (Literal (Integer 1) (at 9))
                                           (at 6)))
                                   #f
                                   (list)
                                   (at 6)))
                     5
                     (at 1))))
          (expect (bind (expanded-Program
                         (list (expanded-Statement (expanded-LocalRef (local "y" 2) (at 3))))
                         3)
                        no-supply)
                  (bound-as (Program (list (Statement (LocalRef (local "y" 2) (at 3)))) 3)))))

      ;; Each linked file is declared first, once, with the next serial,
      ;; where the library first writes it; each use of it calls its
      ;; handle, at the use.
      (define (test-linked-files)
        (let ((digests (table-set (table-set empty-table "lib/data/pixel.png" "aa")
                                  "lib/notes.txt"
                                  "bb")))
          (expect (bind (library (list (expanded-Define (global "x")
                                                        (expanded-LinkedFile
                                                         (list "data" "pixel.png")
                                                         (at 20)
                                                         (at 10))
                                                        (at 1))
                                       (expanded-Statement
                                        (expanded-Call (top-ref "f" 31)
                                                       (list (expanded-LinkedFile (list "notes.txt")
                                                                                  (at 40)
                                                                                  (at 32))
                                                             (expanded-LinkedFile
                                                              (list "data" "pixel.png")
                                                              (at 60)
                                                              (at 50)))
                                                       (at 30))))
                          7)
                        (Supply (None) digests empty-table))
                  (bound-as
                   (Defined a
                     (list (LinkImport (handle 7)
                                       (list "data" "pixel.png")
                                       "aa"
                                       "lib/data/pixel.png"
                                       (at 20))
                           (LinkImport (handle 8) (list "notes.txt") "bb" "lib/notes.txt" (at 40))
                           (Define (global "x") (handle-call 7 10) (at 1))
                           (Statement (Call (TopRef (TopGlobal (global "f")) (at 31))
                                            (list (handle-call 8 32) (handle-call 7 50))
                                            (at 30))))
                     9
                     (at 1))))))

      ;; A target's files are the list `prepend` and `file` build from them,
      ;; ending in `(empty)`; one without files is `(empty)`.
      (define (test-target-files)
        (let* ((request (lambda (target)
                          (expanded-ArtifactFiles target
                                                  (top-ref "File" 3)
                                                  (top-ref "Cons" 4)
                                                  (top-ref "Nil" 5)
                                                  (at 2))))
               (files (list (TargetFile "a.html" (bytes (list 1)))
                            (TargetFile "b.js" (bytes (list 2 3)))))
               (bound-ref
                (lambda (name column) (TopRef (TopGlobal (global name)) (at column))))
               (file (lambda (path contents)
                       (Call (bound-ref "File" 3)
                             (list (Literal (Text path) (at 2))
                                   (Literal (ByteVector contents) (at 2)))
                             (at 2))))
               (empty (Call (bound-ref "Nil" 5) (list) (at 2))))
          (expect (bind (library (list (expanded-Define (global "x") (request "site") (at 1))
                                       (expanded-Define (global "y") (request "none") (at 1)))
                          4)
                        (Supply (None)
                                empty-table
                                (table-set (table-set empty-table "site" files) "none" (list))))
                  (bound-as
                   (Defined a
                     (list (Define (global "x")
                             (Call (bound-ref "Cons" 4)
                                   (list (file "a.html" (bytes (list 1)))
                                         (Call (bound-ref "Cons" 4)
                                               (list (file "b.js" (bytes (list 2 3))) empty)
                                               (at 2)))
                                   (at 2))
                             (at 1))
                           (Define (global "y") empty (at 1)))
                     4
                     (at 1))))))

      ;; The first file's `file` is the expression as written; each later
      ;; file's is a copy whose parameters, and the pattern variable and
      ;; let it binds, are new locals numbered from the first number the
      ;; library has not used. A local bound around the form keeps its
      ;; number in every copy.
      (define (test-copies)
        (let* ((outer (local "outer" 1))
               (written
                (expanded-Lambda
                 (list (local "path" 2) (local "bytes" 3))
                 (expanded-Let (local "kept" 4)
                               (None)
                               (expanded-Match (expanded-LocalRef (local "bytes" 3) (at 5))
                                               (list (expanded-Clause
                                                      (expanded-Bind (local "b" 5) (at 6))
                                                      (expanded-LocalRef (local "b" 5)
                                                                         (at 7))
                                                      (at 6)))
                                               (at 5))
                               (expanded-Call (top-ref "File" 8)
                                              (list (expanded-LocalRef (local "path" 2) (at 9))
                                                    (expanded-LocalRef (local "kept" 4) (at 10))
                                                    (expanded-LocalRef outer (at 11)))
                                              (at 8))
                               (at 4))
                 (at 3)))
               (copy (lambda (path bytes-value kept b)
                       (Lambda (list path bytes-value)
                               (Let kept
                                    (None)
                                    (Match (LocalRef bytes-value (at 5))
                                           (list
                                            (Clause (Bind b (at 6)) (LocalRef b (at 7)) (at 6)))
                                           (at 5))
                                    (Call (TopRef (TopGlobal (global "File")) (at 8))
                                          (list (LocalRef path (at 9))
                                                (LocalRef kept (at 10))
                                                (LocalRef outer (at 11)))
                                          (at 8))
                                    (at 4))
                               (at 3))))
               (cons-ref (TopRef (TopGlobal (global "Cons")) (at 12)))
               (entry (lambda (function path contents)
                        (Call function
                              (list (Literal (Text path) (at 2))
                                    (Literal (ByteVector contents) (at 2)))
                              (at 2)))))
          (expect (bind (library (list (expanded-Define
                                        (global "x")
                                        (expanded-ArtifactFiles "site"
                                                                written
                                                                (top-ref "Cons" 12)
                                                                (top-ref "Nil" 13)
                                                                (at 2))
                                        (at 1)))
                          6)
                        (targets-supply "site"
                                        (list (TargetFile "a" (bytes (list 1)))
                                              (TargetFile "b" (bytes (list 2)))
                                              (TargetFile "c" (bytes (list 3))))))
                  (bound-as
                   (Defined a
                     (list (Define (global "x")
                             (Call cons-ref
                                   (list (entry (copy (local "path" 2)
                                                      (local "bytes" 3)
                                                      (local "kept" 4)
                                                      (local "b" 5))
                                                "a"
                                                (bytes (list 1)))
                                         (Call cons-ref
                                               (list (entry (copy (local "path" 6)
                                                                  (local "bytes" 7)
                                                                  (local "kept" 8)
                                                                  (local "b" 9))
                                                            "b"
                                                            (bytes (list 2)))
                                                     (Call cons-ref
                                                           (list (entry (copy (local "path" 10)
                                                                              (local "bytes" 11)
                                                                              (local "kept" 12)
                                                                              (local "b" 13))
                                                                        "c"
                                                                        (bytes (list 3)))
                                                                 (Call (TopRef (TopGlobal
                                                                                (global "Nil"))
                                                                               (at 13))
                                                                       (list)
                                                                       (at 2)))
                                                           (at 2)))
                                               (at 2)))
                                   (at 2))
                             (at 1)))
                     14
                     (at 1))))))

      ;; The targets come first: a library that asks for one the build
      ;; did not supply waits for it, whatever its links. Then its links:
      ;; a file the build found none for is a problem where it is first
      ;; written, and a target supplied that it does not ask for is no
      ;; matter.
      (define (test-needs-first)
        (let* ((linking (expanded-Define (global "x")
                                         (expanded-LinkedFile (list "absent.bin") (at 20) (at 10))
                                         (at 1)))
               (asking (expanded-Define (global "y")
                                        (expanded-ArtifactFiles "site"
                                                                (top-ref "File" 3)
                                                                (top-ref "Cons" 4)
                                                                (top-ref "Nil" 5)
                                                                (at 30))
                                        (at 1))))
          (expect (bind (library (list linking asking) 2) no-supply)
                  (Ok (WantsTargets (list (TargetRequest "site" (at 30))))))
          (expect (bind (library (list linking) 2) (targets-supply "docs" (list)))
                  (fail (at 20)
                        "the library a links absent.bin, but there is no file at lib/absent.bin"))))))
   (else)))
