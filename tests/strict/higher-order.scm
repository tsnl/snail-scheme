(import (snail strict))
(define (increment x) (+ x 1))
(define (twice f x) (f (f x)))
(twice increment 40)
