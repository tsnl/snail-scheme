(import (snail strict))
(define-overload identity (lambda (value) value))
(define-overload identity (lambda (value) (i64-add value 0)))
(identity 42)
