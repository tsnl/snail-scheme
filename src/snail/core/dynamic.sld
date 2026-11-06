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

    (: try-dynamic
       (All (A e) (-> (-> A ! dyn-cast e) (Result A CastError) ! e)))
    (define (try-dynamic work)
      (handle dyn-cast
          ((conversion-failed (lambda (error) (Err error))))
        (Ok (work))))

    (: cast-error->string (-> CastError String))
    (define (cast-error->string error)
      (string-append (::origin error) ": dyn-cast: "
                     (match (::reason error)
                       ((TypeMismatch) "type mismatch")
                       ((UnsupportedInstance) "unsupported dynamic instance")
                       ((ArgumentMismatch) "arguments have different payload types"))
                     "; expected " (string-join (::expected error) " or ")
                     ", observed type id " (i64->string (::actual error))
                     (if (string=? (::method error) "") ""
                         (string-append "; " (::method error) " argument "
                                        (i64->string (+ 1 (::argument error)))))))

    ;; The abort has already unwound and dropped its owners when reporting
    ;; starts. Returning the failure lets a script choose failure status,
    ;; or an interactive caller continue with its next evaluation.
    (: run-dynamic
       (All (A e) (-> (-> A ! dyn-cast e) (Result A CastError) ! console e)))
    (define (run-dynamic work)
      (match (try-dynamic work)
        ((Ok value) (Ok value))
        ((Err error) (write-line (cast-error->string error)) (Err error))))))
