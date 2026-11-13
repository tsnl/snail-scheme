(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (declare (op (left A) (right B)) (→ Output) (! e)))
(instance (Op (!) I64 I64)
  (type Output I64)
  (type Output I64)
  (define (op (a I64) (b I64)) (→ I64)
    (+ a b)))
