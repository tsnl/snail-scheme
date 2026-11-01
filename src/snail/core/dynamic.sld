;; Explicit boundaries for a dynamic computation. Core never installs a
;; dyn-tc handler implicitly; an interactive client can run each evaluation
;; with run-dynamic, while a script can choose its exit status from Result.
(define-library (snail core dynamic)
  (export
   try-dynamic
   cast-error->string
   run-dynamic)
  (import
   (snail core base)
   (snail core io))
  (begin

    ;; ---- Recovery ----

    (: try-dynamic
       (All (A e) (-> (-> A ! dyn-tc e) (Result A CastError) ! e)))
    (define (try-dynamic work)
      (handle dyn-tc
          ((conversion-failed (lambda (error) (Err error))))
        (Ok (work))))

    (: cast-error->string (-> CastError String))
    (define (cast-error->string error)
      (string-append (CastError-origin error) ": dyn-tc: "
                     (match (CastError-reason error)
                       ((TypeMismatch) "type mismatch")
                       ((UnsupportedInstance) "unsupported dynamic instance")
                       ((ArgumentMismatch) "arguments have different payload types"))
                     "; expected " (string-join (CastError-expected error) " or ")
                     ", observed type id " (i64->string (CastError-actual error))
                     (if (string=? (CastError-method error) "") ""
                         (string-append "; " (CastError-method error) " argument "
                                        (i64->string (+ 1 (CastError-argument error)))))))

    ;; The abort has already unwound and dropped its owners when reporting
    ;; starts. Returning the failure lets a script choose failure status,
    ;; or an interactive caller continue with its next evaluation.
    (: run-dynamic
       (All (A e) (-> (-> A ! dyn-tc e) (Result A CastError) ! console e)))
    (define (run-dynamic work)
      (match (try-dynamic work)
        ((Ok value) (Ok value))
        ((Err error) (write-line (cast-error->string error)) (Err error))))))
