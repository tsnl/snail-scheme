(import (snail strict))
(define value (empty-vector))
(define (read-as-int) (+ (vector-ref value 0) 1))
(define (read-as-bool) (not (vector-ref value 0)))
42
