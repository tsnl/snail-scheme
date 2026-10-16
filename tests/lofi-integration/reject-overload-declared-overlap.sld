(import (lofi base))
(define-overload identity (All (T) (-> T T)) (lambda (value) value))
(define-overload identity (-> I64 I64) (lambda (value) (i64-add value (ann 0 I64))))
(identity (ann 42 I64))
