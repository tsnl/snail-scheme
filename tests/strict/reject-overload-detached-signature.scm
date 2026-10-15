(import (snail strict))
(: select (-> I64 I64))
(define-overload select (-> I64 I64) (lambda (value) value))
42
