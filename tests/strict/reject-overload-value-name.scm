(import (snail strict))
(define (select value) value)
(define-overload select (-> I64 I64) (lambda (value) value))
(select 42)
