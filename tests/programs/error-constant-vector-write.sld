(import
 (snail core base))

(define (main) (→ Unit) (! mut)
  (vector-set! (constant-vector I32 (1)) 0 2)
  (unit))
