(import
 (snail core base))

(struct Resource
  ((value I64)) (deriving Move))
(typeclass (Add e A B)
  (type Output)
  (: add (Fn A B → Output ! e)))
(instance (Add (!) Resource I64)
  (type Output I64)
  (define add (lambda (a b) (match a ((Resource value) (+ value b))))))
(define-instance-set dynamic
  (dynamic-instances Add (Resource I64)))
