(import
 (snail core base))

(define (main) (→ Unit)
  (array-set! (constant-array I32 (1)) 0 2)
  (unit))
