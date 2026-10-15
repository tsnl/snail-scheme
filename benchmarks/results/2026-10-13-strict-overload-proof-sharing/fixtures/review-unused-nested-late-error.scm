(import (snail strict))
(define values (make-vector 1))
(define (outer unused)
  (define (inner other) (+ (vector-ref values 0) (vector-ref values 0)))
  unused)
(vector-set! values 0 #t)
42
