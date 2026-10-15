(import (snail strict))
(define count (ref 0))
(define-overload add-two implementation)
(define implementation
  (begin (ref-set! count (+ (ref-get count) 1))
         (lambda (value) (i64-add value 2))))
(define first (add-two 38))
(define second (add-two first))
(if (= (ref-get count) 1) second (unreachable))
