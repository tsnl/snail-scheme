(import (snail strict))
(define value (make-vector 2 0))
(define alias value)
(vector-set! alias 0 #t)
