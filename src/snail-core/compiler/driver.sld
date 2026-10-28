;; One compiler invocation, shared by the Chibi and Wasm entry programs.
;; The host calls the request publisher only after a failed invocation exits.
(define-library (snail-core compiler driver)
  (export
   compile-command-line
   publish-compiler-request!)
  (import
   (snail-core base)
   (snail-core io)
   (only (snail-core compiler read) DString datum->string)
   (snail-core compiler)
   (snail-core compiler inputs))
  (begin

    ;; ---- Compilation ----

    (: compile-command-line (-> Unit ! mut fs))
    (define (compile-command-line)
      (take-input-request!)
      (match (command-line)
        ((Cons _
               (Cons mode
                     (Cons source (Cons output (Cons generated directories)))))
         (let ((generate (lambda (loading forms)
                           (generated-syntax generated
                                             directories
                                             loading
                                             forms))))
           (cond ((string=? mode "schema")
                  (write-file output
                              (source->schemas directories
                                               source
                                               generate
                                               no-inputs)))
                 ((string=? mode "modules")
                  (write-modules output
                                 generated
                                 (source->modules directories
                                                  source
                                                  generate
                                                  no-inputs)))
                 (else (write-program output
                                      generated
                                      (source->wat directories
                                                   source
                                                   generate
                                                   no-inputs))))))
        (_
         (panic
          "usage: compile wat|modules|schema SOURCE OUTPUT GENERATED [DIRECTORY ...]"))))

    (: write-program (-> String String WholeProgram Unit ! fs))
    (define (write-program output generated program)
      (write-file output (WholeProgram-text program))
      (write-links generated (WholeProgram-links program)))

    (: write-modules (-> String String (List Built) Unit ! fs))
    (define (write-modules directory generated modules)
      (for-each (lambda (module)
                  (write-file
                   (string-append directory "/" (Built-name module) ".wat")
                   (Built-text module)))
                modules)
      (write-file (string-append directory "/modules")
                  (string-concatenate (map (lambda (module)
                                             (string-append (Built-name module)
                                                            "\n"))
                                           modules)))
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
                                                             (DString
                                                              (LinkedFile-name
                                                               link)))
                                                            " "
                                                            (datum->string
                                                             (DString
                                                              (LinkedFile-path
                                                               link)))
                                                            ")\n"))
                                           links))))

    ;; ---- Request publication ----

    (: publish-compiler-request! (-> Unit ! mut fs))
    (define (publish-compiler-request!)
      (match (command-line)
        ((Cons _ (Cons _ (Cons _ (Cons _ (Cons directory _)))))
         (publish-input-request! directory))
        (_ (unit))))

    ))
