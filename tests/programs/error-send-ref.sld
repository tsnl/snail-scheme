(import
 (lofi base))
(: transfer (All (T) (requires (Send T)) (-> T T)))
(define (transfer value) value)
(transfer (ref (ann 1 I64)))
