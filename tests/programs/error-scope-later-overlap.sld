(import
 (snail core base))

;; A scope is checked once every declaration of its library is reached, so
;; it sees the instances of a set declared after it.
(typeclass (Probe T)
  (: probe (impl (Fn T -> I64))))
(instance (Probe I64)
  (define (probe x) 1))
(with-instances (later) (unit))
(define-instance-set later
  (instance (Probe I64)
    (define (probe x) 2)))
