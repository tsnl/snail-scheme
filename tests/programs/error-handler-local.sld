(import
 (lofi base))
(effect Counter ((tick (-> I64))))
(let ((state (ref (ann 1 I64))))
  (handle Counter ((tick (lambda () (let ((state (ref-get state))) state)))) (tick)))
