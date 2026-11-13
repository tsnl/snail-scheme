(import
 (snail core base))

(define oversized (→ (Vector I64)) (make-vector 1000001 0))

(define (main) (→ Unit)
  (vector-length oversized)
  (unit))
