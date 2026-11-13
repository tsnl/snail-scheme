(define-library (owned work)
  (export message run)
  (import
   (snail core base)
   (snail core io))
  (begin
    (define (message (text String))
      (→ (FnOnce → Unit ! output-port))
      (once (lambda () (write-line text))))

    (define (run (work (FnOnce → Unit ! output-port))) (→ Unit) (! output-port) (call-once work))))
