(import
 (snail core base))

;; An instance is compared with those of its class declared before it, and
;; the rule is asymmetric: a bare function type overlaps any type, but I64
;; overlaps only I64 and a variable. So the instance for a function, written
;; second, overlaps the one for I64; asymmetric-overlap.sld writes them in
;; the other order and is accepted.
(typeclass (Probe T)
  (: probe (impl (Fn T -> I64))))
(instance (Probe I64)
  (define (probe x) 1))
(instance (Probe (dyn (Fn I64 -> I64)))
  (define (probe f) 2))
