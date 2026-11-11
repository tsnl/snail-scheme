(define-library (owned work)
  (export message run)
  (import
   (snail core base)
   (snail core io))
  (begin
    (define (message (text String))
      (→ (dyn (FnOnce → Unit ! console)))
      (once (lambda () (write-line text))))

    (define (run (work (dyn (FnOnce → Unit ! console)))) (→ Unit) (! console) (call-once work))))
