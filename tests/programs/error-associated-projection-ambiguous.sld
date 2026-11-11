(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (impl (Fn A B -> Output ! e))))
(: wrong (All (A B e f)
              (requires (Op e A B) (Op f A B))
              (impl (Fn A B -> (Op.Output e A B) ! e))))
(define (wrong a b) (op a b))
