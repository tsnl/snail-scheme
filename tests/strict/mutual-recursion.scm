(import (snail strict))
(define (even n) (if (= n 0) #t (odd (- n 1))))
(define (odd n) (if (= n 0) #f (even (- n 1))))
(if (even 100001) 1 0)
