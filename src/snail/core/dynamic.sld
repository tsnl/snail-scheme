;; Explicit boundaries for a dynamic computation. Core never installs a
;; dyn-cast handler implicitly; an interactive client can run each evaluation
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

    (define (try-dynamic (work (Fn → A ! dyn-cast e))) (→ (Result A CastError)) (! e) (∀ (A e))
      (handle dyn-cast
          ((conversion-failed (lambda (error) (Err error))))
        (Ok (work))))

    (define (cast-error->string (error CastError)) (→ String)
      (string-append (● error origin) ": dyn-cast: "
                     (match (● error reason)
                       ((TypeMismatch) "type mismatch")
                       ((UnsupportedInstance) "unsupported dynamic instance")
                       ((ArgumentMismatch) "arguments have different payload types"))
                     "; expected " (string-join (● error expected) " or ")
                     ", observed type id " (i64->string (● error actual))
                     (if (string=? (● error method) "") ""
                         (string-append "; " (● error method) " argument "
                                        (i64->string (+ 1 (● error argument)))))))

    ;; The abort has already unwound and dropped its owners when reporting
    ;; starts. Returning the failure lets a script choose failure status,
    ;; or an interactive caller continue with its next evaluation.

    (define (run-dynamic (work (Fn → A ! dyn-cast e)))
      (→ (Result A CastError))
      (! output-port e)
      (∀ (A e))
      (match (try-dynamic work)
        ((Ok value) (Ok value))
        ((Err error) (write-line (cast-error->string error)) (Err error))))))
