(import (snail strict))
(define-overload f (lambda (value) (helper value)))
(define (helper value) (f value))
42
