(import
 (snail-core base)
 (snail-core socket))

(: share (All (T) (requires (Sync T)) (-> T T)))
(define (share value) value)

(share (UdpSocket (type-convert (ann 1 I32) Any) 0))
