(import (snail strict))
(define-overload size (-> (Vector I64) I64) vector-length)
(size (empty-vector))
