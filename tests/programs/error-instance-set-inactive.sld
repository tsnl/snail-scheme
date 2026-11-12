(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (Fn A B → Output ! e)))
(define-instance-set first-policy
  (instance (Op (!) I64 I64)
    (type Output I64)
    (define op (lambda (a b) (+ a b)))))
(define-instance-set second-policy
  (instance (Op (!) I64 I64)
    (type Output String)
    (define op (lambda (a b) (show (+ a b))))))
(op (ann 1 I64) (ann 2 I64))
