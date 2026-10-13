(import (snail strict))
(define-overload select (-> I64 I64) (lambda (value) value))
(define-overload select (-> I64 F64) i64->f64)
0
