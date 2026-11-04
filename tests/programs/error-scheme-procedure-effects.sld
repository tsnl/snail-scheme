(import
 (snail core base)
 (snail shell datum))

;; Recovering the nominal wrapper cannot erase its callable field's effects.
(: recover (-> Any (-> (List Any) Any) ! dyn-cast))
(define (recover value)
  (Procedure-call value))
