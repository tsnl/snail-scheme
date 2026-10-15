(import (snail strict))
(define-overload choose (All (T) (-> T T)) (lambda (value) value))
(define-overload choose (-> I64 I64) (lambda (value) value))
(choose 42)
