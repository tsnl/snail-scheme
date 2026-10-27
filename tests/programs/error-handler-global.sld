(import
 (snail-core base))
(effect Counter ((tick (-> I64))))
(define state (ref (ann 1 I64)))
(define (helper) (ref-get state))
(handle Counter ((tick helper)) (tick))
