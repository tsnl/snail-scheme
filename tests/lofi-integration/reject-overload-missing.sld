(import (lofi base))
(define-overload select (-> I64 I64) (lambda (value) value))
(select #t)
