(import (snail strict))
(define-class (Combine T) (: combine (-> T T T)))
(define-instance (Combine I64) (combine (lambda (a b) (+ a b))))
(: twice (All (T) (-> T T)))
(define (twice x) (combine x x))
42
