(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (Fn A B → Output ! e)))
(instance (Op (!) I64 I64)
  (type Output I64)
  (define op (lambda (a b) (+ a b))))
(instance (Op (!) I64 I64)
  (type Output String)
  (define op (lambda (a b) (show (+ a b)))))
