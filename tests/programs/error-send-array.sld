(import
 (snail-core base))
(: transfer (All (T) (requires (Send T)) (-> T T)))
(define (transfer value) value)
(transfer (make-array 1 (ann 1 I64)))
