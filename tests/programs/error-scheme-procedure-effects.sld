(import
 (snail core base)
 (snail shell datum))

;; Recovering the nominal wrapper cannot erase its callable field's effects.
(define (recover (value Any)) (→ (dyn (Fn (List Any) → Any))) (! dyn-cast)
  (::call (type-convert value Procedure)))
