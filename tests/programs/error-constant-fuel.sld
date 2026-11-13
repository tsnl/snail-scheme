(import
 (snail core base))

(define (forever (value I64)) (→ I64)
  (forever (+ value 1)))

(define unending (→ I64) (forever 0))

(define (main) (→ Unit)
  unending
  (unit))
