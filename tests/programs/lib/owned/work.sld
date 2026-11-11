(define-library (owned work)
  (export message run)
  (import
   (snail core base)
   (snail core io))
  (begin
    (: message (impl (Fn String -> (dyn (FnOnce -> Unit ! console)))))
    (define (message text) (once (lambda () (write-line text))))

    (: run (impl (Fn (dyn (FnOnce -> Unit ! console)) -> Unit ! console)))
    (define (run work) (call-once work))))
