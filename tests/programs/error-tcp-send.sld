(import
 (snail-core base)
 (snail-core socket))

(: transfer (All (T) (requires (Send T)) (-> T T)))
(define (transfer value) value)

(transfer (Connection (type-convert (ann 1 I32) Any)))
