(import
 (snail core base)
 (snail core io))

(typeclass (Op E A B)
  (type Output)
  (declare (op (left A) (right B)) (→ Output) (! E)))
(define (wrong (a A) (b B)) (→ (Op.Output E A B)) (∀ (A B E)) (op a b))
