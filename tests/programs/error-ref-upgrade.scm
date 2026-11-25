(import
 (snail core base))

(define (write-it (x (MutRef I64))) (→ Unit)
  (ref-set! x 0))

(define (bad (x (Ref I64))) (→ Unit)
  (write-it (ref! x)))

(define (main) (→ Unit) (unit))
