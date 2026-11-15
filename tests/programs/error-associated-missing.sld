(import
 (snail core base)
 (snail core io))

(typeclass (Op E A B)
  (type Output)
  (declare (op (left A) (right B)) (→ Output) (! E)))
(instance (Op (!) I64 I64)
  (define (op (a I64) (b I64)) (→ Output)
    (+ a b)))
