;; One compiler invocation, shared by stage 0's Chez entry and the
;; `snail-scheme` command line's `compile` action (bootstrap/cli.sld). A
;; compile that fails prints its diagnostic and exits with status 1; one
;; that needs an input publishes its request beside the libraries its
;; producers generate, then exits the same way.
(define-library (snail shell compiler driver)
  (export
   compile-arguments)
  (import
   (snail core base)
   (snail core io)
   (only (snail shell compiler read)
         DString
         datum->string
         compile
         compiling
         Failed
         Requested
         diagnostics->string)
   (snail shell compiler)
   (snail shell compiler inputs))
  (begin

    ;; ---- Compilation ----

    ;; `MODE SOURCE OUTPUT GENERATED DIRECTORY ...`, the one compile.

    (define (compile-arguments (arguments (List String))) (→ Unit) (! mut fs)
      (match arguments
        ((Cons mode (Cons source (Cons output (Cons generated directories))))
         (match (compiling (lambda () (compile-mode mode source output generated directories)))
           ((Ok _) (unit))
           ((Err (Requested request))
            (publish-request generated request)
            (panic "compiler requires an input"))
           ((Err (Failed diagnostics)) (panic (diagnostics->string diagnostics)))))
        (_ (panic "usage: compile wat|modules SOURCE OUTPUT GENERATED [DIRECTORY ...]"))))

    ;; Writes what `mode` asks for: a module for each library, or the whole
    ;; program.

    (define (compile-mode (mode String)
                          (source String)
                          (output String)
                          (generated String)
                          (directories (List String)))
      (→ Unit)
      (! mut fs compile)
      (let ((generate
             (lambda (loading forms) (generated-syntax generated directories loading forms))))
        (if (string=? mode "modules")
            (write-modules output
                           generated
                           (source->modules directories source generate (no-inputs)))
            (write-program output
                           generated
                           (source->wat directories source generate (no-inputs))))))

    (define (write-program (output String) (generated String) (program WholeProgram))
      (→ Unit)
      (! fs)
      (write-file output (● program text))
      (write-links generated (● program links)))

    (define (write-modules (directory String) (generated String) (modules (List Built)))
      (→ Unit)
      (! fs)
      (for-each (lambda (module)
                  (write-file (string-append directory "/" (● module name) ".wat")
                              (● module text)))
                modules)
      (write-file (string-append directory "/modules")
                  (string-concatenate
                   (map (lambda (module) (string-append (● module name) "\n")) modules)))
      (write-links generated (concatenate (map (lambda (record) (● record links)) modules))))

    ;; ---- Linked files ----

    ;; The files the program links, which the build places beside the
    ;; payload under their digests, as `("DIGEST" "PATH")` lines in
    ;; links.datum in the compile's own directory, beside the libraries its
    ;; producers generate; libraries that link the same bytes share a line.

    (define (write-links (directory String) (links (List LinkedFile))) (→ Unit) (! fs)
      (write-file (string-append directory "/links.datum")
                  (string-concatenate
                   (map (lambda (link)
                          (string-append "("
                                         (datum->string (DString (● link digest)))
                                         " "
                                         (datum->string (DString (● link path)))
                                         ")\n"))
                        (delete-duplicates (lambda (a b)
                                             (string=? (● a digest) (● b digest)))
                                           links)))))

    ))
