(import (snail strict))
(define-class (Combine T) (: combine (-> T T T)))
(define-instance (Combine I64) (combine (lambda (a b) (+ a b))))
(define-instance (Combine I64) (combine (lambda (a b) (- a b))))
42
