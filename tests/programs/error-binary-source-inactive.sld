(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (impl (Fn A B → Output ! e))))
(define-instance-set sources
  (instance (Op (!) I64 I64)
    (type Output I64)
    (define op (lambda (a b) (+ a b)))))
(define-instance-set dynamic
  (dynamic-instances Op (I64 I64)))
