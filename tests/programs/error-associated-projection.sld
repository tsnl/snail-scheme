(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (impl (Fn A B -> Output ! e))))
(: wrong (All (A B e) (impl (Fn A B -> (Op.Output e A B)))))
(define (wrong a b) (op a b))
