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

    (: make-session (-> (List String) Session))
    (define (make-session directories)
      (Session directories empty-expansion empty-table))

    ;; ---- Builds ----

    ;; The modules of the program at `source`, in program order, and the
    ;; session after the build. Artifact snapshots and producer outputs
    ;; belong to this invocation, never to the retained session.
    (: build-session
       (-> Session
           String
           (-> (List String) (List Syntax) Bytes ! fs compile)
           Inputs
           (Pair (List Built) Session)
           ! mut fs compile))
    (define (build-session session source generate inputs)
      (let* ((expansion (expand-program (::directories session)
                                        generate
                                        inputs
                                        source
                                        (::expansion session)))
             (program (::program expansion))
             (libraries (library-items program (program-items program)))
             (checked (check-libraries (::compiled session) expansion libraries))
             (built
              (emit-libraries expansion (::second checked) (::first checked) libraries)))
        (Pair (append (control-modules session program) (::first built))
              (Session (::directories session) expansion (::second built)))))

    ;; A program with control effects links the control module first: it
    ;; holds the yield record that the program's modules share. Its text is
    ;; fixed, so a build compiles it only when the build before had none. It
    ;; links no files.
    (: control-modules (-> Session Program (List Built) ! mut))
    (define (control-modules session program)
      (if (null? (control-effects program))
          (Nil)
          (list (Built "snail.core.control" (wat->string (emit-control-module program))
                       (null?
                        (control-effects (::program (::expansion session))))
                       (Nil)))))

    ;; Checks each library whose expansion changed, after the schemes of the
    ;; libraries before it, and returns the whole program checked, with each
    ;; library as compiled now.
    (: check-libraries
       (-> (Table Compiled)
           ExpandedProgram
           (List (Pair String (List Item)))
           (Pair Typed (Table Compiled)) ! compile))
    (define (check-libraries compiled expansion libraries)
      (let loop ((libraries libraries) (compiled compiled) (items (Nil)) (schemes empty-table))
        (match libraries
          ((Cons library rest)
           (let ((checked (checked-library compiled expansion schemes library)))
             (loop rest
                   (table-set compiled (::first library) checked)
                   (append items (::items checked))
                   (table-union schemes (::schemes checked)))))
          ((Nil) (Pair (Typed (::program expansion) items schemes) compiled)))))

    ;; A library as compiled before, if made from its current expansion, or
    ;; checked again.
    (: checked-library
       (-> (Table Compiled)
           ExpandedProgram
           (Table Scheme)
           (Pair String (List Item))
           Compiled
           ! compile))
    (define (checked-library compiled expansion schemes library)
      (let ((key (library-key expansion (::first library))))
        (match (table-ref compiled (::first library))
          ((Some before)
           (if (string=? (::key before) key)
               before
               (check-anew expansion schemes library key)))
          ((None) (check-anew expansion schemes library key)))))

    (: check-anew
       (-> ExpandedProgram (Table Scheme) (Pair String (List Item)) String Compiled ! compile))
    (define (check-anew expansion schemes library key)
      (let ((typed
             (check-library (::program expansion) schemes (::second library))))
        (Compiled key
                  (::items typed)
                  (own-schemes (::schemes typed) (::items typed))
                  (None))))

    ;; Each library's module: the one emitted before, or, for a library just
    ;; checked, a new one, which this build compiled. A library with no items,
    ;; such as a runtime interface's, which only declares externs, has no
    ;; module: its importers call the host's imports themselves, and a module
    ;; of its name would stand where the host's module of that name belongs.
    (: emit-libraries
       (-> ExpandedProgram
           (Table Compiled)
           Typed
           (List (Pair String (List Item)))
           (Pair (List Built) (Table Compiled))
           ! mut compile))
    (define (emit-libraries expansion compiled typed libraries)
      (let ((input (prepare-specialization typed)))
        (let loop ((libraries libraries) (compiled compiled) (built (Nil)))
          (match libraries
            ((Cons (Pair _ (Nil)) rest) (loop rest compiled built))
            ((Cons (Pair name _) rest)
             (let ((before (compiled-of compiled name)))
               (match (::emission before)
                 ((Some emission)
                  (loop rest
                        compiled
                        (Cons
                         (Built name emission #f (library-links expansion name))
                         built)))
                 ((None)
                  (let ((text (wat->string
                               (emit-module (prepare-library input name (::items before))))))
                    (loop rest
                          (table-set compiled name (Compiled-emission-set before (Some text)))
                          (Cons (Built name text #t (library-links expansion name)) built)))))))
            ((Nil) (Pair (reverse built) compiled))))))

    ;; ---- Records ----

    (: compiled-of (-> (Table Compiled) String Compiled))
    (define (compiled-of compiled name)
      (match (table-ref compiled name)
        ((Some found) found)
        ((None) (panic (string-append "internal error: nothing compiled for " name)))))

    ;; The schemes of the definitions among `items`.
    (: own-schemes (-> (Table Scheme) (List Item) (Table Scheme)))
    (define (own-schemes schemes items)
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
     (only (chibi filesystem) create-directory*)
     (only (chibi string) string-contains)
     (only (scheme file) delete-file)
     (snail stage0 testing)
     (only (snail shell compiler inputs) supply-artifact))
    (begin

      ;; A session rebuilds only what an edit changed: a body edit under a
      ;; signature recompiles its library alone, and an edit to what
      ;; importers see recompiles them too. The libraries use only
      ;; primitives, so the session runs quickly on Chibi. The sources are
      ;; written into `directory`; `library` holds the standard libraries,
      ;; (snail core primitive) among them.
      (define (test-session directory library)
        (let ((main (string-append directory "/main.sld")))
          (create-directory* (string-append directory "/sample"))
          (write-sample-a directory "(i64-add x x)" "")
          (write-file (string-append directory "/sample/b.sld") sample-b)
          (write-file main "(import (snail core forms) (snail core primitive) (sample b)) (four)")
          (let* ((first (build-session (make-session (list directory library))
                                       main
                                       no-generation
                                       no-inputs))
                 (unchanged (build-session (::second first) main no-generation no-inputs))
                 (body (begin
                         (write-sample-a directory "(i64-mul x 2)" "")
                         (build-session (::second unchanged) main no-generation no-inputs)))
                 (interface (begin
                              (write-sample-a directory "(i64-mul x 2)" "(define zero 0)")
                              (build-session (::second body) main no-generation no-inputs))))
            (expect (compiled-names first) (list "sample.a" "sample.b" "main"))
            (expect (compiled-names unchanged) (list))
            (expect (compiled-names body) (list "sample.a"))
            (expect (compiled-names interface) (list "sample.a" "sample.b" "main"))))
        (test-specialization-replay directory library)
        (test-instance-replay directory library)
        (test-artifact-replay directory library)
        (test-link-replay directory library)
        (test-extern-library directory library))

      (define (no-generation loading forms) (panic "unexpected generated library"))

      ;; A signed helper's edit still gives the library's instance methods
      ;; fresh names. An importer must select their new evidence and symbols.
      (define (test-instance-replay directory library)
        (let ((main (string-append directory "/instance.sld"))
              (file (string-append directory "/sample/policy.sld")))
          (define (source body)
            (string-append
             "(define-library (sample policy) (export Value value) "
             "(import (snail core forms) (snail core primitive)) (begin "
             "(typeclass (Value A) (: value (-> A I64))) "
             "(instance (Value I64) (define (value x) (helper x))) "
             "(: helper (-> I64 I64)) (define (helper x) " body ")))"))
          (write-file file (source "(i64-add x 1)"))
          (write-file main
                      "(import (snail core forms) (snail core primitive) (sample policy)) (value (ann 2 I64))")
          (let ((first (build-session (make-session (list directory library))
                                      main no-generation no-inputs)))
            (write-file file (source "(i64-add x 2)"))
            (expect
             (compiled-names (build-session (::second first) main no-generation no-inputs))
             (list "sample.policy" "main")))))

      ;; A cached library retains checked generic code, not old concrete
      ;; copies. A new caller can request another type without recompiling
      ;; that library, and gets exactly the same Wasm as a fresh session.
      (define (test-specialization-replay directory library)
        (let ((main (string-append directory "/generic.sld"))
              (source "(import (snail core forms) (snail core primitive) (sample generic)) "))
          (write-file (string-append directory "/sample/generic.sld")
                      (string-append
                       "(define-library (sample generic) (export identity) "
                       "(import (snail core forms) (snail core primitive)) "
                       "(begin (: identity (All (A) (-> A A))) (define (identity x) x)))"))
          (write-file main (string-append source "(identity (ann 1 I64))"))
          (let ((first (build-session (make-session (list directory library))
                                      main no-generation no-inputs)))
            (write-file main (string-append source "(identity (ann 2 I32))"))
            (let ((warm (build-session (::second first) main no-generation no-inputs))
                  (cold (build-session (make-session (list directory library))
                                       main no-generation no-inputs)))
              (expect (compiled-names warm) (list "main"))
              (expect (map ::text (::first warm)) (map ::text (::first cold)))))))

      ;; Unchanged bytes preserve emission. Missing inputs invalidate even
      ;; a replay, but removing the invocation must not demand its old input.
      (define (test-artifact-replay directory library)
        (let ((main (string-append directory "/artifact.sld"))
              (files (list (Pair "page.html" (list->vector (list (i32->u8 1)))))))
          (write-artifact-source directory "(artifact-bundle \"client\")")
          (write-file main "(import (snail core base) (sample assets)) (bundle)")
          (let* ((inputs (supply-artifact no-inputs "client" files))
                 (first
                  (build-session (make-session (list directory library)) main no-generation inputs))
                 (unchanged (build-session (::second first)
                                           main
                                           no-generation
                                           (supply-artifact no-inputs "client" files)))
                 (empty (build-session (::second first)
                                       main
                                       no-generation
                                       (supply-artifact no-inputs "client" (Nil)))))
            (expect (compiled-names unchanged) (Nil))
            (expect (compiled-names empty) (list "sample.assets" "main"))
            (expect (artifact-replay-error (::second empty) main) #t)
            (write-artifact-source directory "(ArtifactBundle (Nil))")
            (expect
             (compiled-names (build-session (::second empty) main no-generation no-inputs))
             (list "sample.assets" "main")))))

      ;; A linked file's digest is in its library's keys and in its
      ;; importers': a build with the file unchanged compiles nothing, and
      ;; editing it compiles the library, whose module names the new
      ;; digest, and its importer. Removing it fails even a replay, naming
      ;; the library and the path.
      (define (test-link-replay directory library)
        (let ((main (string-append directory "/linked.sld"))
              (data (string-append directory "/sample/data.bin")))
          (write-file data "first")
          (write-file (string-append directory "/sample/linked.sld")
                      (string-append
                       "(define-library (sample linked) (export data) (import (snail core forms) (snail core primitive)) "
                       "(begin (: data I32) (define data (link-handle \"./data.bin\"))))"))
          (write-file main
                      "(import (snail core forms) (snail core primitive) (sample linked)) data")
          (let* ((first (build-session (make-session (list directory library))
                                       main
                                       no-generation
                                       no-inputs))
                 (unchanged (build-session (::second first) main no-generation no-inputs))
                 (edited (begin
                           (write-file data "second")
                           (build-session (::second unchanged) main no-generation no-inputs))))
            (expect (compiled-names unchanged) (Nil))
            (expect (compiled-names edited) (list "sample.linked" "main"))
            (expect
             (map (lambda (built) (map ::digest (::links built))) (::first edited))
             (list (list "16367aacb67a4a017c8da8ab95682ccb390863780f7114dda0a0e0c55644c7c4") (Nil)))
            (expect (map ::path (::links (list-ref (::first edited) 0)))
                    (list (string-append directory "/sample/data.bin")))
            (delete-file data)
            (expect (link-missing? (::second edited) main) #t))))

      ;; A library of externs alone emits no module; its importer calls the
      ;; host's import.
      (define (test-extern-library directory library)
        (let ((main (string-append directory "/clock.sld")))
          (write-file (string-append directory "/sample/host.sld")
                      (string-append
                       "(define-library (sample host) (export now) (import (snail core forms) (snail core primitive)) "
                       "(begin (extern now \"sample.host\" \"now\" (-> I64))))"))
          (write-file main "(import (snail core forms) (snail core primitive) (sample host)) (now)")
          (let ((built (::first (build-session (make-session (list directory library))
                                               main
                                               no-generation
                                               no-inputs))))
            (expect (map ::name built) (list "main"))
            (expect (and (string-contains (::text (list-ref built 0))
                                          "(import \"sample.host\" \"now\"")
                         #t)
                    #t))))

      (define (link-missing? session main)
        (let ((message
               (compile-failure (lambda () (build-session session main no-generation no-inputs)))))
          (and message
               (string-contains message
                                "the library sample.linked links data.bin, but there is no file at")
               #t)))

      (define (artifact-replay-error session main)
        (match (compiling (lambda () (build-session session main no-generation no-inputs)))
          ((Err (Requested (ArtifactInput "client" _))) #t)
          (_ #f)))

      (define (write-artifact-source directory body)
        (write-file (string-append directory "/sample/assets.sld")
                    (string-append
                     "(define-library (sample assets) (export bundle) (import (snail core base) (snail shell artifact)) "
                     "(begin (: bundle (-> ArtifactBundle)) (define (bundle) " body ")))")))

      (define (write-sample-a directory body more)
        (write-file (string-append directory "/sample/a.sld")
                    (string-append
                     "(define-library (sample a) (export twice) (import (snail core forms) (snail core primitive)) (begin "
                     "(: twice (-> I64 I64)) (define (twice x) " body ") " more "))")))

      (define sample-b
        "(define-library (sample b) (export four) (import (snail core forms) (snail core primitive) (sample a)) (begin (: four (-> I64)) (define (four) (twice 2))))")

      (define (compiled-names build)
        (map ::name (filter ::compiled? (::first build))))))
   (else)))
