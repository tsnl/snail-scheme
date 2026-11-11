(import
 (snail core base)
 (snail shell datum))

;; Recovering the nominal wrapper cannot erase its callable field's effects.
(: recover (impl (Fn Any -> (dyn (Fn (List Any) -> Any)) ! dyn-cast)))
(define (recover value)
  (::call (type-convert value Procedure)))
