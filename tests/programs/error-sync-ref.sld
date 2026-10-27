(import
 (snail-core base))
(: share (All (T) (requires (Sync T)) (-> T T)))
(define (share value) value)
(share (ref (ann 1 I64)))
