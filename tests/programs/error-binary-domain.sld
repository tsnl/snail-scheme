(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (Fn A B → Output ! e)))
(define-instance-set dynamic
  (dynamic-instances Op (Any I64)))
