(import
 (snail core base))

;; Each scope under which two instances overlap is refused, every one.
(typeclass (Probe T)
  (: probe (impl (Fn T -> I64))))
(define-instance-set first-policy
  (instance (Probe I64)
    (define (probe x) 1)))
(define-instance-set second-policy
  (instance (Probe I64)
    (define (probe x) 2)))
(with-instances (first-policy second-policy) (unit))
(with-instances (second-policy first-policy) (unit))
