(import (snail strict))
(define (make-adder amount) (lambda (x) (+ amount x)))
((make-adder 40) 2)
