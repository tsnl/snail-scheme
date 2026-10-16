(import (lofi base))
(define-overload identity (All (T) (-> T T)) (lambda (value) value))
(identity)
