;; A compiler that keeps running between builds, as a development server's
;; does, and compiles each library to its own module. A session is a value:
;; each build returns the session the next one starts from. A build expands
;; only the libraries whose declarations, or whose imports' interfaces,
;; changed since the build before, and replays the others. It checks,
;; specializes and emits only the libraries whose expansion changed, and
;; keeps every other library's checked items and module text from the build
;; that made them, all in memory.
(define-library (snail-core compiler session)
  (export
   Session
   make-session
   no-artifacts
   Built
   Built-name
   Built-text
   Built-compiled?
   build-session)
  (import
   (snail-core base)
   (snail-core table)
   (snail-core io)
   (snail-core compiler read)
   (snail-core compiler core)
   (snail-core compiler expand)
   (snail-core compiler check)
   (snail-core compiler mono)
   (snail-core compiler handlers)
   (snail-core compiler wasm))
  (begin

    ;; ---- Sessions ----

    ;; What one library's expansion became: its checked items, the schemes
    ;; of its own definitions, and its emission, None until emitted. `key`
    ;; is the build key of the expansion it was made from.
    (struct Compiled
      ((key String)
       (items (List Item))
       (schemes (Table Scheme))
       (emission (Option Emission))))

    ;; Keep the checked monomorphic bodies beside cached text. Handler
    ;; safety depends on imported helpers' bodies, even when their signatures
    ;; stay unchanged; reusing text must not reuse that proof unchecked.
    (struct Emission
      ((text String)
       (items (List Item))))

    ;; Where libraries are found, the last expansion and each library as
    ;; last compiled. Generators and artifact inputs belong to one invocation.
    (struct Session
      ((directories (List String))
       (expansion ExpandedProgram)
       (compiled (Table Compiled))))

    ;; One library's module after a build, and whether this build compiled
    ;; it.
    (struct Built
      ((name String)
       (text String)
       (compiled? Bool)))

    (: make-session (-> (List String) Session))
    (define (make-session directories)
      (Session directories empty-expansion empty-table))

    ;; ---- Builds ----

    ;; The modules of the program at `source`, in program order, and the
    ;; session after the build. Artifact snapshots belong to this invocation,
    ;; never to the retained session.
    (: build-session (-> Session String (-> (List Syntax) Bytes ! mut fs) ArtifactInputs (Pair (List Built) Session) ! mut fs))
    (define (build-session session source generate artifacts)
      (let* ((expansion (expand-program (Session-directories session) generate artifacts source (Session-expansion session)))
             (program (ExpandedProgram-program expansion)) (libraries (library-items program (program-items program)))
             (checked (check-libraries (Session-compiled session) expansion libraries))
             (built (emit-libraries (Pair-second checked) (Pair-first checked) libraries)))
        (Pair (Pair-first built) (Session (Session-directories session) expansion (Pair-second built)))))

    ;; Checks each library whose expansion changed, after the schemes of the
    ;; libraries before it, and returns the whole program checked, with each
    ;; library as compiled now.
    (: check-libraries (-> (Table Compiled) ExpandedProgram (List (Pair String (List Item))) (Pair Typed (Table Compiled))))
    (define (check-libraries compiled expansion libraries)
      (let loop ((libraries libraries) (compiled compiled) (items (Nil)) (schemes empty-table))
        (match libraries
          ((Cons library rest)
           (let ((checked (checked-library compiled expansion schemes library)))
             (loop rest (table-set compiled (Pair-first library) checked) (append items (Compiled-items checked))
                   (table-union schemes (Compiled-schemes checked)))))
          ((Nil) (Pair (Typed (ExpandedProgram-program expansion) items schemes) compiled)))))

    ;; A library as compiled before, if made from its current expansion, or
    ;; checked again.
    (: checked-library (-> (Table Compiled) ExpandedProgram (Table Scheme) (Pair String (List Item)) Compiled))
    (define (checked-library compiled expansion schemes library)
      (let ((key (library-key expansion (Pair-first library))))
        (match (table-ref compiled (Pair-first library))
          ((Some before) (if (string=? (Compiled-key before) key) before (check-anew expansion schemes library key)))
          ((None) (check-anew expansion schemes library key)))))

    (: check-anew (-> ExpandedProgram (Table Scheme) (Pair String (List Item)) String Compiled))
    (define (check-anew expansion schemes library key)
      (let ((typed (check-library (ExpandedProgram-program expansion) schemes (Pair-second library))))
        (Compiled key (Typed-items typed) (own-schemes (Typed-schemes typed) (Typed-items typed)) (None))))

    ;; Each library's module: the one emitted before, or, for a library just
    ;; checked, a new one, which this build compiled.
    (: emit-libraries (-> (Table Compiled) Typed (List (Pair String (List Item))) (Pair (List Built) (Table Compiled)) ! mut))
    (define (emit-libraries compiled typed libraries)
      (let ((input (prepare-specialization typed)))
        (let loop ((libraries libraries) (compiled compiled) (built (Nil)))
          (match libraries
            ((Cons (Pair name _) rest)
             (let ((before (compiled-of compiled name)))
               (match (Compiled-emission before)
                 ((Some emission)
                  (check-handlers (Typed-program typed)
                                  (table-union (Specialization-definitions input) (item-definitions (Emission-items emission)))
                                  (Emission-items emission))
                  (loop rest compiled (Cons (Built name (Emission-text emission) #f) built)))
                 ((None)
                  (let* ((mono (monomorphize-library input name (Compiled-items before)))
                         (text (wat->string (emit-library mono name)))
                         (emission (Emission text (Mono-items mono))))
                    (loop rest (table-set compiled name (Compiled-emission-set before (Some emission)))
                          (Cons (Built name text #t) built)))))))
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
     (only (scheme base) guard error-object? error-object-message)
     (snail-core testing)
     (only (snail-core compiler inputs) take-input-request! ArtifactInput))
    (begin

      ;; A session rebuilds only what an edit changed: a body edit under a
      ;; signature recompiles its library alone, and an edit to what
      ;; importers see recompiles them too. The libraries use only
      ;; primitives, so the session runs quickly on Chibi. The sources are
      ;; written into `directory`.
      (define (test-session directory library)
        (let ((main (string-append directory "/main.sld")))
          (create-directory* (string-append directory "/sample"))
          (write-sample-a directory "(i64-add x x)" "")
          (write-file (string-append directory "/sample/b.sld") sample-b)
          (write-file main "(import (snail-core core) (snail-core primitive) (sample b)) (four)")
          (let* ((first (build-session (make-session (list directory)) main no-generation no-artifacts))
                 (unchanged (build-session (Pair-second first) main no-generation no-artifacts))
                 (body (begin (write-sample-a directory "(i64-mul x 2)" "") (build-session (Pair-second unchanged) main no-generation no-artifacts)))
                 (interface (begin (write-sample-a directory "(i64-mul x 2)" "(define zero 0)") (build-session (Pair-second body) main no-generation no-artifacts))))
            (expect (compiled-names first) (list "sample.a" "sample.b" "main"))
            (expect (compiled-names unchanged) (list))
            (expect (compiled-names body) (list "sample.a"))
            (expect (compiled-names interface) (list "sample.a" "sample.b" "main"))))
        (test-handler-revalidation directory)
        (test-artifact-replay directory library))

      (define (no-generation forms) (panic "unexpected generated library"))

      ;; Unchanged bytes preserve emission. Missing inputs invalidate even
      ;; a replay, but removing the invocation must not demand its old input.
      (define (test-artifact-replay directory library)
        (let ((main (string-append directory "/artifact.sld"))
              (files (list (Pair "page.html" (list->vector (list (i32->u8 1)))))))
          (write-artifact-source directory "(artifact-bundle \"client\")")
          (write-file main "(import (snail-core base) (sample assets)) (bundle)")
          (let* ((inputs (table-set no-artifacts "client" files))
                 (first (build-session (make-session (list directory library)) main no-generation inputs))
                 (unchanged (build-session (Pair-second first) main no-generation (table-set no-artifacts "client" files)))
                 (empty (build-session (Pair-second first) main no-generation (table-set no-artifacts "client" (Nil)))))
            (expect (compiled-names unchanged) (Nil))
            (expect (compiled-names empty) (list "sample.assets" "main"))
            (expect (artifact-replay-error (Pair-second empty) main) #t)
            (write-artifact-source directory "(ArtifactBundle (Nil))")
            (expect (compiled-names (build-session (Pair-second empty) main no-generation no-artifacts)) (list "sample.assets" "main")))))

      (define (artifact-replay-error session main)
        (guard (failure
                ((error-object? failure)
                 (match (take-input-request!)
                   ((Some (ArtifactInput "client" _)) #t)
                   (_ #f))))
          (build-session session main no-generation no-artifacts)
          #f))

      (define (write-artifact-source directory body)
        (write-file (string-append directory "/sample/assets.sld")
                    (string-append "(define-library (sample assets) (export bundle) (import (snail-core base) (snail-core artifact)) "
                                   "(begin (: bundle (-> ArtifactBundle)) (define (bundle) " body ")))")))

      (define (test-handler-revalidation directory)
        (let ((main (string-append directory "/main.sld")))
          (write-handler-helper directory "(ann 1 I64)")
          (write-file (string-append directory "/sample/b.sld")
                      "(define-library (sample b) (export run) (import (snail-core core) (snail-core primitive) (sample a)) (begin (effect Counter ((tick (-> I64)))) (: run (-> I64 ! mut)) (define (run) (handle Counter ((tick (lambda () (helper)))) (tick)))))")
          (write-file main "(import (snail-core core) (snail-core primitive) (sample b)) (run)")
          (let* ((first (build-session (make-session (list directory)) main no-generation no-artifacts))
                 (session (Pair-second first)))
            (expect (compiled-names (build-session session main no-generation no-artifacts)) (list))
            (write-handler-helper directory "(ref-get cell)")
            (expect (guard (failure
                            ((error-object? failure)
                             (if (string-contains (error-object-message failure) "a handler and its captures must satisfy") #t #f)))
                      (build-session session main no-generation no-artifacts)
                      #f)
                    #t))))

      (define (write-handler-helper directory body)
        (write-file (string-append directory "/sample/a.sld")
                    (string-append "(define-library (sample a) (export helper) (import (snail-core core) (snail-core primitive)) (begin "
                                   "(: cell (Ref I64)) (define cell (ref (ann 9 I64))) "
                                   "(: helper (-> I64 ! mut)) (define (helper) " body ")))")))

      (define (write-sample-a directory body more)
        (write-file (string-append directory "/sample/a.sld")
                    (string-append "(define-library (sample a) (export twice) (import (snail-core core) (snail-core primitive)) (begin "
                                   "(: twice (-> I64 I64)) (define (twice x) " body ") " more "))")))

      (define sample-b
        "(define-library (sample b) (export four) (import (snail-core core) (snail-core primitive) (sample a)) (begin (: four (-> I64)) (define (four) (twice 2))))")

      (define (compiled-names build)
        (map Built-name (filter Built-compiled? (Pair-first build))))))
   (else)))
