(import
 (lofi base))
(effect Counter ((tick (-> I64))))
(let* ((state (ref (ann 1 I64)))
       (callback (lambda () (ref-get state)))
       (alias callback))
  (handle Counter ((tick alias)) (tick)))
