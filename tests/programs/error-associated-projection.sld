(import
 (snail core base)
 (snail core io))

(typeclass (Op E A B)
  (type Output)
  (declare (op (left A) (right B)) (→ Output) (! E)))
(define (wrong (a A) (b B)) (→ (Op.Output e A B)) (∀ (A B e)) (op a b))
