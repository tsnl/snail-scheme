(import
 (lofi base))
(def cell
     (ref (empty-vector)))
(def initialized
     (ref-set! cell (make-vector (ann 1 I64) (ann 42 I64))))
(define-overload stored (-> (Vector I64)) (lambda () (ref-get cell)))
(vector-ref (stored) (ann 0 I64))
