(import
 (snail core base))

(define (main)
  (→ Unit)
  (let ((memo (cache (ann (once (lambda () (unit))) (FnOnce → Unit))))) (call-once memo) (unit)))
