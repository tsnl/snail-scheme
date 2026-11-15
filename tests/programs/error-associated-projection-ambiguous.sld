(import
 (snail core base)
 (snail core io))

(typeclass (Op E A B)
  (type Output)
  (declare (op (left A) (right B)) (→ Output) (! E)))
(define (wrong (a A) (b B))
  (→ (Op.Output E A B))
  (! E)
  (∀ (A B E F))
  (⊨ (Op E A B) (Op F A B))
  (op a b))
