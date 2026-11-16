(import
 (snail core base))
(define (main) (→ I64)
  ((lambda ((a I64) b) (→ I64) (+ a b)) 1 2))
