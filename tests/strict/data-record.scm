(import (snail strict))
(define-data Point (point (x F64 point-x) (y I64 point-y) (done Unit point-done)))
(define p (point 3.5 7 (unit)))
(+ (point-y p) (f64->i64 (point-x p)))
