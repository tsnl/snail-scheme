(import
 (snail core base)
 (snail core io))

(define (pure (x I64)) (→ I64)
  (write-line "side effect")
  x)
