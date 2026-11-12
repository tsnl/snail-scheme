;; A compiler that keeps running between builds, as a development server's
;; does, and compiles each library to its own module. A session is a value:
;; each build returns the session the next one starts from. A build expands
;; only the libraries whose declarations, or whose imports' interfaces,
;; changed since the build before, and replays the others. It checks,
;; specializes and emits only the libraries whose expansion changed, and
;; keeps every other library's checked items and module text from the build
;; that made them, all in memory.
(define-library (snail shell compiler session)
  (export
   Session
   make-session
   no-inputs
   Built
   LinkedFile
   build-session)
  (import
   (snail core base)
   (snail core table)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler inputs) Inputs no-inputs)
   (snail shell compiler core)
   (snail shell compiler expand)
   (snail shell compiler check)
   (snail shell compiler specialize)
   (snail shell compiler prepare)
   (snail shell compiler wasm))
  (begin

    ;; ---- Sessions ----

    ;; What one library's expansion became: its checked items, the schemes
    ;; of its own definitions, and its emission, None until emitted. `key`
    ;; is the build key of the expansion it was made from.
    (struct Compiled
      ((key String)
       (items (List Item))
       (schemes (Table Scheme))
       (emission (Option String))))

    ;; Where libraries are found, the last expansion and each library as
    ;; last compiled. Generators and build inputs belong to one invocation.
    (struct Session
      ((directories (List String))
       (expansion ExpandedProgram)
       (compiled (Table Compiled))))

    ;; One library's module after a build, whether this build compiled it,
    ;; and the files the library links, which the build places beside the
    ;; payload whether or not it compiled the module.
    (struct Built
      ((name String)
       (text String)
       (compiled? Bool)
       (links (List LinkedFile))))

    (define (make-session (directories (List String))) (→ Session)
      (Session directories empty-expansion empty-table))

    ;; ---- Builds ----

    ;; The modules of the program at `source`, in program order, and the
    ;; session after the build. Artifact snapshots and producer outputs
    ;; belong to this invocation, never to the retained session.

    (define (build-session (session Session)
                           (source String)
                           (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                           (inputs Inputs))
      (→ (Pair (List Built) Session))
      (! mut fs compile)
      (let* ((expansion (expand-program (● session directories)
                                        generate
                                        inputs
                                        source
                                        (● session expansion)))
             (program (● expansion program))
             (libraries (library-items program (program-items program)))
             (checked (check-libraries (● session compiled) expansion libraries))
             (built
              (emit-libraries expansion (● checked second) (● checked first) libraries)))
        (Pair (append (control-modules session program) (● built first))
              (Session (● session directories) expansion (● built second)))))

    ;; A program with control effects links the control module first: it
    ;; holds the yield record that the program's modules share. Its text is
    ;; fixed, so a build compiles it only when the build before had none. It
    ;; links no files.

    (define (control-modules (session Session) (program Program)) (→ (List Built)) (! mut)
      (if (null? (control-effects program))
          (Nil)
          (list (Built "snail.core.control" (wat->string (emit-control-module program))
                       (null?
                        (control-effects (● (● session expansion) program)))
                       (Nil)))))

    ;; Checks each library whose expansion changed, after the schemes of the
    ;; libraries before it, and returns the whole program checked, with each
    ;; library as compiled now.

    (define (check-libraries (compiled (Table Compiled))
                             (expansion ExpandedProgram)
                             (libraries (List (Pair String (List Item)))))
      (→ (Pair Typed (Table Compiled)))
      (! compile)
      (let loop ((libraries libraries) (compiled compiled) (items (Nil)) (schemes empty-table))
        (match libraries
          ((Cons library rest)
           (let ((checked (checked-library compiled expansion schemes library)))
             (loop rest
                   (table-set compiled (● library first) checked)
                   (append items (● checked items))
                   (table-union schemes (● checked schemes)))))
          ((Nil) (Pair (Typed (● expansion program) items schemes) compiled)))))

    ;; A library as compiled before, if made from its current expansion, or
    ;; checked again.

    (define (checked-library (compiled (Table Compiled))
                             (expansion ExpandedProgram)
                             (schemes (Table Scheme))
                             (library (Pair String (List Item))))
      (→ Compiled)
      (! compile)
      (let ((key (library-key expansion (● library first))))
        (match (table-ref compiled (● library first))
          ((Some before)
           (if (string=? (● before key) key)
               before
               (check-anew expansion schemes library key)))
          ((None) (check-anew expansion schemes library key)))))

    (define (check-anew (expansion ExpandedProgram)
                        (schemes (Table Scheme))
                        (library (Pair String (List Item)))
                        (key String))
      (→ Compiled)
      (! compile)
      (let ((typed
             (check-library (● expansion program) schemes (● library second))))
        (Compiled key
                  (● typed items)
                  (own-schemes (● typed schemes) (● typed items))
                  (None))))

    ;; Each library's module: the one emitted before, or, for a library just
    ;; checked, a new one, which this build compiled. A library with no items,
    ;; such as a runtime interface's, which only declares externs, has no
    ;; module: its importers call the host's imports themselves, and a module
    ;; of its name would stand where the host's module of that name belongs.

    (define (emit-libraries (expansion ExpandedProgram)
                            (compiled (Table Compiled))
                            (typed Typed)
                            (libraries (List (Pair String (List Item)))))
      (→ (Pair (List Built) (Table Compiled)))
      (! mut compile)
      (let ((input (prepare-specialization typed)))
        (let loop ((libraries libraries) (compiled compiled) (built (Nil)))
          (match libraries
            ((Cons (Pair _ (Nil)) rest) (loop rest compiled built))
            ((Cons (Pair name _) rest)
             (let ((before (compiled-of compiled name)))
               (match (● before emission)
                 ((Some emission)
                  (loop rest
                        compiled
                        (Cons
                         (Built name emission #f (library-links expansion name))
                         built)))
                 ((None)
                  (let ((text (wat->string
                               (emit-module (prepare-library input name (● before items))))))
                    (loop rest
                          (table-set compiled name (Compiled-emission-set before (Some text)))
                          (Cons (Built name text #t (library-links expansion name)) built)))))))
            ((Nil) (Pair (reverse built) compiled))))))

    ;; ---- Records ----

    (define (compiled-of (compiled (Table Compiled)) (name String)) (→ Compiled)
      (match (table-ref compiled name)
        ((Some found) found)
        ((None) (panic (string-append "internal error: nothing compiled for " name)))))

    ;; The schemes of the definitions among `items`.

    (define (own-schemes (schemes (Table Scheme)) (items (List Item))) (→ (Table Scheme))
      (fold-left (lambda (own item)
                   (match item
                     ((Define name _) (match (table-ref schemes name)
                                        ((Some scheme) (table-set own name scheme))
                                        ((None) own)))
                     (_ own)))
                 empty-table items))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-session)
    (import
     (only (snail stage0 system) create-directory*)
     (only (snail stage0 system) string-contains)
     (only (chezscheme) delete-file)
     (snail stage0 testing)
     (only (snail shell compiler inputs) supply-artifact))
    (begin

      ;; A session rebuilds only what an edit changed: a body edit under a
      ;; signature recompiles its library alone, and an edit to what
      ;; importers see recompiles them too. The libraries use only
      ;; primitives, so the session runs quickly on Chez. The sources are
      ;; written into `directory`; `library` holds the standard libraries,
      ;; (snail core primitive) among them.
      (define test-session
        (lambda (directory library) (let ((main (string-append directory "/main.sld")))
                                      (create-directory* (string-append directory "/sample"))
                                      (write-sample-a directory "(i64-add x x)" "")
                                      (write-file (string-append directory "/sample/b.sld")
                                                  sample-b)
                                      (write-file main
                                                  "(import (snail core forms) (snail core primitive) (sample b)) (define (main) (→ Unit) (four) (unit))")
                                      (let* ((first
                                              (build-session (make-session (list directory library))
                                                             main
                                                             no-generation
                                                             no-inputs))
                                             (unchanged (build-session (● first second)
                                                                       main
                                                                       no-generation
                                                                       no-inputs))
                                             (body (begin
                                                     (write-sample-a directory "(i64-mul x 2)" "")
                                                     (build-session (● unchanged second)
                                                                    main
                                                                    no-generation
                                                                    no-inputs)))
                                             (interface (begin
                                                          (write-sample-a directory
                                                                          "(i64-mul x 2)"
                                                                          "(define zero 0)")
                                                          (build-session (● body second)
                                                                         main
                                                                         no-generation
                                                                         no-inputs))))
                                        (expect (compiled-names first)
                                                (list "sample.a" "sample.b" "main"))
                                        (expect (compiled-names unchanged) (list))
                                        (expect (compiled-names body) (list "sample.a"))
                                        (expect (compiled-names interface)
                                                (list "sample.a" "sample.b" "main"))))
                (test-specialization-replay directory library)
                (test-header-interfaces directory library)
                (test-instance-replay directory library)
                (test-artifact-replay directory library)
                (test-link-replay directory library)
                (test-extern-library directory library)))

      (define no-generation (lambda (loading forms) (panic "unexpected generated library")))

      ;; A signed helper's edit still gives the library's instance methods
      ;; fresh names. An importer must select their new evidence and symbols.
      (define test-instance-replay
        (lambda (directory library) (let ((main (string-append directory "/instance.sld"))
                                          (file (string-append directory "/sample/policy.sld")))
                                      (define source
                                        (lambda (body) (string-append
                                                        "(define-library (sample policy) (export Value value) "
                                                        "(import (snail core forms) (snail core primitive)) (begin "
                                                        "(typeclass (Value A) (: value (Fn A → I64))) "
                                                        "(instance (Value I64) (define value (lambda (x) (helper x)))) "
                                                        "(define (helper (x I64)) (→ I64) "
                                                        body
                                                        ")))")))
                                      (write-file file (source "(i64-add x 1)"))
                                      (write-file main
                                                  "(import (snail core forms) (snail core primitive) (sample policy)) (define (main) (→ Unit) (value (ann 2 I64)) (unit))")
                                      (let ((first
                                             (build-session (make-session (list directory library))
                                                            main no-generation no-inputs)))
                                        (write-file file (source "(i64-add x 2)"))
                                        (expect
                                         (compiled-names (build-session (● first second)
                                                                        main
                                                                        no-generation
                                                                        no-inputs))
                                         (list "sample.policy" "main"))))))

      ;; A cached library retains checked generic code, not old concrete
      ;; copies. A new caller can request another type without recompiling
      ;; that library, and gets exactly the same Wasm as a fresh session.
      (define test-specialization-replay
        (lambda (directory library) (let ((main (string-append directory "/generic.sld"))
                                          (source
                                           "(import (snail core forms) (snail core primitive) (sample generic)) "))
                                      (write-file (string-append directory "/sample/generic.sld")
                                                  (string-append
                                                   "(define-library (sample generic) (export identity) "
                                                   "(import (snail core forms) (snail core primitive)) "
                                                   "(begin (define (identity (x A)) (→ A) (∀ A) x)))"))
                                      (write-file main
                                                  (string-append source
                                                                 "(define (main) (→ Unit) (identity (ann 1 I64)) (unit))"))
                                      (let ((first
                                             (build-session (make-session (list directory library))
                                                            main no-generation no-inputs)))
                                        (write-file main
                                                    (string-append source
                                                                   "(define (main) (→ Unit) (identity (ann 2 I32)) (unit))"))
                                        (let ((warm (build-session (● first second)
                                                                   main
                                                                   no-generation
                                                                   no-inputs))
                                              (cold (build-session
                                                     (make-session (list directory library))
                                                     main no-generation no-inputs)))
                                          (expect (compiled-names warm) (list "main"))
                                          (expect
                                           (map (lambda (record) (● record text)) (● warm first))
                                           (map (lambda (record) (● record text))
                                                (● cold first))))))))

      ;; Polymorphic bodies specialize in their importers. An ordinary FnOnce
      ;; parameter stays monomorphic, so editing its body only rebuilds its library.
      (define test-header-interfaces
        (lambda (directory library)
          (test-header-edit directory library
                            "(define apply (→ (∀ (A) (Fn A → A))) (lambda (x) x))"
                            "(define apply (→ (∀ (A) (Fn A → A))) (lambda (x) (begin (i64-add 1 2) x)))"
                            "(apply (ann 3 I64))" #t)
          (test-header-edit directory library
                            "(define (apply (f (FnOnce I64 → I64))) (→ I64) (f 1))"
                            "(define (apply (f (FnOnce I64 → I64))) (→ I64) (f 2))"
                            "(apply (lambda (x) (i64-add x 1)))" #f)))

      (define test-header-edit
        (lambda (directory library before after call specialized?)
          (let ((main (string-append directory "/headers.sld"))
                (module (string-append directory "/sample/headers.sld")))
            (define source
              (lambda (definition)
                (string-append
                 "(define-library (sample headers) (export apply) "
                 "(import (snail core base) (only (snail core primitive) i64-add)) (begin "
                 definition "))")))
            (write-file module (source before))
            (write-file main (string-append
                              "(import (snail core base) (only (snail core primitive) i64-add) (sample headers)) "
                              "(define (main) (→ Unit) " call " (unit))"))
            (let ((first (build-session (make-session (list directory library))
                                        main no-generation no-inputs)))
              (write-file module (source after))
              (let ((warm (build-session (● first second) main no-generation no-inputs)))
                (expect (compiled-names warm)
                        (if specialized? (list "sample.headers" "main") (list "sample.headers")))
                (expect (any? (lambda (module)
                                (and (string=? (● module name)
                                               (if specialized? "main" "sample.headers"))
                                     (string-contains (● module text) "(i64.const 2)") #t))
                              (● warm first)) #t))))))

      ;; Unchanged bytes preserve emission. Missing inputs invalidate even
      ;; a replay, but removing the invocation must not demand its old input.
      (define test-artifact-replay
        (lambda (directory library) (let ((main (string-append directory "/artifact.sld"))
                                          (files (list (Pair "page.html"
                                                             (list->vector (list (i32->u8 1)))))))
                                      (write-artifact-source directory
                                                             "(artifact-bundle \"client\")")
                                      (write-file main
                                                  "(import (snail core base) (sample assets)) (define (main) (→ Unit) (bundle) (unit))")
                                      (let* ((inputs (supply-artifact no-inputs "client" files))
                                             (first
                                              (build-session (make-session (list directory library))
                                                             main
                                                             no-generation
                                                             inputs))
                                             (unchanged (build-session (● first second)
                                                                       main
                                                                       no-generation
                                                                       (supply-artifact no-inputs
                                                                                        "client"
                                                                                        files)))
                                             (empty (build-session (● first second)
                                                                   main
                                                                   no-generation
                                                                   (supply-artifact no-inputs
                                                                                    "client"
                                                                                    (Nil)))))
                                        (expect (compiled-names unchanged) (Nil))
                                        (expect (compiled-names empty)
                                                (list "sample.assets" "main"))
                                        (expect (artifact-replay-error (● empty second) main) #t)
                                        (write-artifact-source directory "(ArtifactBundle (Nil))")
                                        (expect
                                         (compiled-names (build-session (● empty second)
                                                                        main
                                                                        no-generation
                                                                        no-inputs))
                                         (list "sample.assets" "main"))))))

      ;; A linked file's digest is in its library's keys and in its
      ;; importers': a build with the file unchanged compiles nothing, and
      ;; editing it compiles the library, whose module names the new
      ;; digest, and its importer. Removing it fails even a replay, naming
      ;; the library and the path.
      (define test-link-replay
        (lambda (directory library) (let ((main (string-append directory "/linked.sld"))
                                          (data (string-append directory "/sample/data.bin")))
                                      (write-file data "first")
                                      (write-file (string-append directory "/sample/linked.sld")
                                                  (string-append
                                                   "(define-library (sample linked) (export data) (import (snail core forms) (snail core primitive)) "
                                                   "(begin (define (data) (→ I32) (link-handle \"./data.bin\"))))"))
                                      (write-file main
                                                  "(import (snail core forms) (snail core primitive) (sample linked)) (define (main) (→ Unit) (data) (unit))")
                                      (let* ((first
                                              (build-session (make-session (list directory library))
                                                             main
                                                             no-generation
                                                             no-inputs))
                                             (unchanged (build-session (● first second)
                                                                       main
                                                                       no-generation
                                                                       no-inputs))
                                             (edited (begin
                                                       (write-file data "second")
                                                       (build-session (● unchanged second)
                                                                      main
                                                                      no-generation
                                                                      no-inputs))))
                                        (expect (compiled-names unchanged) (Nil))
                                        (expect (compiled-names edited)
                                                (list "sample.linked" "main"))
                                        (expect
                                         (map (lambda (built)
                                                (map (lambda (record) (● record digest))
                                                     (● built links)))
                                              (● edited first))
                                         (list
                                          (list
                                           "16367aacb67a4a017c8da8ab95682ccb390863780f7114dda0a0e0c55644c7c4")
                                          (Nil)))
                                        (expect (map (lambda (record) (● record path))
                                                     (● (list-ref (● edited first) 0) links))
                                                (list (string-append directory "/sample/data.bin")))
                                        (delete-file data)
                                        (expect (link-missing? (● edited second) main) #t)))))

      ;; A library of externs alone emits no module; its importer calls the
      ;; host's import.
      (define test-extern-library
        (lambda (directory library) (let ((main (string-append directory "/clock.sld")))
                                      (write-file (string-append directory "/sample/host.sld")
                                                  (string-append
                                                   "(define-library (sample host) (export now) (import (snail core forms) (snail core primitive)) "
                                                   "(begin (extern now \"sample.host\" \"now\" (Fn → I64))))"))
                                      (write-file main
                                                  "(import (snail core forms) (snail core primitive) (sample host)) (define (main) (→ Unit) (now) (unit))")
                                      (let ((built (● (build-session
                                                       (make-session (list directory library))
                                                       main
                                                       no-generation
                                                       no-inputs) first)))
                                        (expect (map (lambda (record) (● record name)) built)
                                                (list "main"))
                                        (expect (and (string-contains (● (list-ref built 0) text)
                                                                      "(import \"sample.host\" \"now\"")
                                                     #t)
                                                #t)))))

      (define link-missing?
        (lambda (session main) (let ((message
                                      (compile-failure (lambda ()
                                                         (build-session session
                                                                        main
                                                                        no-generation
                                                                        no-inputs)))))
                                 (and message
                                      (string-contains message
                                                       "the library sample.linked links data.bin, but there is no file at")
                                      #t))))

      (define artifact-replay-error
        (lambda (session main)
          (match (compiling (lambda () (build-session session main no-generation no-inputs)))
            ((Err (Requested (ArtifactInput "client" _))) #t)
            (_ #f))))

      (define write-artifact-source
        (lambda (directory body) (write-file (string-append directory "/sample/assets.sld")
                                             (string-append
                                              "(define-library (sample assets) (export bundle) (import (snail core base) (snail shell artifact)) "
                                              "(begin (define (bundle) (→ ArtifactBundle) "
                                              body
                                              ")))"))))

      (define write-sample-a
        (lambda (directory body more) (write-file (string-append directory "/sample/a.sld")
                                                  (string-append
                                                   "(define-library (sample a) (export twice) (import (snail core forms) (snail core primitive)) (begin "
                                                   "(define (twice (x I64)) (→ I64) "
                                                   body
                                                   ") "
                                                   more
                                                   "))"))))

      (define sample-b
        "(define-library (sample b) (export four) (import (snail core forms) (snail core primitive) (sample a)) (begin (define (four) (→ I64) (twice 2))))")

      (define compiled-names
        (lambda (build)
          (map (lambda (record) (● record name))
               (filter (lambda (record) (● record compiled?)) (● build first)))))))
   (else)))
