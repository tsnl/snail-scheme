(import (snail strict))
(define values (make-vector 2 (ann 42 Top)))
(vector-set! values 1 (ann #t Top))
(if (ann (vector-ref values 1) Bool) (ann (vector-ref values 0) I64) 0)
