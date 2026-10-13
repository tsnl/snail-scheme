(import (snail strict))
(define (choose flag left right) (if flag left right))
(if (choose #t #t #f) (choose #f 0 42) 0)
