(import (snail strict))
(define-overload add-two (-> I64 I64) implementation)
(define answer (add-two 40))
(define (implementation value) (+ value 2))
answer
