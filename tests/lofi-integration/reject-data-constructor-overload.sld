(import (lofi base))
(def Box (datatype () (box (value I64))))
(define-overload box (-> I64 I64) (lambda (value) value))
(box 1)
