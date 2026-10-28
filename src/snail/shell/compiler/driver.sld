;; One compiler invocation, shared by the Chibi and Wasm entry programs. A
;; compile that fails prints its diagnostic and exits with status 1; one
;; that needs an input publishes its request beside the libraries its
;; producers generate, then exits the same way.
(define-library (snail shell compiler driver)
  (export
   compile-command-line)
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
         diagnostic->string)
   (snail shell compiler)
   (snail shell compiler inputs))
  (begin

    ;; ---- Compilation ----

    (: compile-command-line (-> Unit ! mut fs))
    (define (compile-command-line)
      (match (command-line)
        ((Cons _ (Cons mode (Cons source (Cons output (Cons generated directories)))))
         (match (compiling (lambda () (compile-mode mode source output generated directories)))
           ((Ok _) (unit))
           ((Err (Requested request))
            (publish-request generated request)
            (panic "compiler requires an input"))
           ((Err (Failed diagnostic)) (panic (diagnostic->string diagnostic)))))
        (_ (panic "usage: compile wat|modules|schema SOURCE OUTPUT GENERATED [DIRECTORY ...]"))))

    ;; Writes what `mode` asks for: the program's schemas, a module for each
    ;; library, or the whole program.
    (: compile-mode (-> String String String String (List String) Unit ! mut fs compile))
    (define (compile-mode mode source output generated directories)
      (let ((generate
             (lambda (loading forms) (generated-syntax generated directories loading forms))))
        (cond ((string=? mode "schema")
               (write-file output (source->schemas directories source generate no-inputs)))
              ((string=? mode "modules")
               (write-modules output
                              generated
                              (source->modules directories source generate no-inputs)))
              (else (write-program output
                                   generated
                                   (source->wat directories source generate no-inputs))))))

    (: write-program (-> String String WholeProgram Unit ! fs))
    (define (write-program output generated program)
      (write-file output (WholeProgram-text program))
      (write-links generated (WholeProgram-links program)))

    (: write-modules (-> String String (List Built) Unit ! fs))
    (define (write-modules directory generated modules)
      (for-each (lambda (module)
                  (write-file (string-append directory "/" (Built-name module) ".wat")
                              (Built-text module)))
                modules)
      (write-file (string-append directory "/modules")
                  (string-concatenate
                   (map (lambda (module) (string-append (Built-name module) "\n")) modules)))
      (write-links generated (concatenate (map Built-links modules))))

    ;; ---- Linked files ----

    ;; The files the program links, which the build places beside the
    ;; payload under their names, as `("NAME" "PATH")` lines in links.datum
    ;; in the compile's own directory, beside the libraries its producers
    ;; generate.
    (: write-links (-> String (List LinkedFile) Unit ! fs))
    (define (write-links directory links)
      (write-file (string-append directory "/links.datum")
                  (string-concatenate (map (lambda (link)
                                             (string-append "("
                                                            (datum->string
                                                             (DString (LinkedFile-name link)))
                                                            " "
                                                            (datum->string
                                                             (DString (LinkedFile-path link)))
                                                            ")\n"))
                                           links))))

    ))
