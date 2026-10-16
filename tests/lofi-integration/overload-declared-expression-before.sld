(import (lofi base))
(def cell
     (ref (empty-vector)))
(ref-set! cell (make-vector (ann 1 I64) 42))
(define-overload stored (-> (Vector I32)) (lambda () (ref-get cell)))
(vector-ref (stored) (ann 0 I64))
