(import (snail strict))
(define hidden (ann (make-vector 1 #t) Top))
(vector-ref (ann hidden (Vector I32)) 0)
