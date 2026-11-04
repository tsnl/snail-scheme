(import
 (snail core base))

(: accept (-> (-> I64 I64) I64))
(define (accept function) (function 1))

(: dynamic (-> Any Any))
(define (dynamic value) value)
(accept dynamic)
