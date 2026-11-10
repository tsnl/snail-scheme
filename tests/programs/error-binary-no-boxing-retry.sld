(import
 (snail core base)
 (snail core io))

(typeclass (Op e A B)
  (type Output)
  (: op (impl (Fn A B -> Output ! e))))
(define-instance-set sources
  (instance (Op (!) I64 I64)
    (type Output I64)
    (define (op a b) (+ a b))))
(with-instances (sources)
                (define-instance-set dynamic
                  (dynamic-instances Op (I64 I64))))
(with-instances (dynamic)
                (handle dyn-cast ((conversion-failed (lambda (_) (unit))))
                  (op (ann 1 I64) (ann 2 I64))
                  (unit)))
