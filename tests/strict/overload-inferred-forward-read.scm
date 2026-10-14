(import (snail strict))
(define-overload add-two implementation)
(define answer (add-two 40))
(define (implementation value) (i64-add value 2))
answer
