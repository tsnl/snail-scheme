(import (snail strict))
(define value (box 13))
(define-data Box (box (value I64 unbox)))
(unbox value)
