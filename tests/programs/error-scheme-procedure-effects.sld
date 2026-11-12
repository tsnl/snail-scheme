(import
 (snail core base)
 (snail shell datum))

;; Recovering the nominal wrapper cannot erase its callable field's effects.
(define (recover (value Any)) (→ (Fn (List Any) → Any)) (! dyn-cast)
  (● (type-convert value Procedure) call))
