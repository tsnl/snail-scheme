;; One compiler invocation, shared by stage 0's Chez entry and the
;; `snail-scheme` command line's `compile` action (bootstrap/cli.sld): the
;; interface the command line is bootstrapped through. A compile that
;; fails prints its diagnostic and exits with status 1.
(define-library (snail shell compiler driver)
  (export
   compile-arguments)
  (import
   (snail core base)
   (snail core io)
   (only (snail shell compiler read)
         compiling
         Failed
         Requested
         diagnostics->string)
   (snail shell compiler))
  (begin

    ;; ---- Compilation ----

    ;; `TARGET SOURCE OUTPUT DIRECTORY ...`, the one compile: the whole
    ;; program at SOURCE as WebAssembly text, written to OUTPUT. TARGET
    ;; names the target library, (snail target TARGET), which provides the
    ;; capabilities the program's main asks for, and the directories are where its
    ;; libraries are found. A program that reaches a generated library
    ;; needs a build, which runs producers ((snail shell project build)).

    (define (compile-arguments (mut Mut) (fs Fs) (arguments (List String))) (→ Unit)
      (match arguments
        ((Cons target (Cons source (Cons output directories)))
         (match (compiling (lambda ()
                             (source->wat mut fs directories
                                          source
                                          (lambda (loading forms) (needs-a-build))
                                          (Some (list "snail" "target" target))
                                          (Nil))))
           ((Ok program) (write-file fs output (● program text)))
           ((Err (Requested _)) (needs-a-build))
           ((Err (Failed diagnostics)) (panic (diagnostics->string diagnostics)))))
        (_ (panic "usage: compile TARGET SOURCE OUTPUT [DIRECTORY ...]"))))

    (define (needs-a-build) (→ A) (∀ (A))
      (panic "the program reaches a generated library: build it with snail-scheme build"))

    ))
