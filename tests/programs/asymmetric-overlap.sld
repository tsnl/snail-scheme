(import
 (snail core base)
 (snail core io))

;; The instances error-asymmetric-overlap.sld refuses, in the other order:
;; the instance for I64, written second, is the one compared, and I64 does
;; not overlap a function type, so both are accepted.
(typeclass (Probe T)
  (: probe (impl (Fn T -> I64))))
(instance (Probe (dyn (Fn I64 -> I64)))
  (define (probe f) 2))
(instance (Probe I64)
  (define (probe x) 1))
(display (probe (ann 7 I64)))
(newline)
