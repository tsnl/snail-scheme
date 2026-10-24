(import
 (lofi base))
(: transfer (All (T) (requires (Send T)) (-> T T)))
(define (transfer value) value)
(transfer (list (ref (ann 1 I64))))
