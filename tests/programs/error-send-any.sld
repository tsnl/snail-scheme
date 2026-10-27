(import
 (snail-core base))
(: transfer (All (T) (requires (Send T)) (-> T T)))
(define (transfer value) value)
(transfer (type-convert (ann 1 I64) Any))
