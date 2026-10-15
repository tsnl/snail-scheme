(import (snail strict))
(define-overload identity (lambda (value) value))
(: impossible (All (T) (-> T Bool)))
(define (impossible value) (identity value))
42
