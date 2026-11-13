(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (Fn A B → Output ! e)))
(define (wrong (a A) (b B)) (→ (Op.Output e A B)) (∀ (A B e)) (op a b))
