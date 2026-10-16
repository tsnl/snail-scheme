(import (lofi base))
(define-overload identity (All (T) (-> T T)) (lambda (first) first))
(define-overload identity (All (U) (-> U U)) (lambda (second) second))
42
