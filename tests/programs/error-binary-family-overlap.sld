(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (-> A B Output ! e)))
(define-instance-set sources
  (instance (Op (!) I64 I64)
    (type Output I64)
    (define (op a b) (+ a b))))
(with-instances (sources)
                (define-instance-set dynamic
                  (dynamic-instances Op (I64 I64))))
(with-instances (sources)
                (define-instance-set other
                  (dynamic-instances Op (I64 I64))))
(with-instances (dynamic other) (unit))
