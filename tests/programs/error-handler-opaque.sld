(import
 (lofi base))
(effect Counter ((tick (-> I64))))
(: apply-handler (-> (-> I64) I64))
(define (apply-handler callback)
  (handle Counter ((tick callback)) (tick)))
(apply-handler (lambda () 1))
