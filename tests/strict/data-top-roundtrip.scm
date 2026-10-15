(import (snail strict))
(define-data Choice (left (value I64)) (right (value I64)))
(define boxed (ann (right 18) Top))
(match (ann boxed Choice) ((left value) 0) ((right value) value))
