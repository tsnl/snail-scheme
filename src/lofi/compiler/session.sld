;; A compiler that keeps running between builds, as a development server's
;; does, and compiles each library to its own module. A session is a value:
;; each build returns the session the next one starts from. A build expands
;; only the libraries whose declarations, or whose imports' interfaces,
;; changed since the build before, and replays the others. It checks,
;; specializes and emits only the libraries whose expansion changed, and
;; keeps every other library's checked items and module text from the build
;; that made them, all in memory.
(define-library (lofi compiler session)
  (export
   Session
   make-session
   Built
   Built-name
   Built-text
   Built-compiled?
   build-session)
  (import
   (lofi base)
   (lofi table)
   (lofi io)
   (lofi compiler read)
   (lofi compiler core)
   (lofi compiler expand)
   (lofi compiler check)
   (lofi compiler mono)
   (lofi compiler wasm))
  (begin

    ;; ---- Sessions ----

    ;; What one library's expansion became: its checked items, the schemes
    ;; of its own definitions, and its module's text, None until it is
    ;; emitted. `key` is the build key of the expansion it was made from.
    (struct Compiled
      ((key String)
       (items (List Item))
       (schemes (Table Scheme))
       (text (Option String))))

    ;; Where libraries are found, how generated ones are made, the last
    ;; build's expansion, and each library as last compiled.
    (struct Session
      ((directories (List String))
       (generate (-> (List Syntax) Bytes ! mut fs))
       (expansion ExpandedProgram)
       (compiled (Table Compiled))))

    ;; One library's module after a build, and whether this build compiled
    ;; it.
    (struct Built
      ((name String)
       (text String)
       (compiled? Bool)))

    (: make-session (-> (List String) (-> (List Syntax) Bytes ! mut fs) Session))
    (define (make-session directories generate)
      (Session directories generate empty-expansion empty-table))

    ;; ---- Builds ----

    ;; The modules of the program at `source`, in program order, and the
    ;; session after the build.
    (: build-session (-> Session String (Pair (List Built) Session) ! mut fs))
    (define (build-session session source)
      (let* ((expansion (expand-program (Session-directories session) (Session-generate session) source (Session-expansion session)))
             (program (ExpandedProgram-program expansion)) (libraries (library-items program (program-items program)))
             (checked (check-libraries (Session-compiled session) expansion libraries))
             (built (emit-libraries (Pair-second checked) (Pair-first checked) libraries)))
        (Pair (Pair-first built) (Session (Session-directories session) (Session-generate session) expansion (Pair-second built)))))

    ;; Checks each library whose expansion changed, after the schemes of the
    ;; libraries before it, and returns the whole program checked, with each
    ;; library as compiled now.
    (: check-libraries (-> (Table Compiled) ExpandedProgram (List (Pair String (List Item))) (Pair Typed (Table Compiled)) ! mut))
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
    (: checked-library (-> (Table Compiled) ExpandedProgram (Table Scheme) (Pair String (List Item)) Compiled ! mut))
    (define (checked-library compiled expansion schemes library)
      (let ((key (library-key expansion (Pair-first library))))
        (match (table-ref compiled (Pair-first library))
          ((Some before) (if (string=? (Compiled-key before) key) before (check-anew expansion schemes library key)))
          ((None) (check-anew expansion schemes library key)))))

    (: check-anew (-> ExpandedProgram (Table Scheme) (Pair String (List Item)) String Compiled ! mut))
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
               (match (Compiled-text before)
                 ((Some text) (loop rest compiled (Cons (Built name text #f) built)))
                 ((None)
                  (let ((text (wat->string (emit-library (monomorphize-library input name (Compiled-items before)) name))))
                    (loop rest (table-set compiled name (Compiled-text-set before (Some text))) (Cons (Built name text #t) built)))))))
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
     (lofi testing))
    (begin

      ;; A session rebuilds only what an edit changed: a body edit under a
      ;; signature recompiles its library alone, and an edit to what
      ;; importers see recompiles them too. The libraries use only
      ;; primitives, so the session runs quickly on Chibi. The sources are
      ;; written into `directory`.
      (define (test-session directory)
        (let ((main (string-append directory "/main.sld")))
          (create-directory* (string-append directory "/sample"))
          (write-sample-a directory "(i64-add x x)" "")
          (write-file (string-append directory "/sample/b.sld") sample-b)
          (write-file main "(import (lofi core) (lofi primitive) (sample b)) (four)")
          (let* ((first (build-session (make-session (list directory) (lambda (forms) (panic "no generated libraries"))) main))
                 (unchanged (build-session (Pair-second first) main))
                 (body (begin (write-sample-a directory "(i64-mul x 2)" "") (build-session (Pair-second unchanged) main)))
                 (interface (begin (write-sample-a directory "(i64-mul x 2)" "(define zero 0)") (build-session (Pair-second body) main))))
            (expect (compiled-names first) (list "sample.a" "sample.b" "main"))
            (expect (compiled-names unchanged) (list))
            (expect (compiled-names body) (list "sample.a"))
            (expect (compiled-names interface) (list "sample.a" "sample.b" "main")))))

      (define (write-sample-a directory body more)
        (write-file (string-append directory "/sample/a.sld")
                    (string-append "(define-library (sample a) (export twice) (import (lofi core) (lofi primitive)) (begin "
                                   "(: twice (-> I64 I64)) (define (twice x) " body ") " more "))")))

      (define sample-b
        "(define-library (sample b) (export four) (import (lofi core) (lofi primitive) (sample a)) (begin (: four (-> I64)) (define (four) (twice 2))))")

      (define (compiled-names build)
        (map Built-name (filter Built-compiled? (Pair-first build))))))
   (else)))
