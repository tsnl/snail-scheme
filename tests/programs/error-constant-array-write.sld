(import
 (snail core base))

(define (main (mut Mut)) (→ Unit)
  (array-set! mut (constant-array I32 (1)) 0 2)
  (unit))
