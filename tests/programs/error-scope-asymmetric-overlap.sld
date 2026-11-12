(import
 (snail core base))

;; asymmetric-overlap.sld's instances, accepted where they are declared, are
;; refused at a scope: it compares every two instances active under it both
;; ways, though the set it activates is empty.
(typeclass (Probe T)
  (: probe (impl (Fn T -> I64))))
(instance (Probe (dyn (Fn I64 -> I64)))
  (define (probe f) 2))
(instance (Probe I64)
  (define (probe x) 1))
(define-instance-set none)
(with-instances (none) (unit))
