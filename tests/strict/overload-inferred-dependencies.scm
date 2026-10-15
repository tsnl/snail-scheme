(import (snail strict))
;; Freezing bridge before f is complete would give g an overly broad A -> R row.
(define-overload g (lambda (value) (bridge value)))
(define-overload g (-> I64 Bool) (lambda (value) #t))
(define (bridge value) (helper value))
(define (forward value) (f value))
(define helper forward)
(define-overload f (lambda (value) value))
(if (and (ann (g 42) Bool) (= (ann (g 42) I64) 42)) 42 (unreachable))
