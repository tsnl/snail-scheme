(import
 (lofi base))
(effect Counter ((tick (-> I64))))
(let ((state (ref (ann 1 I64))))
  (handle Counter ((tick (lambda () (ref-get state)))) (tick)))
