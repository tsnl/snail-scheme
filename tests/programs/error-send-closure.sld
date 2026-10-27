(import
 (snail-core base))
(: transfer (All (T) (requires (Send T)) (-> T T)))
(define (transfer value) value)
(transfer (lambda (x) (+ x 1)))
