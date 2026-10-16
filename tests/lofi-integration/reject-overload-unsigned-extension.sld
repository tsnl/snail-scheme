(import (rename (lofi base) (+ sum)))
(define-overload sum (lambda (left right) (i64-add (i32->i64 left) right)))
(sum (ann 20 I32) (ann 22 I64))
