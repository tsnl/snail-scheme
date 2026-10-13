(import (snail strict))
(define-overload select (-> I64 I64) (lambda (value) value))
(define-overload select (-> I64 I64 I64) i64-add)
0
