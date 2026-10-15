(import (snail strict))
(define (identity x) x)
(if (identity #t) (+ (identity 40) (identity 2)) 0)
