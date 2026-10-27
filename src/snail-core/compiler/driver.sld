;; One compiler invocation, shared by the Chibi and Wasm entry programs.
;; The host calls the request publisher only after a failed invocation exits.
(define-library (snail-core compiler driver)
  (export
   compile-command-line
   publish-compiler-request!)
  (import
   (snail-core base)
   (snail-core io)
   (snail-core compiler)
   (snail-core compiler inputs))
  (begin

    ;; ---- Compilation ----

    (: compile-command-line (-> Unit ! mut fs))
    (define (compile-command-line)
      (take-input-request!)
      (match (command-line)
        ((Cons _ (Cons mode (Cons source (Cons output (Cons generated directories)))))
         (let ((generate (lambda (loading forms) (generated-syntax generated directories loading forms))))
           (cond ((string=? mode "schema") (write-file output (source->schemas directories source generate no-inputs)))
                 ((string=? mode "modules") (write-modules output (source->modules directories source generate no-inputs)))
                 (else (write-file output (source->wat directories source generate no-inputs))))))
        (_ (panic "usage: compile wat|modules|schema SOURCE OUTPUT GENERATED [DIRECTORY ...]"))))

    (: write-modules (-> String (List (Pair String String)) Unit ! fs))
    (define (write-modules directory modules)
      (for-each (lambda (module) (write-file (string-append directory "/" (Pair-first module) ".wat") (Pair-second module))) modules)
      (write-file (string-append directory "/modules")
                  (string-concatenate (map (lambda (module) (string-append (Pair-first module) "\n")) modules))))

    ;; ---- Request publication ----

    (: publish-compiler-request! (-> Unit ! mut fs))
    (define (publish-compiler-request!)
      (match (command-line)
        ((Cons _ (Cons _ (Cons _ (Cons _ (Cons directory _)))))
         (publish-input-request! directory))
        (_ (unit))))

    ))
