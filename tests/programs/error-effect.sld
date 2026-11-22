(import
 (snail core base)
 (snail core io))

(define (pure (out OutputPort) (x I64)) (→ I64)
  (write-line out "side effect")
  x)
