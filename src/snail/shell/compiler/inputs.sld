;; The requests a compile makes for what it was not supplied, a
;; producer's output, and the printed producers they name. A request is
;; a compile stopped with `Requested` (snail shell compiler read), which the
;; build that runs the compile takes.
(define-library (snail shell compiler inputs)
  (export
   generated-syntax
   generating-stack
   read-source-file)
  (import
   (snail core base)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler core) fnv-1a))
  (begin

    ;; ---- Producer keys ----

    ;; A producer as a build tells it apart: the library directories its
    ;; imports resolve in, then its program, since two builds with different
    ;; directories may resolve the same recipe's imports to different
    ;; libraries. Its key, a hash of that text, names its files in scratch.

    (define (producer-text (directories (List String)) (forms (List Syntax))) (→ String)
      (string-append (string-join (map quoted directories) " ") "\n" (program-text forms)))

    (define (producer-key (text String)) (→ String)
      (i64->string (fnv-1a text)))

    (define (program-text (forms (List Syntax))) (→ String)
      (string-join (map syntax->string forms) "\n"))

    ;; ---- Requests ----

    ;; A pass that needs an input it was not supplied, such as the expander
    ;; at a generated library, asks for it by stopping the compile. Nothing
    ;; after the call runs: the entry point's boundary takes the request
    ;; and hands it to its caller.

    (define (request-input (request CompilerRequest)) (→ A) (∀ (A))
      (stop (Requested request)))

    (define (quoted (text String)) (→ String)
      (datum->string (DString text)))

    ;; ---- Producer programs ----

    ;; A producer whose output the compile's scratch `directory` does not
    ;; hold, printed there and requested, or its output once the host has
    ;; written it there. The producer is compiled as a program of its own
    ;; while the library it generates is loading, so its printed source
    ;; begins with the libraries loading then, innermost first:
    ;; `(generating "sample.knot" ...)`. Its expansion starts with them
    ;; loading, which makes a producer that imports, along any chain, the
    ;; library it generates an import cycle. The key leaves that line out,
    ;; since what the producer writes does not depend on the chain that
    ;; reached it.

    (define (generated-syntax (fs Fs) (directory String)
                              (directories (List String))
                              (loading (List String))
                              (forms (List Syntax)))
      (→ Bytes)
      (let* ((key (producer-key (producer-text directories forms)))
             (output (string-append directory "/" key ".syntax")))
        (if (file-exists? fs output)
            (read-bytes fs output)
            (begin (print-producer fs (string-append directory "/" key ".sld") loading forms)
                   (request-input (GenerateInput key))))))

    ;; Prints the producer `forms` as the program at `path`, beginning with
    ;; the libraries `loading` when it was reached.

    (define (print-producer (fs Fs) (path String) (loading (List String)) (forms (List Syntax)))
      (→ Unit)
      (write-file fs path (string-append (generating-line loading) "\n" (program-text forms))))

    (define (generating-line (loading (List String))) (→ String)
      (string-append "(generating"
                     (string-concatenate
                      (map (lambda (key) (string-append " " (quoted key))) loading))
                     ")"))

    ;; ---- Source files ----

    ;; The forms of the source file at `path`. One that is not there, as a
    ;; build's entry an editor has just deleted, fails the compile with a
    ;; diagnostic about the file as a whole, so a resident caller reports
    ;; it and builds again once the file is back.

    (define (read-source-file (fs Fs) (path String)) (→ (List Syntax))
      (if (file-exists? fs path)
          (read-text (read-file fs path) path)
          (compile-error (new Loc (file path) (line 0) (column 0)) "no such file or directory")))

    ;; The libraries a program's first form says were loading when it was
    ;; printed, and the forms after it. A program that does not begin with
    ;; `generating` starts with nothing loading.

    (define (generating-stack (forms (List Syntax)))
      (→ (Pair (List String) (List Syntax)))
      (match forms
        ((Cons (Form (Cons (Ident "generating" _ _) keys) _) rest)
         (new Pair (first (map loading-key keys)) (second rest)))
        (_ (new Pair (first (Nil)) (second forms)))))

    (define (loading-key (key Syntax)) (→ String)
      (match key
        ((Atom (DString text) _) text)
        (_ (compile-error (syntax-loc key) "expected a library key string"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-inputs)
    (import
     (only (chezscheme) list)
     (snail stage0 testing))
    (begin
      (define test-inputs
        (lambda ()
          (test-generating-stack)
          (test-producer-key)
          (test-missing-source)))

      ;; The printed stack reads back as the same keys, ahead of the
      ;; producer's own forms; a program without one has nothing loading.
      (define test-generating-stack
        (lambda () (let ((printed (generating-stack
                                   (read-text
                                    (string-append (generating-line (list "sample.knot" "odd\"key"))
                                                   "\n(unit)")
                                    "producer.sld")))
                         (plain (generating-stack (read-text "(unit)" "program.sld"))))
                     (expect (● printed first) (list "sample.knot" "odd\"key"))
                     (expect (length (● printed second)) 1)
                     (expect (● plain first) (list))
                     (expect (length (● plain second)) 1))))

      ;; A source that is not there is a diagnostic naming the file.
      (define test-missing-source
        (lambda ()
          (expect
           (compile-failure
            (lambda () (read-source-file (host-fs (unsafe-host)) "build/tests/missing/main.sld")))
           "build/tests/missing/main.sld: no such file or directory")))

      ;; A printed producer reads back as the text its key hashes, and the
      ;; same program under other directories is another producer.
      (define test-producer-key
        (lambda () (let* ((forms
                           (read-text
                            "(import (snail core base) (srfi 1)) (write \"a\\\"b\\nc\" #u8(1 2) 1.50 #\\x)"
                            "producer.sld"))
                          (printed
                           (string-append (generating-line (list "sample.knot"))
                                          "\n"
                                          (program-text forms)))
                          (text (producer-text (list "/project/src" "/root/src") forms)))
                     (expect (producer-text (list "/project/src" "/root/src")
                                            (● (generating-stack (read-text printed "printed.sld"))
                                               second))
                             text)
                     (expect (string=? (producer-key text)
                                       (producer-key (producer-text (list "/root/src") forms)))
                             #f))))))
   (else)))
